//=========================================================================================
// File         : PCIe_RC_TL_model.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_RC_controller_agent\PCIe_RC_TL_model.sv
// Author       : 
// Date         : 2026-09-09
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

import typedef_enums :: *;

// FLOW CONTROL : DL -> TL credit limits (suffix may be declared only once per package)
`uvm_analysis_imp_decl(_fc_from_dl)

// [ADDED] RC DL -> RC TL : received TLP (completion) path
`uvm_analysis_imp_decl(_dl_rx)

class PCIe_RC_TL_model extends uvm_component;

  `uvm_component_utils(PCIe_RC_TL_model)

  //--------------------------------------------------------------------------
  // TLM ports  (names kept identical to the integration environment)
  //--------------------------------------------------------------------------
  // Input from RC controller driver.
  uvm_analysis_imp #(PCIe_sequence_item, PCIe_RC_TL_model) tx_tl_imp;
  // Output toward RC DL model.
  uvm_analysis_port #(PCIe_sequence_item) tlp_dl_ap;

  uvm_analysis_port #(PCIe_sequence_item) tl_ap;

  // [ADDED] Input from RC DL model : 236B TLP region of every good payload flit
  // (connected in PCIe_RC_controller_agent : rc_dl_model.rc_dl_tl_ap -> rc_tl_model.dl_tl_imp)
  uvm_analysis_imp_dl_rx #(PCIe_sequence_item, PCIe_RC_TL_model) dl_tl_imp;
  int unsigned n_tlp_rcvd;   // TLPs received from the DL model
  int unsigned n_cpl_rcvd;   // of which Cpl / CplD

  // [ENUM] completions kept for a waiting sequence (e.g. enumeration)
  //   write_dl_rx() stores every decoded completion here (key = tag) and fires
  //   cpl_event. A sequence calls wait_completion(tag, ...) to pick it up.
  PCIe_sequence_item cpl_rcvd [bit [`PCIe_TL_TAG_W-1:0]];
  event              cpl_event;

  // [FLIT_SEG] a CplD that is split over several FLITs : the first parts are
  // collected here (key = tag) until the last part (Byte Count covers only
  // its own payload) arrives; only then is the completion published.
  PCIe_sequence_item cpl_partial [bit [`PCIe_TL_TAG_W-1:0]];

  // [FLIT_SEG] segmented Non-Posted request (DMWr) : every segment is its own
  // TLP with its own tag and gets its own Cpl.
  //   seg_parent_of [segment tag] = tag of the original (unsplit) request
  //   seg_cpl_expect[parent tag]  = number of segments / completions expected
  //   seg_cpl_got   [parent tag]  = completions received so far
  bit [`PCIe_TL_TAG_W-1:0] seg_parent_of  [bit [`PCIe_TL_TAG_W-1:0]];
  int unsigned             seg_cpl_expect [bit [`PCIe_TL_TAG_W-1:0]];
  int unsigned             seg_cpl_got    [bit [`PCIe_TL_TAG_W-1:0]];
  string                   seg_desc_of    [bit [`PCIe_TL_TAG_W-1:0]];   // "seg i/N addr len" per segment tag
  string                   seg_cpl_rows   [bit [`PCIe_TL_TAG_W-1:0]];   // completion table per parent tag

  // [FLIT_SEG] read completions (CplD) : how many FLITs each one came in, and
  // the request it answers (address / length) so the full data can be checked
  int unsigned             cpl_part_cnt   [bit [`PCIe_TL_TAG_W-1:0]];
  PCIe_sequence_item       cpl_req_of     [bit [`PCIe_TL_TAG_W-1:0]];
  // [FLIT_SEG] shadow of every DW the RC has written (DW address -> data),
  // used to check the 1024 DW read back in the CplD against what was written
  bit [31:0]               wr_shadow      [bit [63:0]];
  int unsigned             n_rd_cpl_checked, n_rd_cpl_dw_match, n_rd_cpl_dw_mismatch, n_rd_cpl_dw_unwritten;
  int unsigned             n_seg_txn;        // transactions that were split
  int unsigned             n_seg_tlp;        // segment TLPs created
  int unsigned             n_seg_txn_done;   // segmented Non-Posted txns fully completed


  PCIe_sequence_item item;

  //--------------------------------------------------------------------------
  // Configuration knobs
  //--------------------------------------------------------------------------
  // There is no EP->RC upstream path in this environment yet, so completion
  // tracking is recorded but never blocked on. Flip to 1 once the DL model
  // exposes a dl2tl path back into cpl_write().
  bit          wait_for_completion = 1'b0;

  // Outstanding non-posted requests, keyed by tag.
  protected PCIe_sequence_item outstanding [bit [`PCIe_TL_TAG_W-1:0]];

  //--------------------------------------------------------------------------

  //==========================================================================
  // FLOW CONTROL (PCIe Base 6.0 Sec 2.6)  -  VC0 only (TC0 -> VC0)
  //   [FC SHARED] Flit Mode : two pools per type, DEDICATED and SHARED
  //   RECEIVER side : the six TL buffers PH PD NPH NPD CPLH CPLD, one set per pool
  //       CREDITS_ALLOCATED / CREDITS_RECEIVED, overflow check (Eq 2-14).
  //       The pool of a received TLP comes from the Flit Mode Local TLP Prefix
  //       (Sec 2.6.1.2) : "TLP Uses Dedicated Credits" Set -> dedicated, else shared.
  //   TRANSMITTER side : CREDIT_LIMIT / CREDITS_CONSUMED (dedicated) and
  //       SHARED_CREDIT_LIMIT / SHARED_CREDITS_CONSUMED (shared).
  //       Gate order (Sec 2.6.1.1) : shared gate (Eq 2-8) first, then the
  //       dedicated gate (Eq 2-11). A TLP sent on dedicated credits gets the
  //       Flit Mode Local TLP Prefix `PCIe_FC_DED_PREFIX_DW (Sec 2.2.10.3).
  //       Only VC0 exists, so SUM_SHARED_* (Eq 2-3 / 2-8) = the VC0 values.
  //   fc_dl_ap  : TL -> DL  initial credits / UpdateFC requests / status
  //   fc_dl_imp : DL -> TL  credit limits learnt from the peer InitFC1 / UpdateFC
  //   index 0 = P, 1 = NP, 2 = CPL
  //   NOT modelled : shared credit granularity of 4 / 8 credits (Sec 2.6.1),
  //                  Shared Flow Control Usage Limit (Eq 2-9), merged credits.
  //==========================================================================
  uvm_analysis_port #(PCIe_sequence_item) fc_dl_ap;
  uvm_analysis_imp_fc_from_dl #(PCIe_sequence_item, PCIe_RC_TL_model) fc_dl_imp;

  localparam int unsigned FC_FSH = `PCIe_FC_HDR_FIELD_BITS;    // field size, header credits
  localparam int unsigned FC_FSD = `PCIe_FC_DATA_FIELD_BITS;   // field size, data credits
  localparam bit          FC_DED = 1'b0;                      // pool index : dedicated
  localparam bit          FC_SHR = 1'b1;                      // pool index : shared

  // ---- receiver buffers  [pool][class]   pool 0 = dedicated, 1 = shared
  int unsigned fc_rx_max_h   [2][3];   // buffer size in credits
  int unsigned fc_rx_max_d   [2][3];
  int unsigned fc_rx_occ_h   [2][3];   // credits held by TLPs sitting in the buffer
  int unsigned fc_rx_occ_d   [2][3];
  int unsigned fc_rx_alloc_h [2][3];   // CREDITS_ALLOCATED (cumulative, mod 2^FS)
  int unsigned fc_rx_alloc_d [2][3];
  int unsigned fc_rx_recv_h  [2][3];   // CREDITS_RECEIVED  (cumulative, mod 2^FS)
  int unsigned fc_rx_recv_d  [2][3];
  int unsigned fc_rx_adv_h   [2][3];   // CREDITS_ALLOCATED carried by the last InitFC/UpdateFC
  int unsigned fc_rx_adv_d   [2][3];
  bit          fc_rx_pool_q  [3][$];   // pool of every received TLP still in the buffer (FIFO)
  int unsigned fc_rx_overflow_cnt;
  string       fc_rx_reason;

  // ---- transmitter terms  [pool][class]
  int unsigned fc_tx_limit_h [2][3];   // CREDIT_LIMIT / SHARED_CREDIT_LIMIT
  int unsigned fc_tx_limit_d [2][3];
  int unsigned fc_tx_cons_h  [2][3];   // CREDITS_CONSUMED / SHARED_CREDITS_CONSUMED
  int unsigned fc_tx_cons_d  [2][3];
  bit          fc_tx_inf_h   [2][3];
  bit          fc_tx_inf_d   [2][3];
  bit          fc_tx_limit_valid [2][3];   // InitFC1 received for the class / pool
  bit          fc_tx_pool_aa [PCIe_sequence_item];   // pool picked by the gate, per TLP
  bit          fc_tx_alt_next [3];          // FC_POOL_MODE 3 : pool of the next TLP

  // ---- configuration
  int unsigned fc_pool_mode;                // `PCIe_FC_POOL_MODE or +FC_POOL_MODE=<n>

  // ---- statistics
  int unsigned fc_n_rx_tlp [3];
  int unsigned fc_n_tx_tlp [3];
  int unsigned fc_n_tx_pool [2][3];         // TLPs sent per pool
  int unsigned fc_n_rx_pool [2][3];         // TLPs received per pool
  int unsigned fc_n_pfx_tx;                 // TLPs sent with the dedicated prefix
  int unsigned fc_n_pfx_rx;                 // TLPs received with the dedicated prefix
  int unsigned fc_n_upd_published;
  int unsigned fc_n_peer_upd;
  int unsigned fc_n_periodic;
  // [FC_OPT] NEW : time of the last UpdateFC published for each class (0 = P, 1 = NP, 2 = CPL).
  //               Used by fc_run_periodic() to send a refresh only when the spec needs one.
  realtime     fc_last_upd_t [3];
  int unsigned fc_n_blocked;

  function string fc_pool_name(bit p);
    return p ? "SHARED" : "DEDICATED";
  endfunction

  // value put on the wire for a buffer of 'v' credits : clamped to the spec
  // maximum of outstanding credits 2^(FS-1)-1 (127 header / 2047 data)
  function int unsigned fc_wire_val(int unsigned v, int unsigned fs);
    int unsigned mx;
    mx = (32'd1 << (fs - 1)) - 1;
    if ((`PCIe_FC_CLAMP_TO_SPEC_MAX != 0) && (v > mx)) return mx;
    return v;
  endfunction

  function void fc_init();
    int unsigned sz_h [2];
    int unsigned sz_d [2];
    int unsigned pm;
    // pool sizes : defines, then run-time override (+FC_DED_HDR= ... )
    sz_h[FC_DED] = `PCIe_FC_DED_HDR_CREDITS;   sz_d[FC_DED] = `PCIe_FC_DED_DATA_CREDITS;
    sz_h[FC_SHR] = `PCIe_FC_SHR_HDR_CREDITS;   sz_d[FC_SHR] = `PCIe_FC_SHR_DATA_CREDITS;
    void'($value$plusargs("FC_DED_HDR=%d",  sz_h[FC_DED]));
    void'($value$plusargs("FC_DED_DATA=%d", sz_d[FC_DED]));
    void'($value$plusargs("FC_SHR_HDR=%d",  sz_h[FC_SHR]));
    void'($value$plusargs("FC_SHR_DATA=%d", sz_d[FC_SHR]));
    if (sz_h[FC_SHR] == 0 || sz_d[FC_SHR] == 0)
      `uvm_error("RC_TL_FC", $sformatf("SHARED_CREDITS_ZERO_ON_VC0 (hdr=%0d data=%0d) : not permitted (Table 3-2 note 7)",
                 sz_h[FC_SHR], sz_d[FC_SHR]))
    fc_pool_mode = `PCIe_FC_POOL_MODE;
    if ($value$plusargs("FC_POOL_MODE=%d", pm)) begin
      if (pm <= 3) fc_pool_mode = pm;
      else `uvm_error("RC_TL_FC", $sformatf("+FC_POOL_MODE=%0d is not valid (0, 1, 2 or 3)", pm))
    end
    for (int p = 0; p < 2; p++) begin
      for (int c = 0; c < 3; c++) begin
        fc_rx_max_h[p][c]   = sz_h[p];
        fc_rx_max_d[p][c]   = sz_d[p];
        fc_rx_occ_h[p][c]   = 0;  fc_rx_occ_d[p][c]  = 0;
        fc_rx_alloc_h[p][c] = fc_wire_val(sz_h[p], FC_FSH);
        fc_rx_alloc_d[p][c] = fc_wire_val(sz_d[p], FC_FSD);
        fc_rx_recv_h[p][c]  = 0;  fc_rx_recv_d[p][c] = 0;
        fc_rx_adv_h[p][c]   = fc_rx_alloc_h[p][c];
        fc_rx_adv_d[p][c]   = fc_rx_alloc_d[p][c];
        fc_tx_limit_h[p][c] = 0;  fc_tx_limit_d[p][c] = 0;
        fc_tx_cons_h[p][c]  = 0;  fc_tx_cons_d[p][c]  = 0;
        fc_tx_inf_h[p][c]   = 0;  fc_tx_inf_d[p][c]   = 0;
        fc_tx_limit_valid[p][c] = 0;
        fc_n_tx_pool[p][c]  = 0;  fc_n_rx_pool[p][c]  = 0;
      end
    end
    for (int c = 0; c < 3; c++) begin
      fc_n_rx_tlp[c] = 0;  fc_n_tx_tlp[c] = 0;
      fc_rx_pool_q[c].delete();
      fc_tx_alt_next[c] = FC_SHR;
    end
    fc_tx_pool_aa.delete();
    fc_rx_overflow_cnt = 0;
    fc_n_pfx_tx = 0; fc_n_pfx_rx = 0;
    fc_n_upd_published = 0; fc_n_peer_upd = 0; fc_n_periodic = 0; fc_n_blocked = 0;
  endfunction

  function void fc_log(string msg);
    `uvm_info("RC_TL_FC", msg, UVM_LOW)
  endfunction

  function string fc_rx_status(bit p, int unsigned c);
    return $sformatf("%s: %s(MAX=%0d FREE=%0d ALLOCATED=%0d RECEIVED=%0d ADV=%0d) %s(MAX=%0d FREE=%0d ALLOCATED=%0d RECEIVED=%0d ADV=%0d)",
        PCIe_sequence_item::fc_cls_name(c),
        PCIe_sequence_item::fc_hdr_name(c), fc_rx_max_h[p][c], fc_rx_max_h[p][c] - fc_rx_occ_h[p][c], fc_rx_alloc_h[p][c], fc_rx_recv_h[p][c], fc_rx_adv_h[p][c],
        PCIe_sequence_item::fc_dat_name(c), fc_rx_max_d[p][c], fc_rx_max_d[p][c] - fc_rx_occ_d[p][c], fc_rx_alloc_d[p][c], fc_rx_recv_d[p][c], fc_rx_adv_d[p][c]);
  endfunction

  function int unsigned fc_tx_avail_h(bit p, int unsigned c);
    return PCIe_sequence_item::fc_mod_sub(fc_tx_limit_h[p][c], fc_tx_cons_h[p][c], FC_FSH);
  endfunction
  function int unsigned fc_tx_avail_d(bit p, int unsigned c);
    return PCIe_sequence_item::fc_mod_sub(fc_tx_limit_d[p][c], fc_tx_cons_d[p][c], FC_FSD);
  endfunction

  function string fc_tx_status(bit p, int unsigned c);
    return $sformatf("%s: %s(LIMIT=%0d CONSUMED=%0d AVAIL=%0d%s) %s(LIMIT=%0d CONSUMED=%0d AVAIL=%0d%s)",
        PCIe_sequence_item::fc_cls_name(c),
        PCIe_sequence_item::fc_hdr_name(c), fc_tx_limit_h[p][c], fc_tx_cons_h[p][c], fc_tx_avail_h(p, c), fc_tx_inf_h[p][c] ? " INF" : "",
        PCIe_sequence_item::fc_dat_name(c), fc_tx_limit_d[p][c], fc_tx_cons_d[p][c], fc_tx_avail_d(p, c), fc_tx_inf_d[p][c] ? " INF" : "");
  endfunction

  function void fc_print_buffers(string when_s);
    string s;
    s = $sformatf("\n  ================= RC_TL FC BUFFERS (VC0, dedicated + shared) : %s =================\n", when_s);
    for (int p = 0; p < 2; p++) begin
      s = {s, $sformatf("  ---- receiver buffers (%s) ----\n", (p == FC_SHR) ? "shared" : "dedicated")};
      for (int c = 0; c < 3; c++) s = {s, "  ", fc_rx_status(p, c), "\n"};
    end
    for (int p = 0; p < 2; p++) begin
      s = {s, $sformatf("  ---- transmitter view of peer credits (%s) ----\n", (p == FC_SHR) ? "shared" : "dedicated")};
      for (int c = 0; c < 3; c++) s = {s, "  ", fc_tx_status(p, c), "\n"};
    end
    s = {s, "  ======================================================================"};
    fc_log(s);
  endfunction

  // ---- Eq 2-8 / Eq 2-11 : (LIMIT - REQUIRED) mod 2^FS <= 2^FS / 2
  function bit fc_gate_ok(int unsigned limit, int unsigned required, int unsigned fs, bit inf);
    if (inf) return 1'b1;
    return (PCIe_sequence_item::fc_mod_sub(limit, required, fs) <= (32'd1 << (fs - 1)));
  endfunction

  // gate of one pool : p = FC_SHR -> Eq 2-8 (shared gate), FC_DED -> Eq 2-11
  function bit fc_tx_can_send(bit p, int unsigned c, int unsigned h, int unsigned d);
    if (!fc_tx_limit_valid[p][c]) return 1'b0;
    if (!fc_gate_ok(fc_tx_limit_h[p][c], PCIe_sequence_item::fc_mod_add(fc_tx_cons_h[p][c], h, FC_FSH), FC_FSH, fc_tx_inf_h[p][c])) return 1'b0;
    if (d != 0 && !fc_gate_ok(fc_tx_limit_d[p][c], PCIe_sequence_item::fc_mod_add(fc_tx_cons_d[p][c], d, FC_FSD), FC_FSD, fc_tx_inf_d[p][c])) return 1'b0;
    return 1'b1;
  endfunction

  // The ONE place that decides the pool of a TLP (Sec 2.6.1.1).
  //   ded_ok = 0 : the TLP may not use dedicated credits (Non-Flit TLP, or no
  //   room left for the 1 DW prefix in the 236 B region).
  //   returns 1 when the chosen pool has room, 0 when the TLP has to wait.
  function bit fc_tx_pick_pool(int unsigned c, int unsigned h, int unsigned d, bit ded_ok, output bit pool);
    case (fc_pool_mode)
      1 : pool = ded_ok ? FC_DED : FC_SHR;                    // DEDICATED (debug)
      2 : pool = FC_SHR;                                      // SHARED    (debug)
      3 : pool = ded_ok ? fc_tx_alt_next[c] : FC_SHR;         // ALTERNATE (debug)
      default : begin                                         // SPEC
        if (fc_tx_can_send(FC_SHR, c, h, d))           begin pool = FC_SHR; return 1'b1; end   // Eq 2-8
        if (ded_ok && fc_tx_can_send(FC_DED, c, h, d)) begin pool = FC_DED; return 1'b1; end   // Eq 2-11
        pool = FC_SHR;
        return 1'b0;
      end
    endcase
    return fc_tx_can_send(pool, c, h, d);
  endfunction

  //--------------------------------------------------------------------------
  // TL -> DL transactions (PCIe_sequence_item with the fc_* fields)
  //--------------------------------------------------------------------------
  function PCIe_sequence_item fc_make_item(pcie_fc_kind_e k, string reason, bit [2:0] mask);
    PCIe_sequence_item it = PCIe_sequence_item::type_id::create("fc_item");
    it.fc_kind   = k;
    it.fc_origin = "RC_TL";
    it.fc_reason = reason;
    for (int c = 0; c < 3; c++) begin
      it.set_fc_cls    (c, fc_rx_alloc_h[FC_DED][c], fc_rx_alloc_d[FC_DED][c]);
      it.set_fc_cls_shr(c, fc_rx_alloc_h[FC_SHR][c], fc_rx_alloc_d[FC_SHR][c]);
    end
    it.fc_cls_mask     = mask;
    it.fc_cls_mask_shr = mask;
    return it;
  endfunction

  // Spec rule (scale x1) : outstanding credits (ADVERTISED - RECEIVED) of a
  // pool must never be more than 2^(FS-1)-1 (127 header / 2047 data).
  function void fc_check_adv_limit(int unsigned c, string why);
    int unsigned max_h, max_d, out_h, out_d;
    max_h = (32'd1 << (FC_FSH - 1)) - 1;
    max_d = (32'd1 << (FC_FSD - 1)) - 1;
    for (int p = 0; p < 2; p++) begin
      out_h = PCIe_sequence_item::fc_mod_sub(fc_rx_adv_h[p][c], fc_rx_recv_h[p][c], FC_FSH);
      out_d = PCIe_sequence_item::fc_mod_sub(fc_rx_adv_d[p][c], fc_rx_recv_d[p][c], FC_FSD);
      if (out_h > max_h || out_d > max_d)
        `uvm_error("RC_TL_FC", $sformatf("ADVERTISED_OUTSTANDING_CREDITS_OVER_SPEC_MAX class %s %s (%s) : %0d/%0d outstanding (max %0d/%0d)",
                   PCIe_sequence_item::fc_cls_name(c), fc_pool_name(p), why, out_h, out_d, max_h, max_d))
    end
  endfunction

  // Initial credits of both pools
  function void fc_publish_init();
    PCIe_sequence_item it = fc_make_item(FC_ADV_INIT, "INITIAL_ADVERTISEMENT", 3'b111);
    for (int c = 0; c < 3; c++) fc_check_adv_limit(c, "INITIAL_ADVERTISEMENT");
    fc_print_buffers("INITIAL");
    fc_log($sformatf("[FC_TL->DL] INIT CREDITS  %s", it.fc_values_str()));
    fc_dl_ap.write(it);
  endfunction

  function void fc_publish_status(string why);
    PCIe_sequence_item it = fc_make_item(FC_STATUS, why, 3'b000);
    fc_dl_ap.write(it);
  endfunction

  // DL must put an UpdateFC DLLP (dedicated and shared) on the wire for every class in 'mask'
  function void fc_publish_update(bit [2:0] mask, string reason);
    PCIe_sequence_item it;
    for (int c = 0; c < 3; c++) if (mask[c]) begin
      for (int p = 0; p < 2; p++) begin
        fc_rx_adv_h[p][c] = fc_rx_alloc_h[p][c];
        fc_rx_adv_d[p][c] = fc_rx_alloc_d[p][c];
      end
      fc_check_adv_limit(c, reason);
    end
    it = fc_make_item(FC_ADV_UPDATE, reason, mask);
    fc_n_upd_published++;
    // [FC_OPT] NEW : any UpdateFC (mandatory, watermark or refresh) restarts the 30 us timer of its class
    for (int c = 0; c < 3; c++) if (mask[c]) fc_last_upd_t[c] = $realtime;
    fc_log($sformatf("[FC_UPDATE_SCHEDULED] reason=%s classes=%03b (P,NP,CPL=bit0,1,2) -> %s",
                     reason, mask, it.fc_values_str()));
    fc_dl_ap.write(it);
  endfunction

  // periodic refresh (spec: at most every 30 us; Flit Mode debug value 10 us)
  // [FC_OPT] OLD : fixed timer from time 0, every PCIe_FC_UPDATE_PERIOD_NS, all classes
  //   task fc_run_periodic();
  //     forever begin
  //       #(`PCIe_FC_UPDATE_PERIOD_NS * 1ns);
  //       fc_n_periodic++;
  //       fc_publish_update(3'b111, "PERIODIC_REFRESH");
  //     end
  //   endtask
  //
  // [FC_OPT] NEW : refresh only when the spec requires it (PCIe 6.1 Sec 2.6.1.2)
  //   "In L0 an UpdateFC for each non-infinite FC credit type must be scheduled at least once every 30 us."
  //   * The timer starts when flow control is initialised (peer InitFC credits known for P, NP, Cpl).
  //   * A class is refreshed only when PCIe_FC_UPDATE_PERIOD_NS (30 us) has passed since the LAST
  //     UpdateFC of that class. Any earlier UpdateFC (credits freed / watermark) restarts its timer
  //     (see fc_publish_update), so no refresh is sent while normal UpdateFCs keep flowing.
  //   * A short test that ends before 30 us sends no refresh at all.
  task fc_run_periodic();
    bit [2:0] due;
    realtime  next_due;
    wait (fc_tx_limit_valid[0][0] && fc_tx_limit_valid[0][1] && fc_tx_limit_valid[0][2]);
    for (int c = 0; c < 3; c++) fc_last_upd_t[c] = $realtime;     // 30 us timer starts here
    fc_log("[FC_REFRESH] flow control initialised : 30 us UpdateFC refresh timer started");
    forever begin
      // earliest time at which some class reaches 30 us without an UpdateFC
      next_due = fc_last_upd_t[0];
      for (int c = 1; c < 3; c++) if (fc_last_upd_t[c] < next_due) next_due = fc_last_upd_t[c];
      next_due = next_due + `PCIe_FC_UPDATE_PERIOD_NS * 1ns;
      if ($realtime < next_due) #(next_due - $realtime);
      // refresh only the classes that really reached the limit
      due = 3'b000;
      for (int c = 0; c < 3; c++)
        if (($realtime - fc_last_upd_t[c]) >= `PCIe_FC_UPDATE_PERIOD_NS * 1ns) due[c] = 1'b1;
      if (due != 3'b000) begin
      fc_n_periodic++;
        fc_publish_update(due, "PERIODIC_REFRESH");
      end
    end
  endtask

  //--------------------------------------------------------------------------
  // [FC SHARED] Flit Mode Local TLP Prefix
  //--------------------------------------------------------------------------
  // Transmitter : put the dedicated prefix in front of a serialized TLP
  // (after the ECRC is computed - a Local TLP Prefix is not covered by ECRC).
  function void fc_add_ded_prefix(PCIe_sequence_item tr);
    bit [`PCIe_TL_DATA_DW_W-1:0] tmp [];
    tmp    = new[tr.serialized_tlp.size() + 1];
    tmp[0] = `PCIe_FC_DED_PREFIX_DW;
    for (int i = 0; i < tr.serialized_tlp.size(); i++) tmp[i+1] = tr.serialized_tlp[i];
    tr.serialized_tlp      = tmp;
    tr.tlp_header_dw_count = tr.tlp_header_dw_count + 1;    // the prefix is shown with the header
    tr.tlp_total_dw_count  = tr.serialized_tlp.size();
    fc_n_pfx_tx++;
    fc_log($sformatf("[FC_TX_PREFIX] %s : DEDICATED credits -> Flit Mode Local TLP Prefix %08h added (Sec 2.2.10.3)",
                     tr.convert2string(), `PCIe_FC_DED_PREFIX_DW));
  endfunction

  // Receiver : if the 236 B region starts with the prefix, read the
  // "TLP Uses Dedicated Credits" bit and remove the prefix (shift left by
  // 4 bytes) so the normal decode finds the TLP header at byte 0.
  //   returns the pool : FC_DED when the bit is Set, FC_SHR otherwise.
  function bit fc_strip_prefix(PCIe_sequence_item item);
    bit ded;
    if (item.tlp_data[0] != `PCIe_FLITTYPE_PREFIX) return FC_SHR;   // no prefix -> shared
    if (item.pkt_mode != FLIT)
      `uvm_error("RC_TL_FC", "FLIT_MODE_LOCAL_TLP_PREFIX_ON_NON_FLIT_TLP : Malformed TLP (Sec 2.2.10.3)")
    ded = item.tlp_data[1][7];                                      // TLP Uses Dedicated Credits
    for (int b = 0; b < `PCIe_TLP_DATA_BYTE_W; b++)
      item.tlp_data[b] = ((b + 4) < `PCIe_TLP_DATA_BYTE_W) ? item.tlp_data[b+4] : 8'h00;
    if (ded) fc_n_pfx_rx++;
    fc_log($sformatf("[FC_RX_PREFIX] Flit Mode Local TLP Prefix found : TLP Uses Dedicated Credits=%0b -> %s pool",
                     ded, ded ? "DEDICATED" : "SHARED"));
    return ded ? FC_DED : FC_SHR;
  endfunction

  //--------------------------------------------------------------------------
  // RECEIVER : a TLP reached the TL buffer. 'pool' comes from the prefix.
  //--------------------------------------------------------------------------
  function void fc_rx_account(int unsigned c, int unsigned h, int unsigned d, string desc, bit pool = FC_SHR);
    int unsigned lim_h, lim_d, cons_h, cons_d, req_h, req_d, gap_h, gap_d;
    bit ovf;
    lim_h  = fc_rx_adv_h[pool][c];  lim_d  = fc_rx_adv_d[pool][c];
    cons_h = fc_rx_recv_h[pool][c]; cons_d = fc_rx_recv_d[pool][c];
    req_h  = PCIe_sequence_item::fc_mod_add(cons_h, h, FC_FSH);
    req_d  = PCIe_sequence_item::fc_mod_add(cons_d, d, FC_FSD);
    gap_h  = PCIe_sequence_item::fc_mod_sub(lim_h, req_h, FC_FSH);
    gap_d  = PCIe_sequence_item::fc_mod_sub(lim_d, req_d, FC_FSD);
    // CREDITS_RECEIVED += this TLP, buffer occupancy += this TLP, then Eq 2-14
    fc_rx_recv_h[pool][c] = req_h;
    fc_rx_recv_d[pool][c] = req_d;
    fc_rx_occ_h[pool][c] += h;
    fc_rx_occ_d[pool][c] += d;
    ovf = (PCIe_sequence_item::fc_mod_sub(fc_rx_alloc_h[pool][c], fc_rx_recv_h[pool][c], FC_FSH) > (32'd1 << (FC_FSH - 1))) ||
          (PCIe_sequence_item::fc_mod_sub(fc_rx_alloc_d[pool][c], fc_rx_recv_d[pool][c], FC_FSD) > (32'd1 << (FC_FSD - 1))) ||
          (fc_rx_occ_h[pool][c] > fc_rx_max_h[pool][c]) || (fc_rx_occ_d[pool][c] > fc_rx_max_d[pool][c]);
    if (ovf) fc_rx_overflow_cnt++;
    fc_n_rx_tlp[c]++;
    fc_n_rx_pool[pool][c]++;
    fc_rx_pool_q[c].push_back(pool);
    fc_log($sformatf({"\n  ---- [FC_RX] %s -> class %s (%s pool) : needs %s=%0d %s=%0d ----\n",
        "    %s : CREDIT_LIMIT=%0d CREDITS_CONSUMED=%0d CREDITS_REQUIRED=%0d (LIMIT-REQUIRED) mod 2^%0d = %0d (<= %0d : %s)\n",
        "    %s : CREDIT_LIMIT=%0d CREDITS_CONSUMED=%0d CREDITS_REQUIRED=%0d (LIMIT-REQUIRED) mod 2^%0d = %0d (<= %0d : %s)\n",
        "    receiver now : %s"},
        desc, PCIe_sequence_item::fc_cls_name(c), fc_pool_name(pool),
        PCIe_sequence_item::fc_hdr_name(c), h, PCIe_sequence_item::fc_dat_name(c), d,
        PCIe_sequence_item::fc_hdr_name(c), lim_h, cons_h, req_h, FC_FSH, gap_h, 1 << (FC_FSH-1),
        (gap_h <= (1 << (FC_FSH-1))) ? "OK" : "VIOLATION",
        PCIe_sequence_item::fc_dat_name(c), lim_d, cons_d, req_d, FC_FSD, gap_d, 1 << (FC_FSD-1),
        (d == 0 || gap_d <= (1 << (FC_FSD-1))) ? "OK" : "VIOLATION",
        fc_rx_status(pool, c)));
    if (ovf)
      `uvm_error("RC_TL_FC", $sformatf("RECEIVER_OVERFLOW class=%s pool=%s : TLP exceeds advertised credits (Eq 2-14)",
                 PCIe_sequence_item::fc_cls_name(c), fc_pool_name(pool)))
    fc_publish_status($sformatf("RX_%s", PCIe_sequence_item::fc_cls_name(c)));
  endfunction

  //  Does this pool / class need an UpdateFC now? (spec 2.6.1.2)
  //   MANDATORY_HDR  : header credits available to the peer were 0 and credits were freed
  //   MANDATORY_DATA : data credits available < Rx_MPS_Limit and credits were freed
  //   WATERMARK      : enough freed credits collected -> efficient batch update
  //  The 10 us periodic refresh comes from fc_run_periodic().
  function bit fc_should_update(bit p, int unsigned c);
    int unsigned unadv_h, unadv_d, peer_avail_h, peer_avail_d;
    unadv_h      = PCIe_sequence_item::fc_mod_sub(fc_rx_alloc_h[p][c], fc_rx_adv_h[p][c], FC_FSH);
    unadv_d      = PCIe_sequence_item::fc_mod_sub(fc_rx_alloc_d[p][c], fc_rx_adv_d[p][c], FC_FSD);
    peer_avail_h = PCIe_sequence_item::fc_mod_sub(fc_rx_adv_h[p][c], fc_rx_recv_h[p][c], FC_FSH);
    peer_avail_d = PCIe_sequence_item::fc_mod_sub(fc_rx_adv_d[p][c], fc_rx_recv_d[p][c], FC_FSD);
    if (unadv_h == 0 && unadv_d == 0)                              begin fc_rx_reason = "NOTHING_RELEASED";             return 1'b0; end
    if (unadv_h != 0 && peer_avail_h == 0)                         begin fc_rx_reason = "MANDATORY_HDR(avail=0)";       return 1'b1; end
    if (unadv_d != 0 && peer_avail_d < `PCIe_FC_MPS_CREDITS)       begin fc_rx_reason = "MANDATORY_DATA(avail<MPS)";    return 1'b1; end
    if (unadv_h >= `PCIe_FC_HDR_WATERMARK)                         begin fc_rx_reason = "WATERMARK_HDR";                return 1'b1; end
    if (unadv_d >= `PCIe_FC_DATA_WATERMARK)                        begin fc_rx_reason = "WATERMARK_DATA";               return 1'b1; end
    fc_rx_reason = "BELOW_THRESHOLD";
    return 1'b0;
  endfunction

  // The TL has consumed the TLP : free the buffer space of the pool the TLP
  // used (oldest TLP of the class first), maybe schedule an UpdateFC.
  function void fc_rx_release(int unsigned c, int unsigned h, int unsigned d, string desc);
    bit p;
    if (fc_rx_pool_q[c].size() == 0) begin
      `uvm_error("RC_TL_FC", $sformatf("FC_RX_RELEASE class %s without a matching received TLP (%s)",
                 PCIe_sequence_item::fc_cls_name(c), desc))
      return;
    end
    p = fc_rx_pool_q[c].pop_front();
    fc_rx_occ_h[p][c]   = (fc_rx_occ_h[p][c] > h) ? fc_rx_occ_h[p][c] - h : 0;
    fc_rx_occ_d[p][c]   = (fc_rx_occ_d[p][c] > d) ? fc_rx_occ_d[p][c] - d : 0;
    fc_rx_alloc_h[p][c] = PCIe_sequence_item::fc_mod_add(fc_rx_alloc_h[p][c], h, FC_FSH);
    fc_rx_alloc_d[p][c] = PCIe_sequence_item::fc_mod_add(fc_rx_alloc_d[p][c], d, FC_FSD);
    fc_log($sformatf("[FC_RX_RELEASE] %s class %s (%s) freed %s=%0d %s=%0d -> %s",
        desc, PCIe_sequence_item::fc_cls_name(c), fc_pool_name(p),
        PCIe_sequence_item::fc_hdr_name(c), h, PCIe_sequence_item::fc_dat_name(c), d, fc_rx_status(p, c)));
    if (fc_should_update(p, c)) begin
      fc_publish_update(3'b001 << c, $sformatf("%s_%s", fc_pool_name(p), fc_rx_reason));
    end
    else begin
      fc_log($sformatf("[FC_UPDATE_NOT_SENT] class %s (%s) : %s - not sent per packet",
          PCIe_sequence_item::fc_cls_name(c), fc_pool_name(p), fc_rx_reason));
    end
    fc_publish_status($sformatf("FREE_%s", PCIe_sequence_item::fc_cls_name(c)));
  endfunction

  //--------------------------------------------------------------------------
  // TRANSMITTER
  //--------------------------------------------------------------------------
  // Blocks until a pool passes its gate for this TLP (shared first, then
  // dedicated - see fc_tx_pick_pool). 'pool' tells which one was picked.
  task fc_tx_wait(int unsigned c, int unsigned h, int unsigned d, bit ded_ok, string desc, output bit pool);
    int unsigned waited_ns = 0;
    bit          announced = 0;
    while (!fc_tx_pick_pool(c, h, d, ded_ok, pool)) begin
      if (!announced) begin
        announced = 1; fc_n_blocked++;
        fc_log($sformatf("[FC_TX_BLOCKED] %s class %s needs %s=%0d %s=%0d\n    SHARED    %s\n    DEDICATED %s%s",
            desc, PCIe_sequence_item::fc_cls_name(c), PCIe_sequence_item::fc_hdr_name(c), h,
            PCIe_sequence_item::fc_dat_name(c), d, fc_tx_status(FC_SHR, c), fc_tx_status(FC_DED, c),
            ded_ok ? "" : "  (dedicated not allowed for this TLP)"));
      end
      #10ns;
      waited_ns += 10;
      if (waited_ns > 5 * `PCIe_FC_UPDATE_PERIOD_NS) begin
        `uvm_error("RC_TL_FC", $sformatf("FC_CREDIT_STARVATION : no UpdateFC for %0d ns, sending anyway on %s : SHR %s | DED %s",
                   waited_ns, fc_pool_name(pool), fc_tx_status(FC_SHR, c), fc_tx_status(FC_DED, c)))
        break;
      end
    end
    if (announced) fc_log($sformatf("[FC_TX_UNBLOCKED] %s after %0d ns using %s pool", desc, waited_ns, fc_pool_name(pool)));
  endtask

  // Account the TLP that is being sent : (SHARED_)CREDITS_CONSUMED += this TLP
  function void fc_tx_consume(int unsigned c, int unsigned h, int unsigned d, string desc, bit pool);
    int unsigned req_h, req_d, gap_h, gap_d;
    // one line per TLP : how much room each pool had and why this pool was picked
    fc_log($sformatf({"[FC_POOL_DECISION] %s class %s needs %s=%0d %s=%0d\n",
                      "    SHARED    : AVAIL %s=%0d %s=%0d -> %s\n",
                      "    DEDICATED : AVAIL %s=%0d %s=%0d -> %s\n",
                      "    ==> uses %s pool%s"},
        desc, PCIe_sequence_item::fc_cls_name(c),
        PCIe_sequence_item::fc_hdr_name(c), h, PCIe_sequence_item::fc_dat_name(c), d,
        PCIe_sequence_item::fc_hdr_name(c), fc_tx_avail_h(FC_SHR, c), PCIe_sequence_item::fc_dat_name(c), fc_tx_avail_d(FC_SHR, c),
        fc_tx_can_send(FC_SHR, c, h, d) ? "HAS ROOM" : "FULL",
        PCIe_sequence_item::fc_hdr_name(c), fc_tx_avail_h(FC_DED, c), PCIe_sequence_item::fc_dat_name(c), fc_tx_avail_d(FC_DED, c),
        fc_tx_can_send(FC_DED, c, h, d) ? "HAS ROOM" : "FULL",
        fc_pool_name(pool),
        (fc_pool_mode != 0)  ? $sformatf("  (forced by FC POOL MODE %0d)", fc_pool_mode) :
        (pool == FC_SHR)     ? "  (shared is always tried first, Eq 2-8) -> NO prefix" :
                               "  (because SHARED is FULL, Eq 2-11) -> prefix with TLP Uses Dedicated Credits"));
    req_h = PCIe_sequence_item::fc_mod_add(fc_tx_cons_h[pool][c], h, FC_FSH);
    req_d = PCIe_sequence_item::fc_mod_add(fc_tx_cons_d[pool][c], d, FC_FSD);
    gap_h = PCIe_sequence_item::fc_mod_sub(fc_tx_limit_h[pool][c], req_h, FC_FSH);
    gap_d = PCIe_sequence_item::fc_mod_sub(fc_tx_limit_d[pool][c], req_d, FC_FSD);
    fc_log($sformatf({"\n  ---- [FC_TX%s] %s -> class %s : needs %s=%0d %s=%0d ----\n",
        "    %s : CREDIT_LIMIT=%0d CREDITS_CONSUMED=%0d CREDITS_REQUIRED=%0d (LIMIT-REQUIRED) mod 2^%0d = %0d (<= %0d : %s)\n",
        "    %s : CREDIT_LIMIT=%0d CREDITS_CONSUMED=%0d CREDITS_REQUIRED=%0d (LIMIT-REQUIRED) mod 2^%0d = %0d (<= %0d : %s)"},
        (pool == FC_SHR) ? "-SHR" : "", desc, PCIe_sequence_item::fc_cls_name(c),
        PCIe_sequence_item::fc_hdr_name(c), h, PCIe_sequence_item::fc_dat_name(c), d,
        PCIe_sequence_item::fc_hdr_name(c), fc_tx_limit_h[pool][c], fc_tx_cons_h[pool][c], req_h, FC_FSH, gap_h, 1 << (FC_FSH-1),
        (fc_tx_inf_h[pool][c] || gap_h <= (1 << (FC_FSH-1))) ? "OK" : "VIOLATION",
        PCIe_sequence_item::fc_dat_name(c), fc_tx_limit_d[pool][c], fc_tx_cons_d[pool][c], req_d, FC_FSD, gap_d, 1 << (FC_FSD-1),
        (fc_tx_inf_d[pool][c] || d == 0 || gap_d <= (1 << (FC_FSD-1))) ? "OK" : "VIOLATION"));
    fc_tx_cons_h[pool][c] = req_h;
    fc_tx_cons_d[pool][c] = req_d;
    fc_n_tx_tlp[c]++;
    fc_n_tx_pool[pool][c]++;
    fc_tx_alt_next[c] = ~pool;                       // FC_POOL_MODE 3 : other pool next time
    fc_publish_status($sformatf("TX_%s_%s", PCIe_sequence_item::fc_cls_name(c), (pool == FC_SHR) ? "SHR" : "DED"));
  endfunction

  // DL -> TL : InitFC1 / UpdateFC arrived from the peer. The received (cumulative)
  // CREDITS_ALLOCATED value becomes the new CREDIT_LIMIT (dedicated) or
  // SHARED_CREDIT_LIMIT (shared).
  function void write_fc_from_dl(PCIe_sequence_item it);
    for (int p = 0; p < 2; p++) begin
      for (int c = 0; c < 3; c++) begin
        bit          hit;
        int unsigned old_h, old_d;
        hit = (p == FC_SHR) ? it.fc_cls_mask_shr[c] : it.fc_cls_mask[c];
        if (hit) begin
          old_h = fc_tx_limit_h[p][c];
          old_d = fc_tx_limit_d[p][c];
          fc_tx_limit_h[p][c] = ((p == FC_SHR) ? it.fc_hdr_shr[c] : it.fc_hdr[c]) & ((32'd1 << FC_FSH) - 1);
          fc_tx_limit_d[p][c] = ((p == FC_SHR) ? it.fc_dat_shr[c] : it.fc_dat[c]) & ((32'd1 << FC_FSD) - 1);
          fc_tx_inf_h[p][c]   = (p == FC_SHR) ? it.fc_hdr_inf_shr[c] : it.fc_hdr_inf[c];
          fc_tx_inf_d[p][c]   = (p == FC_SHR) ? it.fc_dat_inf_shr[c] : it.fc_dat_inf[c];
          fc_tx_limit_valid[p][c] = 1'b1;
          if (it.fc_kind == FC_PEER_UPDATE) fc_n_peer_upd++;
          fc_log($sformatf("[FC_%s%s] class %s : CREDIT_LIMIT %s %0d -> %0d (+%0d)  %s %0d -> %0d (+%0d) | CONSUMED %s=%0d %s=%0d | AVAILABLE %s=%0d %s=%0d",
              (it.fc_kind == FC_PEER_INIT) ? "INITFC1_RX" : "UPDATEFC_RX", (p == FC_SHR) ? "-SHR" : "",
              PCIe_sequence_item::fc_cls_name(c),
              PCIe_sequence_item::fc_hdr_name(c), old_h, fc_tx_limit_h[p][c], PCIe_sequence_item::fc_mod_sub(fc_tx_limit_h[p][c], old_h, FC_FSH),
              PCIe_sequence_item::fc_dat_name(c), old_d, fc_tx_limit_d[p][c], PCIe_sequence_item::fc_mod_sub(fc_tx_limit_d[p][c], old_d, FC_FSD),
              PCIe_sequence_item::fc_hdr_name(c), fc_tx_cons_h[p][c], PCIe_sequence_item::fc_dat_name(c), fc_tx_cons_d[p][c],
              PCIe_sequence_item::fc_hdr_name(c), fc_tx_avail_h(p, c), PCIe_sequence_item::fc_dat_name(c), fc_tx_avail_d(p, c)));
        end
      end
    end
    fc_publish_status("PEER_CREDITS");
  endfunction

  function void fc_report();
    fc_log($sformatf({"\n  ========== RC_TL FLOW CONTROL SUMMARY ==========\n",
        "  FC POOL MODE   : %0d (%s)\n",
        "  TLPs received  : P=%0d NP=%0d CPL=%0d\n",
        "  TLPs sent      : P=%0d NP=%0d CPL=%0d\n",
        "  TLPs by pool   : sent     P ded=%0d shr=%0d | NP ded=%0d shr=%0d | CPL ded=%0d shr=%0d\n",
        "                   received P ded=%0d shr=%0d | NP ded=%0d shr=%0d | CPL ded=%0d shr=%0d\n",
        "  dedicated prefix (%08h) : sent=%0d received=%0d\n",
        "  UpdateFC scheduled by this TL : %0d (periodic=%0d)  UpdateFC received from peer : %0d\n",
        "  TX blocked by credits : %0d   receiver overflows : %0d\n",
        "  TLPs still in RX buffer : P=%0d NP=%0d CPL=%0d   gated but not accounted : %0d"},
        fc_pool_mode,
        (fc_pool_mode == 1) ? "DEDICATED" : (fc_pool_mode == 2) ? "SHARED" :
        (fc_pool_mode == 3) ? "ALTERNATE" : "SPEC : shared first, then dedicated",
        fc_n_rx_tlp[0], fc_n_rx_tlp[1], fc_n_rx_tlp[2], fc_n_tx_tlp[0], fc_n_tx_tlp[1], fc_n_tx_tlp[2],
        fc_n_tx_pool[FC_DED][0], fc_n_tx_pool[FC_SHR][0], fc_n_tx_pool[FC_DED][1], fc_n_tx_pool[FC_SHR][1],
        fc_n_tx_pool[FC_DED][2], fc_n_tx_pool[FC_SHR][2],
        fc_n_rx_pool[FC_DED][0], fc_n_rx_pool[FC_SHR][0], fc_n_rx_pool[FC_DED][1], fc_n_rx_pool[FC_SHR][1],
        fc_n_rx_pool[FC_DED][2], fc_n_rx_pool[FC_SHR][2],
        `PCIe_FC_DED_PREFIX_DW, fc_n_pfx_tx, fc_n_pfx_rx,
        fc_n_upd_published, fc_n_periodic, fc_n_peer_upd, fc_n_blocked, fc_rx_overflow_cnt,
        fc_rx_pool_q[0].size(), fc_rx_pool_q[1].size(), fc_rx_pool_q[2].size(), fc_tx_pool_aa.num()));
    fc_print_buffers("FINAL");
  endfunction


  function new(string name="PCIe_RC_TL_model", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info("RC_TL_MODEL","ENTERED_INTO_RC_TL_MODEL_BUILD_PHASE",UVM_LOW)
     tx_tl_imp = new("tx_tl_imp", this);
     tlp_dl_ap  = new("tlp_dl_ap",  this);
     tl_ap  = new("tl_ap",  this);
     fc_dl_ap  = new("fc_dl_ap",  this);
     fc_dl_imp = new("fc_dl_imp", this);
     dl_tl_imp = new("dl_tl_imp", this);   // [ADDED] DL -> TL received TLP path
     n_tlp_rcvd = 0;
     n_cpl_rcvd = 0;
     n_seg_txn      = 0;   // [FLIT_SEG]
     n_seg_tlp      = 0;
     n_seg_txn_done = 0;
     fc_init();
    `uvm_info("RC_TL_MODEL","EXIT_FROM_RC_TL_MODEL_BUILD_PHASE",UVM_LOW)
  endfunction

  // FLOW CONTROL : all connections are made by now - advertise the six TL buffers to the DL
  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    fc_publish_init();
  endfunction

  // FLOW CONTROL : periodic UpdateFC refresh timer
  task run_phase(uvm_phase phase);
    fc_run_periodic();
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    fc_report();
    `uvm_info("RC_TL_MODEL", $sformatf("RX_FROM_DL_SUMMARY : TLPs received from RC DL=%0d  completions=%0d  outstanding requests still open=%0d",
              n_tlp_rcvd, n_cpl_rcvd, outstanding.size()), UVM_LOW)
    // [FLIT_SEG] summary + every segmented Non-Posted request must be fully completed
    `uvm_info("RC_TL_FLIT_SEG", $sformatf("FLIT_SEGMENTATION_SUMMARY : transactions split=%0d  segment TLPs sent=%0d  segmented Non-Posted txns fully completed=%0d",
              n_seg_txn, n_seg_tlp, n_seg_txn_done), UVM_LOW)
    `uvm_info("RC_TL_FULL_CPLD", $sformatf("READ_COMPLETION_SUMMARY : reads completed=%0d  DW match=%0d  DW mismatch=%0d  DW never written=%0d  partial CplD still waiting=%0d",
              n_rd_cpl_checked, n_rd_cpl_dw_match, n_rd_cpl_dw_mismatch, n_rd_cpl_dw_unwritten, cpl_partial.size()), UVM_LOW)
    if (cpl_partial.size() != 0)
      `uvm_error("RC_TL_FULL_CPLD", $sformatf("%0d read completion(s) never received their last CplD part", cpl_partial.size()))
    foreach (seg_cpl_expect[ptag]) begin
      if (seg_cpl_got[ptag] != seg_cpl_expect[ptag])
        `uvm_error("RC_TL_FLIT_SEG", $sformatf("SEGMENTED_REQUEST_NOT_FULLY_COMPLETED : parent tag=0x%0h got %0d of %0d completions",
                   ptag, seg_cpl_got[ptag], seg_cpl_expect[ptag]))
    end
  endfunction

  //==========================================================================
  // [ADDED] write_dl_rx : RC DL model -> RC TL model
  //
  //   The RC DL model has already stripped the 6 DLP bytes off the 242 byte flit
  //   (and only forwards GOOD payload flits), so item.tlp_data is the 236 byte TLP
  //   region. Flit Mode completion header layout (same as EP build_completion):
  //     DW0 [31:24] type  [23:21] TC  [20:16] OHC  [15:13] TS  [12:10] Attr  [9:0] Length
  //     DW1 [31:16] Completer ID  [15] EP  [14] LowerAddr[6]  [13:0] Tag
  //     DW2 [31:16] Requester(Dest) ID  [15:12] LowerAddr[5:2]  [11:0] Byte Count
  //     DW3 OHC-A5 (only when OHC[0]=1), then payload
  //==========================================================================
  function bit [31:0] rc_rx_get_dw(PCIe_sequence_item it, int dw_index);
    int b;
    b = dw_index * `PCIe_TL_DW_BYTES;
    if ((b + 3) >= `PCIe_TLP_DATA_BYTE_W)
      return 32'd0;
    return {it.tlp_data[b], it.tlp_data[b+1], it.tlp_data[b+2], it.tlp_data[b+3]};
  endfunction

  function void write_dl_rx(PCIe_sequence_item item);
    bit [31:0]         dw0, dw1, dw2, dw3, d0;
    bit [7:0]          ftype;
    bit [2:0]          tc, ts, attr;
    bit [4:0]          ohc;
    bit [9:0]          len;
    bit [15:0]         cplr_id, req_id;
    bit                ep_bit;
    bit [13:0]         tag;
    bit [11:0]         bc;
    bit [3:0]          la_hi;
    bit                is_cpl;
    bit                has_data;
    int unsigned       hdr_dw, payload_dw;
    string             kind;
    PCIe_sequence_item cpl_it;
    bit                fc_pool;                // [FC SHARED] pool given by the prefix
    int unsigned       fc_c, fc_h, fc_d;       // [FC SHARED] credits of this completion

    n_tlp_rcvd++;

    // [FC SHARED] Flit Mode Local TLP Prefix : read "TLP Uses Dedicated Credits", remove it
    fc_pool = fc_strip_prefix(item);

    `uvm_info("RC_TL_MODEL",
      $sformatf("RECEIVED_236B_TLP_FROM_RC_DL_MODEL #%0d mode=%s",
                 n_tlp_rcvd, item.pkt_mode.name()), UVM_LOW)

    dw0 = rc_rx_get_dw(item, 0);
    dw1 = rc_rx_get_dw(item, 1);
    dw2 = rc_rx_get_dw(item, 2);
    dw3 = rc_rx_get_dw(item, 3);

    `uvm_info("RC_TL_MODEL",
      $sformatf("RX_TLP_DW : DW0=%08h DW1=%08h DW2=%08h DW3=%08h", dw0, dw1, dw2, dw3), UVM_LOW)

    ftype  = dw0[31:24];
    is_cpl = (ftype == `PCIe_FLITTYPE_CPL) || (ftype == `PCIe_FLITTYPE_CPLD);

    if (!is_cpl) begin
      `uvm_info("RC_TL_MODEL",
        $sformatf("RX_TLP_IS_NOT_A_COMPLETION : type byte0=0x%02h (no completion decode)", ftype), UVM_LOW)
      return;
    end

    n_cpl_rcvd++;
    has_data   = (ftype == `PCIe_FLITTYPE_CPLD);
    tc         = dw0[23:21];
    ohc        = dw0[20:16];
    ts         = dw0[15:13];
    attr       = dw0[12:10];
    len        = dw0[9:0];
    cplr_id    = dw1[31:16];
    ep_bit     = dw1[15];
    tag        = dw1[13:0];
    req_id     = dw2[31:16];
    la_hi      = dw2[15:12];
    bc         = dw2[11:0];
    hdr_dw     = 3 + (ohc[0] ? 1 : 0);
    payload_dw = has_data ? ((len == 10'd0) ? `PCIe_TL_MAX_PAYLOAD_DW : int'(len)) : 0;
    d0         = rc_rx_get_dw(item, hdr_dw);
    kind       = has_data ? "CplD (with data)" : "Cpl (no data)";

    `uvm_info("RC_TL_COMPLETION",
      $sformatf({"\n",
        "         ============================================================\n",
        "                  RC TL MODEL : RECEIVED COMPLETION  (from RC DL model)\n",
        "         ============================================================\n",
        "         Packet Mode       : %s\n",
        "         Completion Type   : %s (type byte 0x%02h)\n",
        "         Completer ID      : 0x%04h\n",
        "         Requester ID      : 0x%04h\n",
        "         Tag               : 0x%04h\n",
        "         TC / Attr / TS    : %0d / %03b / %03b\n",
        "         EP                : %0b\n",
        "         Byte Count        : %0d (0x%03h)\n",
        "         Lower Address[6:2]: 0x%02h (bits 5:2 = 0x%01h)\n",
        "         Length            : %0d DW\n",
        "         OHC               : %05b (OHC-A5 present : %s)\n",
        "         Header DWs        : %0d   Payload DWs : %0d\n",
        "         First payload DW  : %08h\n",
        "         ============================================================"},
        item.pkt_mode.name(), kind, ftype, cplr_id, req_id, tag,
        tc, attr, ts, ep_bit, bc, bc, {dw1[14], la_hi}, la_hi, len,
        ohc, ohc[0] ? "YES" : "NO", hdr_dw, payload_dw, d0), UVM_LOW)

    // [FC SHARED] RECEIVER side : the completion takes the RC CPL buffer of the
    // pool given by the prefix, and is consumed right away (the RC TL keeps the
    // data in its own tables), so the credits are given back at once.
    PCIe_sequence_item::fc_classify(PCIe_TL_CPL, PCIe_TL_READ, 1'b0, payload_dw, fc_c, fc_h, fc_d);
    fc_rx_account(fc_c, fc_h, fc_d, $sformatf("RX %s tag=0x%0h len=%0d", kind, tag, payload_dw), fc_pool);
    fc_rx_release(fc_c, fc_h, fc_d, $sformatf("RX %s tag=0x%0h len=%0d", kind, tag, payload_dw));

    // Build the completion item and hand it to the existing cpl_write() so the
    // matching outstanding request (by tag) is closed.
    cpl_it = PCIe_sequence_item::type_id::create("rc_rx_cpl");
    cpl_it.pkt_mode      = item.pkt_mode;
    cpl_it.txn_type      = PCIe_TL_CPL;
    cpl_it.is_completion = 1'b1;
    cpl_it.cpl_has_data  = has_data;
    cpl_it.cpl_status    = ohc[0] ? dw3[`PCIe_TL_OHCA5_STATUS_HI : `PCIe_TL_OHCA5_STATUS_LO]
                                  : `PCIe_CPL_STATUS_SC;
    cpl_it.tag           = tag[`PCIe_TL_TAG_W-1:0];
    cpl_it.requester_id  = req_id;
    cpl_it.completer_id  = cplr_id;
    cpl_it.length        = len;
    cpl_it.byte_count    = bc;
    cpl_it.cpl_data      = new[payload_dw];
    for (int i = 0; i < payload_dw; i++)
      cpl_it.cpl_data[i] = rc_rx_get_dw(item, hdr_dw + i);

    if (outstanding.exists(cpl_it.tag) && !cpl_req_of.exists(cpl_it.tag))
      cpl_req_of[cpl_it.tag] = outstanding[cpl_it.tag];
    if (has_data) begin
      if (cpl_part_cnt.exists(cpl_it.tag)) cpl_part_cnt[cpl_it.tag]++;
      else                                 cpl_part_cnt[cpl_it.tag] = 1;
    end

    cpl_write(cpl_it);

    // [FLIT_SEG] CplD split over several FLITs : Byte Count is the number of
    // bytes still to come INCLUDING this CplD (000h = 4096). Not the last part
    // -> keep the data and wait for the rest before publishing.
    begin
      int unsigned bc_val;
      bc_val = (bc == 12'h000) ? 4096 : int'(bc);
      if (has_data && (bc_val > payload_dw * `PCIe_TL_DW_BYTES)) begin
        if (cpl_partial.exists(cpl_it.tag))
          cpl_partial[cpl_it.tag].cpl_data = {cpl_partial[cpl_it.tag].cpl_data, cpl_it.cpl_data};
        else
          cpl_partial[cpl_it.tag] = cpl_it;
        `uvm_info("RC_TL_FLIT_SEG",
          $sformatf("PARTIAL_CPLD tag=0x%0h : %0d DW in this FLIT, Byte Count still to come=%0d -> waiting for the next CplD (collected %0d DW)",
                    cpl_it.tag, payload_dw, bc_val, cpl_partial[cpl_it.tag].cpl_data.size()), UVM_LOW)
        return;
      end
      if (cpl_partial.exists(cpl_it.tag)) begin
        cpl_it.cpl_data = {cpl_partial[cpl_it.tag].cpl_data, cpl_it.cpl_data};
        cpl_partial.delete(cpl_it.tag);
        `uvm_info("RC_TL_FLIT_SEG",
          $sformatf("LAST_CPLD tag=0x%0h : split completion reassembled, total %0d DW", cpl_it.tag, cpl_it.cpl_data.size()), UVM_LOW)
      end
      if (has_data) begin
        print_full_read_completion(cpl_it, cpl_part_cnt[cpl_it.tag],
                                   cpl_req_of.exists(cpl_it.tag) ? cpl_req_of[cpl_it.tag] : null);
        cpl_part_cnt.delete(cpl_it.tag);
      end
      cpl_req_of.delete(cpl_it.tag);
    end

    // [ENUM] keep it for the sequence that is waiting on this tag
    if (cpl_rcvd.exists(cpl_it.tag))
      `uvm_warning("RC_TL_MODEL", $sformatf("DUPLICATE_COMPLETION tag=0x%0h - older one replaced", cpl_it.tag))
    cpl_rcvd[cpl_it.tag] = cpl_it;
    -> cpl_event;
  endfunction

  //--------------------------------------------------------------------------
  // [FLIT_SEG] print_full_read_completion
  //   Called once per Memory Read when the LAST CplD part has arrived. Shows
  //   the whole data payload the RC TL received (e.g. 1024 DW collected from
  //   19 CplD FLITs) and checks every DW against what the RC wrote earlier to
  //   the same address (wr_shadow). DWs never written are reported, not failed.
  //--------------------------------------------------------------------------
  function void print_full_read_completion(PCIe_sequence_item cpl, int unsigned n_parts,
                                           PCIe_sequence_item req);
    string       dump, line;
    bit [63:0]   base_dw;
    int unsigned n_match, n_mis, n_unw;
    bit          have_req;

    // data check only for Memory Reads (Config / IO reads have no RC write to compare with)
    have_req = (req != null) && (req.txn_type == PCIe_TL_MEM);
    base_dw  = have_req ? (64'(req.address) >> 2) : 64'h0;
    n_match  = 0; n_mis = 0; n_unw = 0;

    dump = "\n";
    for (int i = 0; i < cpl.cpl_data.size(); i++) begin
      if ((i % 8) == 0) line = $sformatf("           DW[%4d] :", i);
      line = {line, $sformatf(" %08h", cpl.cpl_data[i])};
      if (((i % 8) == 7) || (i == cpl.cpl_data.size() - 1)) dump = {dump, line, "\n"};

      if (have_req) begin
        if (!wr_shadow.exists(base_dw + i))           n_unw++;
        else if (wr_shadow[base_dw + i] == cpl.cpl_data[i]) n_match++;
        else begin
          n_mis++;
          if (n_mis <= 10)
            `uvm_error("RC_TL_RD_CHECK", $sformatf("READ_DATA_MISMATCH tag=0x%0h DW[%0d] addr=0x%0h : read=%08h written=%08h",
                       cpl.tag, i, (base_dw + i) << 2, cpl.cpl_data[i], wr_shadow[base_dw + i]))
        end
      end
    end

    n_rd_cpl_checked++;
    n_rd_cpl_dw_match     += n_match;
    n_rd_cpl_dw_mismatch  += n_mis;
    n_rd_cpl_dw_unwritten += n_unw;

    `uvm_info("RC_TL_FULL_CPLD",
      $sformatf({"\n",
        "         ============================================================================\n",
        "              RC TL MODEL : FULL READ COMPLETION RECEIVED (all CplD parts joined)\n",
        "         ============================================================================\n",
        "          Tag                : 0x%0h\n",
        "          Request            : MRd addr=0x%0h  %0d DW\n",
        "          CplD FLITs received: %0d\n",
        "          Total data         : %0d DW (%0d B)\n",
        "          Status             : %s\n",
        "          Check vs RC writes : %0d DW match, %0d DW mismatch, %0d DW never written by RC\n",
        "         ----------------------------------------------------------------------------\n",
        "          DATA%s",
        "         ============================================================================"},
        cpl.tag,
        have_req ? req.address : '0, have_req ? req.get_payload_dw() : 0,
        n_parts,
        cpl.cpl_data.size(), cpl.cpl_data.size() * `PCIe_TL_DW_BYTES,
        cpl_status_str(cpl.cpl_status),
        n_match, n_mis, n_unw,
        dump), UVM_LOW)

    if (have_req && (cpl.cpl_data.size() != req.get_payload_dw()))
      `uvm_error("RC_TL_RD_CHECK", $sformatf("READ_LENGTH_MISMATCH tag=0x%0h : requested %0d DW, completions returned %0d DW",
                 cpl.tag, req.get_payload_dw(), cpl.cpl_data.size()))
  endfunction

  //--------------------------------------------------------------------------
  // [ENUM] wait_completion : block until the completion for 'tag' arrives
  //   (stored by write_dl_rx) or timeout_ns passes. It is removed from cpl_rcvd.
  //--------------------------------------------------------------------------
  task wait_completion(input  bit [`PCIe_TL_TAG_W-1:0] tag,
                       input  int unsigned               timeout_ns,
                       output PCIe_sequence_item         cpl,
                       output bit                        timed_out);
    cpl       = null;
    timed_out = 1'b0;
    // outer fork..join keeps "disable fork" from touching any other process
    fork begin
      fork
        begin : wait_for_tag
          while (!cpl_rcvd.exists(tag)) @(cpl_event);
        end
        begin : wait_timer
          #(timeout_ns * 1ns);
        end
      join_any
      disable fork;
    end join
    if (cpl_rcvd.exists(tag)) begin
      cpl = cpl_rcvd[tag];
      cpl_rcvd.delete(tag);
    end
    else begin
      timed_out = 1'b1;
    end
  endtask

  // [ENUM] completion status name for the log
  function string cpl_status_str(bit [2:0] st);
    case (st)
      `PCIe_CPL_STATUS_SC  : return "SC";
      `PCIe_CPL_STATUS_UR  : return "UR";
      `PCIe_CPL_STATUS_CRS : return "CRS";
      `PCIe_CPL_STATUS_CA  : return "CA";
      default              : return $sformatf("RSVD(%0b)", st);
    endcase
  endfunction

  //==========================================================================
  // [ATTR] ATTRIBUTE TABLE CHECK - info prints only (does not change any bit)
  //   PCIe Base 6.x Sec 2.2.6.4 Table 2-12 (RO / IDO) , Sec 2.2.6.5 Table 2-13 (NS)
  //     Attr[2] = IDO (ID-Based Ordering)
  //     Attr[1] = RO  (Relaxed Ordering)
  //     Attr[0] = NS  (No Snoop)
  //   Called from send_tlp() just before pack_to_tlp_data() (the 236B TL packet print).
  //==========================================================================
  function void print_attr_table_check(PCIe_sequence_item tr);
    string seq_name;
    string ord_type, ord_model;
    string snp_type, snp_model;

    // name of the sequence that sent this item (item name if no parent)
    if (tr.get_parent_sequence() != null)
      seq_name = tr.get_parent_sequence().get_name();
    else
      seq_name = tr.get_name();

    `uvm_info("RC_TL_ATTR",
      $sformatf("ENTERED_ATTR_CHECK : sequence=%s  %s %s tag=0x%0h  attr[2:0]=%03b",
                seq_name, tr.pkt_mode.name(), tr.txn_type.name(), tr.tag, tr.attr), UVM_LOW)

    //------------------------------------------------------------------------
    // Table 2-12 : Ordering Attributes  ->  {Attr[2] IDO , Attr[1] RO}
    //------------------------------------------------------------------------
    case ({tr.attr[2], tr.attr[1]})
      2'b00 : begin ord_type = "Default Ordering";
                    ord_model = "PCI Strongly Ordered Model"; end
      2'b01 : begin ord_type = "Relaxed Ordering";
                    ord_model = "PCI-X Relaxed Ordering Model"; end
      2'b10 : begin ord_type = "ID-Based Ordering";
                    ord_model = "Independent ordering based on Requester/Completer ID"; end
      2'b11 : begin ord_type = "Relaxed Ordering plus ID-Based Ordering";
                    ord_model = "Logical OR of Relaxed Ordering and IDO"; end
    endcase

    `uvm_info("RC_TL_ATTR",
      $sformatf("RO_CHECK  : sequence=%s is RO=%0b  -> Relaxed Ordering %s",
                seq_name, tr.attr[1], tr.attr[1] ? "ENABLED" : "DISABLED"), UVM_LOW)

    `uvm_info("RC_TL_ATTR",
      $sformatf("IDO_CHECK : sequence=%s is IDO=%0b -> ID-Based Ordering %s",
                seq_name, tr.attr[2], tr.attr[2] ? "ENABLED" : "DISABLED"), UVM_LOW)

    `uvm_info("RC_TL_ATTR",
      $sformatf("RO_IDO_ORDERING_ATTRIBUTES_TABLE_CHECKED : IDO(Attr[2])=%0b RO(Attr[1])=%0b -> Ordering Type = %s | Ordering Model = %s",
                tr.attr[2], tr.attr[1], ord_type, ord_model), UVM_LOW)

    //------------------------------------------------------------------------
    // Table 2-13 : Cache Coherency Management Attribute  ->  Attr[0] NS
    //------------------------------------------------------------------------
    if (tr.attr[0]) begin
      snp_type  = "No Snoop";
      snp_model = "Hardware enforced cache coherency not expected";
    end
    else begin
      snp_type  = "Default";
      snp_model = "Hardware enforced cache coherency expected";
    end

    `uvm_info("RC_TL_ATTR",
      $sformatf("NO_SNOOP_ATTRIBUTE_TABLE_CHECKED : No Snoop(Attr[0])=%0b -> Cache Coherency Management Type = %s | Coherency Model = %s",
                tr.attr[0], snp_type, snp_model), UVM_LOW)

    `uvm_info("RC_TL_ATTR",
      $sformatf("ATTR_CHECK_DONE : sequence=%s is RO=%0b IDO=%0b NS=%0b , checked Ordering Attributes table (RO / IDO) and No Snoop Attribute table",
                seq_name, tr.attr[1], tr.attr[2], tr.attr[0]), UVM_LOW)
  endfunction


  function bit fc_applies(PCIe_sequence_item tr);
    return !((tr.pkt_mode == FLIT) && (tr.flit_type != PCIe_PAYLOAD_flit));
  endfunction

  // [FC SHARED] may this TLP use DEDICATED credits ?
  //   Flit Mode only (the prefix is not allowed on a Non-Flit TLP), and the
  //   1 DW prefix must still fit in the 236 B (59 DW) TLP region.
  function bit fc_ded_allowed(PCIe_sequence_item tr);
    int unsigned hb_dw, ohc_dw, trl_dw;
    if (tr.pkt_mode != FLIT) return 1'b0;
    flit_seg_overhead(tr, hb_dw, ohc_dw, trl_dw);
    return ((hb_dw + ohc_dw + trl_dw + tr.data.size() + 1) <= `PCIe_FLIT_TLP_REGION_DW);
  endfunction

  // Called by the RC controller driver BEFORE the TLP is handed to the TL:
  // blocks until a pool passes its gate for this TLP (shared Eq 2-8 first,
  // then dedicated Eq 2-11). The pool is kept for fc_account_tlp / the prefix.
  task wait_for_fc_credits(PCIe_sequence_item tr);
    int unsigned c, h, d;
    bit          pool;
    if (!fc_applies(tr)) return;
    PCIe_sequence_item::fc_classify(tr.txn_type, tr.dir, tr.mem_deferrable, tr.data.size(), c, h, d);
    fc_tx_wait(c, h, d, fc_ded_allowed(tr), tr.convert2string(), pool);
    fc_tx_pool_aa[tr] = pool;
    fc_log($sformatf("[FC_TX_POOL] %s class %s -> %s pool picked by the gate",
           tr.convert2string(), PCIe_sequence_item::fc_cls_name(c), fc_pool_name(pool)));
  endtask

  // [FC SHARED] pool of this TLP (from the gate, or picked now when the gate
  // was not called) + the dedicated prefix when it uses dedicated credits.
  // Called by send_tlp after the ECRC and before the FLIT region is built.
  function void fc_tx_prepare_pool(PCIe_sequence_item tr);
    int unsigned c, h, d;
    bit          pool;
    if (!fc_applies(tr)) return;
    if (!fc_tx_pool_aa.exists(tr)) begin
      PCIe_sequence_item::fc_classify(tr.txn_type, tr.dir, tr.mem_deferrable, tr.data.size(), c, h, d);
      if (!fc_tx_pick_pool(c, h, d, fc_ded_allowed(tr), pool))
        `uvm_error("RC_TL_FC", $sformatf("TLP_SENT_WITHOUT_CREDITS (gate not called?) %s : SHR %s | DED %s",
                   tr.convert2string(), fc_tx_status(FC_SHR, c), fc_tx_status(FC_DED, c)))
      fc_tx_pool_aa[tr] = pool;
      fc_log($sformatf("[FC_TX_POOL] %s class %s -> %s pool (picked at send time)",
             tr.convert2string(), PCIe_sequence_item::fc_cls_name(c), fc_pool_name(pool)));
    end
    if ((tr.pkt_mode == FLIT) && (fc_tx_pool_aa[tr] == FC_DED))
      fc_add_ded_prefix(tr);
  endfunction

  // Account the TLP being sent ((SHARED_)CREDITS_CONSUMED) on the pool picked above
  function void fc_account_tlp(PCIe_sequence_item tr);
    int unsigned c, h, d;
    bit          pool;
    if (!fc_applies(tr)) return;
    PCIe_sequence_item::fc_classify(tr.txn_type, tr.dir, tr.mem_deferrable, tr.data.size(), c, h, d);
    if (fc_tx_pool_aa.exists(tr)) begin
      pool = fc_tx_pool_aa[tr];
      fc_tx_pool_aa.delete(tr);
    end
    else
      pool = FC_SHR;
    fc_tx_consume(c, h, d, tr.convert2string(), pool);
  endfunction

  //==========================================================================
  // [FLIT_SEG] FLIT-MODE TLP SEGMENTATION
  //
  //   One FLIT has a 236 byte (59 DW) TLP region. Header Base + OHC + Payload
  //   (+ 1 DW ECRC trailer when TS = 001b) must all fit inside it. A Memory
  //   Write / Deferrable Memory Write whose payload does not fit is split into
  //   N complete TLPs (each with its own header, address advanced by the bytes
  //   already sent) and every TLP is sent in its own FLIT. The last TLP carries
  //   the remainder; the unused bytes of its FLIT are NOP TLPs (all zeros).
  //
  //     max payload/TLP = 59 - HeaderBase(3|4) - OHC(0|1) - ECRC(0|1)  DW
  //     TLPs            = ceil(payload_dw / max payload/TLP)
  //
  //   1024 DW (4096 B), no ECRC :
  //     3DW       : 56 DW/TLP -> 19 TLPs, last 16 DW , 160 B unused
  //     4DW       : 55 DW/TLP -> 19 TLPs, last 34 DW , 84 B unused
  //     3DW + OHC : 55 DW/TLP -> 19 TLPs, last 34 DW , 84 B unused
  //     4DW + OHC : 54 DW/TLP -> 19 TLPs, last 52 DW , 8 B unused
  //
  //   Posted MWr  : every segment keeps the request tag.
  //   DMWr (Non-Posted) : every segment gets its own tag (tag, tag+1, ...)
  //   because each one is a separate request that receives its own Cpl. The
  //   completions are tracked back to the original request (seg_parent_of).
  //==========================================================================

  // Header Base / OHC / trailer DWs the request needs (same rules as
  // serialize_flit_header / serialize_ohc / append_ecrc)
  function void flit_seg_overhead(PCIe_sequence_item tr,
                                  output int unsigned hb_dw,
                                  output int unsigned ohc_dw,
                                  output int unsigned trl_dw);
    hb_dw  = tr.is_64bit_addr() ? `PCIe_TL_HDR4DW : `PCIe_TL_HDR3DW;
    tr.determine_ohc_a();
    ohc_dw = (tr.ohc_a_type != OHC_A_NONE) ? `PCIe_TL_OHC_A_DW : 0;
    trl_dw = ((tr.ts == `PCIe_TL_TS_1DW_ECRC) || (tr.td == 1'b1)) ? `PCIe_TL_ECRC_DW : 0;
  endfunction

  // 1 => this FLIT-mode request does not fit in one 236 byte TLP region
  function bit flit_needs_segmentation(PCIe_sequence_item tr);
    int unsigned hb_dw, ohc_dw, trl_dw;
    if (tr == null)                            return 1'b0;
    if (tr.pkt_mode != FLIT)                   return 1'b0;
    if (tr.flit_type != PCIe_PAYLOAD_flit)     return 1'b0;
    if (tr.is_flit_segment)                    return 1'b0;
    if (!((tr.txn_type == PCIe_TL_MEM) && (tr.dir == PCIe_TL_WRITE))) return 1'b0;
    flit_seg_overhead(tr, hb_dw, ohc_dw, trl_dw);
    return ((hb_dw + ohc_dw + trl_dw + tr.data.size()) > `PCIe_FLIT_TLP_REGION_DW);
  endfunction

  // Copy every request field a segment needs from the parent request
  function void flit_seg_copy_fields(PCIe_sequence_item src, PCIe_sequence_item dst);
    dst.pkt_mode             = src.pkt_mode;
    dst.target_gen           = src.target_gen;
    dst.directed_recovery    = src.directed_recovery;
    dst.txn_type             = src.txn_type;
    dst.dir                  = src.dir;
    dst.mem_locked           = src.mem_locked;
    dst.mem_deferrable       = src.mem_deferrable;
    dst.requester_id         = src.requester_id;
    dst.completer_id         = src.completer_id;
    dst.tc                   = src.tc;
    dst.attr                 = src.attr;
    dst.td                   = src.td;
    dst.ep                   = src.ep;
    dst.ts                   = src.ts;
    dst.at                   = src.at;
    dst.cfg_reg_num          = src.cfg_reg_num;
    dst.cfg_ext_reg_num      = src.cfg_ext_reg_num;
    dst.cfg_bus_num          = src.cfg_bus_num;
    dst.cfg_dev_num          = src.cfg_dev_num;
    dst.cfg_fn_num           = src.cfg_fn_num;
    dst.cfg_type1            = src.cfg_type1;
    dst.io_data              = src.io_data;
    dst.msg_code             = src.msg_code;
    dst.msg_route            = src.msg_route;
    dst.msg_has_data         = src.msg_has_data;
    dst.flit_type            = src.flit_type;
    dst.electrical_idle_test = src.electrical_idle_test;
    dst.no_receiver_test     = src.no_receiver_test;
    dst.tx_elec_idle         = src.tx_elec_idle;
    dst.tx_valid             = src.tx_valid;
    dst.rate                 = src.rate;
    dst.dllp_content         = src.dllp_content;
    dst.credit               = src.credit;
  endfunction

  //--------------------------------------------------------------------------
  // split_flit_tlp : parent request -> segs[] (one complete TLP per FLIT)
  //   Called by the RC controller driver; the driver sends segs[i] through
  //   the normal TL -> DL -> PL path and drives one FLIT per segment.
  //--------------------------------------------------------------------------
  function void split_flit_tlp(PCIe_sequence_item tr, ref PCIe_sequence_item segs[$]);
    int unsigned hb_dw, ohc_dw, trl_dw;
    int unsigned total_dw, max_dw, n_seg, off_dw, len_dw, last_dw, used_b;
    bit [`PCIe_TL_TAG_W-1:0] seg_tag;
    bit                      non_posted;
    PCIe_sequence_item       seg;
    string                   rows;

    segs.delete();
    flit_seg_overhead(tr, hb_dw, ohc_dw, trl_dw);

    total_dw   = tr.data.size();
    max_dw     = PCIe_sequence_item::flit_seg_max_payload_dw(hb_dw, ohc_dw, trl_dw);
    n_seg      = PCIe_sequence_item::flit_seg_count(total_dw, max_dw);
    non_posted = is_non_posted(tr);

    if (n_seg == 0) begin
      `uvm_error("RC_TL_FLIT_SEG", $sformatf("CANNOT_SEGMENT : header+OHC+trailer=%0d DW leave no payload room in the %0d DW region",
                 hb_dw + ohc_dw + trl_dw, `PCIe_FLIT_TLP_REGION_DW))
      return;
    end

    last_dw = total_dw - ((n_seg - 1) * max_dw);
    rows    = "";
    off_dw  = 0;

    for (int unsigned i = 0; i < n_seg; i++) begin
      len_dw = ((total_dw - off_dw) > max_dw) ? max_dw : (total_dw - off_dw);

      seg = PCIe_sequence_item::type_id::create($sformatf("%s_seg%0d", tr.get_name(), i));
      flit_seg_copy_fields(tr, seg);

      seg.address = tr.address + (off_dw * `PCIe_TL_DW_BYTES);
      seg.length  = len_dw[`PCIe_TL_LEN_W-1:0];          // <= 56, never needs the 0 => 1024 encoding

      seg.data = new[len_dw];
      for (int unsigned k = 0; k < len_dw; k++)
        seg.data[k] = tr.data[off_dw + k];

      // Byte enables : the original First DW BE on the first segment, the
      // original Last DW BE on the last segment, all bytes in between.
      seg.first_dw_be = (i == 0)         ? tr.first_dw_be : 4'hF;
      seg.last_dw_be  = (i == n_seg - 1) ? tr.last_dw_be  : 4'hF;
      if (len_dw == 1) begin
        // 1 DW TLP : Last DW BE must be 0000b, the last-byte enables move into First DW BE
        if (i == n_seg - 1) seg.first_dw_be = tr.last_dw_be;
        seg.last_dw_be = 4'h0;
      end

      // keep OHC-A1 on every segment when the parent needed it (uniform size)
      seg.flit_seg_keep_ohc = (ohc_dw != 0);

      // Non-Posted (DMWr) : one tag per segment, each gets its own completion
      seg_tag  = non_posted ? (tr.tag + i) : tr.tag;
      seg.tag  = seg_tag;

      seg.is_flit_segment        = 1'b1;
      seg.flit_seg_idx           = i;
      seg.flit_seg_total         = n_seg;
      seg.flit_seg_parent_len_dw = total_dw;
      seg.flit_seg_parent_tag    = tr.tag;

      if (non_posted) begin
        if (seg_parent_of.exists(seg_tag))
          `uvm_warning("RC_TL_FLIT_SEG", $sformatf("TAG_REUSED : segment tag 0x%0h still outstanding", seg_tag))
        seg_parent_of[seg_tag] = tr.tag;
        seg_desc_of[seg_tag]   = $sformatf("%3d/%0d | 0x%016h | %3d DW (%4d B)",
                                           i + 1, n_seg, seg.address, len_dw, len_dw * `PCIe_TL_DW_BYTES);
      end

      used_b = (hb_dw + ohc_dw + trl_dw + len_dw) * `PCIe_TL_DW_BYTES;
      rows = {rows, $sformatf("          %3d  | 0x%016h | 0x%04h | %3d DW (%4d B) | %3d B used | %3d B zero (NOP) padded\n",
                              i + 1, seg.address, seg_tag, len_dw, len_dw * `PCIe_TL_DW_BYTES,
                              used_b, `PCIe_FLIT_TLP_BYTES - used_b)};

      segs.push_back(seg);
      off_dw += len_dw;
    end

    if (non_posted) begin
      seg_cpl_expect[tr.tag] = n_seg;
      seg_cpl_got[tr.tag]    = 0;
      seg_cpl_rows[tr.tag]   = "";
    end
    n_seg_txn++;
    n_seg_tlp += n_seg;

    `uvm_info("RC_TL_FLIT_SEG",
      $sformatf({"\n",
        "         ============================================================================\n",
        "                 FLIT MODE TLP SEGMENTATION  (TLP does not fit one 236 B region)\n",
        "         ============================================================================\n",
        "          Request            : %s %s%s  tag=0x%0h\n",
        "          Payload            : %0d DW (%0d B)\n",
        "          TLP region / FLIT  : %0d B (%0d DW)\n",
        "          Header Base        : %0d DW (%0d B)\n",
        "          OHC                : %0d DW (%0d B)%s\n",
        "          ECRC trailer       : %0d DW (%0d B)\n",
        "          Max payload / TLP  : %0d - %0d = %0d B (%0d DW)\n",
        "          TLPs / FLITs       : ceil(%0d / %0d) = %0d\n",
        "          First %0d TLPs      : %0d DW each\n",
        "          Last TLP           : %0d DW (%0d B) -> %0d + %0d = %0d B used, %0d B unused (zero / NOP padded)\n",
        "          Completions        : %s\n",
        "         ----------------------------------------------------------------------------\n",
        "          seg  | address            | tag    | payload        | region usage\n",
        "         ----------------------------------------------------------------------------\n",
        "%s",
        "         ============================================================================"},
        tr.is_64bit_addr() ? "4DW" : "3DW",
        tr.mem_deferrable ? "DMWr" : "MWr",
        (ohc_dw != 0) ? " + OHC-A1" : "",
        tr.tag,
        total_dw, total_dw * `PCIe_TL_DW_BYTES,
        `PCIe_FLIT_TLP_BYTES, `PCIe_FLIT_TLP_REGION_DW,
        hb_dw, hb_dw * `PCIe_TL_DW_BYTES,
        ohc_dw, ohc_dw * `PCIe_TL_DW_BYTES, (ohc_dw != 0) ? "  (kept on every segment)" : "",
        trl_dw, trl_dw * `PCIe_TL_DW_BYTES,
        `PCIe_FLIT_TLP_BYTES, (hb_dw + ohc_dw + trl_dw) * `PCIe_TL_DW_BYTES,
        max_dw * `PCIe_TL_DW_BYTES, max_dw,
        total_dw, max_dw, n_seg,
        n_seg - 1, max_dw,
        last_dw, last_dw * `PCIe_TL_DW_BYTES,
        (hb_dw + ohc_dw + trl_dw) * `PCIe_TL_DW_BYTES, last_dw * `PCIe_TL_DW_BYTES,
        (hb_dw + ohc_dw + trl_dw + last_dw) * `PCIe_TL_DW_BYTES,
        `PCIe_FLIT_TLP_BYTES - ((hb_dw + ohc_dw + trl_dw + last_dw) * `PCIe_TL_DW_BYTES),
        non_posted ? $sformatf("%0d expected (one Cpl per segment, tags 0x%0h..0x%0h)", n_seg, tr.tag, seg_tag)
                   : "none (Posted Memory Write)",
        rows), UVM_LOW)
  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: write (tx_tl_imp) - entry point from the RC controller driver.
  //--------------------------------------------------------------------------
  virtual function void write(PCIe_sequence_item tr);
    `uvm_info("RC_TL_MODEL", $sformatf("RECEIVED_TL_PAYLOAD_FROM_RC_CONTROLLER_DRIVER %s", tr.pkt_mode.name()), UVM_LOW)
     send_tlp(tr);
  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: send_tlp - build the complete TLP / FLIT and push it to the DL.
  //--------------------------------------------------------------------------
  virtual function void send_tlp(PCIe_sequence_item tr);

    bit [`PCIe_TL_DATA_DW_W-1:0] hdr[];
       //----------------------------------------------------------------------
    // IDLE / NOP FLIT (Table 4-16) : both carry NOP TLPs across all 236 bytes,
    // so there is no header to serialize and no payload to append.
    //----------------------------------------------------------------------
    if ((tr.pkt_mode == FLIT) && (tr.flit_type != PCIe_PAYLOAD_flit)) begin
      build_idle_or_nop_flit(tr);
      return;
    end


    serialize_header(tr, hdr);       // Header Base + OHC
    tr.hdr_dw_count = hdr.size();

    build_complete_tlp(tr, hdr);     // Header + OHC + Payload -> serialized_tlp

     // ---- ECRC (Section 2.7.1) --------------------------------------------
    // Non-Flit Mode : appended as the TLP Digest when TD == 1
    // Flit Mode     : appended as a 1 DW Trailer when TS[2:0] == 001b
    append_ecrc(tr);
    // ----------------------------------------------------------------------

    // [FC SHARED] pool of this TLP is known (gate). DEDICATED -> Flit Mode
    // Local TLP Prefix in front of the TLP. Added after the ECRC : a Local TLP
    // Prefix is not covered by ECRC.
    fc_tx_prepare_pool(tr);

    // FLIT MODE : pack the TLP into the 236 byte FLIT TLP region and pad the
    // remainder with NOP TLPs (Sec 2.2.1.2). Non-Flit Mode has no such region.
    if (tr.pkt_mode == FLIT)
      assemble_flit(tr);

    `uvm_info(get_type_name(),
      $sformatf("[TL->DL] RC-TL launch: %s | header_dw=%0d payload_dw=%0d total_dw=%0d",
                 tr.convert2string(), tr.tlp_header_dw_count,
                 tr.tlp_payload_dw_count, tr.tlp_total_dw_count), UVM_MEDIUM);

    //----------------------------------------------------------------------
    // Track non-posted requests (completion matching, when it is wired up)
    //----------------------------------------------------------------------
    if (is_non_posted(tr)) begin
      outstanding[tr.tag] = tr;
    end

    //----------------------------------------------------------------------
    // Hand the 236 byte TLP region to the DL in the field it consumes
    //----------------------------------------------------------------------
    // FLOW CONTROL : CREDITS_CONSUMED += this TLP (gate already passed in the driver)
    fc_account_tlp(tr);

    print_attr_table_check(tr);      // [ATTR] info : RO / IDO / NS table check (just before the 236B TL packet print)

    pack_to_tlp_data(tr);

    // [FLIT_SEG] byte layout of this segment inside its 236 B FLIT TLP region
    if (tr.is_flit_segment) print_flit_seg_layout(tr);

    // [FLIT_SEG] remember what was written, to check later read completions
    if ((tr.txn_type == PCIe_TL_MEM) && (tr.dir == PCIe_TL_WRITE))
      foreach (tr.data[i]) wr_shadow[(64'(tr.address) >> 2) + i] = tr.data[i];

    `uvm_info(get_type_name(), "[TL->DL] TLP_SENT_TO_DL", UVM_MEDIUM);
     tlp_dl_ap.write(tr);

  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: pack_to_tlp_data
  //
  //   The DL model consumes item.tlp_data - a packed 236 byte array where
  //   byte 0 is the first byte on the wire - inside form_dl_packet().
  //   Flatten the TL's DW output into it, MSB-first within each DW (same byte
  //   order used by print_flit_region), and zero-fill anything beyond.
  //--------------------------------------------------------------------------
  virtual function void pack_to_tlp_data(PCIe_sequence_item tr);

    bit [`PCIe_TL_DATA_DW_W-1:0] src[];
    int nbytes;
    int b;

    // FLIT mode  : the padded 236 byte region (59 DW)
    // NON-FLIT   : the raw serialized TLP, zero padded up to 236 B
    if (tr.pkt_mode == FLIT)
      src = tr.flit_tlp_region;
    else
      src = tr.serialized_tlp;

    tr.tlp_data = '0;                                 // clear all 236 bytes

    nbytes = src.size() * 4;
    if (nbytes > `PCIe_TLP_DATA_BYTE_W)
      nbytes = `PCIe_TLP_DATA_BYTE_W;                 // longer than one flit -> truncate

    for (b = 0; b < nbytes; b++)
      tr.tlp_data[b] = src[b/4][ 8*(3-(b%4)) +: 8 ];

    // DL flags : this flit carries a real TLP payload
    tr.is_payload = 1'b1;
    tr.drive_flit = (tr.pkt_mode == FLIT);

    `uvm_info("RC_TL_MODEL",
      $sformatf("PACKED_FOR_DL : mode=%s src_dw=%0d packed_bytes=%0d",
                 tr.pkt_mode.name(), src.size(), nbytes), UVM_LOW)

    print_tlp_data(tr);
    print_full_packet(tr);

  endfunction

  //--------------------------------------------------------------------------
  // [FLIT_SEG] print_flit_seg_layout : where Header / OHC / Payload / zeros
  // sit inside the 236 byte TLP region of one segment FLIT, e.g. 3DW + OHC :
  //   FLIT 1..18 : bytes 0-11 header, 12-15 OHC, 16-235 payload (220 B)
  //   FLIT 19    : bytes 0-11 header, 12-15 OHC, 16-151 payload, 152-235 zero
  //--------------------------------------------------------------------------
  virtual function void print_flit_seg_layout(PCIe_sequence_item tr);
    int unsigned hb_b, ohc_b, pl_b, trl_b, used_b, zero_b, pos;
    string       s;

    hb_b   = (tr.is_64bit_addr() ? `PCIe_TL_HDR4DW : `PCIe_TL_HDR3DW) * `PCIe_TL_DW_BYTES;
    ohc_b  = (tr.tlp_header_dw_count * `PCIe_TL_DW_BYTES) - hb_b;
    pl_b   = tr.tlp_payload_dw_count * `PCIe_TL_DW_BYTES;
    trl_b  = tr.ecrc_present ? (`PCIe_TL_ECRC_DW * `PCIe_TL_DW_BYTES) : 0;
    used_b = hb_b + ohc_b + pl_b + trl_b;
    zero_b = `PCIe_FLIT_TLP_BYTES - used_b;

    s   = $sformatf("\n          ===== FLIT %0d / %0d  (236 B TLP region, %s%s) =====\n",
                    tr.flit_seg_idx + 1, tr.flit_seg_total,
                    tr.is_64bit_addr() ? "4DW" : "3DW", (ohc_b != 0) ? " + OHC" : "");
    pos = 0;
    s   = {s, $sformatf("          bytes %3d - %3d : Header Base  %3d B\n", pos, pos + hb_b - 1, hb_b)};
    pos += hb_b;
    if (ohc_b != 0) begin
      s   = {s, $sformatf("          bytes %3d - %3d : OHC          %3d B\n", pos, pos + ohc_b - 1, ohc_b)};
      pos += ohc_b;
    end
    s   = {s, $sformatf("          bytes %3d - %3d : Payload      %3d B (%0d DW)  address 0x%0h\n",
                        pos, pos + pl_b - 1, pl_b, tr.tlp_payload_dw_count, tr.address)};
    pos += pl_b;
    if (trl_b != 0) begin
      s   = {s, $sformatf("          bytes %3d - %3d : ECRC trailer %3d B\n", pos, pos + trl_b - 1, trl_b)};
      pos += trl_b;
    end
    if (zero_b != 0)
      s = {s, $sformatf("          bytes %3d - %3d : ZERO (NOP)   %3d B\n", pos, `PCIe_FLIT_TLP_BYTES - 1, zero_b)};
    s = {s, $sformatf("          used %0d B + zero %0d B = %0d B", used_b, zero_b, `PCIe_FLIT_TLP_BYTES)};

    `uvm_info("RC_TL_FLIT_LAYOUT", s, UVM_LOW)
  endfunction

  //--------------------------------------------------------------------------
  // Dump the 236 bytes exactly as the DL will receive them
  //--------------------------------------------------------------------------
  virtual function void print_tlp_data(PCIe_sequence_item tr);

    string line;
    string dump;
    int    b;

    dump = "\n";
    line = "";

    for (b = 0; b < `PCIe_TLP_DATA_BYTE_W; b++) begin
      if ((b % `PCIe_FLIT_DUMP_BPL) == 0)
        line = $sformatf("  [%3d] :", b);

      line = {line, $sformatf(" %02h", tr.tlp_data[b])};

      if (((b % `PCIe_FLIT_DUMP_BPL) == `PCIe_FLIT_DUMP_BPL-1) ||
          (b == `PCIe_TLP_DATA_BYTE_W-1)) begin
        dump = {dump, line, "\n"};
      end
    end

    `uvm_info("TL_TO_DL_236B", dump, UVM_LOW)

  endfunction

  //--------------------------------------------------------------------------
  // Dump full packet fields separately.
  // Existing 236-byte tlp_data dump is retained.
  //
  // NON-FLIT : Header + Payload
  // FLIT     : Header + payload
  //--------------------------------------------------------------------------
  virtual function void print_full_packet(PCIe_sequence_item tr);

    string line;
    string dump;
    int    b;

    dump = $sformatf({"\n",
      "         ************************************************************\n",
      "                          TLP FULL PACKET\n",
      "         ************************************************************\n",
      "         Packet Mode     : %s\n",
      "         Header          : %0d DW / %0d bytes\n",
      "         Payload         : %0d DW / %0d bytes\n"},
      (tr.pkt_mode == FLIT) ? "FLIT" : "NON-FLIT",
      tr.tlp_header_dw_count,
      tr.tlp_header_dw_count * `PCIe_TL_DW_BYTES,
      tr.tlp_payload_dw_count,
      tr.tlp_payload_dw_count * `PCIe_TL_DW_BYTES);

    // HEADER BYTES
    dump = {dump,
      "         ------------------------------------------------------------\n",
      "         HEADER BYTES\n",
      "         ------------------------------------------------------------\n"};
    line = "";

    for (b = 0;
         b < (tr.tlp_header_dw_count * `PCIe_TL_DW_BYTES);
         b++) begin

      if ((b % `PCIe_FLIT_DUMP_BPL) == 0)
        line = $sformatf("           [%3d] :", b);

      line = {line, $sformatf(" %02h", tr.tlp_data[b])};

      if (((b % `PCIe_FLIT_DUMP_BPL) == `PCIe_FLIT_DUMP_BPL-1) ||
          (b == (tr.tlp_header_dw_count * `PCIe_TL_DW_BYTES)-1))
        dump = {dump, line, "\n"};
    end

    // PAYLOAD BYTES
    dump = {dump,
      "         ------------------------------------------------------------\n",
      "         PAYLOAD BYTES\n",
      "         ------------------------------------------------------------\n"};

    if (tr.tlp_payload_dw_count == 0) begin
      dump = {dump, "           <none>\n"};
    end
    else begin
      line = "";

      for (b = (tr.tlp_header_dw_count * `PCIe_TL_DW_BYTES);
           b < ((tr.tlp_header_dw_count + tr.tlp_payload_dw_count) *
                `PCIe_TL_DW_BYTES);
           b++) begin

        if ((b % `PCIe_FLIT_DUMP_BPL) == 0)
          line = $sformatf("           [%3d] :", b);

        line = {line, $sformatf(" %02h", tr.tlp_data[b])};

        if (((b % `PCIe_FLIT_DUMP_BPL) == `PCIe_FLIT_DUMP_BPL-1) ||
            (b == ((tr.tlp_header_dw_count + tr.tlp_payload_dw_count) *
                   `PCIe_TL_DW_BYTES)-1))
          dump = {dump, line, "\n"};
      end
    end
/*
    // LCRC BYTES
    dump = {dump,
      "         ------------------------------------------------------------\n",
      "         LCRC BYTES\n",
      "         ------------------------------------------------------------\n"};

    if (tr.pkt_mode == FLIT) begin
      dump = {dump,
        "           < LCRC not valid for FLIT mode >\n"};
    end
    else begin
      dump = {dump,
        $sformatf(
          "           Byte range : [%0d:%0d] = %0d bytes\n",
          (tr.tlp_header_dw_count + tr.tlp_payload_dw_count) *
            `PCIe_TL_DW_BYTES,
          ((tr.tlp_header_dw_count + tr.tlp_payload_dw_count) *
            `PCIe_TL_DW_BYTES) +
            (`PCIe_DL_LCRC_W / `PCIe_BYTE_W) - 1,
          `PCIe_DL_LCRC_W / `PCIe_BYTE_W),
        "           Value      : <LCRC_generation_not_present_in_RC_TL_model>\n"};
    end*/

    `uvm_info("FULL_PACKET", dump, UVM_LOW)

  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: is_non_posted - reads, MRdLk, DMWr, and all cfg expect a Cpl.
  //--------------------------------------------------------------------------
  virtual function bit is_non_posted(PCIe_sequence_item tr);
    case (tr.txn_type)
      PCIe_TL_MEM : return (!tr.is_write()) || tr.mem_deferrable;
      PCIe_TL_IO  : return 1'b1;
      PCIe_TL_CFG : return 1'b1;
      PCIe_TL_MSG : return 1'b0;
      default     : return 1'b0;
    endcase
  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: cpl_write - inbound completion; match by tag, copy fields.
  //   Not connected yet (no upstream path in this environment). Call this from
  //   a future RC_DL dl2tl analysis port.
  //--------------------------------------------------------------------------
  virtual function void cpl_write(PCIe_sequence_item cpl);
    PCIe_sequence_item req_h;
    int unsigned       bc_val;
    bit                last_part;
    if (outstanding.exists(cpl.tag)) begin
      req_h = outstanding[cpl.tag];
      // [FLIT_SEG] a CplD may be split over several FLITs; the request stays
      // outstanding until the part whose Byte Count covers only its own data.
      bc_val    = (cpl.byte_count == 12'h000) ? 4096 : int'(cpl.byte_count);
      last_part = !cpl.cpl_has_data || (bc_val <= cpl.cpl_data.size() * `PCIe_TL_DW_BYTES);
      req_h.cpl_data   = {req_h.cpl_data, cpl.cpl_data};
      req_h.cpl_status = cpl.cpl_status;
      if (last_part) begin
        outstanding.delete(cpl.tag);
        `uvm_info(get_type_name(),
          $sformatf("RC-TL got completion tag=0x%0h status=%0d dw=%0d (total collected %0d DW)",
                     cpl.tag, cpl.cpl_status, cpl.cpl_data.size(), req_h.cpl_data.size()), UVM_LOW)
      end
      else begin
        `uvm_info(get_type_name(),
          $sformatf("RC-TL got PART of a split completion tag=0x%0h dw=%0d byte_count_remaining=%0d (collected %0d DW so far)",
                     cpl.tag, cpl.cpl_data.size(), bc_val, req_h.cpl_data.size()), UVM_LOW)
      end

      // [FLIT_SEG] completion of one segment of a split Non-Posted request (DMWr)
      if (seg_parent_of.exists(cpl.tag)) begin
        bit [`PCIe_TL_TAG_W-1:0] ptag;
        ptag = seg_parent_of[cpl.tag];
        seg_parent_of.delete(cpl.tag);
        seg_cpl_got[ptag]++;
        // Cpl (no data) = 3 DW header (+1 DW OHC-A5 when not SC) in its own FLIT,
        // the rest of the 236 B TLP region is zero (NOP TLPs)
        seg_cpl_rows[ptag] = {seg_cpl_rows[ptag],
          $sformatf("          %s | tag 0x%04h | Cpl %-3s | %2d B hdr + %3d B zero (NOP) padded\n",
                    seg_desc_of.exists(cpl.tag) ? seg_desc_of[cpl.tag] : "?", cpl.tag,
                    cpl_status_str(cpl.cpl_status),
                    (cpl.cpl_status == `PCIe_CPL_STATUS_SC) ? 12 : 16,
                    `PCIe_FLIT_TLP_BYTES - ((cpl.cpl_status == `PCIe_CPL_STATUS_SC) ? 12 : 16))};
        seg_desc_of.delete(cpl.tag);
        `uvm_info("RC_TL_FLIT_SEG",
          $sformatf("SEGMENT_COMPLETION_RECEIVED : parent tag=0x%0h segment tag=0x%0h status=%s -> %0d / %0d completions",
                    ptag, cpl.tag, cpl_status_str(cpl.cpl_status), seg_cpl_got[ptag], seg_cpl_expect[ptag]), UVM_LOW)
        if (cpl.cpl_status != `PCIe_CPL_STATUS_SC)
          `uvm_error("RC_TL_FLIT_SEG", $sformatf("SEGMENT_COMPLETION_NOT_SC : segment tag=0x%0h status=%s",
                     cpl.tag, cpl_status_str(cpl.cpl_status)))
        if (seg_cpl_got[ptag] == seg_cpl_expect[ptag]) begin
          n_seg_txn_done++;
          `uvm_info("RC_TL_FLIT_SEG",
            $sformatf({"\n",
              "         ============================================================\n",
              "          SEGMENTED NON-POSTED REQUEST FULLY COMPLETED\n",
              "         ============================================================\n",
              "          Parent tag          : 0x%0h\n",
              "          Segments (TLPs/FLITs): %0d\n",
              "          Completions received: %0d (one Cpl per segment, each in its own FLIT)\n",
              "         ------------------------------------------------------------------------------------------\n",
              "          seg     | segment address    | segment payload | completion\n",
              "         ------------------------------------------------------------------------------------------\n",
              "%s",
              "         ============================================================"},
              ptag, seg_cpl_expect[ptag], seg_cpl_got[ptag], seg_cpl_rows[ptag]), UVM_LOW)
        end
      end
    end
    else begin
      `uvm_warning(get_type_name(),
        $sformatf("Unexpected/duplicate completion tag=0x%0h", cpl.tag))
    end
  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: serialize_header
  //
  //   NON_FLIT : Fmt[2:0] + Type[4:0], 3DW / 4DW headers
  //   FLIT     : Type[7:0], Header Base size determined by Type, OHC appended
  //--------------------------------------------------------------------------
  virtual function void serialize_header(PCIe_sequence_item tr,
                                         ref bit [`PCIe_TL_DATA_DW_W-1:0] hdr[]);

    `uvm_info("RC_TL_MODEL",
      $sformatf("ENTERED_INTO_SERIALIZE_HEADER_FOR_%s", tr.pkt_mode.name()), UVM_LOW)

    if (tr.pkt_mode == FLIT)
      serialize_flit_header(tr, hdr);
    else
      serialize_non_flit_header(tr, hdr);

  endfunction

  //--------------------------------------------------------------------------
  // NON-FLIT TLP HEADER
  //--------------------------------------------------------------------------
  virtual function void serialize_non_flit_header(PCIe_sequence_item tr,
                                                  ref bit [`PCIe_TL_DATA_DW_W-1:0] hdr[]);

    bit [`PCIe_TL_FMTTYPE_W-1:0] ft;
    bit [`PCIe_TL_DATA_DW_W-1:0] dw0;
    bit [`PCIe_TL_DATA_DW_W-1:0] dw1;
    bit [`PCIe_TL_DATA_DW_W-1:0] dw2;
    bit [`PCIe_TL_DATA_DW_W-1:0] dw3;

    ft = tr.get_fmttype();

    dw0 = '0;
    dw1 = '0;
    dw2 = '0;
    dw3 = '0;

    //======================================================================
    // DW0 - PCIe Base 6.0 Fig 2-5 / Fig 2-31 (Non-Flit Mode)
    //
    //   byte0  [31:24] = Fmt[2:0] , Type[4:0]
    //   byte1  [23]    = T9   (Tag[9])
    //          [22:20] = TC[2:0]
    //          [19]    = T8   (Tag[8])
    //          [18]    = A2   (Attr[2] - IDO)
    //          [17]    = R    (Reserved - was LN, deprecated)
    //          [16]    = TH
    //   byte2  [15]    = TD
    //          [14]    = EP
    //          [13:12] = Attr[1:0]
    //          [11:10] = AT[1:0]
    //          [9:8]   = Length[9:8]
    //   byte3  [7:0]   = Length[7:0]
    //======================================================================

    dw0[31:24] = ft;

    // Tag[9] / Tag[8] - non-contiguous with Tag[7:0] in Non-Flit Mode
    dw0[23]    = tr.tag[9];
    dw0[22:20] = tr.tc;
    dw0[19]    = tr.tag[8];

    // Attr[2] (IDO)
    dw0[18]    = tr.attr[2];

    // dw0[17] Reserved (deprecated LN bit) ; dw0[16] TH - not modelled

    dw0[15]    = tr.td;
    dw0[14]    = tr.ep;
    dw0[13:12] = tr.attr[1:0];
    dw0[11:10] = tr.at;
    dw0[9:0]   = tr.length;

    //======================================================================
    // DW1
    //   [31:16] Requester ID
    //   [15:8]  Tag[7:0]
    //   [7:4]   Last DW BE
    //   [3:0]   First DW BE
    //======================================================================

    dw1[31:16] = tr.requester_id;
    dw1[15:8]  = tr.tag[7:0];
    dw1[7:4]   = tr.last_dw_be;
    dw1[3:0]   = tr.first_dw_be;

    //======================================================================
    // Address / Request-specific header
    //======================================================================
    case (tr.txn_type)

      PCIe_TL_MEM: begin
        if (tr.is_4dw()) begin
          // 4DW Memory Request
          dw2 = tr.address[63:32];
          dw3 = {tr.address[31:2], 2'b00};
          hdr = new[4];
          hdr[0] = dw0;
          hdr[1] = dw1;
          hdr[2] = dw2;
          hdr[3] = dw3;
        end
        else begin
          // 3DW Memory Request
          dw2 = {tr.address[31:2], 2'b00};
          hdr = new[3];
          hdr[0] = dw0;
          hdr[1] = dw1;
          hdr[2] = dw2;
        end
      end

      PCIe_TL_IO: begin
        dw2 = {tr.address[31:2], 2'b00};
        hdr = new[3];
        hdr[0] = dw0;
        hdr[1] = dw1;
        hdr[2] = dw2;
      end

      PCIe_TL_CFG: begin
        dw2 = '0;
        dw2[31:24] = tr.cfg_bus_num;
        dw2[23:19] = tr.cfg_dev_num;
        dw2[18:16] = tr.cfg_fn_num;
        dw2[11:2]  = tr.cfg_reg_num[11:2];
        hdr = new[3];
        hdr[0] = dw0;
        hdr[1] = dw1;
        hdr[2] = dw2;
      end

      PCIe_TL_MSG: begin
        dw0[26:24] = tr.msg_route;
        dw1[7:0]   = tr.msg_code;
        dw3 = '0;
        hdr = new[4];
        hdr[0] = dw0;
        hdr[1] = dw1;
        hdr[2] = dw2;
        hdr[3] = dw3;;
      end

      default: begin
        hdr = new[1];
        hdr[0] = dw0;
      end
    endcase

  endfunction

  //==========================================================================
  // Serialize OHC
  //==========================================================================
  virtual function void serialize_ohc(PCIe_sequence_item tr,
                                      ref bit [`PCIe_TL_DATA_DW_W-1:0] ohc_data[]);

    bit [`PCIe_TL_DATA_DW_W-1:0] dw;

    dw = '0;

    //----------------------------------------------------------------------
    // No OHC
    //----------------------------------------------------------------------
    if (tr.ohc[0] == 1'b0) begin
      ohc_data = new[0];
      return;
    end

    case (tr.ohc_a_type)

      OHC_A1: begin   // OHC-A1 - explicit Byte Enables
                dw = '0;
                dw[7:4] = tr.last_dw_be;   // [7:4] = Last DW BE
                dw[3:0] = tr.first_dw_be;  // [3:0] = First DW BE
                ohc_data = new[1];
                ohc_data[0] = dw;
      end
      OHC_A2: begin   // OHC-A2 - IO Requests (Fig 2-8)
                dw = '0;
                // [31:8] Reserved
                dw[7:4] = tr.last_dw_be;   // must be 0000b for IO
                dw[3:0] = tr.first_dw_be;
                ohc_data = new[1];
                ohc_data[0] = dw;
      end
      OHC_A3: begin  // OHC-A3 - Configuration
                dw = '0;
                // [FIX] OHC-A3 also carries the DW Byte Enables. They were left 0, so
                // the EP saw first_dw_be=0000 and silently dropped every CfgWr
                // (Command readback 0000 instead of 0004).
                dw[7:4] = tr.last_dw_be;   // [7:4] = Last DW BE
                dw[3:0] = tr.first_dw_be;  // [3:0] = First DW BE
                ohc_data = new[1];
                ohc_data[0] = dw;
      end
      OHC_A4: begin   // OHC-A4 - Message
                dw = '0;
                ohc_data = new[1];
                ohc_data[0] = dw;
      end
      OHC_A5: begin  // OHC-A5 - Completion
                dw = '0;
                ohc_data = new[1];
                ohc_data[0] = dw;
      end
      default: begin
                ohc_data = new[0];
      end
    endcase

  endfunction

  //==========================================================================
  // FLIT HEADER SERIALIZER
  //
  //   32-bit Address : Header Base = 3 DW
  //   64-bit Address : Header Base = 4 DW
  //   OHC is appended after the Header Base.
  //==========================================================================
  virtual function void serialize_flit_header(PCIe_sequence_item tr,
                                              ref bit [`PCIe_TL_DATA_DW_W-1:0] hdr[]);

    bit [`PCIe_TL_DATA_DW_W-1:0] dw0;
    bit [`PCIe_TL_DATA_DW_W-1:0] dw1;
    bit [`PCIe_TL_DATA_DW_W-1:0] dw2;
    bit [`PCIe_TL_DATA_DW_W-1:0] dw3;

    bit [`PCIe_TL_DATA_DW_W-1:0] ohc_data[];

    pcie_flit_type_e flit_type;

    bit [`PCIe_TL_DATA_DW_W-1:0] tmp[];

    int header_base_dw;
    int ohc_dw;
    int total_header_dw;
    int i;

    tr.determine_ohc();               // Determine OHC
    flit_type = tr.get_flit_type();   // FLIT Type

    //======================================================================
    // Header Base size
    //======================================================================
    //if (tr.is_64bit_addr())
	        if (tr.is_64bit_addr() || (tr.txn_type == PCIe_TL_MSG))
      header_base_dw = 4;
    else
      header_base_dw = 3;

    dw0 = '0;
    dw1 = '0;
    dw2 = '0;
    dw3 = '0;

    //======================================================================
    // DW0
    //   [31:24] Type   [23:21] TC   [20:16] OHC
    //   [15:13] TS     [12:10] Attr [9:0]   Length
    //======================================================================
    dw0[31:24] = flit_type;
    dw0[23:21] = tr.tc;
    dw0[20:16] = tr.ohc;
    dw0[15:13] = tr.ts;
    dw0[12:10] = tr.attr;
    dw0[9:0]   = tr.length;

    //======================================================================
    // DW1
    //   [31:16] Requester ID   [15] EP   [14] Reserved   [13:0] Tag
    //======================================================================
    dw1[31:16] = tr.requester_id;
    dw1[15]    = tr.ep;
    dw1[14]    = 1'b0;
    dw1[13:0]  = tr.tag;

    //======================================================================
    // MEMORY REQUEST
    //======================================================================
    if (tr.txn_type == PCIe_TL_MEM) begin

      if (tr.is_64bit_addr()) begin
        // 64-bit address
        dw2 = tr.address[63:32];

        dw3 = '0;
        dw3[31:2] = tr.address[31:2];
        dw3[1:0]  = tr.at;

        hdr = new[header_base_dw];
        hdr[0] = dw0;
        hdr[1] = dw1;
        hdr[2] = dw2;
        hdr[3] = dw3;
      end

      else begin
        // 32-bit address
        dw2 = '0;
        dw2[31:2] = tr.address[31:2];
        dw2[1:0]  = tr.at;

        hdr = new[header_base_dw];
        hdr[0] = dw0;
        hdr[1] = dw1;
        hdr[2] = dw2;
      end

    end

    //======================================================================
    // IO REQUEST - Flit Mode (Fig 2-41)
    //   Header Base is always 3 DW (IO is 32-bit addressed only).
    //   DW2 = Address[31:2], bits [1:0] Reserved (AT is Memory-only in Flit).
    //   OHC-A2 is mandatory for all IO Requests (Sec 2.2.5.2).
    //======================================================================
    else if (tr.txn_type == PCIe_TL_IO) begin

      dw2 = '0;
      dw2[31:2] = tr.address[31:2];
      dw2[1:0]  = 2'b00;          // Reserved

      hdr = new[3];
      hdr[0] = dw0;
      hdr[1] = dw1;
      hdr[2] = dw2;

    end

    else if (tr.txn_type == PCIe_TL_CFG) begin

      dw2 = '0;
      dw2[31:24] = tr.cfg_bus_num;
      dw2[23:19] = tr.cfg_dev_num;
      dw2[18:16] = tr.cfg_fn_num;
      dw2[11:2]  = tr.cfg_reg_num[11:2];

      hdr = new[3];
      hdr[0] = dw0;
      hdr[1] = dw1;
      hdr[2] = dw2;

    end

    else if (tr.txn_type == PCIe_TL_MSG) begin
      dw1[14:0] = '0;
      dw1[7:0]  = tr.msg_code;      // Message Code
      hdr = new[4];
      hdr[0] = dw0; hdr[1] = dw1; hdr[2] = dw2; hdr[3] = dw3;
    end

    else begin
      hdr = new[1];
      hdr[0] = dw0;
    end

    //======================================================================
    // Serialize OHC and append it to the Header Base
    //======================================================================
    serialize_ohc(tr, ohc_data);

    ohc_dw = ohc_data.size();

    if (ohc_dw != 0) begin

      tmp = new[hdr.size() + ohc_dw];

      // Header Base
      for (i = 0; i < hdr.size(); i++)
        tmp[i] = hdr[i];

      // OHC
      for (i = 0; i < ohc_dw; i++)
        tmp[hdr.size() + i] = ohc_data[i];

      hdr = tmp;

    end

    total_header_dw = hdr.size();

    //======================================================================
    // PRINT HEADER INFORMATION
    //======================================================================
    `uvm_info("FLIT_HEADER",
      $sformatf({"\n",
        "         ---------------------------------------------\n",
        "                   PCIe Gen6 FLIT TLP HEADER\n",
        "         ---------------------------------------------\n",
        "         Packet Mode       : FLIT\n",
        "         Transaction Type  : %s\n",
        "         Direction         : %s\n",
        "         FLIT Type         : 0x%02h\n",
        "         Address           : 0x%016h\n",
        "         Address Mode      : %s\n",
        "         Payload Length    : %0d DW (%0d bytes)\n",
        "         Header Base       : %0d DW (%0d bytes)\n",
        "         OHC DWs           : %0d DW (%0d bytes)\n",
        "         TOTAL TLP HEADER  : %0d DW (%0d bytes)\n",
        "         ---------------------------------------------"},
        tr.txn_type.name(),
        tr.dir.name(),
        flit_type,
        tr.address,
        tr.is_64bit_addr() ? "64-bit" : "32-bit",
        tr.length,
        tr.length * 4,
        header_base_dw,
        header_base_dw * 4,
        ohc_dw,
        ohc_dw * 4,
        total_header_dw,
        total_header_dw * 4), UVM_LOW);

    foreach (hdr[i]) begin
      `uvm_info("FLIT_HEADER_DW", $sformatf("HEADER DW[%0d] = %08h", i, hdr[i]), UVM_LOW);
    end

  endfunction

  //==========================================================================
  // FLIT ASSEMBLY
  //
  //   A Gen6 FLIT is 256 bytes:
  //       236 B TLP region + 6 B DLP + 8 B CRC + 6 B FEC
  //
  //   The 236 B (59 DW) TLP region is a CONTAINER, not a single TLP. It holds
  //   one or more TLPs; whatever is left over must be filled with NOP TLPs.
  //
  //   PCIe Base 6.0 Sec 2.2.1.2:
  //     "It is required to transmit NOP TLPs while TLP transmission is active
  //      if there are no other TLPs to transmit..."
  //
  //   NOP = Type 8'h00, 1 DW Header Base, no payload -> the DW is all zeros.
  //==========================================================================
  virtual function void assemble_flit(PCIe_sequence_item tr);

    int tlp_dw;
    int nop_dw;
    int i;

    tlp_dw = tr.serialized_tlp.size();

    //----------------------------------------------------------------------
    // A TLP larger than the region has to be spread over several FLITs.
    // Multi-FLIT segmentation is not modelled yet - flag it rather than
    // silently truncating.
    //----------------------------------------------------------------------
    if (tlp_dw > `PCIe_FLIT_TLP_DW) begin
      `uvm_warning("FLIT_ASSEMBLY",
         $sformatf("TLP is %0d DW (%0d B) which exceeds the %0d DW (%0d B) FLIT TLP region - it should have been split by split_flit_tlp() (send it through the RC controller driver), region left unpadded",
                    tlp_dw, tlp_dw*4, `PCIe_FLIT_TLP_DW, `PCIe_FLIT_TLP_BYTES))
      tr.flit_tlp_region = new[tlp_dw];
      foreach (tr.serialized_tlp[i])
        tr.flit_tlp_region[i] = tr.serialized_tlp[i];
      tr.flit_tlp_dw_count = tlp_dw;
      tr.flit_nop_dw_count = 0;
      return;
    end

    nop_dw = `PCIe_FLIT_TLP_DW - tlp_dw;

    tr.flit_tlp_region   = new[`PCIe_FLIT_TLP_DW];
    tr.flit_tlp_dw_count = tlp_dw;
    tr.flit_nop_dw_count = nop_dw;

    // The TLP
    for (i = 0; i < tlp_dw; i++)
      tr.flit_tlp_region[i] = tr.serialized_tlp[i];

    // NOP TLP padding - one 1 DW NOP TLP per remaining DW
    for (i = tlp_dw; i < `PCIe_FLIT_TLP_DW; i++)
      tr.flit_tlp_region[i] = `PCIe_FLIT_NOP_DW;

    print_flit_region(tr);

  endfunction

  //==========================================================================
  // Dump the assembled 236 byte FLIT TLP region
  //==========================================================================
  virtual function void print_flit_region(PCIe_sequence_item tr);

    string line;
    string dump;
    int    b;
    int    total_bytes;
    bit [7:0] byte_val;
    bit    mark_line;

    total_bytes = tr.flit_tlp_region.size() * 4;

    `uvm_info("FLIT_REGION",
       $sformatf({"\n",
         "         ============================================================\n",
         "                    ASSEMBLED FLIT TLP REGION\n",
         "         ============================================================\n",
         "         TLP DWs           : %0d  (%0d bytes)\n",
         "         NOP padding DWs   : %0d  (%0d bytes)\n",
         "         TOTAL REGION DWs  : %0d  (%0d bytes)\n",
         "         FLIT on the wire  : %0d B TLP + %0d B DLP + %0d B CRC + %0d B FEC = %0d B\n",
         "         ============================================================"},
         tr.flit_tlp_dw_count, tr.flit_tlp_dw_count*4,
         tr.flit_nop_dw_count, tr.flit_nop_dw_count*4,
         tr.flit_tlp_region.size(), total_bytes,
         `PCIe_FLIT_TLP_BYTES, `PCIe_FLIT_DLP_BYTES, `PCIe_FLIT_CRC_BYTES,
         `PCIe_FLIT_FEC_BYTES, `PCIe_FLIT_TOTAL_BYTES), UVM_LOW)

    //----------------------------------------------------------------------
    // Byte dump, 16 bytes per line (byte 0 = first byte on the wire)
    //----------------------------------------------------------------------
    dump      = "\n";
    line      = "";
    mark_line = 1'b0;

    for (b = 0; b < total_bytes; b++) begin

      byte_val = tr.flit_tlp_region[b/4][ 8*(3-(b%4)) +: 8 ];

      if ((b % `PCIe_FLIT_DUMP_BPL) == 0) begin
        line      = $sformatf("  [%3d] :", b);
        mark_line = 1'b0;
      end

      line = {line, $sformatf(" %02h", byte_val)};

      if (b == (tr.flit_tlp_dw_count*4 - 1))
        mark_line = 1'b1;

      if (((b % `PCIe_FLIT_DUMP_BPL) == `PCIe_FLIT_DUMP_BPL-1) ||
          (b == total_bytes-1)) begin
        if (mark_line)
          line = {line, $sformatf("   <- TLP ends at byte %0d, NOP padding follows",
                                   tr.flit_tlp_dw_count*4 - 1)};
        dump = {dump, line, "\n"};
      end
    end

    `uvm_info("FLIT_REGION_BYTES", dump, UVM_LOW)

  endfunction

  //==========================================================================
  // Build complete serialized TLP :  Header + OHC + Payload
  //==========================================================================
  virtual function void build_complete_tlp(PCIe_sequence_item tr,
                                           input bit [`PCIe_TL_DATA_DW_W-1:0] hdr[]);

    int header_dw;
    int payload_dw;
    int total_dw;
    int i;

    header_dw  = hdr.size();
    payload_dw = tr.data.size();

    total_dw = header_dw + payload_dw;

    tr.serialized_tlp = new[total_dw];

    // Header + OHC
    for (i = 0; i < header_dw; i++)
      tr.serialized_tlp[i] = hdr[i];

    // Payload
    for (i = 0; i < payload_dw; i++)
      tr.serialized_tlp[header_dw + i] = tr.data[i];

    // Save counts
    tr.tlp_header_dw_count  = header_dw;
    tr.tlp_payload_dw_count = payload_dw;
    tr.tlp_total_dw_count   = total_dw;

    `uvm_info("FULL_TLP",
      $sformatf({"\n",
        "         ============================================================\n",
        "                       COMPLETE PCIe TLP\n",
        "         ============================================================\n",
        "         Packet Mode       : %s\n",
        "         Header DWs        : %0d\n",
        "         Header Bytes      : %0d\n",
        "         Payload DWs       : %0d\n",
        "         Payload Bytes     : %0d\n",
        "         TOTAL TLP DWs     : %0d\n",
        "         TOTAL TLP Bytes   : %0d\n",
        "         ============================================================"},
        (tr.pkt_mode == FLIT) ? "FLIT" : "NON-FLIT",
        header_dw,
        header_dw * 4,
        payload_dw,
        payload_dw * 4,
        total_dw,
        total_dw * 4), UVM_LOW);

    for (i = 0; i < total_dw; i++) begin
      if (i < header_dw) begin
        `uvm_info("FULL_TLP_DW",$sformatf("TLP DW[%0d] = %08h  <-- HEADER", i, tr.serialized_tlp[i]),UVM_LOW)
      end
      else begin
        `uvm_info("FULL_TLP_DW",$sformatf("TLP DW[%0d] = %08h  <-- PAYLOAD",i, tr.serialized_tlp[i]),UVM_LOW)
      end
    end

  endfunction

   //==========================================================================
  //                   ECRC GENERATION  -  Section 2.7.1        [ADDED]
  //
  //   "A 32-bit ECRC is calculated for the TLP (End-End TLP Prefixes/OHC,
  //    header, and data payload) ... and appended to the end of the TLP"
  //
  //     * polynomial 04C1 1DB7h
  //     * seed FFFF FFFFh
  //     * calculation starts with bit 0 of byte 0 and proceeds from bit 0 to
  //       bit 7 of each byte  ->  LSB-first, hence the reflected polynomial
  //     * all Variant bits are treated as Set:
  //         Non-Flit Mode : header symbol 0 bit 0 (Type[0])
  //                         header symbol 2 bit 6 (EP)
  //         Flit Mode     : header symbol 0 bit 0 (Type[0])
  //                         header symbol 6 bit 7 (EP)
  //     * the result is complemented and mapped into the 32-bit TLP Digest
  //       (NFM) / Trailer (FM) through Table 2-55 - a byte-wise bit reversal
  //
  //   ECRC is generated HERE, on the transmitting side. The EP TL model
  //   recalculates it on the receiving side (PCIe_EP_TL_model::check_ecrc_rx).
  //==========================================================================

  // ---- Core byte-serial CRC-32, LSB-first ----
  function automatic bit [31:0] ecrc_byte_update(bit [31:0] crc_in, bit [7:0] data_byte);
    bit [31:0] crc;
    bit [7:0]  b;
    crc = crc_in;
    b   = data_byte;
    for (int i = 0; i < 8; i++) begin
      if ((crc[0] ^ b[0]) == 1'b1) crc = (crc >> 1) ^ `PCIe_TL_ECRC_POLY_REFLECTED;
      else                         crc = (crc >> 1);
      b = b >> 1;
    end
    return crc;
  endfunction

  // ---- Table 2-55 : ECRC result bit n -> TLP Digest bit position ----
  function automatic bit [`PCIe_TL_ECRC_W-1:0] ecrc_map_bits(bit [31:0] crc_result);
    bit [`PCIe_TL_ECRC_W-1:0] digest;
    digest = '0;
    for (int byte_i = 0; byte_i < 4; byte_i++)
      for (int bit_i = 0; bit_i < 8; bit_i++)
        digest[(byte_i*8) + (7 - bit_i)] = crc_result[(byte_i*8) + bit_i];
    return digest;
  endfunction

  //--------------------------------------------------------------------------
  // generate_ecrc - run the CRC over the serialized TLP (header + OHC +
  // payload). dw_stream[] is DW oriented; byte 0 of the TLP is the MSB of
  // dw_stream[0], matching pack_to_tlp_data / print_flit_region.
  //--------------------------------------------------------------------------
  virtual function bit [`PCIe_TL_ECRC_W-1:0] generate_ecrc(
      input bit [`PCIe_TL_DATA_DW_W-1:0] dw_stream [],
      input pkt_mode_e                   mode);

    bit [31:0] crc;
    bit [7:0]  b;
    int        nbytes;
    int        var_sym;
    int        var_bit;

    crc     = `PCIe_TL_ECRC_SEED;
    nbytes  = dw_stream.size() * `PCIe_TL_DW_BYTES;
    var_sym = (mode == FLIT) ? `PCIe_TL_ECRC_FM_VAR_SYM     : `PCIe_TL_ECRC_NFM_VAR_SYM;
    var_bit = (mode == FLIT) ? `PCIe_TL_ECRC_FM_VAR_SYM_BIT : `PCIe_TL_ECRC_NFM_VAR_SYM_BIT;

    `uvm_info("ECRC_TX",
      $sformatf("ECRC_START : mode=%s bytes_covered=%0d variant_bits={sym%0d.bit%0d , sym%0d.bit%0d}",
                 mode.name(), nbytes,
                 `PCIe_TL_ECRC_VAR_SYM0, `PCIe_TL_ECRC_VAR_SYM0_BIT, var_sym, var_bit), UVM_LOW)

    for (int i = 0; i < nbytes; i++) begin
      b = dw_stream[i/4][ 8*(3-(i%4)) +: 8 ];

      // "All Variant bits must be treated as Set for ECRC calculations"
      if (i == `PCIe_TL_ECRC_VAR_SYM0) b[`PCIe_TL_ECRC_VAR_SYM0_BIT] = 1'b1;
      if (i == var_sym)                b[var_bit]                    = 1'b1;

      crc = ecrc_byte_update(crc, b);
      `uvm_info("ECRC_TX",
        $sformatf("  byte[%0d]=%02h running_crc=%08h", i, b, crc), UVM_HIGH)
    end

    crc = ~crc;                          // complement the result
    return ecrc_map_bits(crc);           // Table 2-55 bit mapping
  endfunction

  //--------------------------------------------------------------------------
  // append_ecrc - decide whether this TLP carries an ECRC and, if so, append
  // it to serialized_tlp.
  //
  //   NON-FLIT : TD == 1  ->  32-bit TLP Digest field at the end of the TLP
  //   FLIT     : TS == 001b ->  1 DW Trailer containing ECRC
  //              (a sequence that sets td == 1 in FLIT mode is treated as a
  //               request for the ECRC trailer and TS is forced to 001b)
  //--------------------------------------------------------------------------
  virtual function void append_ecrc(PCIe_sequence_item tr);

    bit [`PCIe_TL_ECRC_W-1:0]    digest;
    bit [`PCIe_TL_DATA_DW_W-1:0] tmp [];
    int i;

    tr.ecrc_present = 1'b0;
    tr.ecrc_state   = PCIe_ECRC_ABSENT;

    if (tr.pkt_mode == NON_FLIT) begin
      if (tr.td != 1'b1) begin
        `uvm_info("ECRC_TX",
          "NON_FLIT TD=0 : no TLP Digest appended (Section 2.7.1)", UVM_LOW)
        return;
      end
    end
    else begin
      // FLIT : the trailer is selected by TS[2:0]. Accept td==1 as a request
      // for it so the existing sequences keep working unchanged.
      if ((tr.ts != `PCIe_TL_TS_1DW_ECRC) && (tr.td != 1'b1)) begin
        `uvm_info("ECRC_TX",
          $sformatf("FLIT TS=%03b TD=%0b : no ECRC trailer appended", tr.ts, tr.td), UVM_LOW)
        return;
      end
      if (tr.ts != `PCIe_TL_TS_1DW_ECRC) begin
        tr.ts = `PCIe_TL_TS_1DW_ECRC;
        // DW0[15:13] carries TS - patch the already serialized header.
        if (tr.serialized_tlp.size() > 0) begin
          tr.serialized_tlp[0][15:13] = `PCIe_TL_TS_1DW_ECRC;
        end
        `uvm_info("ECRC_TX",
          "FLIT TD=1 : TS[2:0] forced to 001b (1 DW Trailer containing ECRC)", UVM_LOW)
      end
    end

    digest = generate_ecrc(tr.serialized_tlp, tr.pkt_mode);

    tmp = new[tr.serialized_tlp.size() + `PCIe_TL_ECRC_DW];
    for (i = 0; i < tr.serialized_tlp.size(); i++)
      tmp[i] = tr.serialized_tlp[i];
    tmp[tr.serialized_tlp.size()] = digest;
    tr.serialized_tlp = tmp;

    tr.ecrc         = digest;
    tr.ecrc_present = 1'b1;

    tr.tlp_total_dw_count = tr.serialized_tlp.size();

    `uvm_info("ECRC_TX",
      $sformatf({"\n",
        "         ============================================================\n",
        "                    ECRC APPENDED BY THE RC TL MODEL\n",
        "         ============================================================\n",
        "         Packet Mode       : %s\n",
        "         Carried in        : %s\n",
        "         Bytes covered     : %0d  (header + OHC + payload)\n",
        "         TLP Digest value  : 0x%08h\n",
        "         New total TLP DWs : %0d\n",
        "         ============================================================"},
        tr.pkt_mode.name(),
        (tr.pkt_mode == FLIT) ? "1 DW Trailer (TS=001b)" : "TLP Digest field (TD=1)",
        (tr.serialized_tlp.size() - `PCIe_TL_ECRC_DW) * `PCIe_TL_DW_BYTES,
        digest,
        tr.serialized_tlp.size()), UVM_LOW)

  endfunction

  //==========================================================================
  //         IDLE FLIT / NOP FLIT BUILDER  -  Table 4-16        [ADDED]
  //
  //   Flit Type   TLP Bytes                       DLP 0,1                        DLP 2..5
  //   ---------   -----------------------------   ----------------------------   --------------
  //   IDLE Flit   NOP TLPs across all 236 Bytes   All 0s (Flit Seq Num = 0)      NOP2 DLLP
  //   NOP  Flit   NOP TLPs across all 236 Bytes   Flit Usage = 00b,              Any valid
  //                                               Flit Seq Num =                 encoding
  //                                               NEXT_TX_FLIT_SEQ_NUM - 1
  //                                               when Replay Command is 00b
  //
  //   Both are built entirely inside the Transaction Layer: the 236 byte TLP
  //   region is filled with 1 DW NOP TLPs (Type 00h, all zeros). The DLP bytes
  //   are the Data Link Layer's business and are left to the DL model.
  //==========================================================================
  virtual function void build_idle_or_nop_flit(PCIe_sequence_item tr);

    int i;

    tr.serialized_tlp = new[0];

    tr.flit_tlp_region = new[`PCIe_FLIT_TLP_REGION_DW];
    for (i = 0; i < `PCIe_FLIT_TLP_REGION_DW; i++)
      tr.flit_tlp_region[i] = `PCIe_FLIT_NOP_TLP_DW;

    tr.flit_tlp_dw_count = 0;
    tr.flit_nop_dw_count = `PCIe_FLIT_TLP_REGION_DW;

    tr.tlp_header_dw_count  = 0;
    tr.tlp_payload_dw_count = 0;
    tr.tlp_total_dw_count   = 0;
    tr.hdr_dw_count         = 0;

    // 236 bytes of NOP TLPs handed to the DL
    tr.tlp_data   = '0;
    tr.is_payload = 1'b0;            // Flit Usage = 00b
    tr.drive_flit = 1'b1;
    tr.ecrc_present = 1'b0;
    tr.ecrc_state   = PCIe_ECRC_ABSENT;

    if (tr.flit_type == PCIe_IDLE_flit) begin
      // IDLE : DLP0 and DLP1 all 0s (so Flit Sequence Number 0) and a NOP2
      // DLLP (all zeros, Figure 3-8) in DLP 2..5.
      tr.dllp_content            = `PCIe_FLIT_NOP2_DLLP;
      tr.NEXT_TX_FLIT_SEQ_NUM    = `PCIe_FLIT_IDLE_SEQ_NUM;
      tr.TX_ACKNACK_FLIT_SEQ_NUM = `PCIe_FLIT_IDLE_SEQ_NUM;
      tr.seq_num                 = `PCIe_FLIT_IDLE_SEQ_NUM;
    end
    else begin
      // NOP : any valid DLLP encoding is allowed in DLP 2..5; NOP2 is used
      // here. The Flit Sequence Number rule (NEXT_TX_FLIT_SEQ_NUM - 1) is a
      // Data Link Layer rule and is applied by the DL model.
      tr.dllp_content = `PCIe_FLIT_NOP2_DLLP;
    end

    `uvm_info("FLIT_IDLE_NOP",
      $sformatf({"\n",
        "         ============================================================\n",
        "                       %s FLIT BUILT BY THE RC TL MODEL\n",
        "                       (PCIe Base 6.1 Table 4-16)\n",
        "         ============================================================\n",
        "         Flit Kind         : %s\n",
        "         TLP region        : %0d DW of NOP TLPs (%0d bytes, all 0x00)\n",
        "         Flit Usage        : 00b (IDLE Flit or NOP Flit)\n",
        "         DLLP payload      : 0x%08h %s\n",
        "         Flit Seq Num rule : %s\n",
        "         ============================================================"},
        (tr.flit_type == PCIe_IDLE_flit) ? "IDLE" : "NOP",
        tr.flit_type.name(),
        `PCIe_FLIT_TLP_REGION_DW, `PCIe_FLIT_TLP_BYTES,
        tr.dllp_content,
        (tr.flit_type == PCIe_IDLE_flit) ? "(NOP2 DLLP)" : "(NOP2 DLLP - any valid encoding allowed)",
        (tr.flit_type == PCIe_IDLE_flit) ? "Flit Sequence Number = 0"
                                              : "Flit Sequence Number = NEXT_TX_FLIT_SEQ_NUM - 1"),
      UVM_LOW)

    print_tlp_data(tr);

    `uvm_info(get_type_name(), "[TL->DL] IDLE/NOP FLIT SENT TO DL", UVM_MEDIUM)
    tl_ap.write(tr);

  endfunction


endclass

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
  // FLOW CONTROL (PCIe Base 6.0 Sec 2.6)  -  VC0 only (TC0 -> VC0), dedicated credits
  //   RECEIVER side : the six TL buffers PH PD NPH NPD CPLH CPLD
  //       CREDITS_ALLOCATED / CREDITS_RECEIVED, overflow check (Eq 2-14)
  //   TRANSMITTER side : CREDIT_LIMIT / CREDITS_CONSUMED / CREDITS_REQUIRED,
  //       gate (Eq 2-11)  (CREDIT_LIMIT - CREDITS_REQUIRED) mod 2^FS <= 2^FS/2
  //   fc_dl_ap  : TL -> DL  initial credits / UpdateFC requests / status
  //   fc_dl_imp : DL -> TL  credit limits learnt from the peer InitFC1 / UpdateFC
  //   index 0 = P, 1 = NP, 2 = CPL
  //==========================================================================
  uvm_analysis_port #(PCIe_sequence_item) fc_dl_ap;
  uvm_analysis_imp_fc_from_dl #(PCIe_sequence_item, PCIe_RC_TL_model) fc_dl_imp;

  localparam int unsigned FC_FSH = `PCIe_FC_HDR_FIELD_BITS;    // field size, header credits
  localparam int unsigned FC_FSD = `PCIe_FC_DATA_FIELD_BITS;   // field size, data credits

  // ---- receiver buffers
  int unsigned fc_rx_max_h   [3];   // buffer size in credits (`PCIe_FC_MAX_HDR_CREDITS)
  int unsigned fc_rx_max_d   [3];   // buffer size in credits (`PCIe_FC_MAX_DATA_CREDITS)
  int unsigned fc_rx_occ_h   [3];   // credits held by TLPs sitting in the buffer
  int unsigned fc_rx_occ_d   [3];
  int unsigned fc_rx_alloc_h [3];   // CREDITS_ALLOCATED (cumulative, mod 2^FS)
  int unsigned fc_rx_alloc_d [3];
  int unsigned fc_rx_recv_h  [3];   // CREDITS_RECEIVED  (cumulative, mod 2^FS)
  int unsigned fc_rx_recv_d  [3];
  int unsigned fc_rx_adv_h   [3];   // CREDITS_ALLOCATED carried by the last InitFC/UpdateFC
  int unsigned fc_rx_adv_d   [3];
  int unsigned fc_rx_overflow_cnt;
  string       fc_rx_reason;

  // ---- transmitter terms
  int unsigned fc_tx_limit_h [3];   // CREDIT_LIMIT
  int unsigned fc_tx_limit_d [3];
  int unsigned fc_tx_cons_h  [3];   // CREDITS_CONSUMED
  int unsigned fc_tx_cons_d  [3];
  bit          fc_tx_inf_h   [3];
  bit          fc_tx_inf_d   [3];
  bit          fc_tx_limit_valid [3];   // InitFC1 received for the class

  // ---- statistics
  int unsigned fc_n_rx_tlp [3];
  int unsigned fc_n_tx_tlp [3];
  int unsigned fc_n_upd_published;
  int unsigned fc_n_peer_upd;
  int unsigned fc_n_periodic;
  int unsigned fc_n_blocked;

  function void fc_init();
    for (int c = 0; c < 3; c++) begin
      fc_rx_max_h[c]   = `PCIe_FC_MAX_HDR_CREDITS;
      fc_rx_max_d[c]   = `PCIe_FC_MAX_DATA_CREDITS;
      fc_rx_occ_h[c]   = 0;  fc_rx_occ_d[c] = 0;
      // 128 / 2048 are clamped to 127 / 2047 on the wire (see PCIe_FC_CLAMP_TO_SPEC_MAX)
      fc_rx_alloc_h[c] = PCIe_sequence_item::fc_wire_credits(fc_rx_max_h[c], `PCIe_FC_CLAMP_TO_SPEC_MAX);
      fc_rx_alloc_d[c] = PCIe_sequence_item::fc_wire_credits(fc_rx_max_d[c], `PCIe_FC_CLAMP_TO_SPEC_MAX);
      fc_rx_recv_h[c]  = 0;  fc_rx_recv_d[c] = 0;
      fc_rx_adv_h[c]   = fc_rx_alloc_h[c];
      fc_rx_adv_d[c]   = fc_rx_alloc_d[c];
      fc_tx_limit_h[c] = 0;  fc_tx_limit_d[c] = 0;
      fc_tx_cons_h[c]  = 0;  fc_tx_cons_d[c]  = 0;
      fc_tx_inf_h[c]   = 0;  fc_tx_inf_d[c]   = 0;
      fc_tx_limit_valid[c] = 0;
      fc_n_rx_tlp[c]   = 0;  fc_n_tx_tlp[c]   = 0;
    end
    fc_rx_overflow_cnt = 0;
    fc_n_upd_published = 0; fc_n_peer_upd = 0; fc_n_periodic = 0; fc_n_blocked = 0;
  endfunction

  function void fc_log(string msg);
    `uvm_info("RC_TL_FC", msg, UVM_LOW)
  endfunction

  function string fc_rx_status(int unsigned c);
    return $sformatf("%s: %s(MAX=%0d FREE=%0d ALLOCATED=%0d RECEIVED=%0d ADV=%0d) %s(MAX=%0d FREE=%0d ALLOCATED=%0d RECEIVED=%0d ADV=%0d)",
        PCIe_sequence_item::fc_cls_name(c),
        PCIe_sequence_item::fc_hdr_name(c), fc_rx_max_h[c], fc_rx_max_h[c] - fc_rx_occ_h[c], fc_rx_alloc_h[c], fc_rx_recv_h[c], fc_rx_adv_h[c],
        PCIe_sequence_item::fc_dat_name(c), fc_rx_max_d[c], fc_rx_max_d[c] - fc_rx_occ_d[c], fc_rx_alloc_d[c], fc_rx_recv_d[c], fc_rx_adv_d[c]);
  endfunction

  function int unsigned fc_tx_avail_h(int unsigned c);
    return PCIe_sequence_item::fc_mod_sub(fc_tx_limit_h[c], fc_tx_cons_h[c], FC_FSH);
  endfunction
  function int unsigned fc_tx_avail_d(int unsigned c);
    return PCIe_sequence_item::fc_mod_sub(fc_tx_limit_d[c], fc_tx_cons_d[c], FC_FSD);
  endfunction

  function string fc_tx_status(int unsigned c);
    return $sformatf("%s: %s(LIMIT=%0d CONSUMED=%0d AVAIL=%0d%s) %s(LIMIT=%0d CONSUMED=%0d AVAIL=%0d%s)",
        PCIe_sequence_item::fc_cls_name(c),
        PCIe_sequence_item::fc_hdr_name(c), fc_tx_limit_h[c], fc_tx_cons_h[c], fc_tx_avail_h(c), fc_tx_inf_h[c] ? " INF" : "",
        PCIe_sequence_item::fc_dat_name(c), fc_tx_limit_d[c], fc_tx_cons_d[c], fc_tx_avail_d(c), fc_tx_inf_d[c] ? " INF" : "");
  endfunction

  function void fc_print_buffers(string when_s);
    string s;
    s = $sformatf("\n  ================= RC_TL FC BUFFERS (VC0, dedicated) : %s =================\n", when_s);
    for (int c = 0; c < 3; c++) s = {s, "  ", fc_rx_status(c), "\n"};
    s = {s, "  ---- transmitter view of peer credits ----\n"};
    for (int c = 0; c < 3; c++) s = {s, "  ", fc_tx_status(c), "\n"};
    s = {s, "  ======================================================================"};
    fc_log(s);
  endfunction

  // ---- Eq 2-11 : (CREDIT_LIMIT - CREDITS_REQUIRED) mod 2^FS <= 2^FS / 2
  function bit fc_gate_ok(int unsigned limit, int unsigned required, int unsigned fs, bit inf);
    if (inf) return 1'b1;
    return (PCIe_sequence_item::fc_mod_sub(limit, required, fs) <= (32'd1 << (fs - 1)));
  endfunction

  function bit fc_tx_can_send(int unsigned c, int unsigned h, int unsigned d);
    if (!fc_tx_limit_valid[c]) return 1'b0;
    if (!fc_gate_ok(fc_tx_limit_h[c], PCIe_sequence_item::fc_mod_add(fc_tx_cons_h[c], h, FC_FSH), FC_FSH, fc_tx_inf_h[c])) return 1'b0;
    if (d != 0 && !fc_gate_ok(fc_tx_limit_d[c], PCIe_sequence_item::fc_mod_add(fc_tx_cons_d[c], d, FC_FSD), FC_FSD, fc_tx_inf_d[c])) return 1'b0;
    return 1'b1;
  endfunction

  //--------------------------------------------------------------------------
  // TL -> DL transactions (PCIe_sequence_item with the fc_* fields)
  //--------------------------------------------------------------------------
  function PCIe_sequence_item fc_make_item(pcie_fc_kind_e k, string reason, bit [2:0] mask);
    PCIe_sequence_item it = PCIe_sequence_item::type_id::create("fc_item");
    it.fc_kind   = k;
    it.fc_origin = "RC_TL";
    it.fc_reason = reason;
    for (int c = 0; c < 3; c++) it.set_fc_cls(c, fc_rx_alloc_h[c], fc_rx_alloc_d[c]);
    it.fc_cls_mask = mask;
    return it;
  endfunction

  // Initial credits : 128 hdr / 2048 data buffers (clamped on the wire)
  function void fc_publish_init();
    PCIe_sequence_item it = fc_make_item(FC_ADV_INIT, "INITIAL_ADVERTISEMENT", 3'b111);
    fc_print_buffers("INITIAL");
    fc_log($sformatf("[FC_TL->DL] INIT CREDITS  %s", it.fc_values_str()));
    fc_dl_ap.write(it);
  endfunction

  function void fc_publish_status(string why);
    PCIe_sequence_item it = fc_make_item(FC_STATUS, why, 3'b000);
    fc_dl_ap.write(it);
  endfunction

  // DL must put an UpdateFC DLLP on the wire for every class in 'mask'
  function void fc_publish_update(bit [2:0] mask, string reason);
    PCIe_sequence_item it;
    for (int c = 0; c < 3; c++) if (mask[c]) begin
      fc_rx_adv_h[c] = fc_rx_alloc_h[c];
      fc_rx_adv_d[c] = fc_rx_alloc_d[c];
    end
    it = fc_make_item(FC_ADV_UPDATE, reason, mask);
    fc_n_upd_published++;
    fc_log($sformatf("[FC_UPDATE_SCHEDULED] reason=%s classes=%03b (P,NP,CPL=bit0,1,2) -> %s",
                     reason, mask, it.fc_values_str()));
    fc_dl_ap.write(it);
  endfunction

  // periodic refresh (spec: at most every 30 us; Flit Mode debug value 10 us)
  task fc_run_periodic();
    forever begin
      #(`PCIe_FC_UPDATE_PERIOD_NS * 1ns);
      fc_n_periodic++;
      fc_publish_update(3'b111, "PERIODIC_REFRESH");
    end
  endtask

  //--------------------------------------------------------------------------
  // RECEIVER : a TLP reached the TL buffer.
  //   CREDIT_LIMIT (as seen by the peer = last advertised), CREDITS_CONSUMED
  //   (received before this TLP), CREDITS_REQUIRED (consumed + this TLP) and the
  //   Eq 2-11 / 2-14 check are computed and printed.
  //--------------------------------------------------------------------------
  function void fc_rx_account(int unsigned c, int unsigned h, int unsigned d, string desc);
    int unsigned lim_h, lim_d, cons_h, cons_d, req_h, req_d, gap_h, gap_d;
    bit ovf;
    lim_h  = fc_rx_adv_h[c];  lim_d  = fc_rx_adv_d[c];
    cons_h = fc_rx_recv_h[c]; cons_d = fc_rx_recv_d[c];
    req_h  = PCIe_sequence_item::fc_mod_add(cons_h, h, FC_FSH);
    req_d  = PCIe_sequence_item::fc_mod_add(cons_d, d, FC_FSD);
    gap_h  = PCIe_sequence_item::fc_mod_sub(lim_h, req_h, FC_FSH);
    gap_d  = PCIe_sequence_item::fc_mod_sub(lim_d, req_d, FC_FSD);
    // CREDITS_RECEIVED += this TLP, buffer occupancy += this TLP, then Eq 2-14
    fc_rx_recv_h[c] = req_h;
    fc_rx_recv_d[c] = req_d;
    fc_rx_occ_h[c] += h;
    fc_rx_occ_d[c] += d;
    ovf = (PCIe_sequence_item::fc_mod_sub(fc_rx_alloc_h[c], fc_rx_recv_h[c], FC_FSH) > (32'd1 << (FC_FSH - 1))) ||
          (PCIe_sequence_item::fc_mod_sub(fc_rx_alloc_d[c], fc_rx_recv_d[c], FC_FSD) > (32'd1 << (FC_FSD - 1))) ||
          (fc_rx_occ_h[c] > fc_rx_max_h[c]) || (fc_rx_occ_d[c] > fc_rx_max_d[c]);
    if (ovf) fc_rx_overflow_cnt++;
    fc_n_rx_tlp[c]++;
    fc_log($sformatf({"\n  ---- [FC_RX] %s -> class %s : needs %s=%0d %s=%0d ----\n",
        "    %s : CREDIT_LIMIT=%0d CREDITS_CONSUMED=%0d CREDITS_REQUIRED=%0d (LIMIT-REQUIRED) mod 2^%0d = %0d (<= %0d : %s)\n",
        "    %s : CREDIT_LIMIT=%0d CREDITS_CONSUMED=%0d CREDITS_REQUIRED=%0d (LIMIT-REQUIRED) mod 2^%0d = %0d (<= %0d : %s)\n",
        "    receiver: %s ALLOCATED=%0d RECEIVED=%0d FREE=%0d | %s ALLOCATED=%0d RECEIVED=%0d FREE=%0d"},
        desc, PCIe_sequence_item::fc_cls_name(c),
        PCIe_sequence_item::fc_hdr_name(c), h, PCIe_sequence_item::fc_dat_name(c), d,
        PCIe_sequence_item::fc_hdr_name(c), lim_h, cons_h, req_h, FC_FSH, gap_h, 1 << (FC_FSH-1),
        (gap_h <= (1 << (FC_FSH-1))) ? "OK" : "VIOLATION",
        PCIe_sequence_item::fc_dat_name(c), lim_d, cons_d, req_d, FC_FSD, gap_d, 1 << (FC_FSD-1),
        (gap_d <= (1 << (FC_FSD-1))) ? "OK" : "VIOLATION",
        PCIe_sequence_item::fc_hdr_name(c), fc_rx_alloc_h[c], fc_rx_recv_h[c], fc_rx_max_h[c] - fc_rx_occ_h[c],
        PCIe_sequence_item::fc_dat_name(c), fc_rx_alloc_d[c], fc_rx_recv_d[c], fc_rx_max_d[c] - fc_rx_occ_d[c]));
    if (ovf)
      `uvm_error("RC_TL_FC", $sformatf("RECEIVER_OVERFLOW class=%s : TLP exceeds advertised credits (Eq 2-14)",
                 PCIe_sequence_item::fc_cls_name(c)))
    fc_publish_status($sformatf("RX_%s", PCIe_sequence_item::fc_cls_name(c)));
  endfunction

  // UpdateFC scheduling (Sec 2.6.1.2 / 3.4.2). Returns 1 when an UpdateFC for class c is due now.
  //  1. MANDATORY header : the peer's available header credits are 0 and >= 1 was freed since the last UpdateFC
  //  2. MANDATORY data   : the peer's available data credits < one max-size TLP (Rx_MPS_Limit) and data was freed
  //  3. WATERMARK        : enough credits freed (spec permits more frequent UpdateFC; avoids one per packet)
  //  The 10 us periodic refresh comes from fc_run_periodic().
  function bit fc_should_update(int unsigned c);
    int unsigned unadv_h, unadv_d, peer_avail_h, peer_avail_d;
    unadv_h      = PCIe_sequence_item::fc_mod_sub(fc_rx_alloc_h[c], fc_rx_adv_h[c], FC_FSH);
    unadv_d      = PCIe_sequence_item::fc_mod_sub(fc_rx_alloc_d[c], fc_rx_adv_d[c], FC_FSD);
    peer_avail_h = PCIe_sequence_item::fc_mod_sub(fc_rx_adv_h[c], fc_rx_recv_h[c], FC_FSH);
    peer_avail_d = PCIe_sequence_item::fc_mod_sub(fc_rx_adv_d[c], fc_rx_recv_d[c], FC_FSD);
    if (unadv_h == 0 && unadv_d == 0)                              begin fc_rx_reason = "NOTHING_RELEASED";             return 1'b0; end
    if (unadv_h != 0 && peer_avail_h == 0)                         begin fc_rx_reason = "MANDATORY_HDR(avail=0)";       return 1'b1; end
    if (unadv_d != 0 && peer_avail_d < `PCIe_FC_MPS_CREDITS)       begin fc_rx_reason = "MANDATORY_DATA(avail<MPS)";    return 1'b1; end
    if (unadv_h >= `PCIe_FC_HDR_WATERMARK)                         begin fc_rx_reason = "WATERMARK_HDR";                return 1'b1; end
    if (unadv_d >= `PCIe_FC_DATA_WATERMARK)                        begin fc_rx_reason = "WATERMARK_DATA";               return 1'b1; end
    fc_rx_reason = "BELOW_THRESHOLD";
    return 1'b0;
  endfunction

  // The TL has consumed the TLP : free the buffer space (CREDITS_ALLOCATED grows),
  // maybe schedule an UpdateFC.
  function void fc_rx_release(int unsigned c, int unsigned h, int unsigned d, string desc);
    fc_rx_occ_h[c]   = (fc_rx_occ_h[c] > h) ? fc_rx_occ_h[c] - h : 0;
    fc_rx_occ_d[c]   = (fc_rx_occ_d[c] > d) ? fc_rx_occ_d[c] - d : 0;
    fc_rx_alloc_h[c] = PCIe_sequence_item::fc_mod_add(fc_rx_alloc_h[c], h, FC_FSH);
    fc_rx_alloc_d[c] = PCIe_sequence_item::fc_mod_add(fc_rx_alloc_d[c], d, FC_FSD);
    fc_log($sformatf("[FC_RX_RELEASE] %s class %s freed %s=%0d %s=%0d -> %s",
        desc, PCIe_sequence_item::fc_cls_name(c),
        PCIe_sequence_item::fc_hdr_name(c), h, PCIe_sequence_item::fc_dat_name(c), d, fc_rx_status(c)));
    if (fc_should_update(c)) begin
      fc_publish_update(3'b001 << c, fc_rx_reason);
    end
    else begin
      fc_log($sformatf("[FC_UPDATE_NOT_SENT] class %s : %s - not sent per packet",
          PCIe_sequence_item::fc_cls_name(c), fc_rx_reason));
    end
    fc_publish_status($sformatf("FREE_%s", PCIe_sequence_item::fc_cls_name(c)));
  endfunction

  //--------------------------------------------------------------------------
  // TRANSMITTER
  //--------------------------------------------------------------------------
  // Blocks until the Eq 2-11 gate passes for this TLP.
  task fc_tx_wait(int unsigned c, int unsigned h, int unsigned d, string desc);
    int unsigned waited_ns = 0;
    bit          announced = 0;
    while (!fc_tx_can_send(c, h, d)) begin
      if (!announced) begin
        announced = 1; fc_n_blocked++;
        fc_log($sformatf("[FC_TX_BLOCKED] %s class %s needs %s=%0d %s=%0d : %s",
            desc, PCIe_sequence_item::fc_cls_name(c), PCIe_sequence_item::fc_hdr_name(c), h,
            PCIe_sequence_item::fc_dat_name(c), d, fc_tx_status(c)));
      end
      #10ns;
      waited_ns += 10;
      if (waited_ns > 5 * `PCIe_FC_UPDATE_PERIOD_NS) begin
        `uvm_error("RC_TL_FC", $sformatf("FC_CREDIT_STARVATION : no UpdateFC for %0d ns, sending anyway: %s", waited_ns, fc_tx_status(c)))
        break;
      end
    end
    if (announced) fc_log($sformatf("[FC_TX_UNBLOCKED] %s after %0d ns : %s", desc, waited_ns, fc_tx_status(c)));
  endtask

  // Account the TLP that is being sent : CREDITS_CONSUMED += this TLP
  function void fc_tx_consume(int unsigned c, int unsigned h, int unsigned d, string desc);
    int unsigned req_h, req_d, gap_h, gap_d;
    req_h = PCIe_sequence_item::fc_mod_add(fc_tx_cons_h[c], h, FC_FSH);
    req_d = PCIe_sequence_item::fc_mod_add(fc_tx_cons_d[c], d, FC_FSD);
    gap_h = PCIe_sequence_item::fc_mod_sub(fc_tx_limit_h[c], req_h, FC_FSH);
    gap_d = PCIe_sequence_item::fc_mod_sub(fc_tx_limit_d[c], req_d, FC_FSD);
    fc_log($sformatf({"\n  ---- [FC_TX] %s -> class %s : needs %s=%0d %s=%0d ----\n",
        "    %s : CREDIT_LIMIT=%0d CREDITS_CONSUMED=%0d CREDITS_REQUIRED=%0d (LIMIT-REQUIRED) mod 2^%0d = %0d (<= %0d : %s)\n",
        "    %s : CREDIT_LIMIT=%0d CREDITS_CONSUMED=%0d CREDITS_REQUIRED=%0d (LIMIT-REQUIRED) mod 2^%0d = %0d (<= %0d : %s)"},
        desc, PCIe_sequence_item::fc_cls_name(c),
        PCIe_sequence_item::fc_hdr_name(c), h, PCIe_sequence_item::fc_dat_name(c), d,
        PCIe_sequence_item::fc_hdr_name(c), fc_tx_limit_h[c], fc_tx_cons_h[c], req_h, FC_FSH, gap_h, 1 << (FC_FSH-1),
        (fc_tx_inf_h[c] || gap_h <= (1 << (FC_FSH-1))) ? "OK" : "VIOLATION",
        PCIe_sequence_item::fc_dat_name(c), fc_tx_limit_d[c], fc_tx_cons_d[c], req_d, FC_FSD, gap_d, 1 << (FC_FSD-1),
        (fc_tx_inf_d[c] || d == 0 || gap_d <= (1 << (FC_FSD-1))) ? "OK" : "VIOLATION"));
    fc_tx_cons_h[c] = req_h;
    fc_tx_cons_d[c] = req_d;
    fc_n_tx_tlp[c]++;
    fc_publish_status($sformatf("TX_%s", PCIe_sequence_item::fc_cls_name(c)));
  endfunction

  // DL -> TL : InitFC1 / UpdateFC arrived from the peer. The received (cumulative)
  // CREDITS_ALLOCATED value becomes the new CREDIT_LIMIT.
  function void write_fc_from_dl(PCIe_sequence_item it);
    for (int c = 0; c < 3; c++) begin
      if (it.fc_cls_mask[c]) begin
        int unsigned old_h = fc_tx_limit_h[c];
        int unsigned old_d = fc_tx_limit_d[c];
        fc_tx_limit_h[c] = it.fc_hdr[c] & ((32'd1 << FC_FSH) - 1);
        fc_tx_limit_d[c] = it.fc_dat[c] & ((32'd1 << FC_FSD) - 1);
        fc_tx_inf_h[c]   = it.fc_hdr_inf[c];
        fc_tx_inf_d[c]   = it.fc_dat_inf[c];
        fc_tx_limit_valid[c] = 1'b1;
        if (it.fc_kind == FC_PEER_UPDATE) fc_n_peer_upd++;
        fc_log($sformatf("[FC_%s] class %s : CREDIT_LIMIT %s %0d -> %0d (+%0d)  %s %0d -> %0d (+%0d) | CONSUMED %s=%0d %s=%0d | AVAILABLE %s=%0d %s=%0d",
            (it.fc_kind == FC_PEER_INIT) ? "INITFC1_RX" : "UPDATEFC_RX",
            PCIe_sequence_item::fc_cls_name(c),
            PCIe_sequence_item::fc_hdr_name(c), old_h, fc_tx_limit_h[c], PCIe_sequence_item::fc_mod_sub(fc_tx_limit_h[c], old_h, FC_FSH),
            PCIe_sequence_item::fc_dat_name(c), old_d, fc_tx_limit_d[c], PCIe_sequence_item::fc_mod_sub(fc_tx_limit_d[c], old_d, FC_FSD),
            PCIe_sequence_item::fc_hdr_name(c), fc_tx_cons_h[c], PCIe_sequence_item::fc_dat_name(c), fc_tx_cons_d[c],
            PCIe_sequence_item::fc_hdr_name(c), fc_tx_avail_h(c), PCIe_sequence_item::fc_dat_name(c), fc_tx_avail_d(c)));
      end
    end
    fc_publish_status("PEER_CREDITS");
  endfunction

  function void fc_report();
    fc_log($sformatf({"\n  ========== RC_TL FLOW CONTROL SUMMARY ==========\n",
        "  TLPs received  : P=%0d NP=%0d CPL=%0d\n",
        "  TLPs sent      : P=%0d NP=%0d CPL=%0d\n",
        "  UpdateFC scheduled by this TL : %0d (periodic=%0d)  UpdateFC received from peer : %0d\n",
        "  TX blocked by credits : %0d   receiver overflows : %0d"},
        fc_n_rx_tlp[0], fc_n_rx_tlp[1], fc_n_rx_tlp[2], fc_n_tx_tlp[0], fc_n_tx_tlp[1], fc_n_tx_tlp[2],
        fc_n_upd_published, fc_n_periodic, fc_n_peer_upd, fc_n_blocked, fc_rx_overflow_cnt));
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

    n_tlp_rcvd++;

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

    cpl_write(cpl_it);

    // [ENUM] keep it for the sequence that is waiting on this tag
    if (cpl_rcvd.exists(cpl_it.tag))
      `uvm_warning("RC_TL_MODEL", $sformatf("DUPLICATE_COMPLETION tag=0x%0h - older one replaced", cpl_it.tag))
    cpl_rcvd[cpl_it.tag] = cpl_it;
    -> cpl_event;
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

  // Called by the RC controller driver BEFORE the TLP is handed to the TL:
  // blocks until the transmitter gate (Eq 2-11) passes for this TLP.
  task wait_for_fc_credits(PCIe_sequence_item tr);
    int unsigned c, h, d;
    if (!fc_applies(tr)) return;
    PCIe_sequence_item::fc_classify(tr.txn_type, tr.dir, tr.mem_deferrable, tr.data.size(), c, h, d);
    fc_tx_wait(c, h, d, tr.convert2string());
  endtask

  // Account the TLP being sent (CREDITS_CONSUMED / CREDITS_REQUIRED)
  function void fc_account_tlp(PCIe_sequence_item tr);
    int unsigned c, h, d;
    if (!fc_applies(tr)) return;
    PCIe_sequence_item::fc_classify(tr.txn_type, tr.dir, tr.mem_deferrable, tr.data.size(), c, h, d);
    fc_tx_consume(c, h, d, tr.convert2string());
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
    if (outstanding.exists(cpl.tag)) begin
      req_h = outstanding[cpl.tag];
      req_h.cpl_data   = cpl.cpl_data;
      req_h.cpl_status = cpl.cpl_status;
      outstanding.delete(cpl.tag);
      `uvm_info(get_type_name(),
        $sformatf("RC-TL got completion tag=0x%0h status=%0d dw=%0d",
                   cpl.tag, cpl.cpl_status, cpl.cpl_data.size()), UVM_LOW)
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
        dw2 = '0;
        hdr = new[3];
        hdr[0] = dw0;
        hdr[1] = dw1;
        hdr[2] = dw2;
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
    if (tr.is_64bit_addr())
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
         $sformatf("TLP is %0d DW (%0d B) which exceeds the %0d DW (%0d B) FLIT TLP region - multi-FLIT segmentation is not implemented, region left unpadded",
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

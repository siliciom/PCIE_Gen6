//=========================================================================================
// File         : PCIe_EP_TL_model.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_EP_controller_agent\PCIe_EP_TL_model.sv
//                Endpoint Transaction Layer model.
//                  - receives the 236 byte TLP region from the EP controller
//                    monitor (FLIT and NON-FLIT) over a UVM analysis imp
//                  - decodes the TLP header / OHC / payload
//                  - drives three memory models (mem3dw, mem4dw, io3dw) sized
//                    entirely from PCIe_defines.sv
//                  - recalculates ECRC on the receive side (Section 2.7.1)
//                  - builds a spec accurate Completion (Section 2.2.9) and
//                    publishes it to the EP DL model over an analysis port
// Author       :
// Date         : 2026-09-14
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

import typedef_enums :: *;

// Second analysis imp so the EP TL model can take input from BOTH the EP
// controller driver (tl_imp, the original path) and the EP controller monitor
// (tl_mon_imp, the 236 byte TLP region carved out of the 242 byte flit).
`uvm_analysis_imp_decl(_mon)

class PCIe_EP_TL_model extends uvm_component;

  `uvm_component_utils(PCIe_EP_TL_model)

  //--------------------------------------------------------------------------
  // TLM ports
  //--------------------------------------------------------------------------
  // Input from the EP controller driver (unchanged, original path).
  uvm_analysis_imp      #(PCIe_sequence_item, PCIe_EP_TL_model) tl_imp;
  // Input from the EP controller monitor : 236 byte TLP region.
  uvm_analysis_imp_mon  #(PCIe_sequence_item, PCIe_EP_TL_model) tl_mon_imp;
  // Output toward the EP DL model (TLPs and generated Completions).
  uvm_analysis_port     #(PCIe_sequence_item) tl_ap;

  PCIe_sequence_item item;

  PCIe_env_config    pcie_ecfg;
  //==========================================================================
  //                        THREE MEMORY MODELS
  //   Depth and width come from PCIe_defines.sv - there is not one hard coded
  //   size in this file.
  //     mem3dw : 3DW header (32-bit address) Memory Requests, FLIT + NON-FLIT
  //     mem4dw : 4DW header (64-bit address) Memory Requests, FLIT + NON-FLIT
  //     io3dw  : 3DW header I/O Requests,                     FLIT + NON-FLIT
  //==========================================================================
  bit [`PCIe_TL_MEM_DATA_W-1:0] mem3dw [0:`PCIe_TL_MEM3DW_DEPTH-1];
  bit [`PCIe_TL_MEM_DATA_W-1:0] mem4dw [0:`PCIe_TL_MEM4DW_DEPTH-1];
  bit [`PCIe_TL_MEM_DATA_W-1:0] io3dw  [0:`PCIe_TL_IO3DW_DEPTH -1];

  //==========================================================================
  //                     CONFIGURATION SPACE MODEL
  //   Two completely independent 4 KB (1024 DW) flat mirrors of the PCIe
  //   Configuration Space, each indexed by the byte offset (cfg_reg_num) >> 2:
  //     cfg_space_t0 / cfg_ro_mask_t0 : serves every CfgRd0/CfgWr0 (Type 0)
  //     cfg_space_t1 / cfg_ro_mask_t1 : serves every CfgRd1/CfgWr1 (Type 1)
  //   d_cfg_type1 (decoded from the Fmt/Type or FLIT Type field) selects
  //   which pair cfg_access() operates on for a given request - see
  //   service_request(). A Type 0 access can never see or modify Type 1
  //   state and vice versa.
  //
  //   cfg_ro_mask_* : per-DW read-only bit mask for the 64 B (16 DW)
  //                 Predefined Header that is actually implemented in each
  //                 mirror - a 1 in any bit position means that bit must
  //                 never be changed by a Configuration Write (Section
  //                 7.5.1.1 / 7.5.1.2 for Type 0, Section 7.5.1.3 for
  //                 Type 1).
  //   Only the header (index 0..PCIe_TL_CFG_HDR_DW_DEPTH-1) is populated in
  //   either mirror; the remaining locations exist purely so each array is
  //   a true 4 KB mirror for later use (e.g. Capability structures) and are
  //   completed with Unsupported Request today (see cfg_access()).
  //==========================================================================
  // Fixed-size array types - needed so the arrays can be passed to 'ref' formals
  typedef bit [31:0] cfg_space_arr_t [0:`PCIe_TL_CFG_SPACE_DW_DEPTH-1];
  typedef bit [31:0] cfg_mask_arr_t  [0:`PCIe_TL_CFG_HDR_DW_DEPTH-1];

  bit [31:0] cfg_space_t0  [0:`PCIe_TL_CFG_SPACE_DW_DEPTH-1];
  bit [31:0] cfg_ro_mask_t0[0:`PCIe_TL_CFG_HDR_DW_DEPTH-1];
  bit [31:0] cfg_space_t1  [0:`PCIe_TL_CFG_SPACE_DW_DEPTH-1];
  bit [31:0] cfg_ro_mask_t1[0:`PCIe_TL_CFG_HDR_DW_DEPTH-1];

  //--------------------------------------------------------------------------
  // Decoded view of the TLP currently being processed
  //--------------------------------------------------------------------------
  pkt_mode_e                            d_mode;
  bit [`PCIe_TL_FMTTYPE_W-1:0]          d_byte0;        // Fmt/Type (NFM) or Type (FM)
  pcie_tl_txn_type_e                    d_txn_type;
  pcie_tl_dir_e                         d_dir;
  bit                                   d_is_4dw;
  bit                                   d_has_data;
  bit                                   d_mem_locked;
  bit                                   d_mem_deferrable;
  bit [63:0]                            d_address;      // always 64-bit internally
  bit [`PCIe_TL_LEN_W-1:0]              d_length;
  bit [`PCIe_TL_TC_W-1:0]               d_tc;
  bit [`PCIe_TL_ATTR_W-1:0]             d_attr;
  bit [4:0]                             d_ohc;
  bit [2:0]                             d_ts;
  bit [`PCIe_TL_REQ_ID_W-1:0]           d_requester_id;
  bit [`PCIe_TL_CPL_TAG_W-1:0]          d_tag;          // 14-bit (Flit Mode max)
  bit                                   d_td;
  bit                                   d_ep;
  bit [`PCIe_TL_DW_BE_W-1:0]            d_first_dw_be;
  bit [`PCIe_TL_DW_BE_W-1:0]            d_last_dw_be;
  bit [1:0]                             d_at;
  bit                                   d_cfg_type1;
  // Configuration Request addressing (Figure 2-33 / Figure 2-52) - only
  // meaningful when d_txn_type == PCIe_TL_CFG.
  bit [`PCIe_TL_CFG_BUS_W-1:0]          d_cfg_bus_num;
  bit [`PCIe_TL_CFG_DEV_W-1:0]          d_cfg_dev_num;
  bit [`PCIe_TL_CFG_FN_W-1:0]           d_cfg_fn_num;
  bit [`PCIe_TL_CFG_EXT_REG_W-1:0]      d_cfg_ext_reg_num;
  bit [`PCIe_TL_CFG_REG_W-1:0]          d_cfg_reg_num;      // byte offset, DW aligned
  // Completion status override for the current request - defaults to SC and
  // is only steered to UR by the Configuration path today (cfg_access()),
  // but is intentionally generic so any other Request type can drive it the
  // same way later instead of build_completion() always hardcoding SC.
  bit [`PCIe_TL_CPL_STATUS_W-1:0]       cfg_status_override;
  int                                   d_hdr_base_dw;
  int                                   d_ohc_dw;
  int                                   d_hdr_dw;
  int                                   d_payload_dw;
  int                                   d_total_dw;
  bit                                   d_valid;
  bit [`PCIe_TL_DATA_DW_W-1:0]          d_payload [];

  //--------------------------------------------------------------------------
  // Statistics
  //--------------------------------------------------------------------------
  int unsigned n_tlp_rcvd;
  int unsigned n_cpl_sent;
  int unsigned n_ecrc_pass;
  int unsigned n_ecrc_fail;
  int unsigned n_cfg_rd;
  int unsigned n_cfg_wr;
  int unsigned n_cfg_ur;
  int unsigned n_dmwr_rcvd;        // [FLIT_SEG] DMWr TLPs received (one Cpl each)
  int unsigned n_cpl_split_txn;    // [FLIT_SEG] completions that had to be split
  int unsigned n_cpl_split_parts;  // [FLIT_SEG] CplD parts sent for them

  //==========================================================================

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
  uvm_analysis_imp_fc_from_dl #(PCIe_sequence_item, PCIe_EP_TL_model) fc_dl_imp;

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
      `uvm_error("EP_TL_FC", $sformatf("SHARED_CREDITS_ZERO_ON_VC0 (hdr=%0d data=%0d) : not permitted (Table 3-2 note 7)",
                 sz_h[FC_SHR], sz_d[FC_SHR]))
    fc_pool_mode = `PCIe_FC_POOL_MODE;
    if ($value$plusargs("FC_POOL_MODE=%d", pm)) begin
      if (pm <= 3) fc_pool_mode = pm;
      else `uvm_error("EP_TL_FC", $sformatf("+FC_POOL_MODE=%0d is not valid (0, 1, 2 or 3)", pm))
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
    `uvm_info("EP_TL_FC", msg, UVM_LOW)
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
    s = $sformatf("\n  ================= EP_TL FC BUFFERS (VC0, dedicated + shared) : %s =================\n", when_s);
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
    it.fc_origin = "EP_TL";
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
        `uvm_error("EP_TL_FC", $sformatf("ADVERTISED_OUTSTANDING_CREDITS_OVER_SPEC_MAX class %s %s (%s) : %0d/%0d outstanding (max %0d/%0d)",
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
      `uvm_error("EP_TL_FC", "FLIT_MODE_LOCAL_TLP_PREFIX_ON_NON_FLIT_TLP : Malformed TLP (Sec 2.2.10.3)")
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
      `uvm_error("EP_TL_FC", $sformatf("RECEIVER_OVERFLOW class=%s pool=%s : TLP exceeds advertised credits (Eq 2-14)",
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
      `uvm_error("EP_TL_FC", $sformatf("FC_RX_RELEASE class %s without a matching received TLP (%s)",
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
        `uvm_error("EP_TL_FC", $sformatf("FC_CREDIT_STARVATION : no UpdateFC for %0d ns, sending anyway on %s : SHR %s | DED %s",
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
    fc_log($sformatf({"\n  ========== EP_TL FLOW CONTROL SUMMARY ==========\n",
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


  function new(string name="PCIe_EP_TL_model", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info("EP_TL_MODEL","ENTERED_INTO_EP_TL_MODEL_BUILD_PHASE",UVM_LOW)

    tl_imp     = new("tl_imp",     this);
    tl_mon_imp = new("tl_mon_imp", this);
    tl_ap      = new("tl_ap",      this);
    fc_dl_ap   = new("fc_dl_ap",   this);
    fc_dl_imp  = new("fc_dl_imp",  this);
    fc_init();

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

  // Completion leaves the EP : CREDITS_CONSUMED of the RC's CPL buffer.
  // `PCIe_FC_GATE_EP_COMPLETIONS = 1 additionally checks the gate (non-blocking,
  // it runs from a function) and flags a violation.
  //   [FC SHARED] pool : shared first, dedicated when shared is full (Sec 2.6.1.1).
  //   A completion on dedicated credits gets the Flit Mode Local TLP Prefix, and
  //   the 236 B region is packed again. Must be called BEFORE the completion is
  //   printed / sent, so the prefix is part of what goes on the wire.
  function void fc_account_cpl(PCIe_sequence_item cpl);
    int unsigned c, h, d;
    bit          pool, ok, ded_ok;
    PCIe_sequence_item::fc_classify(PCIe_TL_CPL, PCIe_TL_READ, 1'b0, cpl.data.size(), c, h, d);
    // dedicated : Flit Mode only, and the 1 DW prefix must still fit in the region
    ded_ok = (cpl.pkt_mode == FLIT) && ((cpl.serialized_tlp.size() + 1) <= `PCIe_FLIT_TLP_REGION_DW);
    ok = fc_tx_pick_pool(c, h, d, ded_ok, pool);
    if (!ok && `PCIe_FC_GATE_EP_COMPLETIONS != 0)
      `uvm_error("EP_TL_FC", $sformatf("COMPLETION_SENT_WITHOUT_CREDITS : SHR %s | DED %s",
                 fc_tx_status(FC_SHR, c), fc_tx_status(FC_DED, c)))
    fc_log($sformatf("[FC_TX_POOL] COMPLETION tag=0x%0h class %s -> %s pool",
           cpl.tag, PCIe_sequence_item::fc_cls_name(c), fc_pool_name(pool)));
    if (pool == FC_DED) begin
      fc_add_ded_prefix(cpl);
      pack_completion_region(cpl);
    end
    fc_tx_consume(c, h, d, $sformatf("COMPLETION tag=0x%0h", cpl.tag), pool);
  endfunction

   task reset_phase(uvm_phase phase);
     phase.raise_objection(this);
     clear_all_memories();
     init_cfg_space();

    `uvm_info("EP_TL_MODEL",
      $sformatf({"\n",
        "         ============================================================\n",
        "                    EP TL MODEL MEMORY CONFIGURATION\n",
        "         ============================================================\n",
        "         Default packet mode : %s\n",
        "         mem3dw  : %0d x %0d-bit  (%0d bytes)\n",
        "         mem4dw  : %0d x %0d-bit  (%0d bytes)\n",
        "         io3dw   : %0d x %0d-bit  (%0d bytes)\n",
        "         cfg_space_t0 (Type0) : %0d x %0d-bit (%0d bytes) - %0d byte header populated\n",
        "         cfg_space_t1 (Type1) : %0d x %0d-bit (%0d bytes) - %0d byte header populated\n",
        "         ============================================================"},
        d_mode.name(),   // [FIX] %s for 'Default packet mode' had no argument ($sformatf: Too few arguments)
        `PCIe_TL_MEM3DW_DEPTH, `PCIe_TL_MEM_DATA_W, `PCIe_TL_MEM3DW_DEPTH*4,
        `PCIe_TL_MEM4DW_DEPTH, `PCIe_TL_MEM_DATA_W, `PCIe_TL_MEM4DW_DEPTH*4,
        `PCIe_TL_IO3DW_DEPTH,  `PCIe_TL_MEM_DATA_W, `PCIe_TL_IO3DW_DEPTH*4,
        `PCIe_TL_CFG_SPACE_DW_DEPTH, `PCIe_TL_MEM_DATA_W, `PCIe_TL_CFG_SPACE_BYTES,
        `PCIe_TL_CFG_HDR_BYTES,
        `PCIe_TL_CFG_SPACE_DW_DEPTH, `PCIe_TL_MEM_DATA_W, `PCIe_TL_CFG_SPACE_BYTES,
        `PCIe_TL_CFG_HDR_BYTES), UVM_LOW)

    `uvm_info("EP_TL_MODEL","EXIT_FROM_EP_TL_MODEL_RESET_PHASE",UVM_LOW)
     phase.drop_objection(this);
   endtask

  function void clear_all_memories();
    for (int i = 0; i < `PCIe_TL_MEM3DW_DEPTH; i++) mem3dw[i] = `PCIe_TL_MEM_INIT_VALUE;
    for (int i = 0; i < `PCIe_TL_MEM4DW_DEPTH; i++) mem4dw[i] = `PCIe_TL_MEM_INIT_VALUE;
    for (int i = 0; i < `PCIe_TL_IO3DW_DEPTH;  i++) io3dw [i] = `PCIe_TL_MEM_INIT_VALUE;
  endfunction

  //==========================================================================
  //  init_cfg_header_common - fills the 4 DW (offsets 000h-00Ch) that the
  //  Type 0 and the Type 1 Predefined Header share BYTE FOR BYTE (Section
  //  7.5.1.1) into whichever {space, ro_mask} pair the caller passes in.
  //  This is the single reusable engine behind both init_cfg_space_type0()
  //  and init_cfg_space_type1() - none of this logic is duplicated between
  //  the two header types.
  //
  //    +000h : Device ID [31:16] | Vendor ID [15:0]     - both HwInit, RO.
  //    +004h : Status [31:16] | Command [15:0]           - Table 7-4 / 7-5.
  //      Command RW bits : 0 IOSE, 1 MSE, 2 Bus Master, 6 Parity Err Rsp,
  //                        8 SERR# Enable, 10 Interrupt Disable. All other
  //      Command bits are RO (hardwired 0). Status is modelled fully RO for
  //      now: every architected bit is either RO or RW1C, and this model
  //      never sets an error/interrupt condition on its own, so RO-forced-0
  //      is equivalent until real RW1C emulation is added (see
  //      cfg_access()). Capabilities List (Status bit 4) is hardwired 0b
  //      since no Capability structures are implemented (deliberate
  //      deviation from Table 7-5).
  //    +008h : Class Code [31:8] | Revision ID [7:0]     - both RO/HwInit.
  //    +00Ch : BIST[31:24] | HeaderType[23:16] | LatencyTimer[15:8] |
  //            CacheLineSize[7:0]. Cache Line Size is the only RW field;
  //      Latency Timer, Header Type and BIST (BIST Capable = 0 here) are
  //      all RO/hardwired.
  //==========================================================================
  function void init_cfg_header_common(ref   cfg_space_arr_t space,
                                        ref   cfg_mask_arr_t  ro_mask,
                                        input bit [15:0] vendor_id,
                                        input bit [15:0] device_id,
                                        input bit [7:0]  revision_id,
                                        input bit [23:0] class_code,
                                        input bit [7:0]  header_type);

    space[`PCIe_TL_CFG_IDX_VENDOR_DEVICE_ID]    = {device_id, vendor_id};
    ro_mask[`PCIe_TL_CFG_IDX_VENDOR_DEVICE_ID]   = 32'hFFFF_FFFF;

    space[`PCIe_TL_CFG_IDX_COMMAND_STATUS]       = 32'h0000_0000;
    ro_mask[`PCIe_TL_CFG_IDX_COMMAND_STATUS]     =
      {16'hFFFF,                                    // Status  - fully RO
       16'hFAB8};                                   // Command - RO bits 15:11,9,7,5,4,3

    space[`PCIe_TL_CFG_IDX_REVID_CLASSCODE]      = {class_code, revision_id};
    ro_mask[`PCIe_TL_CFG_IDX_REVID_CLASSCODE]    = 32'hFFFF_FFFF;

    space[`PCIe_TL_CFG_IDX_CACHE_LAT_HDR_BIST]   = {8'h00, header_type, 8'h00, 8'h00};
    ro_mask[`PCIe_TL_CFG_IDX_CACHE_LAT_HDR_BIST] = 32'hFFFF_FF00;

  endfunction

  //==========================================================================
  //  init_cfg_space_type0 - power-on defaults for the 64 B Type 0
  //  Predefined Header (Section 7.5.1.1 / 7.5.1.2) into cfg_space_t0 /
  //  cfg_ro_mask_t0. DW0-DW3 come from init_cfg_header_common(); everything
  //  below is Type 0 specific (Section 7.5.1.2). Everything beyond the
  //  header (up to the 4 KB boundary) is left at `PCIe_TL_CFG_INIT_VALUE
  //  since no Capability structures are implemented here (see the note at
  //  the `PCIe_TL_CFG_SPACE_BYTES macro in PCIe_defines.sv).
  //==========================================================================
  function void init_cfg_space_type0();

    for (int i = 0; i < `PCIe_TL_CFG_SPACE_DW_DEPTH; i++)
      cfg_space_t0[i] = `PCIe_TL_CFG_INIT_VALUE;
    for (int i = 0; i < `PCIe_TL_CFG_HDR_DW_DEPTH; i++)
      cfg_ro_mask_t0[i] = 32'h0000_0000;   // default : fully read/write

    init_cfg_header_common(cfg_space_t0, cfg_ro_mask_t0,
                            `PCIe_TL_CFG_DEFAULT_VENDOR_ID,
                            `PCIe_TL_CFG_DEFAULT_DEVICE_ID,
                            `PCIe_TL_CFG_DEFAULT_REVISION_ID,
                            `PCIe_TL_CFG_DEFAULT_CLASS_CODE,
                            `PCIe_TL_CFG_DEFAULT_HEADER_TYPE);

    //------------------------------------------------------------------------
    // +010h..024h : BAR0-5                              - Section 7.5.1.2.1
    //   No Memory/IO ranges are decoded by this model, so every BAR is left
    //   "Unimplemented Base Address register" and hardwired to zero, exactly
    //   as the spec permits.
    //------------------------------------------------------------------------
  // BAR0 : 32-bit memory, 4 KB
cfg_space_t0  [`PCIe_TL_CFG_IDX_BAR0] = 32'h0000_0000;
cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_BAR0] = 32'h0000_0FFF;   // low 12 bits fixed 0 ? 4 KB

// BAR1 : IO, 256 bytes
cfg_space_t0  [`PCIe_TL_CFG_IDX_BAR1] = 32'h0000_0001;   // bit0 = 1 ? IO BAR
cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_BAR1] = 32'h0000_00FF;   // low 8 bits fixed ? 256 B

// BAR2 + BAR3 : 64-bit prefetchable memory, 1 MB (uses 2 boxes)
cfg_space_t0  [`PCIe_TL_CFG_IDX_BAR2] = 32'h0000_000C;   // bits[3:0]=1100 ? 64-bit, prefetchable
cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_BAR2] = 32'h000F_FFFF;   // low 20 bits fixed ? 1 MB
cfg_space_t0  [`PCIe_TL_CFG_IDX_BAR3] = 32'h0000_0000;   // upper 32 bits of the address
cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_BAR3] = 32'h0000_0000;   // fully writable

// BAR4, BAR5 : not used
cfg_space_t0  [`PCIe_TL_CFG_IDX_BAR4] = 32'h0000_0000;
cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_BAR4] = 32'hFFFF_FFFF;
cfg_space_t0  [`PCIe_TL_CFG_IDX_BAR5] = 32'h0000_0000;
cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_BAR5] = 32'hFFFF_FFFF; 
    //------------------------------------------------------------------------
    // +028h : Cardbus CIS Pointer                        - Section 7.5.1.2.2
    //   "does not apply to PCI Express and must be hardwired to Zero."
    //------------------------------------------------------------------------
    cfg_space_t0[`PCIe_TL_CFG_IDX_CARDBUS_CIS]  = 32'h0000_0000;
    cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_CARDBUS_CIS] = 32'hFFFF_FFFF;

    //------------------------------------------------------------------------
    // +02Ch : Subsystem ID[31:16] | Subsystem Vendor ID[15:0]
    //                                                    - Section 7.5.1.2.3
    //------------------------------------------------------------------------
    cfg_space_t0[`PCIe_TL_CFG_IDX_SUBSYS_IDS] =
      {`PCIe_TL_CFG_DEFAULT_SUBSYS_ID, `PCIe_TL_CFG_DEFAULT_SUBSYS_VID};
    cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_SUBSYS_IDS] = 32'hFFFF_FFFF;

    //------------------------------------------------------------------------
    // +030h : Expansion ROM Base Address
    //   No expansion ROM implemented -> hardwired to zero.
    //------------------------------------------------------------------------
    cfg_space_t0[`PCIe_TL_CFG_IDX_EXPROM_BAR]  = 32'h0000_0000;
    cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_EXPROM_BAR] = 32'hFFFF_FFFF;

    //------------------------------------------------------------------------
    // +034h : Reserved[31:8] | Capabilities Pointer[7:0]
    //   Capabilities are explicitly out of scope for this model, so the
    //   pointer is forced to 00h instead of the spec-required non-zero value
    //   (Section 7.5.1.1.11) - documented deviation.
    //------------------------------------------------------------------------
    cfg_space_t0[`PCIe_TL_CFG_IDX_CAP_PTR]  = 32'h0000_0000;
    cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_CAP_PTR] = 32'hFFFF_FFFF;

    //------------------------------------------------------------------------
    // +038h : Reserved
    //------------------------------------------------------------------------
    cfg_space_t0[`PCIe_TL_CFG_IDX_RESERVED_038]  = 32'h0000_0000;
    cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_RESERVED_038] = 32'hFFFF_FFFF;

    //------------------------------------------------------------------------
    // +03Ch : Max_Lat[31:24] | Min_Gnt[23:16] | Int Pin[15:8] | Int Line[7:0]
    //                                                  - Section 7.5.1.1.12/13
    //   Interrupt Line is RW (software-programmed routing); Interrupt Pin is
    //   RO (fixed at INTA# here); Min_Gnt/Max_Lat are obsolete and RO(0).
    //------------------------------------------------------------------------
    cfg_space_t0[`PCIe_TL_CFG_IDX_INTLINE_INTPIN] =
      {8'h00, 8'h00, `PCIe_TL_CFG_DEFAULT_INT_PIN, 8'h00};
    cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_INTLINE_INTPIN] = 32'hFFFF_FF00;
 
  endfunction

  //==========================================================================
  //  init_cfg_space_type1 - power-on defaults for the 64 B Type 1
  //  (PCI-to-PCI Bridge) Predefined Header (Section 7.5.1.3 / PCI-to-PCI
  //  Bridge Architecture Spec 1.2, Figure 7-5/Table 7-11) into cfg_space_t1
  //  / cfg_ro_mask_t1. DW0-DW3 come from init_cfg_header_common(), exactly
  //  the same reusable engine init_cfg_space_type0() uses; everything below
  //  is Type 1 specific. Only the header is populated - no Capability
  //  structures (same documented deviation as Type 0).
  //==========================================================================
  function void init_cfg_space_type1();

    for (int i = 0; i < `PCIe_TL_CFG_SPACE_DW_DEPTH; i++)
      cfg_space_t1[i] = `PCIe_TL_CFG_INIT_VALUE;
    for (int i = 0; i < `PCIe_TL_CFG_HDR_DW_DEPTH; i++)
      cfg_ro_mask_t1[i] = 32'h0000_0000;   // default : fully read/write

    init_cfg_header_common(cfg_space_t1, cfg_ro_mask_t1,
                            `PCIe_TL_CFG_T1_DEFAULT_VENDOR_ID,
                            `PCIe_TL_CFG_T1_DEFAULT_DEVICE_ID,
                            `PCIe_TL_CFG_T1_DEFAULT_REVISION_ID,
                            `PCIe_TL_CFG_T1_DEFAULT_CLASS_CODE,
                            `PCIe_TL_CFG_T1_DEFAULT_HEADER_TYPE);

    //------------------------------------------------------------------------
    // +010h..014h : BAR0-1                                     - Table 7-11
    //   Same "no Memory/IO ranges decoded" deviation as the Type 0 BARs.
    //------------------------------------------------------------------------
    cfg_space_t1[`PCIe_TL_CFG_T1_IDX_BAR0] = 32'h0000_0000;
    cfg_space_t1[`PCIe_TL_CFG_T1_IDX_BAR1] = 32'h0000_0000;
    cfg_ro_mask_t1[`PCIe_TL_CFG_T1_IDX_BAR0] = 32'hFFFF_FFFF;  // [FIX] BAR hardwired to 0 (unimplemented) as documented above
    cfg_ro_mask_t1[`PCIe_TL_CFG_T1_IDX_BAR1] = 32'hFFFF_FFFF;  // [FIX] BAR hardwired to 0 (unimplemented) as documented above

    //------------------------------------------------------------------------
    // +018h : Secondary Latency Timer[31:24] | Subordinate Bus[23:16] |
    //         Secondary Bus[15:8] | Primary Bus[7:0]
    //   The three Bus Number fields are RW (software-programmed by the Bus
    //   Enumerator, exactly like real bridge hardware); Secondary Latency
    //   Timer is obsolete and RO(0), same treatment as Type 0's Latency
    //   Timer.
    //------------------------------------------------------------------------
    cfg_space_t1[`PCIe_TL_CFG_T1_IDX_BUSNUM_SECLAT] = 32'h0000_0000;
    cfg_ro_mask_t1[`PCIe_TL_CFG_T1_IDX_BUSNUM_SECLAT] = 32'hFF00_0000;

    //------------------------------------------------------------------------
    // +01Ch : Secondary Status[31:16] | I/O Limit[15:8] | I/O Base[7:0]
    //   No I/O range is decoded behind this model - I/O Base/Limit are left
    //   "32-bit I/O addressing not supported" and hardwired to zero, same
    //   deviation as the unimplemented Type 0 BARs. Secondary Status is
    //   modelled fully RO, same treatment as primary Status.
    //------------------------------------------------------------------------
    cfg_space_t1[`PCIe_TL_CFG_T1_IDX_SECSTATUS_IOLIMIT_BASE] = 32'h0000_0000;
    cfg_ro_mask_t1[`PCIe_TL_CFG_T1_IDX_SECSTATUS_IOLIMIT_BASE] = 32'hFFFF_FFFF;

    //------------------------------------------------------------------------
    // +020h : Memory Limit[31:16] | Memory Base[15:0]
    //   No memory range decoded behind this model -> hardwired to zero.
    //------------------------------------------------------------------------
    cfg_space_t1[`PCIe_TL_CFG_T1_IDX_MEM_LIMIT_BASE] = 32'h0000_0000;
    cfg_ro_mask_t1[`PCIe_TL_CFG_T1_IDX_MEM_LIMIT_BASE] = 32'hFFFF_FFFF;

    //------------------------------------------------------------------------
    // +024h : Prefetchable Memory Limit[31:16] | Prefetchable Memory Base[15:0]
    //   "Bridge does not support prefetchable memory range" -> hardwired to
    //   zero (both nibbles 0h per Section 3.2.5.6/8 encoding).
    //------------------------------------------------------------------------
    cfg_space_t1[`PCIe_TL_CFG_T1_IDX_PREF_MEM_LIMIT_BASE] = 32'h0000_0000;
    cfg_ro_mask_t1[`PCIe_TL_CFG_T1_IDX_PREF_MEM_LIMIT_BASE] = 32'hFFFF_FFFF;

    //------------------------------------------------------------------------
    // +028h / +02Ch : Prefetchable Base/Limit Upper 32 Bits
    //   No 64-bit prefetchable range implemented -> hardwired to zero.
    //------------------------------------------------------------------------
    cfg_space_t1[`PCIe_TL_CFG_T1_IDX_PREF_BASE_UPPER32]  = 32'h0000_0000;
    cfg_space_t1[`PCIe_TL_CFG_T1_IDX_PREF_LIMIT_UPPER32] = 32'h0000_0000;
    cfg_ro_mask_t1[`PCIe_TL_CFG_T1_IDX_PREF_BASE_UPPER32]  = 32'hFFFF_FFFF;
    cfg_ro_mask_t1[`PCIe_TL_CFG_T1_IDX_PREF_LIMIT_UPPER32] = 32'hFFFF_FFFF;

    //------------------------------------------------------------------------
    // +030h : I/O Limit Upper 16[31:16] | I/O Base Upper 16[15:0]
    //   No 32-bit I/O range implemented -> hardwired to zero.
    //------------------------------------------------------------------------
    cfg_space_t1[`PCIe_TL_CFG_T1_IDX_IO_LIMIT_BASE_UPPER16] = 32'h0000_0000;
    cfg_ro_mask_t1[`PCIe_TL_CFG_T1_IDX_IO_LIMIT_BASE_UPPER16] = 32'hFFFF_FFFF;

    //------------------------------------------------------------------------
    // +034h : Reserved[31:8] | Capability Pointer[7:0]
    //   Capabilities are out of scope, same documented deviation as Type 0 -
    //   the pointer is forced to 00h.
    //------------------------------------------------------------------------
    cfg_space_t1[`PCIe_TL_CFG_T1_IDX_CAP_PTR] = 32'h0000_0000;
    cfg_ro_mask_t1[`PCIe_TL_CFG_T1_IDX_CAP_PTR] = 32'hFFFF_FFFF;

    //------------------------------------------------------------------------
    // +038h : Expansion ROM Base Address
    //   No expansion ROM implemented -> hardwired to zero.
    //------------------------------------------------------------------------
    cfg_space_t1[`PCIe_TL_CFG_T1_IDX_EXPROM_BAR] = 32'h0000_0000;
    cfg_ro_mask_t1[`PCIe_TL_CFG_T1_IDX_EXPROM_BAR] = 32'hFFFF_FFFF;

    //------------------------------------------------------------------------
    // +03Ch : Bridge Control[31:16] | Interrupt Pin[15:8] | Interrupt Line[7:0]
    //   Interrupt Line is RW; Interrupt Pin is RO (fixed at INTA# here).
    //   Bridge Control RW bits modelled : 16 Parity Err Resp Enable,
    //   17 SERR# Enable, 22 Secondary Bus Reset - the remaining Bridge
    //   Control bits are RO/hardwired 0 in this behavioural model.
    //------------------------------------------------------------------------
    cfg_space_t1[`PCIe_TL_CFG_T1_IDX_BRIDGE_CTRL_INTPIN] =
      {16'h0000, `PCIe_TL_CFG_T1_DEFAULT_INT_PIN, 8'h00};
    cfg_ro_mask_t1[`PCIe_TL_CFG_T1_IDX_BRIDGE_CTRL_INTPIN] = 32'hFFBF_FF00;
 
  endfunction

  //==========================================================================
  //  init_cfg_space - top level entry point called from reset_phase().
  //  Rebuilds BOTH independent header mirrors (Type 0 and Type 1) so either
  //  one always starts from a clean, spec-accurate power-on state.
  //==========================================================================
  function void init_cfg_space();
    init_cfg_space_type0();
    init_cfg_space_type1();
  endfunction

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    fc_report();
    `uvm_info("EP_TL_MODEL",
      $sformatf({"EP_TL_SUMMARY : tlp_received=%0d completions_sent=%0d ecrc_pass=%0d ecrc_fail=%0d ",
                  "cfg_rd=%0d cfg_wr=%0d cfg_unsupported=%0d"},
                 n_tlp_rcvd, n_cpl_sent, n_ecrc_pass, n_ecrc_fail,
                 n_cfg_rd, n_cfg_wr, n_cfg_ur), UVM_LOW)
    `uvm_info("EP_TL_FLIT_SEG",
      $sformatf("EP_FLIT_SEG_SUMMARY : DMWr received=%0d (one Cpl each)  split completions=%0d  CplD parts sent=%0d",
                 n_dmwr_rcvd, n_cpl_split_txn, n_cpl_split_parts), UVM_LOW)
  endfunction

  //==========================================================================
  //  write      : original path, EP controller driver -> EP DL model
  //==========================================================================
  function void write(PCIe_sequence_item item);
    `uvm_info("EP_TL_MODEL",
      $sformatf("TL -> DL (driver path): drive_flit=%0d", item.drive_flit), UVM_MEDIUM)
    tl_ap.write(item);
  endfunction

  //==========================================================================
  //  write_mon  : EP controller monitor -> EP TL model
  //
  //   The monitor has already stripped the 6 DLP bytes off the 242 byte flit,
  //   so what arrives here is the 236 byte TLP region and nothing else.
  //==========================================================================
  function void write_mon(PCIe_sequence_item item);

    PCIe_sequence_item cpl;
    int unsigned fc_c, fc_h, fc_d;
    bit          fc_pool;                      // [FC SHARED] pool given by the prefix

    n_tlp_rcvd++;

    // [FC SHARED] Flit Mode Local TLP Prefix : read "TLP Uses Dedicated Credits", remove it
    fc_pool = fc_strip_prefix(item);

    `uvm_info("EP_TL_MODEL",
      $sformatf("RECEIVED_236B_TLP_FROM_EP_DL_MODEL #%0d mode=%s",
                 n_tlp_rcvd, item.pkt_mode.name()), UVM_LOW)

    // decode_tlp()/get_dw()/check_ecrc_rx() all read item.tlp_data
    // (the 236 byte TLP region filled by the EP DL model).
    if (item.tlp_data == '0)
      `uvm_warning("EP_TL_MODEL",
        "RECEIVED_ITEM_HAS_ALL_ZERO_tlp_data - EP DL model did not fill the 236B TLP region")

    d_mode = item.pkt_mode;

    `uvm_info("EP_TL_MODEL",
      $sformatf("DECODE_INPUT : mode=%s DW0=%08h DW1=%08h DW2=%08h DW3=%08h",
                 d_mode.name(), get_dw(item,0), get_dw(item,1),
                 get_dw(item,2), get_dw(item,3)), UVM_LOW)

    decode_tlp(item);

    if (!d_valid) begin
      `uvm_info("EP_TL_MODEL",
        $sformatf({"DECODED_AS_NOP_OR_UNSUPPORTED_TLP (mode=%s byte0=0x%02h) : ",
                   "no memory access, no completion"}, d_mode.name(), d_byte0), UVM_LOW)
      return;
    end

    print_decoded_tlp(item);

    // ---- receive side ECRC recalculation (Section 2.7.1) -------------------
    check_ecrc_rx(item);

    // ---- FLOW CONTROL : the TLP is now sitting in the VC0 buffer -----------
    PCIe_sequence_item::fc_classify(d_txn_type, d_dir, d_mem_deferrable, d_payload_dw,
                                    fc_c, fc_h, fc_d);
    fc_rx_account(fc_c, fc_h, fc_d,
                  $sformatf("%s %s len=%0d", d_txn_type.name(), d_dir.name(), d_payload_dw), fc_pool);

    // ---- drive the memory models ------------------------------------------
    cpl = PCIe_sequence_item::type_id::create("ep_tl_completion");
    service_request(item, cpl);

    // ---- FLOW CONTROL : request serviced -> buffer space is free again.
    //      CREDITS_ALLOCATED grows; UpdateFC only goes out when it is needed
    //      (mandatory / watermark / periodic), never once per packet.
    fc_rx_release(fc_c, fc_h, fc_d,
                  $sformatf("%s %s len=%0d", d_txn_type.name(), d_dir.name(), d_payload_dw));

  endfunction

  //==========================================================================
  //                          TLP DECODE
  //==========================================================================
  function void decode_tlp(PCIe_sequence_item item);

    bit [`PCIe_TL_DATA_DW_W-1:0] dw0, dw1, dw2, dw3;
    bit [`PCIe_TL_DATA_DW_W-1:0] ohc_val;
    int i;

    d_valid          = 1'b0;
    d_ohc_dw         = 0;
    d_mem_locked     = 1'b0;
    d_mem_deferrable = 1'b0;
    d_cfg_type1      = 1'b0;
    d_td             = 1'b0;
    d_ts             = 3'b000;
    d_ohc            = 5'b00000;
    d_cfg_bus_num     = '0;
    d_cfg_dev_num     = '0;
    d_cfg_fn_num      = '0;
    d_cfg_ext_reg_num = '0;
    d_cfg_reg_num     = '0;

    dw0 = get_dw(item, 0);
    dw1 = get_dw(item, 1);
    dw2 = get_dw(item, 2);
    dw3 = get_dw(item, 3);

    d_byte0 = dw0[31:24];

    // A 1 DW all-zero header is a NOP TLP (FLIT Type 00h) - nothing to service.
    if (d_byte0 == `PCIe_FLITTYPE_NOP && d_mode == FLIT) begin
      `uvm_info("EP_TL_DECODE","FIRST_TLP_IN_REGION_IS_A_NOP_TLP",UVM_LOW)
      return;
    end

    if (d_mode == FLIT) decode_flit_header (dw0, dw1, dw2, dw3);
    else                decode_nonflit_header(dw0, dw1, dw2, dw3);

    if (!d_valid)
      return;

    //----------------------------------------------------------------------
    // OHC-A1 / OHC-A2 : the single OHC DW sits immediately after the Header
    // Base and carries [7:4] Last DW BE, [3:0] First DW BE. When no OHC is
    // present the byte enables are implied (all bytes enabled).
    //----------------------------------------------------------------------
    if ((d_mode == FLIT) && (d_ohc_dw != 0)) begin
      ohc_val       = get_dw(item, d_hdr_base_dw);
      d_last_dw_be  = ohc_val[7:4];
      d_first_dw_be = ohc_val[3:0];
      `uvm_info("EP_TL_DECODE",
        $sformatf("OHC_DW=%08h -> first_dw_be=%04b last_dw_be=%04b",
                   ohc_val, d_first_dw_be, d_last_dw_be), UVM_LOW)
    end

    //----------------------------------------------------------------------
    // Payload : 0 to 1024 DW. Length==0 encodes 1024 DW.
    //----------------------------------------------------------------------
    d_hdr_dw     = d_hdr_base_dw + d_ohc_dw;
    d_payload_dw = d_has_data ? ((d_length == 10'd0) ? `PCIe_TL_MAX_PAYLOAD_DW : int'(d_length)) : 0;
    d_total_dw   = d_hdr_dw + d_payload_dw;

    d_payload = new[d_payload_dw];
    for (i = 0; i < d_payload_dw; i++) begin
      if ((((d_hdr_dw + i) * `PCIe_TL_DW_BYTES) + `PCIe_TL_DW_BYTES) <= `PCIe_TLP_DATA_BYTE_W)
        d_payload[i] = get_dw(item, d_hdr_dw + i);
      else begin
        // The 236 byte region only holds 59 DW. A longer TLP spans several
        // flits; multi-flit reassembly is not modelled here (same limitation
        // the RC TL model already flags on the transmit side).
        d_payload[i] = '0;
        if (i == (`PCIe_FLIT_TLP_REGION_DW - d_hdr_dw))
          `uvm_warning("EP_TL_DECODE",
            $sformatf("TLP claims %0d payload DW but only %0d DW fit in the %0d byte region - remaining DW read as 0",
                       d_payload_dw, `PCIe_FLIT_TLP_REGION_DW - d_hdr_dw, `PCIe_TLP_DATA_BYTE_W))
      end
    end

    // Mirror onto the item so downstream components can see the same view
    item.txn_type     = d_txn_type;
    item.dir          = d_dir;
    item.address      = d_address[`PCIe_TL_ADDR_W-1:0];
    item.length       = d_length;
    item.tc           = d_tc;
    item.attr         = d_attr;
    item.ohc          = d_ohc;
    item.ts           = d_ts;
    item.requester_id = d_requester_id;
    item.tag          = d_tag[`PCIe_TL_TAG_W-1:0];
    item.td           = d_td;
    item.ep           = d_ep;
    item.first_dw_be  = d_first_dw_be;
    item.last_dw_be   = d_last_dw_be;
    item.at           = d_at;
    item.cfg_type1    = d_cfg_type1;
    item.cfg_bus_num     = d_cfg_bus_num;
    item.cfg_dev_num     = d_cfg_dev_num;
    item.cfg_fn_num      = d_cfg_fn_num;
    item.cfg_ext_reg_num = d_cfg_ext_reg_num;
    item.cfg_reg_num     = d_cfg_reg_num;
    item.mem_locked   = d_mem_locked;
    item.mem_deferrable = d_mem_deferrable;
    item.hdr_dw_count = d_hdr_dw;
    item.tlp_header_dw_count  = d_hdr_dw;
    item.tlp_payload_dw_count = d_payload_dw;
    item.tlp_total_dw_count   = d_total_dw;
    item.flit_type    = PCIe_PAYLOAD_flit;

    print_attr_table_check(item, "RX_REQUEST");      // [ATTR] info : RO / IDO / NS table check

  endfunction

  //--------------------------------------------------------------------------
  // FLIT MODE header decode  (mirror of PCIe_RC_TL_model::serialize_flit_header)
  //   DW0 [31:24] Type   [23:21] TC  [20:16] OHC  [15:13] TS  [12:10] Attr  [9:0] Length
  //   DW1 [31:16] Requester ID  [15] EP  [14] R  [13:0] Tag
  //   DW2 (/DW3) Address, then the OHC DW when OHC[0] is set
  //--------------------------------------------------------------------------
  function void decode_flit_header(bit [31:0] dw0, bit [31:0] dw1,
                                   bit [31:0] dw2, bit [31:0] dw3);

    d_tc           = dw0[23:21];
    d_ohc          = dw0[20:16];
    d_ts           = dw0[15:13];
    d_attr         = dw0[12:10];
    d_length       = dw0[9:0];
    d_requester_id = dw1[31:16];
    d_ep           = dw1[15];
    d_tag          = dw1[13:0];

    // ECRC is carried in a Trailer in Flit Mode, selected by TS[2:0]
    d_td = (d_ts == `PCIe_TL_TS_1DW_ECRC);

    d_ohc_dw = (d_ohc[0] == 1'b1) ? `PCIe_TL_OHC_A_DW : 0;

    case (d_byte0)
      `PCIe_FLITTYPE_MRD_32   : begin d_txn_type=PCIe_TL_MEM; d_dir=PCIe_TL_READ;  d_is_4dw=0; d_has_data=0; end
      `PCIe_FLITTYPE_MWR_32   : begin d_txn_type=PCIe_TL_MEM; d_dir=PCIe_TL_WRITE; d_is_4dw=0; d_has_data=1; end
      `PCIe_FLITTYPE_MRDLK_32 : begin d_txn_type=PCIe_TL_MEM; d_dir=PCIe_TL_READ;  d_is_4dw=0; d_has_data=0; d_mem_locked=1; end
      `PCIe_FLITTYPE_DMWR_32  : begin d_txn_type=PCIe_TL_MEM; d_dir=PCIe_TL_WRITE; d_is_4dw=0; d_has_data=1; d_mem_deferrable=1; end
      `PCIe_FLITTYPE_MRD_64   : begin d_txn_type=PCIe_TL_MEM; d_dir=PCIe_TL_READ;  d_is_4dw=1; d_has_data=0; end
      `PCIe_FLITTYPE_MWR_64   : begin d_txn_type=PCIe_TL_MEM; d_dir=PCIe_TL_WRITE; d_is_4dw=1; d_has_data=1; end
      `PCIe_FLITTYPE_MRDLK_64 : begin d_txn_type=PCIe_TL_MEM; d_dir=PCIe_TL_READ;  d_is_4dw=1; d_has_data=0; d_mem_locked=1; end
      `PCIe_FLITTYPE_DMWR_64  : begin d_txn_type=PCIe_TL_MEM; d_dir=PCIe_TL_WRITE; d_is_4dw=1; d_has_data=1; d_mem_deferrable=1; end
      `PCIe_FLITTYPE_IORD     : begin d_txn_type=PCIe_TL_IO;  d_dir=PCIe_TL_READ;  d_is_4dw=0; d_has_data=0; end
      `PCIe_FLITTYPE_IOWR     : begin d_txn_type=PCIe_TL_IO;  d_dir=PCIe_TL_WRITE; d_is_4dw=0; d_has_data=1; end
      `PCIe_FLITTYPE_CFGRD0   : begin d_txn_type=PCIe_TL_CFG; d_dir=PCIe_TL_READ;  d_is_4dw=0; d_has_data=0; d_cfg_type1=0; end
      `PCIe_FLITTYPE_CFGWR0   : begin d_txn_type=PCIe_TL_CFG; d_dir=PCIe_TL_WRITE; d_is_4dw=0; d_has_data=1; d_cfg_type1=0; end
      `PCIe_FLITTYPE_CFGRD1   : begin d_txn_type=PCIe_TL_CFG; d_dir=PCIe_TL_READ;  d_is_4dw=0; d_has_data=0; d_cfg_type1=1; end
      `PCIe_FLITTYPE_CFGWR1   : begin d_txn_type=PCIe_TL_CFG; d_dir=PCIe_TL_WRITE; d_is_4dw=1'b0; d_has_data=1; d_cfg_type1=1; end
      default : begin
        `uvm_warning("EP_TL_DECODE",
           $sformatf("UNSUPPORTED_FLIT_TYPE=0x%02h - TLP ignored by the EP TL model", d_byte0))
        return;
      end
    endcase

    d_hdr_base_dw = d_is_4dw ? `PCIe_TL_HDR4DW : `PCIe_TL_HDR3DW;

    if (d_txn_type == PCIe_TL_CFG) begin
      // Configuration Request - ID routed, DW2 carries Bus/Device/Function
      // and the Register/Extended-Register Number, NOT a memory address
      // (Figure 2-33 / Figure 2-52). Mirrors PCIe_RC_TL_model's dw2 packing.
      decode_cfg_addr(dw2);
      d_at = 2'b00;
    end
    else if (d_is_4dw) begin
      d_address = {dw2, dw3[31:2], 2'b00};
      d_at      = dw3[1:0];
    end
    else begin
      d_address = {dw2[31:2], 2'b00};
      d_at      = dw2[1:0];
    end

    //----------------------------------------------------------------------
    // OHC-A : byte enables for Memory (A1) and I/O (A2)
    //   [7:4] Last DW BE   [3:0] First DW BE
    // When OHC-A1 is absent the byte enables are implied all ones.
    //----------------------------------------------------------------------
    // Implied byte enables when no OHC-A is present; decode_tlp overwrites
    // these from the real OHC DW when OHC[0] is Set.
    d_first_dw_be = 4'hF;
    d_last_dw_be  = (d_length == 10'd1) ? 4'h0 : 4'hF;

    d_valid = 1'b1;

  endfunction

  //--------------------------------------------------------------------------
  // NON-FLIT MODE header decode (mirror of serialize_non_flit_header)
  //   DW0 [31:24] Fmt/Type [23] Tag9 [22:20] TC [19] Tag8 [18] Attr2
  //       [15] TD [14] EP [13:12] Attr[1:0] [11:10] AT [9:0] Length
  //   DW1 [31:16] Requester ID [15:8] Tag[7:0] [7:4] Last DW BE [3:0] First DW BE
  //   DW2 (/DW3) Address or CFG fields
  //--------------------------------------------------------------------------
  function void decode_nonflit_header(bit [31:0] dw0, bit [31:0] dw1,
                                      bit [31:0] dw2, bit [31:0] dw3);

    d_tc           = dw0[22:20];
    d_td           = dw0[15];
    d_ep           = dw0[14];
    d_attr         = {dw0[18], dw0[13:12]};
    d_at           = dw0[11:10];
    d_length       = dw0[9:0];
    d_requester_id = dw1[31:16];
    d_tag          = {4'h0, dw0[23], dw0[19], dw1[15:8]};
    d_last_dw_be   = dw1[7:4];
    d_first_dw_be  = dw1[3:0];
    d_ohc          = 5'b00000;
    d_ohc_dw       = 0;
    d_ts           = 3'b000;

    case (d_byte0)
      `PCIe_FMTTYPE_MRD_32   : begin d_txn_type=PCIe_TL_MEM; d_dir=PCIe_TL_READ;  d_is_4dw=0; d_has_data=0; end
      `PCIe_FMTTYPE_MWR_32   : begin d_txn_type=PCIe_TL_MEM; d_dir=PCIe_TL_WRITE; d_is_4dw=0; d_has_data=1; end
      `PCIe_FMTTYPE_MRDLK_32 : begin d_txn_type=PCIe_TL_MEM; d_dir=PCIe_TL_READ;  d_is_4dw=0; d_has_data=0; d_mem_locked=1; end
      `PCIe_FMTTYPE_DMWR_32  : begin d_txn_type=PCIe_TL_MEM; d_dir=PCIe_TL_WRITE; d_is_4dw=0; d_has_data=1; d_mem_deferrable=1; end
      `PCIe_FMTTYPE_MRD_64   : begin d_txn_type=PCIe_TL_MEM; d_dir=PCIe_TL_READ;  d_is_4dw=1; d_has_data=0; end
      `PCIe_FMTTYPE_MWR_64   : begin d_txn_type=PCIe_TL_MEM; d_dir=PCIe_TL_WRITE; d_is_4dw=1; d_has_data=1; end
      `PCIe_FMTTYPE_MRDLK_64 : begin d_txn_type=PCIe_TL_MEM; d_dir=PCIe_TL_READ;  d_is_4dw=1; d_has_data=0; d_mem_locked=1; end
      `PCIe_FMTTYPE_DMWR_64  : begin d_txn_type=PCIe_TL_MEM; d_dir=PCIe_TL_WRITE; d_is_4dw=1; d_has_data=1; d_mem_deferrable=1; end
      `PCIe_FMTTYPE_IORD     : begin d_txn_type=PCIe_TL_IO;  d_dir=PCIe_TL_READ;  d_is_4dw=0; d_has_data=0; end
      `PCIe_FMTTYPE_IOWR     : begin d_txn_type=PCIe_TL_IO;  d_dir=PCIe_TL_WRITE; d_is_4dw=0; d_has_data=1; end
      `PCIe_FMTTYPE_CFGRD0   : begin d_txn_type=PCIe_TL_CFG; d_dir=PCIe_TL_READ;  d_is_4dw=0; d_has_data=0; d_cfg_type1=0; end
      `PCIe_FMTTYPE_CFGWR0   : begin d_txn_type=PCIe_TL_CFG; d_dir=PCIe_TL_WRITE; d_is_4dw=0; d_has_data=1; d_cfg_type1=0; end
      `PCIe_FMTTYPE_CFGRD1   : begin d_txn_type=PCIe_TL_CFG; d_dir=PCIe_TL_READ;  d_is_4dw=0; d_has_data=0; d_cfg_type1=1; end
      `PCIe_FMTTYPE_CFGWR1   : begin d_txn_type=PCIe_TL_CFG; d_dir=PCIe_TL_WRITE; d_is_4dw=0; d_has_data=1; d_cfg_type1=1; end
      default : begin
        `uvm_warning("EP_TL_DECODE",
           $sformatf("UNSUPPORTED_NONFLIT_FMTTYPE=0x%02h - TLP ignored by the EP TL model", d_byte0))
        return;
      end
    endcase

    d_hdr_base_dw = d_is_4dw ? `PCIe_TL_HDR4DW : `PCIe_TL_HDR3DW;

    if (d_txn_type == PCIe_TL_CFG) begin
      // Configuration Request - see decode_flit_header() above for the field
      // layout reference (identical DW2 packing in both modes).
      decode_cfg_addr(dw2);
    end
    else if (d_is_4dw)
      d_address = {dw2, dw3[31:2], 2'b00};
    else
      d_address = {dw2[31:2], 2'b00};

    d_valid = 1'b1;

  endfunction

  //--------------------------------------------------------------------------
  // decode_cfg_addr - split DW2 of a Configuration Request header into
  // Bus/Device/Function + {Extended Register Number, Register Number}
  // (Figure 2-33 Non-Flit / Figure 2-52 Flit - both use the same layout):
  //   [31:24] Bus Number   [23:19] Device Number   [18:16] Function Number
  //   [15:12] Reserved     [11:2]  {Ext Reg Num[3:0], Register Number[5:0]}
  //   [1:0]   Reserved
  // cfg_reg_num is kept as a byte offset (bits[1:0] forced 0) so it indexes
  // cfg_space[]/cfg_ro_mask[] directly after a >>2.
  //--------------------------------------------------------------------------
  function void decode_cfg_addr(bit [31:0] dw2);
    d_cfg_bus_num     = dw2[31:24];
    d_cfg_dev_num     = dw2[23:19];
    d_cfg_fn_num      = dw2[18:16];
    d_cfg_ext_reg_num = dw2[11:8];
    d_cfg_reg_num     = {dw2[11:2], 2'b00};
    d_address         = '0;   // not a memory address for CFG - unused downstream
  endfunction

  //--------------------------------------------------------------------------
  // Fetch DW n out of the 236 byte region. Byte 0 of the region is the MSB of
  // DW0, matching the packing done by PCIe_RC_TL_model::pack_to_tlp_data.
  //--------------------------------------------------------------------------
  function bit [`PCIe_TL_DATA_DW_W-1:0] get_dw(PCIe_sequence_item item, int dw_index);
    int b;
    bit [`PCIe_TL_DATA_DW_W-1:0] dw;
    b = dw_index * `PCIe_TL_DW_BYTES;
    if ((b + 3) >= `PCIe_TLP_DATA_BYTE_W)
      return '0;
    dw = {item.tlp_data[b], item.tlp_data[b+1],
          item.tlp_data[b+2], item.tlp_data[b+3]};
    return dw;
  endfunction

  //==========================================================================
  //                       ECRC  -  Section 2.7.1
  //
  //   Polynomial 04C1 1DB7h, seed FFFF FFFFh, calculation starts with bit 0 of
  //   byte 0 and proceeds bit 0 -> bit 7 of each byte, so the reflected
  //   polynomial EDB8 8320h is used. All Variant bits are treated as Set:
  //     NFM : header symbol 0 bit 0 (Type[0]) , header symbol 2 bit 6 (EP)
  //     FM  : header symbol 0 bit 0 (Type[0]) , header symbol 6 bit 7 (EP)
  //   The result is complemented and mapped into the 32-bit TLP Digest (NFM) /
  //   Trailer (FM) through Table 2-55, which is a byte-wise bit reversal.
  //==========================================================================
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

  // Table 2-55 : ECRC result bit n -> TLP Digest bit position (byte-wise reversal)
  function automatic bit [`PCIe_TL_ECRC_W-1:0] ecrc_map_bits(bit [31:0] crc_result);
    bit [`PCIe_TL_ECRC_W-1:0] digest;
    digest = '0;
    for (int byte_i = 0; byte_i < 4; byte_i++)
      for (int bit_i = 0; bit_i < 8; bit_i++)
        digest[(byte_i*8) + (7 - bit_i)] = crc_result[(byte_i*8) + bit_i];
    return digest;
  endfunction

  //--------------------------------------------------------------------------
  // generate_ecrc - run over tlp_byte_len bytes of the given 236 byte region.
  //   tlp_byte_len must NOT include the TLP Digest / Trailer itself.
  //--------------------------------------------------------------------------
  function automatic bit [`PCIe_TL_ECRC_W-1:0] generate_ecrc(
      input bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_bytes,
      input int unsigned tlp_byte_len,
      input pkt_mode_e   mode);

    bit [31:0] crc;
    bit [7:0]  b;
    int        var_sym;
    int        var_bit;

    crc     = `PCIe_TL_ECRC_SEED;
    var_sym = (mode == FLIT) ? `PCIe_TL_ECRC_FM_VAR_SYM     : `PCIe_TL_ECRC_NFM_VAR_SYM;
    var_bit = (mode == FLIT) ? `PCIe_TL_ECRC_FM_VAR_SYM_BIT : `PCIe_TL_ECRC_NFM_VAR_SYM_BIT;

    `uvm_info("ECRC",
      $sformatf("ECRC_START mode=%s bytes=%0d variant_bits={sym%0d.bit%0d, sym%0d.bit%0d}",
                 mode.name(), tlp_byte_len,
                 `PCIe_TL_ECRC_VAR_SYM0, `PCIe_TL_ECRC_VAR_SYM0_BIT, var_sym, var_bit), UVM_HIGH)

    for (int unsigned i = 0; i < tlp_byte_len; i++) begin
      b = tlp_bytes[i];
      // "All Variant bits must be treated as Set for ECRC calculations"
      if (i == `PCIe_TL_ECRC_VAR_SYM0) b[`PCIe_TL_ECRC_VAR_SYM0_BIT] = 1'b1;
      if (i == var_sym)                b[var_bit]                    = 1'b1;
      crc = ecrc_byte_update(crc, b);
    end

    crc = ~crc;                       // "The result ... is complemented"
    return ecrc_map_bits(crc);        // Table 2-55
  endfunction

  //--------------------------------------------------------------------------
  // check_ecrc_rx - receive side recalculation.
  //   ECRC is only present when TD==1 (Non-Flit Mode) or TS==001b (Flit Mode).
  //--------------------------------------------------------------------------
  function void check_ecrc_rx(PCIe_sequence_item item);

    int unsigned covered_bytes;
    bit [`PCIe_TL_ECRC_W-1:0] rx_digest;
    bit [`PCIe_TL_ECRC_W-1:0] recomputed;

    item.ecrc_present = d_td;

    if (!d_td) begin
      item.ecrc_state = PCIe_ECRC_ABSENT;
      `uvm_info("ECRC_RX",
        $sformatf("NO_ECRC_IN_THIS_TLP (mode=%s TD=%0b TS=%03b) - nothing to check",
                   d_mode.name(), d_td, d_ts), UVM_LOW)
      return;
    end

    // ECRC covers the header, OHC and the whole payload but not the Digest.
    covered_bytes = d_total_dw * `PCIe_TL_DW_BYTES;

    if ((covered_bytes + `PCIe_TL_ECRC_W/8) > `PCIe_TLP_DATA_BYTE_W) begin
      `uvm_warning("ECRC_RX",
        $sformatf("TLP+digest is %0d bytes, longer than the %0d byte region - ECRC check skipped",
                   covered_bytes + `PCIe_TL_ECRC_W/8, `PCIe_TLP_DATA_BYTE_W))
      item.ecrc_state = PCIe_ECRC_ABSENT;
      return;
    end

    rx_digest  = get_dw(item, d_total_dw);                       // the trailing digest DW
    recomputed = generate_ecrc(item.tlp_data, covered_bytes, d_mode);

    item.ecrc    = rx_digest;
    item.ecrc_rx = recomputed;

    if (rx_digest == recomputed) begin
      item.ecrc_state = PCIe_ECRC_PASS;
      n_ecrc_pass++;
      `uvm_info("ECRC_RX",
        $sformatf("******** ECRC_PASS ******** mode=%s covered=%0d B received=%08h recalculated=%08h",
                   d_mode.name(), covered_bytes, rx_digest, recomputed), UVM_LOW)
    end
    else begin
      item.ecrc_state = PCIe_ECRC_FAIL;
      n_ecrc_fail++;
      `uvm_error("ECRC_RX",
        $sformatf("******** ECRC_FAIL ******** mode=%s covered=%0d B received=%08h recalculated=%08h",
                   d_mode.name(), covered_bytes, rx_digest, recomputed))
    end

  endfunction

  //==========================================================================
  //   MEMORY ACCESS FUNCTION 1 of 2
  //
  //   mem_access() - the single entry point for EVERY memory transaction:
  //       mem3dw write , mem3dw read , mem4dw write , mem4dw read
  //   in BOTH FLIT and NON-FLIT mode. The is_4dw argument picks mem4dw over
  //   mem3dw, the op argument picks read over write.
  //==========================================================================
 function void mem_access(input  pcie_tl_mem_op_e              op,
                           input  bit                           is_4dw,
                           input  pkt_mode_e                    mode,
                           input  bit [63:0]                    addr,
                           input  int unsigned                  len_dw,
                           input  bit [`PCIe_TL_DATA_DW_W-1:0]  wdata [],
                           output bit [`PCIe_TL_DATA_DW_W-1:0]  rdata []);

    int unsigned idx;
    int unsigned depth;
    string       mem_name;
    string       data_str;

    depth    = is_4dw ? `PCIe_TL_MEM4DW_DEPTH : `PCIe_TL_MEM3DW_DEPTH;
    mem_name = is_4dw ? "mem4dw" : "mem3dw";
    data_str = "";

    `uvm_info("EP_TL_MEM",
      $sformatf("%s_%s : mode=%s addr=0x%016h len=%0d DW depth=%0d",
                 mem_name, (op == PCIe_TL_MEM_OP_WRITE) ? "WRITE" : "READ",
                 mode.name(), addr, len_dw, depth), UVM_LOW)

    rdata = new[(op == PCIe_TL_MEM_OP_READ) ? len_dw : 0];

    for (int unsigned i = 0; i < len_dw; i++) begin

      idx = ((addr >> `PCIe_TL_MEM_ADDR_LSB) + i) % depth;

      if (op == PCIe_TL_MEM_OP_WRITE) begin
        if (i < wdata.size()) begin
          if (is_4dw) mem4dw[idx] = wdata[i];
          else        mem3dw[idx] = wdata[i];
          data_str = {data_str, (i == 0) ? "" : ", ", $sformatf("DW%0d=0x%08h", i, wdata[i])};
          `uvm_info("EP_TL_MEM",
            $sformatf("  %s[%0d] <= %08h   (byte addr 0x%016h)",
                       mem_name, idx, wdata[i], addr + (64'(i)*`PCIe_TL_DW_BYTES)), UVM_HIGH)
        end
      end
      else begin
        rdata[i] = is_4dw ? mem4dw[idx] : mem3dw[idx];
        data_str = {data_str, (i == 0) ? "" : ", ", $sformatf("DW%0d=0x%08h", i, rdata[i])};
        `uvm_info("EP_TL_MEM",
          $sformatf("  %s[%0d] => %08h   (byte addr 0x%016h)",
                     mem_name, idx, rdata[i], addr + (64'(i)*`PCIe_TL_DW_BYTES)), UVM_HIGH)
      end
    end

    `uvm_info("EP_TL_MEM",
      $sformatf("%s_%s_COMPLETE : %0d DW touched : data = [ %s ]",
                 mem_name, (op == PCIe_TL_MEM_OP_WRITE) ? "WRITE" : "READ", len_dw, data_str), UVM_LOW)

  endfunction
 
    //==========================================================================
  //   MEMORY ACCESS FUNCTION 2 of 2
  //
  //   io_access() - the single entry point for EVERY I/O transaction:
  //       io3dw write , io3dw read
  //   in BOTH FLIT and NON-FLIT mode. I/O Requests are always 3DW header and
  //   always exactly 1 DW (Section 2.2.7), so no length argument is needed.
  //==========================================================================
  function void io_access(input  pcie_tl_mem_op_e             op,
                          input  pkt_mode_e                   mode,
                          input  bit [63:0]                   addr,
                          input  bit [`PCIe_TL_DATA_DW_W-1:0] wdata,
                          output bit [`PCIe_TL_DATA_DW_W-1:0] rdata);

    int unsigned idx;

    idx = (addr >> `PCIe_TL_MEM_ADDR_LSB) % `PCIe_TL_IO3DW_DEPTH;

    if (op == PCIe_TL_MEM_OP_WRITE) begin
      io3dw[idx] = wdata;
      rdata      = '0;
      `uvm_info("EP_TL_IO",
        $sformatf("io3dw_WRITE : mode=%s addr=0x%08h io3dw[%0d] <= %08h",
                   mode.name(), addr[31:0], idx, wdata), UVM_LOW)
    end
    else begin
      rdata = io3dw[idx];
      `uvm_info("EP_TL_IO",
        $sformatf("io3dw_READ  : mode=%s addr=0x%08h io3dw[%0d] => %08h",
                   mode.name(), addr[31:0], idx, rdata), UVM_LOW)
    end

  endfunction

  //==========================================================================
  //  be_to_byte_mask - expand a 4-bit DW Byte Enable field into the 32-bit
  //  byte mask used to merge a Configuration Write into cfg_space[] (one
  //  8'hFF per enabled byte lane, byte 0 = bits[7:0]).
  //==========================================================================
  function automatic bit [31:0] be_to_byte_mask(bit [3:0] be);
    bit [31:0] mask;
    mask = '0;
    for (int b = 0; b < 4; b++)
      if (be[b]) mask[8*b +: 8] = 8'hFF;
    return mask;
  endfunction

  //==========================================================================
  //   CONFIGURATION SPACE ACCESS FUNCTION
  //
  //   cfg_access() - the single, generalized engine for EVERY Configuration
  //   Read/Write serviced by this model, Type 0 or Type 1, FLIT or
  //   NON-FLIT. The caller (service_request()) has already resolved the
  //   request into a byte offset + byte enables AND picked which header
  //   mirror to operate on via the space/ro_mask ref arguments - Type 0
  //   requests pass {cfg_space_t0, cfg_ro_mask_t0}, Type 1 requests pass
  //   {cfg_space_t1, cfg_ro_mask_t1} - so this function body itself is
  //   completely mode-agnostic and header-type-agnostic, and is reused
  //   unchanged for both (and for any further header/function this model
  //   grows to support later, without adding another copy of the logic).
  //
  //   Behaviour :
  //     - byte_offset >= PCIe_TL_CFG_HDR_BYTES (i.e. outside the 64 B
  //       header that is actually implemented) -> Unsupported Request
  //       (Table 2-40), no data returned, no write applied.
  //     - Read  : rdata = space[idx] as-is.
  //     - Write : each byte lane enabled in first_dw_be is merged into
  //       space[idx], but only through the bits that ro_mask[idx] marks
  //       writable - read-only bits (and RW1C bits, modelled as RO for now,
  //       see init_cfg_header_common() / init_cfg_space_type0() /
  //       init_cfg_space_type1()) always keep their previous value
  //       regardless of what the Requester sent, exactly like real
  //       read-only hardware register bits.
  //==========================================================================
  function void cfg_access(input  pcie_tl_cfg_op_e            op,
                           input  bit [`PCIe_TL_CFG_REG_W-1:0] byte_offset,
                           input  bit [3:0]                    first_dw_be,
                           input  bit [`PCIe_TL_DATA_DW_W-1:0] wdata,
                           output bit [`PCIe_TL_DATA_DW_W-1:0] rdata,
                           output bit                          unsupported,
                           ref    cfg_space_arr_t              space,
                           ref    cfg_mask_arr_t               ro_mask);

    int unsigned idx;
    bit [31:0]   byte_mask;
    bit [31:0]   writable_mask;

    idx         = byte_offset >> `PCIe_TL_MEM_ADDR_LSB;
    unsupported = 1'b0;
    rdata       = '0;

    if (idx >= `PCIe_TL_CFG_HDR_DW_DEPTH) begin
      // Nothing implemented past the 64 byte header - Unsupported Request.
      unsupported = 1'b1;
      `uvm_warning("EP_TL_CFG",
        $sformatf("CFG_%s_OUT_OF_RANGE : byte_offset=0x%03h (DW idx=%0d) is beyond the %0d byte modelled header - completing UR",
                   (op == PCIe_TL_MEM_OP_WRITE) ? "WRITE" : "READ",
                   byte_offset, idx, `PCIe_TL_CFG_HDR_BYTES))
      return;
    end

    if (op == PCIe_TL_MEM_OP_READ) begin
      rdata = space[idx];
      `uvm_info("EP_TL_CFG",
        $sformatf("CFG_READ  : byte_offset=0x%03h (DW idx=%0d) => %08h", byte_offset, idx, rdata), UVM_LOW)
    end
    else begin
      // ---- generalized read-modify-write : byte-enable AND read-only mask
      byte_mask     = be_to_byte_mask(first_dw_be);
      writable_mask = byte_mask & ~ro_mask[idx];

      `uvm_info("EP_TL_CFG",
        $sformatf("CFG_WRITE : byte_offset=0x%03h (DW idx=%0d) wdata=%08h first_dw_be=%04b ro_mask=%08h writable_mask=%08h old=%08h",
                   byte_offset, idx, wdata, first_dw_be, ro_mask[idx], writable_mask, space[idx]), UVM_LOW)

      space[idx] = (space[idx] & ~writable_mask) | (wdata & writable_mask);

      `uvm_info("EP_TL_CFG",
        $sformatf("CFG_WRITE_COMPLETE : cfg_space[%0d] <= %08h", idx, space[idx]), UVM_LOW)
    end

  endfunction

  //==========================================================================
  //  service_request - run the decoded TLP against the memory models and
  //  build the Completion when the Request is Non-Posted.
  //
  //  Posted     : MWr / DMWr-as-posted / MsgD  -> no Completion
  //  Non-Posted : MRd, MRdLk, IORd, IOWr, CfgRd, CfgWr -> Completion required
  //==========================================================================
  function void service_request(PCIe_sequence_item req, PCIe_sequence_item cpl);

    bit [`PCIe_TL_DATA_DW_W-1:0] rdata [];
    bit [`PCIe_TL_DATA_DW_W-1:0] io_rd;
    bit [`PCIe_TL_DATA_DW_W-1:0] dummy [];
    bit                          need_cpl;
    bit                          cpl_with_data;
    int unsigned                 rd_len_dw;

    need_cpl             = 1'b0;
    cpl_with_data        = 1'b0;
    cfg_status_override  = `PCIe_CPL_STATUS_SC;

    case (d_txn_type)

      //------------------------------------------------------------------
      // MEMORY : mem3dw (3DW header) or mem4dw (4DW header)
      //------------------------------------------------------------------
      PCIe_TL_MEM: begin
        if (d_dir == PCIe_TL_WRITE) begin
          mem_access(PCIe_TL_MEM_OP_WRITE, d_is_4dw, d_mode,
                     d_address, d_payload_dw, d_payload, dummy);
          // Deferrable Memory Write is Non-Posted and is completed with a
          // Cpl (no data). A plain Memory Write is Posted.
          need_cpl      = d_mem_deferrable;
          cpl_with_data = 1'b0;
        end
        else begin
          rd_len_dw = (d_length == 10'd0) ? `PCIe_TL_MAX_PAYLOAD_DW : int'(d_length);
          mem_access(PCIe_TL_MEM_OP_READ, d_is_4dw, d_mode,
                     d_address, rd_len_dw, dummy, rdata);
          need_cpl      = 1'b1;
          cpl_with_data = 1'b1;
        end
      end

      //------------------------------------------------------------------
      // I/O : io3dw
      //------------------------------------------------------------------
      PCIe_TL_IO: begin
        if (d_dir == PCIe_TL_WRITE) begin
          io_access(PCIe_TL_MEM_OP_WRITE, d_mode, d_address,
                    (d_payload_dw > 0) ? d_payload[0] : '0, io_rd);
          need_cpl      = 1'b1;   // I/O Write is Non-Posted -> Cpl without data
          cpl_with_data = 1'b0;
        end
        else begin
          io_access(PCIe_TL_MEM_OP_READ, d_mode, d_address, '0, io_rd);
          rdata    = new[1];
          rdata[0] = io_rd;
          need_cpl      = 1'b1;
          cpl_with_data = 1'b1;
        end
      end

      //------------------------------------------------------------------
      // CONFIGURATION : always Non-Posted (Section 2.2.7). Serviced against
      // whichever header mirror d_cfg_type1 selects - cfg_space_t0/
      // cfg_ro_mask_t0 for CfgRd0/CfgWr0, cfg_space_t1/cfg_ro_mask_t1 for
      // CfgRd1/CfgWr1 - built by init_cfg_space() and read/written through
      // the single reusable cfg_access() engine.
      //------------------------------------------------------------------
      PCIe_TL_CFG: begin

        bit [`PCIe_TL_DATA_DW_W-1:0] cfg_rdata;
        bit                          cfg_ur;
        bit [`PCIe_TL_DATA_DW_W-1:0] cfg_wdata;

        need_cpl      = 1'b1;
        cpl_with_data = (d_dir == PCIe_TL_READ);

        if (d_dir == PCIe_TL_WRITE) begin
          // ------------------------------------------------------------
          // Configuration Write data comes straight from the decoded TLP
          // payload (d_payload[0]) - the exact DW carried by the Cfg Write
          // Request that decode_tlp() reconstructed from the 236 byte TLP
          // region the EP controller monitor published on ep_mon_tl_ap
          // (PCIe_EP_controller_monitor::send_tlp_to_ep_tl() ->
          //  tl_mon_imp -> write_mon() -> decode_tlp() -> d_payload).
          // No hardcoded/fixed pattern is ever driven into cfg_space: a
          // Configuration Write always carries exactly 1 DW of payload
          // (Section 2.2.7), so an empty d_payload here means the request
          // was decoded with no data - that is flagged, not papered over.
          // ------------------------------------------------------------
          if (d_payload_dw > 0) begin
            cfg_wdata = d_payload[0];
            `uvm_info("EP_TL_CFG",
              $sformatf("CFG_WRITE_DATA_SOURCE=DECODED_PAYLOAD (%08h)", cfg_wdata), UVM_LOW)
          end
          else begin
            cfg_wdata = '0;
            `uvm_error("EP_TL_CFG",
              "CFG_WRITE_NO_PAYLOAD : Configuration Write TLP decoded with 0 payload DW - no write data available from the monitor path, write not applied with real data")
          end

	  if (d_cfg_type1) begin 

            cfg_access(PCIe_TL_CFG_WRITE, d_cfg_reg_num, d_first_dw_be,
                       cfg_wdata, cfg_rdata, cfg_ur, cfg_space_t1, cfg_ro_mask_t1);

	    `uvm_info("EP_TL_CFG",
           $sformatf("CFG_SPACE_TYPE1_WRITE_INITIALISED : %0d DW total, %0d DW (%0d B) header populated",
                 `PCIe_TL_CFG_SPACE_DW_DEPTH, `PCIe_TL_CFG_HDR_DW_DEPTH,
                 `PCIe_TL_CFG_HDR_BYTES), UVM_LOW)

          end

	  else begin
            cfg_access(PCIe_TL_CFG_WRITE, d_cfg_reg_num, d_first_dw_be,
                       cfg_wdata, cfg_rdata, cfg_ur, cfg_space_t0, cfg_ro_mask_t0);

          `uvm_info("EP_TL_CFG",
           $sformatf("CFG_SPACE_TYPE0_WRITE_INITIALISED : %0d DW total, %0d DW (%0d B) header populated",
                 `PCIe_TL_CFG_SPACE_DW_DEPTH, `PCIe_TL_CFG_HDR_DW_DEPTH,
                 `PCIe_TL_CFG_HDR_BYTES), UVM_LOW)

	  end

          n_cfg_wr++;

        end
        else begin

          if (d_cfg_type1) begin 

            cfg_access(PCIe_TL_CFG_READ, d_cfg_reg_num, d_first_dw_be,
                       '0, cfg_rdata, cfg_ur, cfg_space_t1, cfg_ro_mask_t1);

            `uvm_info("EP_TL_CFG",
               $sformatf("CFG_SPACE_TYPE1_READ_INITIALISED : %0d DW total, %0d DW (%0d B) header populated",
                 `PCIe_TL_CFG_SPACE_DW_DEPTH, `PCIe_TL_CFG_HDR_DW_DEPTH,
                 `PCIe_TL_CFG_HDR_BYTES), UVM_LOW)

	  end

	  else begin
            cfg_access(PCIe_TL_CFG_READ, d_cfg_reg_num, d_first_dw_be,
                       '0, cfg_rdata, cfg_ur, cfg_space_t0, cfg_ro_mask_t0);

             `uvm_info("EP_TL_CFG",
               $sformatf("CFG_SPACE_TYPE0_READ_INITIALISED : %0d DW total, %0d DW (%0d B) header populated",
                 `PCIe_TL_CFG_SPACE_DW_DEPTH, `PCIe_TL_CFG_HDR_DW_DEPTH,
                 `PCIe_TL_CFG_HDR_BYTES), UVM_LOW)

          end

          n_cfg_rd++;
        end

        if (cfg_ur) begin
          n_cfg_ur++;
          cfg_status_override = `PCIe_CPL_STATUS_UR;
          cpl_with_data        = 1'b0;   // UR completions never carry data
        end
        else begin
          cfg_status_override = `PCIe_CPL_STATUS_SC;
        end

        if (cpl_with_data) begin
          rdata    = new[1];
          rdata[0] = cfg_rdata;
        end

        `uvm_info("EP_TL_MODEL",
          $sformatf("CONFIGURATION_REQUEST : bus=%0d dev=%0d fn=%0d byte_off=0x%03h %s -> %s",
                     d_cfg_bus_num, d_cfg_dev_num, d_cfg_fn_num, d_cfg_reg_num,
                     (d_dir == PCIe_TL_WRITE) ? "WRITE" : "READ",
                     cfg_ur ? "UNSUPPORTED_REQUEST" : "SUCCESSFUL_COMPLETION"), UVM_LOW)
      end

      default: begin
        `uvm_info("EP_TL_MODEL","POSTED_OR_UNHANDLED_TXN_TYPE : no completion",UVM_LOW)
      end

    endcase

    if (!need_cpl) begin
      `uvm_info("EP_TL_MODEL",
        $sformatf("POSTED_REQUEST (%s %s) : no Completion generated",
                   d_txn_type.name(), d_dir.name()), UVM_LOW)
      return;
    end

    // [FLIT_SEG] Deferrable Memory Write : each segment of a split DMWr is its
    // own request, so it gets its own Cpl (no data) in its own FLIT.
    if (d_txn_type == PCIe_TL_MEM && d_dir == PCIe_TL_WRITE && d_mem_deferrable) begin
      n_dmwr_rcvd++;
      `uvm_info("EP_TL_FLIT_SEG",
        $sformatf("DMWr #%0d received : addr=0x%0h len=%0d DW tag=0x%0h -> Cpl (SC, no data) sent in its own FLIT : 12 B Cpl header + 224 B zero (NOP) padding",
                  n_dmwr_rcvd, d_address, d_payload_dw, d_tag), UVM_LOW)
    end

    // [FLIT_SEG] Completion with data that does not fit one 236 B TLP region
    // (e.g. MRd of 1024 DW) -> several CplDs, one per FLIT, same rule as the
    // RC TL model uses for requests.
    if ((d_mode == FLIT) && cpl_with_data &&
        ((`PCIe_TL_CPL_HDR_DW + `PCIe_TL_OHC_A_DW + rdata.size()) > `PCIe_FLIT_TLP_REGION_DW)) begin
      send_split_completions(req, rdata);
      return;
    end

    build_completion(req, cpl, cpl_with_data, rdata);

    fc_account_cpl(cpl);          // FLOW CONTROL [FC SHARED] : pool, prefix if dedicated, credits consumed

    // [FLIT_SEG] completion of one DMWr segment : show its own FLIT layout
    if (d_txn_type == PCIe_TL_MEM && d_dir == PCIe_TL_WRITE && d_mem_deferrable && d_mode == FLIT)
      print_cpl_flit_layout(cpl, $sformatf("Cpl for DMWr #%0d (tag 0x%0h)", n_dmwr_rcvd, d_tag));

    print_attr_table_check(cpl, "TX_COMPLETION");    // [ATTR] info : RO / IDO / NS table check (just before the 236B completion print)

    print_completion(cpl);

    n_cpl_sent++;

    `uvm_info("EP_TL_MODEL",
      $sformatf("COMPLETION_SENT_FROM_EP_TL_MODEL_TO_EP_DL_MODEL #%0d", n_cpl_sent), UVM_LOW)

//    fc_account_cpl(cpl);          // FLOW CONTROL : completion credits consumed
    tl_ap.write(cpl);

  endfunction

  //==========================================================================
  //  build_completion - Section 2.2.9
  //
  //    Non-Flit Mode (Figure 2-73), 3 DW header:
  //      DW0 [31:24] Fmt/Type  [23] T9 [22:20] TC [19] T8 [18] A2 [16] TH
  //          [15] TD [14] EP [13:12] Attr[1:0] [11:10] AT [9:0] Length
  //      DW1 [31:16] Completer ID [15:13] Cpl Status [12] BCM [11:0] Byte Count
  //      DW2 [31:16] Requester ID [15:8] Tag[7:0] [7] R [6:0] Lower Address
  //
  //    Flit Mode (Figure 2-76), 3 DW Header Base:
  //      DW0 [31:24] Type [23:21] TC [20:16] OHC [15:13] TS [12:10] Attr [9:0] Length
  //      DW1 [31:16] Completer ID [15] EP [14] LA[6] [13:0] Tag[13:0]
  //      DW2 [31:16] Destination BDF / BF (ARI) [15:12] LA[5:2] [11:0] Byte Count
  //      OHC-A5 (Figure 2-11) is appended when required by Section 2.2.9.2.
  //==========================================================================
  function void build_completion(PCIe_sequence_item req,
                                 PCIe_sequence_item cpl,
                                 bit                with_data,
                                 bit [`PCIe_TL_DATA_DW_W-1:0] rdata [],
                                 int                bc_ovr = -1,    // [FLIT_SEG] Byte Count of a split CplD part
                                 int                la_ovr = -1);   // [FLIT_SEG] Lower Address of a split CplD part

    bit [`PCIe_TL_DATA_DW_W-1:0] hdr [];
    bit [`PCIe_TL_DATA_DW_W-1:0] dw0, dw1, dw2, ohc_a5;
    bit [`PCIe_TL_CPL_LOWER_ADDR_W-1:0] la;
    bit [`PCIe_TL_CPL_BYTE_COUNT_W-1:0] bc;
    bit                                 need_ohc_a5;
    bit [`PCIe_TL_CPL_TAG_W-1:0]        cpl_tag;
    int unsigned                        cpl_len_dw;
    int i;

    //----------------------------------------------------------------------
    // Common completion attributes
    //----------------------------------------------------------------------
    cpl.pkt_mode      = d_mode;
    cpl.txn_type      = PCIe_TL_CPL;
    cpl.is_completion = 1'b1;
    cpl.cpl_has_data  = with_data;
    // Memory/IO requests always complete SC in this model; Configuration
    // Requests can also complete UR (cfg_status_override, driven by
    // cfg_access() above) when the access misses the implemented header.
    cpl.cpl_status    = cfg_status_override;
    cpl.requester_id  = d_requester_id;
    cpl.completer_id  = `PCIe_TL_CPL_COMPLETER_ID;
    cpl.dest_bdf      = d_requester_id;
    cpl_tag           = d_tag;
    cpl.tag           = d_tag[`PCIe_TL_TAG_W-1:0];
    cpl.tc            = d_tc;
    cpl.attr          = d_attr;
    cpl.at            = 2'b00;
    cpl.ep            = 1'b0;
    cpl.td            = 1'b0;
    cpl.first_dw_be   = d_first_dw_be;
    cpl.last_dw_be    = d_last_dw_be;
    cpl.address       = d_address[`PCIe_TL_ADDR_W-1:0];
    cpl_len_dw        = rdata.size();
    cpl.length        = with_data ? ((cpl_len_dw == `PCIe_TL_MAX_PAYLOAD_DW) ? 10'd0
                                                                            : cpl_len_dw[9:0])
                                  : 10'd0;
    cpl.ohc_a_type    = OHC_A5;
    cpl.flit_type     = PCIe_PAYLOAD_flit;
    cpl.is_payload    = 1'b1;
    cpl.drive_flit    = (d_mode == FLIT);

    //----------------------------------------------------------------------
    // Byte Count (Table 2-40) and Lower Address (Table 2-41)
    //----------------------------------------------------------------------
    if (d_txn_type == PCIe_TL_MEM && d_dir == PCIe_TL_READ) begin
      req.first_dw_be = d_first_dw_be;
      req.last_dw_be  = d_last_dw_be;
      req.length      = d_length;
      req.address     = d_address;
      bc = req.calc_byte_count();
      la = req.calc_lower_address();
    end
    else begin
      // "For all other types of Completions, the Byte Count value must be 4"
      bc = `PCIe_TL_CPL_DEFAULT_BYTE_CNT;
      la = '0;
    end

    // [FLIT_SEG] parts 2..N of a split CplD : remaining Byte Count and the
    // Lower Address of the first byte this part returns (Section 2.3.1.1)
    if (bc_ovr >= 0) bc = bc_ovr[`PCIe_TL_CPL_BYTE_COUNT_W-1:0];   // 4096 -> 000h
    if (la_ovr >= 0) la = la_ovr[`PCIe_TL_CPL_LOWER_ADDR_W-1:0];

    cpl.byte_count    = bc;
    cpl.lower_address = la;
    cpl.bcm           = 1'b0;                    // never Set by a PCIe Completer

    //----------------------------------------------------------------------
    // Payload
    //----------------------------------------------------------------------
    if (with_data) begin
      cpl.data     = new[rdata.size()];
      cpl.cpl_data = new[rdata.size()];
      foreach (rdata[i]) begin
        cpl.data[i]     = rdata[i];
        cpl.cpl_data[i] = rdata[i];
      end
    end
    else begin
      cpl.data     = new[0];
      cpl.cpl_data = new[0];
    end

    //----------------------------------------------------------------------
    // Header
    //----------------------------------------------------------------------
    dw0 = '0; dw1 = '0; dw2 = '0; ohc_a5 = '0;

    if (d_mode == FLIT) begin

      // OHC-A5 required for unsuccessful Completions, for non-UIO Completions
      // with Lower Address[1:0] != 00b, and when a Destination Segment is
      // needed (Section 2.2.9.2).
      need_ohc_a5 = (cpl.cpl_status != `PCIe_CPL_STATUS_SC) || (la[1:0] != 2'b00);

      dw0[31:24] = with_data ? `PCIe_FLITTYPE_CPLD : `PCIe_FLITTYPE_CPL;
      dw0[23:21] = cpl.tc;
      dw0[20:16] = need_ohc_a5 ? 5'b00001 : 5'b00000;
      dw0[15:13] = `PCIe_TL_TS_NO_TRAILER;
      dw0[12:10] = cpl.attr;
      dw0[9:0]   = cpl.length;

      dw1[31:16] = cpl.completer_id;
      dw1[15]    = cpl.ep;
      dw1[14]    = la[6];
      dw1[13:0]  = cpl_tag;

      dw2[31:16] = cpl.dest_bdf;
      dw2[15:12] = la[5:2];
      dw2[11:0]  = bc;

      cpl.ohc = dw0[20:16];

      if (need_ohc_a5) begin
        ohc_a5[`PCIe_TL_OHCA5_DEST_SEG_HI : `PCIe_TL_OHCA5_DEST_SEG_LO] = 8'h00;
        ohc_a5[`PCIe_TL_OHCA5_CPL_SEG_HI  : `PCIe_TL_OHCA5_CPL_SEG_LO ] = 8'h00;
        ohc_a5[`PCIe_TL_OHCA5_DSV]                                      = 1'b0;
        ohc_a5[`PCIe_TL_OHCA5_LA_HI       : `PCIe_TL_OHCA5_LA_LO      ] = la[1:0];
        ohc_a5[`PCIe_TL_OHCA5_STATUS_HI   : `PCIe_TL_OHCA5_STATUS_LO  ] = cpl.cpl_status;

        hdr = new[`PCIe_TL_CPL_HDR_DW + `PCIe_TL_OHC_A_DW];
        hdr[0] = dw0; hdr[1] = dw1; hdr[2] = dw2; hdr[3] = ohc_a5;
      end
      else begin
        hdr = new[`PCIe_TL_CPL_HDR_DW];
        hdr[0] = dw0; hdr[1] = dw1; hdr[2] = dw2;
      end

    end
    else begin

      dw0[31:24] = with_data ? `PCIe_FMTTYPE_CPLD : `PCIe_FMTTYPE_CPL;
      dw0[23]    = cpl_tag[9];
      dw0[22:20] = cpl.tc;
      dw0[19]    = cpl_tag[8];
      dw0[18]    = cpl.attr[2];
      dw0[15]    = cpl.td;
      dw0[14]    = cpl.ep;
      dw0[13:12] = cpl.attr[1:0];
      dw0[11:10] = cpl.at;
      dw0[9:0]   = cpl.length;

      dw1[31:16] = cpl.completer_id;
      dw1[15:13] = cpl.cpl_status;
      dw1[12]    = cpl.bcm;
      dw1[11:0]  = bc;

      dw2[31:16] = cpl.requester_id;
      dw2[15:8]  = cpl_tag[7:0];
      dw2[7]     = 1'b0;
      dw2[6:0]   = la;

      hdr = new[`PCIe_TL_CPL_HDR_DW];
      hdr[0] = dw0; hdr[1] = dw1; hdr[2] = dw2;

    end

    //----------------------------------------------------------------------
    // Serialize : header (+OHC) + payload, then pack into the 236 byte region
    //----------------------------------------------------------------------
    cpl.serialized_tlp = new[hdr.size() + cpl.data.size()];
    for (i = 0; i < hdr.size(); i++)
      cpl.serialized_tlp[i] = hdr[i];
    for (i = 0; i < cpl.data.size(); i++)
      cpl.serialized_tlp[hdr.size() + i] = cpl.data[i];

    cpl.tlp_header_dw_count  = hdr.size();
    cpl.tlp_payload_dw_count = cpl.data.size();
    cpl.tlp_total_dw_count   = cpl.serialized_tlp.size();
    cpl.hdr_dw_count         = hdr.size();

    pack_completion_region(cpl);

  endfunction

  //==========================================================================
  // [FLIT_SEG] send_split_completions
  //
  //   A CplD whose 3 DW header (+ OHC-A5) + data does not fit the 236 byte
  //   FLIT TLP region is returned as several CplDs, each a complete TLP in
  //   its own FLIT (same split rule as the RC TL model uses for requests):
  //
  //     max data / CplD = 59 - 3 (Cpl header) - OHC-A5 (0|1)  DW
  //       no OHC-A5 : 56 DW -> 1024 DW = 19 CplDs (last 16 DW)
  //       OHC-A5    : 55 DW -> 1024 DW = 19 CplDs (last 34 DW)
  //
  //   Every part carries the same Tag / Requester ID. Byte Count = bytes
  //   still to be returned INCLUDING this part (Section 2.2.9), so only the
  //   last part has Byte Count == its own data; Lower Address = address of
  //   the first byte the part returns.
  //==========================================================================
  function void send_split_completions(PCIe_sequence_item req,
                                       bit [`PCIe_TL_DATA_DW_W-1:0] rdata []);
    bit [`PCIe_TL_DATA_DW_W-1:0]        part [];
    bit [`PCIe_TL_CPL_LOWER_ADDR_W-1:0] la0;
    PCIe_sequence_item                  cpl;
    int unsigned total_dw, max_dw, n_part, off_dw, len_dw, lead_off;
    int          bc_total, bc_left, bytes_this;
    bit          first_needs_ohc;
    string       rows;

    // Byte Count / Lower Address of the whole request (Table 2-40 / 2-41)
    req.first_dw_be = d_first_dw_be;
    req.last_dw_be  = d_last_dw_be;
    req.length      = d_length;
    req.address     = d_address;
    bc_total = req.calc_byte_count();
    if (bc_total == 0) bc_total = 4096;            // 000h encodes 4096
    la0      = req.calc_lower_address();

    // leading disabled bytes of the first DW (they are not counted in Byte Count)
    casez (d_first_dw_be)
      4'b???1 : lead_off = 0;
      4'b??10 : lead_off = 1;
      4'b?100 : lead_off = 2;
      4'b1000 : lead_off = 3;
      default : lead_off = 0;
    endcase

    first_needs_ohc = (cfg_status_override != `PCIe_CPL_STATUS_SC) || (la0[1:0] != 2'b00);
    total_dw = rdata.size();
    max_dw   = PCIe_sequence_item::flit_seg_max_payload_dw(`PCIe_TL_CPL_HDR_DW,
                                                           first_needs_ohc ? `PCIe_TL_OHC_A_DW : 0, 0);
    n_part   = PCIe_sequence_item::flit_seg_count(total_dw, max_dw);

    n_cpl_split_txn++;
    rows    = "";
    off_dw  = 0;
    bc_left = bc_total;

    for (int unsigned i = 0; i < n_part; i++) begin
      len_dw = ((total_dw - off_dw) > max_dw) ? max_dw : (total_dw - off_dw);
      part   = new[len_dw];
      for (int unsigned k = 0; k < len_dw; k++) part[k] = rdata[off_dw + k];

      cpl = PCIe_sequence_item::type_id::create($sformatf("ep_tl_completion_part%0d", i));
      if (i == 0)
        build_completion(req, cpl, 1'b1, part);                        // Byte Count = whole request
      else
        build_completion(req, cpl, 1'b1, part, bc_left,
                         int'((d_address + (64'(off_dw) * `PCIe_TL_DW_BYTES)) & 64'h7F));
      cpl.is_flit_segment = 1'b1;
      cpl.flit_seg_idx    = i;
      cpl.flit_seg_total  = n_part;
      fc_account_cpl(cpl);        // FLOW CONTROL [FC SHARED] : pool, prefix if dedicated, credits consumed

      rows = {rows, $sformatf("          %3d  | tag 0x%04h | %3d DW (%4d B) | Byte Count %4d | Lower Addr 0x%02h | %3d B zero (NOP) padded\n",
                              i + 1, cpl.tag, len_dw, len_dw * `PCIe_TL_DW_BYTES,
                              (cpl.byte_count == 0) ? 4096 : int'(cpl.byte_count), cpl.lower_address,
                              `PCIe_FLIT_TLP_BYTES - (cpl.tlp_total_dw_count * `PCIe_TL_DW_BYTES))};

      print_cpl_flit_layout(cpl, $sformatf("CplD part %0d / %0d (tag 0x%0h)", i + 1, n_part, d_tag));
      print_attr_table_check(cpl, "TX_COMPLETION");
      print_completion(cpl);
      n_cpl_sent++;
      n_cpl_split_parts++;
      `uvm_info("EP_TL_FLIT_SEG",
        $sformatf("SPLIT_CPLD_PART %0d/%0d SENT_TO_EP_DL_MODEL : %0d DW, Byte Count=%0d (completion #%0d)",
                  i + 1, n_part, len_dw, bc_left, n_cpl_sent), UVM_LOW)
  //    fc_account_cpl(cpl);
      tl_ap.write(cpl);

      bytes_this = (len_dw * `PCIe_TL_DW_BYTES) - ((i == 0) ? lead_off : 0);
      bc_left   -= bytes_this;
      off_dw    += len_dw;
    end

    `uvm_info("EP_TL_FLIT_SEG",
      $sformatf({"\n",
        "         ============================================================================\n",
        "            FLIT MODE COMPLETION SEGMENTATION  (CplD does not fit one 236 B region)\n",
        "         ============================================================================\n",
        "          Request            : MRd tag=0x%0h  %0d DW (%0d B, Byte Count %0d)\n",
        "          CplD header        : %0d DW (%0d B)  OHC-A5 : %0d DW\n",
        "          Max data / CplD    : %0d DW (%0d B)\n",
        "          CplDs / FLITs      : ceil(%0d / %0d) = %0d\n",
        "         ----------------------------------------------------------------------------\n",
        "%s",
        "         ============================================================================"},
        d_tag, total_dw, total_dw * `PCIe_TL_DW_BYTES, bc_total,
        `PCIe_TL_CPL_HDR_DW, `PCIe_TL_CPL_HDR_DW * `PCIe_TL_DW_BYTES, first_needs_ohc ? 1 : 0,
        max_dw, max_dw * `PCIe_TL_DW_BYTES,
        total_dw, max_dw, n_part, rows), UVM_LOW)
  endfunction

  //--------------------------------------------------------------------------
  // [FLIT_SEG] print_cpl_flit_layout : Cpl / CplD inside its 236 B TLP region
  //   Cpl  (DMWr) : bytes 0-11 Cpl header, 12-235 zero (224 B)
  //   CplD (MRd)  : bytes 0-11 Cpl header, 12-.. data, rest zero
  //--------------------------------------------------------------------------
  function void print_cpl_flit_layout(PCIe_sequence_item cpl, string what);
    int unsigned hdr_b, pl_b, used_b, zero_b, pos;
    string       s;
    hdr_b  = cpl.tlp_header_dw_count  * `PCIe_TL_DW_BYTES;
    pl_b   = cpl.tlp_payload_dw_count * `PCIe_TL_DW_BYTES;
    used_b = hdr_b + pl_b;
    zero_b = `PCIe_FLIT_TLP_BYTES - used_b;
    s   = $sformatf("\n          ===== COMPLETION FLIT : %s (236 B TLP region) =====\n", what);
    pos = 0;
    s   = {s, $sformatf("          bytes %3d - %3d : %s header %3d B\n", pos, pos + hdr_b - 1,
                        cpl.cpl_has_data ? "CplD" : "Cpl ", hdr_b)};
    pos += hdr_b;
    if (pl_b != 0) begin
      s   = {s, $sformatf("          bytes %3d - %3d : Data        %3d B (%0d DW)\n", pos, pos + pl_b - 1, pl_b, cpl.tlp_payload_dw_count)};
      pos += pl_b;
    end
    if (zero_b != 0)
      s = {s, $sformatf("          bytes %3d - %3d : ZERO (NOP)  %3d B\n", pos, `PCIe_FLIT_TLP_BYTES - 1, zero_b)};
    s = {s, $sformatf("          used %0d B + zero %0d B = %0d B", used_b, zero_b, `PCIe_FLIT_TLP_BYTES)};
    `uvm_info("EP_TL_FLIT_LAYOUT", s, UVM_LOW)
  endfunction

  //--------------------------------------------------------------------------
  // pack_completion_region : serialized Completion -> 236 byte tlp_data, NOP
  // padded in FLIT mode exactly like the RC TL model does for requests.
  //--------------------------------------------------------------------------
  function void pack_completion_region(PCIe_sequence_item cpl);

    int tlp_dw;
    int b;
    int nbytes;

    tlp_dw = cpl.serialized_tlp.size();

    cpl.flit_tlp_region = new[`PCIe_FLIT_TLP_REGION_DW];
    for (int i = 0; i < `PCIe_FLIT_TLP_REGION_DW; i++)
      cpl.flit_tlp_region[i] = (i < tlp_dw) ? cpl.serialized_tlp[i] : `PCIe_FLIT_NOP_TLP_DW;

    cpl.flit_tlp_dw_count = (tlp_dw > `PCIe_FLIT_TLP_REGION_DW) ? `PCIe_FLIT_TLP_REGION_DW : tlp_dw;
    cpl.flit_nop_dw_count = `PCIe_FLIT_TLP_REGION_DW - cpl.flit_tlp_dw_count;

    cpl.tlp_data = '0;
    nbytes = `PCIe_FLIT_TLP_REGION_DW * `PCIe_TL_DW_BYTES;
    if (nbytes > `PCIe_TLP_DATA_BYTE_W) nbytes = `PCIe_TLP_DATA_BYTE_W;

    for (b = 0; b < nbytes; b++)
      cpl.tlp_data[b] = cpl.flit_tlp_region[b/4][ 8*(3-(b%4)) +: 8 ];

  endfunction

  //==========================================================================
  //                        UVM_INFO PACKET DISPLAYS
  //==========================================================================
  function void print_decoded_tlp(PCIe_sequence_item item);

    `uvm_info("EP_TL_RX_PACKET",
      $sformatf({"\n",
        "         ============================================================\n",
        "              EP TL MODEL : DECODED PACKET FROM EP MONITOR\n",
        "         ============================================================\n",
        "         Packet Mode       : %s\n",
        "         Byte0 (Fmt/Type)  : 0x%02h\n",
        "         Transaction Type  : %s\n",
        "         Direction         : %s\n",
        "         Header Base       : %0d DW   OHC : %0d DW   Total Header : %0d DW\n",
        "         Address           : 0x%016h  (%s)\n",
        "         Length            : %0d DW (%0d bytes)\n",
        "         Requester ID      : 0x%04h    Tag : 0x%04h\n",
        "         TC / Attr / AT    : %0d / %03b / %02b\n",
        "         TD / EP           : %0b / %0b        TS[2:0] : %03b   OHC[4:0] : %05b\n",
        "         First DW BE       : %04b       Last DW BE : %04b\n",
        "         Payload DWs       : %0d\n",
        "         Targets            : %s\n",
        "         ============================================================"},
        d_mode.name(), d_byte0, d_txn_type.name(), d_dir.name(),
        d_hdr_base_dw, d_ohc_dw, d_hdr_dw,
        d_address, d_is_4dw ? "4DW header / 64-bit" : "3DW header / 32-bit",
        d_length, d_length * 4,
        d_requester_id, d_tag,
        d_tc, d_attr, d_at,
        d_td, d_ep, d_ts, d_ohc,
        d_first_dw_be, d_last_dw_be,
        d_payload_dw,
        (d_txn_type == PCIe_TL_CFG) ?
          $sformatf("cfg_space  bus=0x%02h dev=0x%02h fn=0x%01h byte_off=0x%03h (Type%0d)",
                     d_cfg_bus_num, d_cfg_dev_num, d_cfg_fn_num, d_cfg_reg_num, d_cfg_type1) :
        (d_txn_type == PCIe_TL_IO) ? "io3dw" : (d_is_4dw ? "mem4dw" : "mem3dw")), UVM_LOW)

    for (int i = 0; i < d_payload_dw; i++)
      `uvm_info("EP_TL_RX_PAYLOAD_DW",
        $sformatf("PAYLOAD DW[%0d] = %08h", i, d_payload[i]), UVM_HIGH)

  endfunction

  function void print_completion(PCIe_sequence_item cpl);

    string dump;
    string line;
    int    b;

    `uvm_info("EP_TL_COMPLETION",
      $sformatf({"\n",
        "         ============================================================\n",
        "                  EP TL MODEL : GENERATED COMPLETION\n",
        "                  (PCIe Base 6.1 Section 2.2.9)\n",
        "         ============================================================\n",
        "         Packet Mode       : %s\n",
        "         Completion Type   : %s\n",
        "         Cpl Status        : %03b (%s)\n",
        "         Completer ID      : 0x%04h\n",
        "         Requester ID      : 0x%04h\n",
        "         Destination BDF   : 0x%04h\n",
        "         Tag               : 0x%04h\n",
        "         Byte Count        : %0d (0x%03h)\n",
        "         Lower Address     : 0x%02h\n",
        "         BCM               : %0b\n",
        "         Length            : %0d DW\n",
        "         OHC-A5 present    : %s\n",
        "         Header DWs        : %0d   Payload DWs : %0d   Total : %0d DW\n",
        "         ============================================================"},
        cpl.pkt_mode.name(),
        cpl.cpl_has_data ? "CplD (with data)" : "Cpl (no data)",
        cpl.cpl_status, cpl_status_name(cpl.cpl_status),
        cpl.completer_id, cpl.requester_id, cpl.dest_bdf, d_tag,
        cpl.byte_count, cpl.byte_count, cpl.lower_address, cpl.bcm,
        cpl.length,
        (cpl.pkt_mode == FLIT) ? (cpl.ohc[0] ? "YES" : "NO") : "N/A (Non-Flit)",
        cpl.tlp_header_dw_count, cpl.tlp_payload_dw_count, cpl.tlp_total_dw_count), UVM_LOW)

    foreach (cpl.serialized_tlp[i])
      `uvm_info("EP_TL_COMPLETION_DW",
        $sformatf("CPL DW[%0d] = %08h  %s", i, cpl.serialized_tlp[i],
                   (i < cpl.tlp_header_dw_count) ? "<-- HEADER/OHC" : "<-- DATA"), UVM_LOW)

    dump = "\n";
    line = "";
    for (b = 0; b < `PCIe_TLP_DATA_BYTE_W; b++) begin
      if ((b % `PCIe_FLIT_DUMP_BPL) == 0)
        line = $sformatf("  [%3d] :", b);
      line = {line, $sformatf(" %02h", cpl.tlp_data[b])};
      if (((b % `PCIe_FLIT_DUMP_BPL) == `PCIe_FLIT_DUMP_BPL-1) ||
          (b == `PCIe_TLP_DATA_BYTE_W-1))
        dump = {dump, line, "\n"};
    end
    `uvm_info("EP_TL_COMPLETION_236B", dump, UVM_LOW)

  endfunction

  function string cpl_status_name(bit [`PCIe_TL_CPL_STATUS_W-1:0] st);
    case (st)
      `PCIe_CPL_STATUS_SC  : return "Successful Completion";
      `PCIe_CPL_STATUS_UR  : return "Unsupported Request";
      `PCIe_CPL_STATUS_CRS : return "Request Retry Status";
      `PCIe_CPL_STATUS_CA  : return "Completer Abort";
      default              : return "Reserved";
    endcase
  endfunction

  //==========================================================================
  // [ATTR] ATTRIBUTE TABLE CHECK - info prints only (does not change any bit)
  //   PCIe Base 6.x Sec 2.2.6.4 Ordering Attributes table (RO / IDO)
  //                 Sec 2.2.6.5 No Snoop Attribute table (Cache Coherency Management)
  //     Attr[2] = IDO (ID-Based Ordering)
  //     Attr[1] = RO  (Relaxed Ordering)
  //     Attr[0] = NS  (No Snoop)
  //   Called from :
  //     decode_tlp()       -> request received from RC  ("RX_REQUEST")
  //     service_request()  -> just before print_completion(), the 236B completion
  //                           sent back to RC ("TX_COMPLETION")
  //==========================================================================
  function void print_attr_table_check(PCIe_sequence_item tr, string where);
    string seq_name;
    string ord_type, ord_model;
    string snp_type, snp_model;

    // name of the sequence that sent this item (item name if no parent)
    if (tr.get_parent_sequence() != null)
      seq_name = tr.get_parent_sequence().get_name();
    else
      seq_name = tr.get_name();

    `uvm_info("EP_TL_ATTR",
      $sformatf("ENTERED_ATTR_CHECK [%s] : sequence=%s  %s %s tag=0x%0h  attr[2:0]=%03b",
                where, seq_name, tr.pkt_mode.name(), tr.txn_type.name(), tr.tag, tr.attr), UVM_LOW)

    // Ordering Attributes table : {Attr[2] IDO , Attr[1] RO}
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

    `uvm_info("EP_TL_ATTR",
      $sformatf("RO_CHECK  [%s] : sequence=%s is RO=%0b  -> Relaxed Ordering %s",
                where, seq_name, tr.attr[1], tr.attr[1] ? "ENABLED" : "DISABLED"), UVM_LOW)

    `uvm_info("EP_TL_ATTR",
      $sformatf("IDO_CHECK [%s] : sequence=%s is IDO=%0b -> ID-Based Ordering %s",
                where, seq_name, tr.attr[2], tr.attr[2] ? "ENABLED" : "DISABLED"), UVM_LOW)

    `uvm_info("EP_TL_ATTR",
      $sformatf("RO_IDO_ORDERING_ATTRIBUTES_TABLE_CHECKED [%s] : IDO(Attr[2])=%0b RO(Attr[1])=%0b -> Ordering Type = %s | Ordering Model = %s",
                where, tr.attr[2], tr.attr[1], ord_type, ord_model), UVM_LOW)

    // No Snoop Attribute table : Attr[0]
    if (tr.attr[0]) begin
      snp_type  = "No Snoop";
      snp_model = "Hardware enforced cache coherency not expected";
    end
    else begin
      snp_type  = "Default";
      snp_model = "Hardware enforced cache coherency expected";
    end

    `uvm_info("EP_TL_ATTR",
      $sformatf("NO_SNOOP_ATTRIBUTE_TABLE_CHECKED [%s] : No Snoop(Attr[0])=%0b -> Cache Coherency Management Type = %s | Coherency Model = %s",
                where, tr.attr[0], snp_type, snp_model), UVM_LOW)

    `uvm_info("EP_TL_ATTR",
      $sformatf("ATTR_CHECK_DONE [%s] : sequence=%s is RO=%0b IDO=%0b NS=%0b , checked Ordering Attributes table (RO / IDO) and No Snoop Attribute table",
                where, seq_name, tr.attr[1], tr.attr[2], tr.attr[0]), UVM_LOW)
  endfunction


endclass

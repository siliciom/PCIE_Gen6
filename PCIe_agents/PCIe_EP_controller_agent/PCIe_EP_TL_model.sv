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

  //==========================================================================
  function new(string name="PCIe_EP_TL_model", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info("EP_TL_MODEL","ENTERED_INTO_EP_TL_MODEL_BUILD_PHASE",UVM_LOW)

    tl_imp     = new("tl_imp",     this);
    tl_mon_imp = new("tl_mon_imp", this);
    tl_ap      = new("tl_ap",      this);

  endfunction

   task reset_phase(uvm_phase phase);
     phase.raise_objection(this);
    clear_all_memories();

    `uvm_info("EP_TL_MODEL",
      $sformatf({"\n",
        "         ============================================================\n",
        "                    EP TL MODEL MEMORY CONFIGURATION\n",
        "         ============================================================\n",
        "         Default packet mode : %s\n",
        "         mem3dw  : %0d x %0d-bit  (%0d bytes)\n",
        "         mem4dw  : %0d x %0d-bit  (%0d bytes)\n",
        "         io3dw   : %0d x %0d-bit  (%0d bytes)\n",
        "         ============================================================"},
        `PCIe_TL_MEM3DW_DEPTH, `PCIe_TL_MEM_DATA_W, `PCIe_TL_MEM3DW_DEPTH*4,
        `PCIe_TL_MEM4DW_DEPTH, `PCIe_TL_MEM_DATA_W, `PCIe_TL_MEM4DW_DEPTH*4,
        `PCIe_TL_IO3DW_DEPTH,  `PCIe_TL_MEM_DATA_W, `PCIe_TL_IO3DW_DEPTH*4), UVM_LOW)

    `uvm_info("EP_TL_MODEL","EXIT_FROM_EP_TL_MODEL_RESET_PHASE",UVM_LOW)
     phase.drop_objection(this);
   endtask

  function void clear_all_memories();
    for (int i = 0; i < `PCIe_TL_MEM3DW_DEPTH; i++) mem3dw[i] = `PCIe_TL_MEM_INIT_VALUE;
    for (int i = 0; i < `PCIe_TL_MEM4DW_DEPTH; i++) mem4dw[i] = `PCIe_TL_MEM_INIT_VALUE;
    for (int i = 0; i < `PCIe_TL_IO3DW_DEPTH;  i++) io3dw [i] = `PCIe_TL_MEM_INIT_VALUE;
  endfunction

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("EP_TL_MODEL",
      $sformatf("EP_TL_SUMMARY : tlp_received=%0d completions_sent=%0d ecrc_pass=%0d ecrc_fail=%0d",
                 n_tlp_rcvd, n_cpl_sent, n_ecrc_pass, n_ecrc_fail), UVM_LOW)
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

    n_tlp_rcvd++;

    `uvm_info("EP_TL_MODEL",
      $sformatf("RECEIVED_236B_TLP_FROM_EP_CONTROLLER_MONITOR #%0d mode=%s",
                 n_tlp_rcvd, item.pkt_mode.name()), UVM_LOW)

    d_mode = item.pkt_mode;
    decode_tlp(item);

    if (!d_valid) begin
      `uvm_info("EP_TL_MODEL",
        "DECODED_AS_NOP_OR_UNSUPPORTED_TLP : no memory access, no completion", UVM_LOW)
      return;
    end

    print_decoded_tlp(item);

    // ---- receive side ECRC recalculation (Section 2.7.1) -------------------
    check_ecrc_rx(item);

    // ---- drive the memory models ------------------------------------------
    cpl = PCIe_sequence_item::type_id::create("ep_tl_completion");
    service_request(item, cpl);

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
    item.mem_locked   = d_mem_locked;
    item.mem_deferrable = d_mem_deferrable;
    item.hdr_dw_count = d_hdr_dw;
    item.tlp_header_dw_count  = d_hdr_dw;
    item.tlp_payload_dw_count = d_payload_dw;
    item.tlp_total_dw_count   = d_total_dw;
    item.flit_type    = PCIe_PAYLOAD_flit;

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

    if (d_is_4dw) begin
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

    if (d_is_4dw)
      d_address = {dw2, dw3[31:2], 2'b00};
    else
      d_address = {dw2[31:2], 2'b00};

    d_valid = 1'b1;

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
    dw = {item.tlp_from_mon[b], item.tlp_from_mon[b+1],
          item.tlp_from_mon[b+2], item.tlp_from_mon[b+3]};
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
    recomputed = generate_ecrc(item.tlp_from_mon, covered_bytes, d_mode);

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

    depth    = is_4dw ? `PCIe_TL_MEM4DW_DEPTH : `PCIe_TL_MEM3DW_DEPTH;
    mem_name = is_4dw ? "mem4dw" : "mem3dw";

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
          `uvm_info("EP_TL_MEM",
            $sformatf("  %s[%0d] <= %08h   (byte addr 0x%016h)",
                       mem_name, idx, wdata[i], addr + (64'(i)*`PCIe_TL_DW_BYTES)), UVM_HIGH)
        end
      end
      else begin
        rdata[i] = is_4dw ? mem4dw[idx] : mem3dw[idx];
        `uvm_info("EP_TL_MEM",
          $sformatf("  %s[%0d] => %08h   (byte addr 0x%016h)",
                     mem_name, idx, rdata[i], addr + (64'(i)*`PCIe_TL_DW_BYTES)), UVM_HIGH)
      end
    end

    `uvm_info("EP_TL_MEM",
      $sformatf("%s_%s_COMPLETE : %0d DW touched",
                 mem_name, (op == PCIe_TL_MEM_OP_WRITE) ? "WRITE" : "READ", len_dw), UVM_LOW)

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

    need_cpl      = 1'b0;
    cpl_with_data = 1'b0;

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
      // CONFIGURATION : always Non-Posted; no dedicated memory model here,
      // Cfg space is out of scope for this task.
      //------------------------------------------------------------------
      PCIe_TL_CFG: begin
        need_cpl      = 1'b1;
        cpl_with_data = (d_dir == PCIe_TL_READ);
        if (cpl_with_data) begin
          rdata    = new[1];
          rdata[0] = '0;
        end
        `uvm_info("EP_TL_MODEL",
          "CONFIGURATION_REQUEST : no cfg-space model, completing with zeros", UVM_LOW)
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

    build_completion(req, cpl, cpl_with_data, rdata);
    print_completion(cpl);

    n_cpl_sent++;

    `uvm_info("EP_TL_MODEL",
      $sformatf("COMPLETION_SENT_FROM_EP_TL_MODEL_TO_EP_DL_MODEL #%0d", n_cpl_sent), UVM_LOW)

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
                                 bit [`PCIe_TL_DATA_DW_W-1:0] rdata []);

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
    cpl.cpl_status    = `PCIe_CPL_STATUS_SC;     // memory is zero initialised, so SC
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

    for (b = 0; b < `PCIe_TLP_DATA_BYTE_W; b++)
      cpl.tlp_from_mon[b] = cpl.tlp_data[b];

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
        "         Targets memory    : %s\n",
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

endclass


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
    cfg_space_t0[`PCIe_TL_CFG_IDX_BAR0] = 32'h0000_0000;
    cfg_space_t0[`PCIe_TL_CFG_IDX_BAR1] = 32'h0000_0000;
    cfg_space_t0[`PCIe_TL_CFG_IDX_BAR2] = 32'h0000_0000;
    cfg_space_t0[`PCIe_TL_CFG_IDX_BAR3] = 32'h0000_0000;
    cfg_space_t0[`PCIe_TL_CFG_IDX_BAR4] = 32'h0000_0000;
    cfg_space_t0[`PCIe_TL_CFG_IDX_BAR5] = 32'h0000_0000;
    cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_BAR0] = 32'h0000_0000;
    cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_BAR1] = 32'h0000_0000;
    cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_BAR2] = 32'h0000_0000;
    cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_BAR3] = 32'h0000_0000;
    cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_BAR4] = 32'h0000_0000;
    cfg_ro_mask_t0[`PCIe_TL_CFG_IDX_BAR5] = 32'h0000_0000;

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
    cfg_ro_mask_t1[`PCIe_TL_CFG_T1_IDX_BAR0] = 32'h0000_0000;
    cfg_ro_mask_t1[`PCIe_TL_CFG_T1_IDX_BAR1] = 32'h0000_0000;

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
    `uvm_info("EP_TL_MODEL",
      $sformatf({"EP_TL_SUMMARY : tlp_received=%0d completions_sent=%0d ecrc_pass=%0d ecrc_fail=%0d ",
                  "cfg_rd=%0d cfg_wr=%0d cfg_unsupported=%0d"},
                 n_tlp_rcvd, n_cpl_sent, n_ecrc_pass, n_ecrc_fail,
                 n_cfg_rd, n_cfg_wr, n_cfg_ur), UVM_LOW)
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

endclass







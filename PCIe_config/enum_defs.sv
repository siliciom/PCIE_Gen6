//=========================================================================================
// File         : enum_defs.sv
// Project      : PCIE_Gen6
// Description  : PCIe_config\enum_defs.sv
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

package typedef_enums;

  // TL enum encodings below come from the `define macros, so the macro file
  // must be visible inside this package (enum_defs.sv is compiled standalone
  // by run.do, before PCIe_pkg.sv).
  `include "PCIe_defines.sv"

  //============================================================================
  //                    TRANSACTION LAYER ENUMS
  //============================================================================

  //--------------------------------------------------------------------------
  // pcie_dllp_type_e - Data-Link Layer Packet type
  //--------------------------------------------------------------------------
  typedef enum bit [1:0] {
    PCIe_DLLP_NONE = 2'd0,   // carries a TLP, not a DLLP
    PCIe_DLLP_ACK  = 2'd1,   // acknowledge
    PCIe_DLLP_NAK  = 2'd2    // negative acknowledge (retry)
  } pcie_dllp_type_e;

  //--------------------------------------------------------------------------
  // pcie_tl_txn_type_e - top-level TLP category
  //--------------------------------------------------------------------------
  typedef enum bit [3:0] {
    PCIe_TL_MEM = 3'd0,   // Memory Read / Write
    PCIe_TL_IO  = 3'd1,   // I/O Read / Write
    PCIe_TL_CFG = 3'd2,   // Configuration Read / Write (Type 0 / Type 1)
    PCIe_TL_MSG = 3'd3,   // Message (with or without data)
    PCIe_TL_CPL = 3'd4    // Completion / Completion with Data
  } pcie_tl_txn_type_e;

  //--------------------------------------------------------------------------
  // pcie_tl_dir_e - read vs. write direction (not used for messages)
  //--------------------------------------------------------------------------
  typedef enum bit {
    PCIe_TL_READ  = 1'b0,
    PCIe_TL_WRITE = 1'b1
  } pcie_tl_dir_e;

  //--------------------------------------------------------------------------
  // pcie_fmttype_e - Non-Flit Mode {Fmt[2:0], Type[4:0]}
  //--------------------------------------------------------------------------
  typedef enum bit [`PCIe_TL_FMTTYPE_W-1:0] {
    PCIe_FMTTYPE_MRD_32   = `PCIe_FMTTYPE_MRD_32,
    PCIe_FMTTYPE_MRD_64   = `PCIe_FMTTYPE_MRD_64,
    PCIe_FMTTYPE_MRDLK_32 = `PCIe_FMTTYPE_MRDLK_32,
    PCIe_FMTTYPE_MRDLK_64 = `PCIe_FMTTYPE_MRDLK_64,
    PCIe_FMTTYPE_MWR_32   = `PCIe_FMTTYPE_MWR_32,
    PCIe_FMTTYPE_MWR_64   = `PCIe_FMTTYPE_MWR_64,

    PCIe_FMTTYPE_IORD     = `PCIe_FMTTYPE_IORD,
    PCIe_FMTTYPE_IOWR     = `PCIe_FMTTYPE_IOWR,

    PCIe_FMTTYPE_CFGRD0   = `PCIe_FMTTYPE_CFGRD0,
    PCIe_FMTTYPE_CFGWR0   = `PCIe_FMTTYPE_CFGWR0,
    PCIe_FMTTYPE_CFGRD1   = `PCIe_FMTTYPE_CFGRD1,
    PCIe_FMTTYPE_CFGWR1   = `PCIe_FMTTYPE_CFGWR1,

    PCIe_FMTTYPE_TCFGRD   = `PCIe_FMTTYPE_TCFGRD,
    PCIe_FMTTYPE_DMWR_32  = `PCIe_FMTTYPE_DMWR_32,
    PCIe_FMTTYPE_DMWR_64  = `PCIe_FMTTYPE_DMWR_64,

    PCIe_FMTTYPE_MSG      = `PCIe_FMTTYPE_MSG,
    PCIe_FMTTYPE_MSGD     = `PCIe_FMTTYPE_MSGD,

    PCIe_FMTTYPE_CPL      = `PCIe_FMTTYPE_CPL,
    PCIe_FMTTYPE_CPLD     = `PCIe_FMTTYPE_CPLD,
    PCIe_FMTTYPE_CPLLK    = `PCIe_FMTTYPE_CPLLK,
    PCIe_FMTTYPE_CPLDLK   = `PCIe_FMTTYPE_CPLDLK,

    PCIe_FMTTYPE_FETCHADD_32 = `PCIe_FMTTYPE_FETCHADD_32,
    PCIe_FMTTYPE_FETCHADD_64 = `PCIe_FMTTYPE_FETCHADD_64,
    PCIe_FMTTYPE_SWAP_32     = `PCIe_FMTTYPE_SWAP_32,
    PCIe_FMTTYPE_SWAP_64     = `PCIe_FMTTYPE_SWAP_64,
    PCIe_FMTTYPE_CAS_32      = `PCIe_FMTTYPE_CAS_32,
    PCIe_FMTTYPE_CAS_64      = `PCIe_FMTTYPE_CAS_64,

    PCIe_FMTTYPE_LPRFX    = `PCIe_FMTTYPE_LPRFX,
    PCIe_FMTTYPE_EPRFX    = `PCIe_FMTTYPE_EPRFX
  } pcie_fmttype_e;

  //--------------------------------------------------------------------------
  // pcie_flit_type_e - Flit Mode Type[7:0]
  //--------------------------------------------------------------------------
  typedef enum bit [`PCIe_TL_FLIT_TYPE_W-1:0] {
    PCIe_FLITTYPE_MRD_32       = `PCIe_FLITTYPE_MRD_32,
    PCIe_FLITTYPE_MRD_64       = `PCIe_FLITTYPE_MRD_64,

    PCIe_FLITTYPE_MWR_32       = `PCIe_FLITTYPE_MWR_32,
    PCIe_FLITTYPE_MWR_64       = `PCIe_FLITTYPE_MWR_64,

    PCIe_FLITTYPE_MRDLK_32     = `PCIe_FLITTYPE_MRDLK_32,
    PCIe_FLITTYPE_MRDLK_64     = `PCIe_FLITTYPE_MRDLK_64,

    PCIe_FLITTYPE_DMWR_32      = `PCIe_FLITTYPE_DMWR_32,
    PCIe_FLITTYPE_DMWR_64      = `PCIe_FLITTYPE_DMWR_64,

    PCIe_FLITTYPE_IORD         = `PCIe_FLITTYPE_IORD,
    PCIe_FLITTYPE_IOWR         = `PCIe_FLITTYPE_IOWR,

    PCIe_FLITTYPE_CFGRD0       = `PCIe_FLITTYPE_CFGRD0,
    PCIe_FLITTYPE_CFGWR0       = `PCIe_FLITTYPE_CFGWR0,
    PCIe_FLITTYPE_CFGRD1       = `PCIe_FLITTYPE_CFGRD1,
    PCIe_FLITTYPE_CFGWR1       = `PCIe_FLITTYPE_CFGWR1,

    PCIe_FLITTYPE_MSG          = `PCIe_FLITTYPE_MSG,
    PCIe_FLITTYPE_MSGD         = `PCIe_FLITTYPE_MSGD,

    PCIe_FLITTYPE_CPL          = `PCIe_FLITTYPE_CPL,
    PCIe_FLITTYPE_CPLD         = `PCIe_FLITTYPE_CPLD,

    PCIe_FLITTYPE_CPLLK        = `PCIe_FLITTYPE_CPLLK,
    PCIe_FLITTYPE_CPLDLK       = `PCIe_FLITTYPE_CPLDLK,

    PCIe_FLITTYPE_FETCHADD_32  = `PCIe_FLITTYPE_FETCHADD_32,
    PCIe_FLITTYPE_FETCHADD_64  = `PCIe_FLITTYPE_FETCHADD_64,

    PCIe_FLITTYPE_SWAP_32      = `PCIe_FLITTYPE_SWAP_32,
    PCIe_FLITTYPE_SWAP_64      = `PCIe_FLITTYPE_SWAP_64,

    PCIe_FLITTYPE_CAS_32       = `PCIe_FLITTYPE_CAS_32,
    PCIe_FLITTYPE_CAS_64       = `PCIe_FLITTYPE_CAS_64
  } pcie_flit_type_e;

  //--------------------------------------------------------------------------
  // pcie_msg_route_e - message routing sub-field (Type[2:0])
  //--------------------------------------------------------------------------
  typedef enum bit [`PCIe_TL_MSG_ROUTE_W-1:0] {
    PCIe_MSG_ROUTE_TO_RC       = `PCIe_MSG_ROUTE_TO_RC,
    PCIe_MSG_ROUTE_BY_ADDR     = `PCIe_MSG_ROUTE_BY_ADDR,
    PCIe_MSG_ROUTE_BY_ID       = `PCIe_MSG_ROUTE_BY_ID,
    PCIe_MSG_ROUTE_BROADCAST   = `PCIe_MSG_ROUTE_BROADCAST,
    PCIe_MSG_ROUTE_LOCAL       = `PCIe_MSG_ROUTE_LOCAL,
    PCIe_MSG_ROUTE_GATHER      = `PCIe_MSG_ROUTE_GATHER
  } pcie_msg_route_e;

  //--------------------------------------------------------------------------
  // pkt_mode_e - TL packet mode selector used by the sequences
  //--------------------------------------------------------------------------
  typedef enum logic {
    NON_FLIT = 1'b0,
    FLIT     = 1'b1
  } pkt_mode_e;

  //--------------------------------------------------------------------------
  // ohc_a_type_e - Orthogonal Header Content, category A sub-type
  //--------------------------------------------------------------------------
  typedef enum {
    OHC_A_NONE,
    OHC_A1,
    OHC_A2,
    OHC_A3,
    OHC_A4,
    OHC_A5
  } ohc_a_type_e;


  //============================================================================
  //          TL MEMORY-MODEL / COMPLETION / FLIT-KIND ENUMS       [ADDED]
  //============================================================================

  //--------------------------------------------------------------------------
  // pcie_tl_mem_sel_e - which of the three EP TL memory models is targeted
  //--------------------------------------------------------------------------
  typedef enum bit [1:0] {
    PCIe_TL_MEM_SEL_3DW = 2'd0,   // mem3dw : 3DW header (32-bit address) MEM
    PCIe_TL_MEM_SEL_4DW = 2'd1,   // mem4dw : 4DW header (64-bit address) MEM
    PCIe_TL_MEM_SEL_IO  = 2'd2    // io3dw  : 3DW header I/O
  } pcie_tl_mem_sel_e;

  //--------------------------------------------------------------------------
  // pcie_tl_mem_op_e - direction handed to the memory access functions
  //--------------------------------------------------------------------------
  typedef enum bit {
    PCIe_TL_MEM_OP_WRITE = 1'b0,
    PCIe_TL_MEM_OP_READ  = 1'b1
  } pcie_tl_mem_op_e;

  //--------------------------------------------------------------------------
  // pcie_cpl_status_e - Completion Status[2:0]  (Table 2-37)
  //--------------------------------------------------------------------------
  typedef enum bit [`PCIe_TL_CPL_STATUS_W-1:0] {
    PCIe_CPL_SC  = `PCIe_CPL_STATUS_SC,   // 000b Successful Completion
    PCIe_CPL_UR  = `PCIe_CPL_STATUS_UR,   // 001b Unsupported Request
    PCIe_CPL_RRS = `PCIe_CPL_STATUS_CRS,  // 010b Request Retry Status
    PCIe_CPL_CA  = `PCIe_CPL_STATUS_CA    // 100b Completer Abort
  } pcie_cpl_status_e;

  //--------------------------------------------------------------------------
  // PCIe_flit_type_e - Flit Type as defined in Table 4-16
  //--------------------------------------------------------------------------
  typedef enum bit [1:0] {
    PCIe_IDLE_flit    = 2'd0,  // NOP TLPs, DLP0/1 all 0s, NOP2 DLLP
    PCIe_NOP_flit     = 2'd1,  // NOP TLPs, Flit Usage 00b, seq = NEXT-1
    PCIe_PAYLOAD_flit = 2'd2   // at least one non-NOP TLP, Flit Usage 01b
  } PCIe_flit_type_e;

  //--------------------------------------------------------------------------
  // pcie_ecrc_state_e - result of the receive-side ECRC recalculation
  //--------------------------------------------------------------------------
  typedef enum bit [1:0] {
    PCIe_ECRC_ABSENT = 2'd0,   // TD==0 (NFM) / TS==000b (FM) : nothing to check
    PCIe_ECRC_PASS   = 2'd1,
    PCIe_ECRC_FAIL   = 2'd2
  } pcie_ecrc_state_e;

  //============================================================================
  //                 DATA-LINK / PHYSICAL LAYER ENUMS  (unchanged)
  //============================================================================

  typedef enum bit {
                    STANDARD_REPLAY  = 1'b0, // Replays ALL unacknowledged flits in the buffer
                    SELECTIVE_REPLAY = 1'b1  // Replays ONLY the single flit requested
                   } replay_scheduled_type_e;


  typedef enum
     {
        DETECT,
        POLLING,
        CONFIGURATION,
        RECOVERY,
        L0
     } main_state_e;
     
  typedef enum
     {
        DETECT_QUIET,
        DETECT_ACTIVE
     } detect_state_e;
     
  typedef enum
     {
        POLLING_ACTIVE,
        POLLING_CONFIGURATION,
        POLLING_COMPLIANCE
     } polling_state_e;
     
  typedef enum
     {
        LINKWIDTH_START,
        LINKWIDTH_ACCEPT,
        LANENUM_WAIT,
        LANENUM_ACCEPT,
        CONFIG_COMPLETE,
        CONFIG_IDLE
     } config_state_e; 

typedef enum
     {
        DL_INACTIVE, DL_FEATURE, DL_INIT, DL_ACTIVE
     } dl_state_e;

typedef enum 
     {
       INIT_FC1, INIT_FC2
     } dl_init_substate_e;
typedef struct {
    bit [`PCIe_TLP_DATA_BYTE_W-1:0][`PCIe_BYTE_W-1:0] tlp_data;
    bit [`PCIe_SEQ_NUM_W-1:0] seq_num;
  } tx_buffer_t;
     

endpackage

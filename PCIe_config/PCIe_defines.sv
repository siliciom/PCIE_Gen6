//////////////////////////////////////////////////////////////////////////////////
// FILE:  PCIE_defines.svh
// DESC:  Central `define macro repository for the PCIe Gen6 environment.
//          - TL field bit-widths (mirror PCIE_sequence_item members)
//          - length limits and 3DW/4DW address boundary
//          - Fmt/Type, completion-status, message-routing encodings
//          - Data-Link / Physical layer widths and framing tokens
//        Included FIRST in PCIE_pkg (before enum_defs.sv) so all typedefs,
//        the sequence item, the TL/DL/PL models, and drivers share one source.
//////////////////////////////////////////////////////////////////////////////////

`ifndef PCIe_DEFINES_SVH
`define PCIe_DEFINES_SVH
//==============================================================================
// Force 4DW header for all memory transactions (non-standard, for debug)
//==============================================================================
`ifdef FORCE_4DW
  `define PCIe_FORCE_4DW 1
`else
  `define PCIe_FORCE_4DW 0
`endif

//==============================================================================
// Configuration variants
//==============================================================================
`ifdef DEFAULT
  // 3DW header only (32-bit address)
  `define PCIe_TL_ADDR_W        32
  `define PCIe_TL_LEN_W         10
  `define PCIe_TL_DW_BE_W        4
  `define PCIe_TL_REQ_ID_W      16
  `define PCIe_TL_CPL_ID_W      16
  `define PCIe_TL_TAG_W         14
  `define PCIe_TL_TC_W           3
  `define PCIe_TL_ATTR_W         3
  `define PCIe_TL_DATA_DW_W     32

  `define PCIe_TL_CFG_REG_W     12
  initial $display("PCIe Config: DEFAULT (3DW, 32-bit addr)");
  `define PCIe_TL_CFG_EXT_REG_W  4
  `define PCIe_TL_CFG_BUS_W      8
  `define PCIe_TL_CFG_DEV_W      5
  `define PCIe_TL_CFG_FN_W       3

  `define PCIe_TL_MSG_CODE_W     8
  `define PCIe_TL_MSG_ROUTE_W    3
  `define PCIe_TL_CPL_STATUS_W   3
  `define PCIe_TL_FMTTYPE_W      8

  `define PCIe_TL_LEN_MIN       10'd1
  `define PCIe_TL_LEN_MAX       10'd1023
  `define PCIe_TL_ADDR32_MAX    32'hFFFF_FFFF

`elsif CONFIG_4DW
  // 4DW header (64-bit address)
  `define PCIe_TL_ADDR_W        64
  `define PCIe_TL_LEN_W         10
  `define PCIe_TL_DW_BE_W        4
  `define PCIe_TL_REQ_ID_W      16
  `define PCIe_TL_CPL_ID_W      16
  `define PCIe_TL_TAG_W         10
  `define PCIe_TL_TC_W           3
  `define PCIe_TL_ATTR_W         3
  `define PCIe_TL_DATA_DW_W     32

  `define PCIe_TL_CFG_REG_W     12
  `define PCIe_TL_CFG_EXT_REG_W  4
  `define PCIe_TL_CFG_BUS_W      8
  `define PCIe_TL_CFG_DEV_W      5
  `define PCIe_TL_CFG_FN_W       3

  `define PCIe_TL_MSG_CODE_W     8
  `define PCIe_TL_MSG_ROUTE_W    3
  `define PCIe_TL_CPL_STATUS_W   3
  `define PCIe_TL_FMTTYPE_W      8

  `define PCIe_TL_LEN_MIN       10'd1
  `define PCIe_TL_LEN_MAX       10'd1023
  `define PCIe_TL_ADDR32_MAX    64'h0000_0000_FFFF_FFFF

`else
  // Default fallback (3DW)
  `define PCIe_TL_ADDR_W        32
  `define PCIe_TL_LEN_W         10
  `define PCIe_TL_DW_BE_W        4
  `define PCIe_TL_REQ_ID_W      16
  `define PCIe_TL_CPL_ID_W      16
  `define PCIe_TL_TAG_W         10
  `define PCIe_TL_TC_W           3
  `define PCIe_TL_ATTR_W         3
  `define PCIe_TL_DATA_DW_W     32

  `define PCIe_TL_CFG_REG_W     12
  `define PCIe_TL_CFG_EXT_REG_W  4
  `define PCIe_TL_CFG_BUS_W      8
  `define PCIe_TL_CFG_DEV_W      5
  `define PCIe_TL_CFG_FN_W       3

  `define PCIe_TL_MSG_CODE_W     8
  `define PCIe_TL_MSG_ROUTE_W    3
  `define PCIe_TL_CPL_STATUS_W   3
  `define PCIe_TL_FMTTYPE_W      8

  `define PCIe_TL_LEN_MIN       10'd1
  `define PCIe_TL_LEN_MAX       10'd1023
  `define PCIe_TL_ADDR32_MAX    32'hFFFF_FFFF

`endif

//==============================================================================
// Fmt/Type encodings : {Fmt[2:0], Type[4:0]}
//   Fmt[2]=4DW header, Fmt[1]=data payload present, Fmt[0]=TLP Prefix present
//==============================================================================
`define PCIe_FMTTYPE_MRD_32     8'b000_00000
`define PCIe_FMTTYPE_MRD_64     8'b001_00000
`define PCIe_FMTTYPE_MRDLK_32   8'b000_00001
`define PCIe_FMTTYPE_MRDLK_64   8'b001_00001
`define PCIe_FMTTYPE_MWR_32     8'b010_00000
`define PCIe_FMTTYPE_MWR_64     8'b011_00000

`define PCIe_FMTTYPE_IORD       8'b000_00010
`define PCIe_FMTTYPE_IOWR       8'b010_00010

`define PCIe_FMTTYPE_CFGRD0     8'b000_00100
`define PCIe_FMTTYPE_CFGWR0     8'b010_00100
`define PCIe_FMTTYPE_CFGRD1     8'b000_00101
`define PCIe_FMTTYPE_CFGWR1     8'b010_00101

`define PCIe_FMTTYPE_TCFGRD     8'b000_11011
`define PCIe_FMTTYPE_DMWR_32    8'b010_11011
`define PCIe_FMTTYPE_DMWR_64    8'b011_11011

`define PCIe_FMTTYPE_MSG        8'b001_10000
`define PCIe_FMTTYPE_MSGD       8'b011_10000

`define PCIe_FMTTYPE_CPL        8'b000_01010
`define PCIe_FMTTYPE_CPLD       8'b010_01010
`define PCIe_FMTTYPE_CPLLK      8'b000_01011
`define PCIe_FMTTYPE_CPLDLK     8'b010_01011

`define PCIe_FMTTYPE_FETCHADD_32 8'b010_01100
`define PCIe_FMTTYPE_FETCHADD_64 8'b011_01100
`define PCIe_FMTTYPE_SWAP_32     8'b010_01101
`define PCIe_FMTTYPE_SWAP_64     8'b011_01101
`define PCIe_FMTTYPE_CAS_32      8'b010_01110
`define PCIe_FMTTYPE_CAS_64      8'b011_01110

`define PCIe_FMTTYPE_LPRFX      8'b100_00000
`define PCIe_FMTTYPE_EPRFX      8'b100_10000

//==============================================================================
// FLIT Mode Type[7:0] encodings
//==============================================================================

// Type[7:0] = 8-bit FLIT-mode TLP Type
// No Fmt field exists in FLIT Mode.
//==============================================================================
`define PCIe_FLITTYPE_NOP          8'h00
`define PCIe_TL_FLIT_TYPE_W          8'h8

//------------------------------------------------------------------------------
// Memory Read / I/O / Configuration Requests
//------------------------------------------------------------------------------
`define PCIe_FLITTYPE_MRDLK_32     8'h01
`define PCIe_FLITTYPE_IORD         8'h02
`define PCIe_FLITTYPE_MRD_32       8'h03

`define PCIe_FLITTYPE_CFGRD0       8'h04
`define PCIe_FLITTYPE_CFGRD1       8'h05

//------------------------------------------------------------------------------
// Completion
//------------------------------------------------------------------------------
`define PCIe_FLITTYPE_CPL          8'h0A
`define PCIe_FLITTYPE_CPLLK        8'h0B

//------------------------------------------------------------------------------
// 64-bit Memory Read
//------------------------------------------------------------------------------
`define PCIe_FLITTYPE_MRD_64       8'h20
`define PCIe_FLITTYPE_MRDLK_64     8'h21

//------------------------------------------------------------------------------
// Messages without Data
//------------------------------------------------------------------------------
`define PCIe_FLITTYPE_MSG_RC       8'h30
`define PCIe_FLITTYPE_MSG_ID       8'h31
`define PCIe_FLITTYPE_MSG_BRC      8'h32
`define PCIe_FLITTYPE_MSG_LOCAL    8'h33

//------------------------------------------------------------------------------
// Memory Write / I/O Write / Configuration Write
//------------------------------------------------------------------------------
`define PCIe_FLITTYPE_MWR_32       8'h40
`define PCIe_FLITTYPE_IOWR         8'h42
`define PCIe_FLITTYPE_CFGWR0       8'h44
`define PCIe_FLITTYPE_CFGWR1       8'h45

//------------------------------------------------------------------------------
// Deferrable Memory Write
//------------------------------------------------------------------------------
`define PCIe_FLITTYPE_DMWR_32      8'h5B

//------------------------------------------------------------------------------
// 64-bit Memory Write
//------------------------------------------------------------------------------
`define PCIe_FLITTYPE_MWR_64       8'h60

//------------------------------------------------------------------------------
// Atomic Operations - 64-bit addressing
//------------------------------------------------------------------------------
`define PCIe_FLITTYPE_FETCHADD_64  8'h6C
`define PCIe_FLITTYPE_SWAP_64      8'h6D
`define PCIe_FLITTYPE_CAS_64       8'h6E

//------------------------------------------------------------------------------
// Message with Data
//------------------------------------------------------------------------------
`define PCIe_FLITTYPE_MSGD_RC      8'h70
`define PCIe_FLITTYPE_MSGD_ID      8'h71
`define PCIe_FLITTYPE_MSGD_BRC     8'h72
`define PCIe_FLITTYPE_MSGD_LOCAL   8'h73

//------------------------------------------------------------------------------
// Deferrable Memory Write - 64-bit
//------------------------------------------------------------------------------
`define PCIe_FLITTYPE_DMWR_64      8'h7C

//------------------------------------------------------------------------------
// FLIT Mode Local TLP Prefix
//------------------------------------------------------------------------------
`define PCIe_FLITTYPE_PREFIX       8'h8D
`define PCIe_FLITTYPE_MSG        8'b001_10000
`define PCIe_FLITTYPE_MSGD       8'b011_10000
`define PCIe_FLITTYPE_CPLD       8'h4A
`define PCIe_FLITTYPE_CPLLK        8'h0B
`define PCIe_FLITTYPE_CPLDLK       8'h4B

`define PCIe_FLITTYPE_FETCHADD_32  8'h4C
`define PCIe_FLITTYPE_FETCHADD_64  8'h6C

`define PCIe_FLITTYPE_SWAP_32      8'h4D
`define PCIe_FLITTYPE_SWAP_64      8'h6D

`define PCIe_FLITTYPE_CAS_32       8'h4E
`define PCIe_FLITTYPE_CAS_64       8'h6E
//==============================================================================
// Completion status codes (cpl_status field, bit [2:0])
//==============================================================================
`define PCIe_CPL_STATUS_SC   3'b000  // Successful Completion
`define PCIe_CPL_STATUS_UR   3'b001  // Unsupported Request
`define PCIe_CPL_STATUS_CRS  3'b010  // Config Request Retry Status
`define PCIe_CPL_STATUS_CA   3'b100  // Completer Abort

//==============================================================================
// Message routing sub-field (Type[2:0])
//==============================================================================
`define PCIe_MSG_ROUTE_TO_RC      3'b000
`define PCIe_MSG_ROUTE_BY_ADDR    3'b001
`define PCIe_MSG_ROUTE_BY_ID      3'b010
`define PCIe_MSG_ROUTE_BROADCAST  3'b011
`define PCIe_MSG_ROUTE_LOCAL      3'b100
`define PCIe_MSG_ROUTE_GATHER     3'b101

//==============================================================================
// Data-Link / Physical layer field widths and framing tokens
//==============================================================================
`define PCIe_DL_SEQNUM_W     12    // TLP sequence number (DL)
`define PCIe_DL_LCRC_W       32    // Link CRC (DL)
`define PCIe_PL_FRAME_W       8    // STP/END framing token width (PL)

`define PCIe_PL_STP          8'hFB // Start TLP
`define PCIe_PL_END          8'hFD // End Good
`define PCIe_PL_EDB          8'hFE // End Bad (nullified)
//------------------------------------------------------------------------------
// Data Link Layer fields
//------------------------------------------------------------------------------
`define PCIe_DLLP_CONTENT_W          32
`define PCIe_SEQ_NUM_W               10

//------------------------------------------------------------------------------
// Sequence item control fields
//------------------------------------------------------------------------------
`define PCIe_NAK_SCHEDULED_W         1
`define PCIe_NAK_SCHEDULED_TYPE_W    1
`define PCIe_STANDARD_NAK_W          1
`define PCIe_LAST_FLIT_PAYLOAD_W     1
`define PCIe_CREDIT_W                1
`define PCIe_IS_PAYLOAD_W            1

//------------------------------------------------------------------------------
// FLIT / DLP data widths
//------------------------------------------------------------------------------
`define PCIe_TLP_DATA_BYTE_W         236
`define PCIe_DLP_FLIT_BYTE_W         242
`define PCIe_REPLAYED_FLIT_BYTE_W    242
`define PCIe_DLP_BYTE_W              6
`define PCIe_BYTE_W  		     8
`define PCIe_REPLAY_CMD_W            2
`define PCIe_FLIT_USAGE_W            2
`define PCIe_FLIT_REPLAY_NUM_W       3
`define PCIe_MAX_UNACK_FLITS         511

//==============================================================================
// Flow Control DLLP field widths
//==============================================================================
`define PCIe_FC_PHASE_W             2
`define PCIe_FC_CLASS_W             2
`define PCIe_FC_VC_W                3
`define PCIe_FC_SCALE_W             2
`define PCIe_FC_HDR_W              12
`define PCIe_FC_DATA_W             16
`define PCIe_FC_HDR_TX_W            8
`define PCIe_FC_DATA_TX_W          12
`define PCIe_DLLP_TYPE_PREFIX_W     4

//------------------------------------------------------------------------------
// Monitor interface fields
//------------------------------------------------------------------------------
`define PCIe_MON_DATA_W              32
`define PCIe_MON_DATA                8
`define PCIe_SB_DATA_W               32

`define PCIe_TX_VALID_W               1
`define PCIe_TX_ELEC_IDLE_W           1
`define PCIe_TX_DETECT_RX_W           1
`define PCIe_POWERDOWN_W              2
`define PCIe_RATE_W                   3

`define PCIe_RX_VALID_W               1
`define PCIe_RX_ELEC_IDLE_W           1
`define PCIe_RX_STATUS_W              3
`define PCIe_PHY_STATUS_W             1

//==============================================================================
// Physical Layer / Scrambler / PIPE widths
//==============================================================================
`define PCIe_PL_PIPE_WORD_W          32
`define PCIe_PL_BYTES_PER_WORD       4
`define PCIe_PL_SYMBOL_W             2
`define PCIe_PL_SCRAMBLER_LFSR_W     23

`define PCIe_PL_SCRAMBLER_POLYNOMIAL 23'b01000010000000100100101
`define PCIe_PL_SCRAMBLER_SEED       23'h7FFFFF

//==============================================================================
// Initial values for state machines and sequence numbers
//==============================================================================
`define PCIe_INIT_PREVIOUS_SYMBOL    2'b11
`define PCIe_INIT_TX_ACKNAK_SEQ_NUM  10'h3FF
`define PCIe_INIT_NEXT_TX_FLIT_SEQ_NUM  10'h001
`define PCIe_INIT_NEXT_EXPECTED_RX_FLIT_SEQ_NUM  10'h001
`define PCIe_INIT_IMPLICIT_RX_FLIT_SEQ_NUM  10'h000
`define PCIe_INIT_ACKD_FLIT_SEQ_NUM  10'h3FF
`define PCIe_INIT_FLIT_REPLAY_NUM    3'b000
`define PCIe_INIT_TX_REPLAY_FLIT_SEQ_NUM  10'h000
`define PCIe_INIT_NAK_IGNORE_FLIT_SEQ_NUM  10'h000
`define PCIe_INIT_RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM  10'h000
`define PCIe_INIT_NEXT_RX_FLIT_SEQ_NUM_TO_STORE  10'h001

//==============================================================================
// TS Ordered Set configuration
//==============================================================================
`define PCIe_TS_OS_SIZE              16
`define PCIe_TS1_TX_COUNT            10
`define PCIe_TS1_RX_COUNT            8
`define PCIe_TS2_TX_COUNT            16
`define PCIe_TS2_RX_COUNT            8
`define PCIe_OS_BYPASS_IDX_0         0
`define PCIe_OS_BYPASS_IDX_1         8
`define PCIe_OS_BYPASS_IDX_2         15

//==============================================================================
// TS K-symbol encodings (first symbol of ordered set)
//==============================================================================
`define PCIe_TS_K_SYMBOL_TS1         2'b11  // COM (K-symbol for TS1)
`define PCIe_TS_K_SYMBOL_TS2         2'b10  // COM (K-symbol for TS2)
`define PCIe_TS_K_SYMBOL_IDLE        2'b00  // IDLE (K-symbol for IDLE)

//==============================================================================
// FLIT mode configuration
//==============================================================================
`define PCIe_FLIT_DWORDS             61

//==============================================================================
// Sequence Number Constants
//==============================================================================
`define PCIe_SEQ_NUM_ZERO            10'h000
`define PCIe_SEQ_NUM_MAX             10'h3FF  // 1023

`define PCIe_FLIT_REPLAY_NUM         3'h0  // 1023

//==============================================================================
// PHY timing (for monitors only - PHY driver keeps hardcoded values per requirement)
//==============================================================================
`define PCIe_PHY_MON_RX_SAMPLE_DELAY 15.625ps
`define PCIe_PHY_TX_BIT_DELAY        31.25ps

//==============================================================================
// DLLP/FLIT field bit positions
//==============================================================================
`define PCIe_DLP0_FLIT_USAGE_HI      7
`define PCIe_DLP0_FLIT_USAGE_LO      6
`define PCIe_DLP0_LAST_FLIT_PAYLOAD  5
`define PCIe_DLP0_DLLP_TYPE          4
`define PCIe_DLP0_REPLAY_CMD_HI      3
`define PCIe_DLP0_REPLAY_CMD_LO      2
`define PCIe_DLP0_SEQ_NUM_HI_HI      1
`define PCIe_DLP0_SEQ_NUM_HI_LO      0

`define PCIe_DLP1_SEQ_NUM_LO_HI      7
`define PCIe_DLP1_SEQ_NUM_LO_LO      0

`define PCIe_FLIT_USAGE_PAYLOAD      2'b01
`define PCIe_FLIT_USAGE_NOP          2'b00
`define PCIe_FLIT_USAGE_IDLE         2'b00

`define PCIe_REPLAY_CMD_EXPLICIT     2'b00
`define PCIe_REPLAY_CMD_ACK          2'b01
`define PCIe_REPLAY_CMD_NAK_STD      2'b10
`define PCIe_REPLAY_CMD_NAK_SEL      2'b11

`define PCIe_DLLP_TYPE_REGULAR       1'b0
`define PCIe_DLLP_TYPE_OPTIMIZED     1'b1


//==============================================================================
// FLIT assembly (Gen6 256 B flit) - used by the TL FLIT packer
//   256 B = 236 B TLP region + 6 B DLP + 8 B CRC + 6 B FEC
//==============================================================================
`define PCIe_FLIT_TOTAL_BYTES     256
`define PCIe_FLIT_TLP_BYTES       236
`define PCIe_FLIT_TLP_DW           59
`define PCIe_FLIT_DLP_BYTES         6
`define PCIe_FLIT_CRC_BYTES         8
`define PCIe_FLIT_FEC_BYTES         6
`define PCIe_FLIT_NOP_DW      32'h0000_0000
`define PCIe_FLIT_DUMP_BPL         16

`endif 
// PCIe_DEFINES_SVH

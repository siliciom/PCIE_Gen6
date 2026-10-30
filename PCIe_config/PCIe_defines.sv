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
// First decoded symbol of a complete Ordered Set. The 2-bit K symbols above are
// only visible after de-precoding, so the receive path classifies Ordered Sets
// on the fully decoded symbol 0: TS1 = 0xBC, TS2 = 0x39, IDLE = 0x4A.
//==============================================================================
`define PCIe_OS_SYM0_TS1             8'hBC
`define PCIe_OS_SYM0_TS2             8'h39
`define PCIe_OS_SYM0_IDLE            8'h4A

//==============================================================================
// Scrambler steps per Ordered Set. Symbols 0, 8 and 15 bypass the scrambler,
// so of the 16 symbols only 13 are descrambled : 13 bytes = 104 LFSR steps.
// send_ordered_set() keeps ONE LFSR running across every Ordered Set of a
// burst, so the receiver can re-derive the descrambler state for Ordered Set n
// of a burst as `PCIe_OS_LFSR_STEPS * n steps from the seed.
//==============================================================================
`define PCIe_OS_SCRAMBLED_BYTES     13
`define PCIe_OS_LFSR_STEPS          (`PCIe_OS_SCRAMBLED_BYTES * 8)
// Receive-side descrambler phase search, in BYTES, searched BOTH WAYS.
//
// The transmit scrambler is one continuous LFSR shared between the Ordered Set
// path (13 scrambled bytes per 16 symbol slots, so `PCIe_OS_LFSR_STEPS steps per
// receive window) and the 32 bit data path (scramble_32(), 4 scrambled bytes per
// dword, so 128 steps per window). The receiver cannot tell the two apart before
// it has decoded something, so its nominal phase drifts either way:
//
//   * data windows cost the transmitter MORE than the nominal 104, so the true
//     phase runs AHEAD of nominal;
//   * a data window that the receiver falsely accepts as an Ordered Set costs the
//     receiver LESS than the transmitter did, so the true phase runs BEHIND.
//
// The search therefore has to run in both directions, which needs a backward
// LFSR step. The polynomial is primitive, so the step is invertible.
//
// A window can never cost fewer than 104 steps, because any 16 consecutive slots
// contain exactly one slot of each residue mod 16 and only slots 0, 8 and 15
// bypass the scrambler.
`define PCIe_RX_LFSR_PHASE_SEARCH   200

//==============================================================================
// Link data rate : PIPE `rate` encoding + TS Data Rate Identifier
//   PCIe Base 6.0 Table 4-26. The 3-bit value on the PIPE `rate` signal is a
//   model-internal label; what actually goes on the wire is the 5-bit Data
//   Rate Identifier carried in TS1/TS2 symbol 4. `PCIe_RATE_GEN6 stays 3'b101
//   because the existing Polling.Active already drives 3'b101 for Gen6.
//==============================================================================
`define PCIe_RATE_NOT_NEGOTIATED  3'b000
`define PCIe_RATE_GEN1            3'b001  //  2.5 GT/s
`define PCIe_RATE_GEN2            3'b010  //  5.0 GT/s
`define PCIe_RATE_GEN3            3'b011  //  8.0 GT/s
`define PCIe_RATE_GEN4            3'b100  // 16.0 GT/s
`define PCIe_RATE_GEN5            3'b110  // 32.0 GT/s
`define PCIe_RATE_GEN6            3'b101  // 64.0 GT/s

//------------------------------------------------------------------------------
// Data Rate Identifier : TS1/TS2 symbol 4 bit layout (Table 4-26)
//   bit 0    : speed_change
//   bits 5:1 : Data Rates Supported (the advertised data rate)
//   bits 7:6 : Autonomous Change / Flit Mode Supported - not modelled
//------------------------------------------------------------------------------
`define PCIe_DRI_SPEED_CHANGE_BIT   0
`define PCIe_DRI_RATE_SHIFT         1
`define PCIe_DRI_RATE_W             5

// Advertised data rate, symbol 4 bits [5:1]
`define PCIe_DRI_GEN1  5'b00001  //  2.5 GT/s
`define PCIe_DRI_GEN2  5'b00011  //  5.0 GT/s
`define PCIe_DRI_GEN3  5'b00111  //  8.0 GT/s
`define PCIe_DRI_GEN4  5'b01111  // 16.0 GT/s
`define PCIe_DRI_GEN5  5'b11111  // 32.0 GT/s
`define PCIe_DRI_GEN6  5'b10111  // 64.0 GT/s

//------------------------------------------------------------------------------
// Symbol indices of the 16-byte TS1/TS2 layout used by this environment.
//   TS1 : 0 TS1 ID | 1 Link | 2 Lane | 3 N_FTS | 4 Data Rate ID
//         5 Equalization Control | 6 Equalization Coef | 7 Latency Timer
//   TS2 : 0 TS2 ID | 1 Link | 2 Lane | 3 N_FTS | 4 Data Rate ID
//         5 Power/Autonomous BW   | 6 Training Control | 7 TLP Prefix
//------------------------------------------------------------------------------
`define PCIe_OS_SYM_TS_ID          0
`define PCIe_OS_SYM_LINK           1
`define PCIe_OS_SYM_LANE           2
`define PCIe_OS_SYM_N_FTS          3
`define PCIe_OS_SYM_RATE_ID        4
`define PCIe_OS_SYM_EQ_CTRL        5
`define PCIe_OS_SYM_EQ_COEF        6

//==============================================================================
// Recovery substates - PCIe Base 6.0 Section 4.2.7.4
//==============================================================================
`define PCIe_RECOVERY_TS1_TX_COUNT   8    // TX 8 TS1 in RcvrLock / Equalization
`define PCIe_RECOVERY_TS1_RX_COUNT   8    // RX 8 consecutive TS1
`define PCIe_RECOVERY_TS2_TX_COUNT   16   // TX 16 TS2 in RcvrCfg
`define PCIe_RECOVERY_TS2_RX_COUNT   8    // RX 8 consecutive TS2
`define PCIe_RECOVERY_IDLE_COUNT      2   // 2 IDLE in Recovery.Idle -> L0
`define PCIe_RECOVERY_EQ_PHASE_COUNT  3   // Downstream/Upstream Phases 1..3
// Lowest generation (8.0 GT/s) at or above which equalization is performed
`define PCIe_EQ_MIN_GEN              3

// [MERGE] Length, in PIPE dwords, of the training Ordered Set stream of a plain
// (non directed) link-up: 58 Ordered Sets x 4 dwords. The controller monitors
// leave Ordered Set mode / place the first flit boundary after this many dwords.
// A directed Recovery walk uses the real count from the PL model instead
// (rc_tx_training_dwords() / ep_tx_training_dwords()).
`define PCIe_LINKUP_TRAINING_DWORDS  232

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


//==============================================================================
// TL MEMORY MODELS  (EP TL model)                              [ADDED]
//   Three independent memory models live in the EP TL model:
//     mem3dw  - target of 3DW-header (32-bit address) Memory Requests
//     mem4dw  - target of 4DW-header (64-bit address) Memory Requests
//     io3dw   - target of 3DW-header I/O Requests
//   Every one of them is declared from the macros below, never with a
//   hard-coded literal inside the model.
//==============================================================================
`define PCIe_TL_MEM_DATA_W          32          // one memory location = 1 DW
`define PCIe_TL_MEM_ADDR_LSB         2          // byte address -> DW index shift

`define PCIe_TL_MEM3DW_DEPTH      1024          // 1024 DW = 4 KB
`define PCIe_TL_MEM4DW_DEPTH      1024          // 1024 DW = 4 KB
`define PCIe_TL_IO3DW_DEPTH       1024          // 1024 DW = 4 KB
// cfg_space  - target of Configuration Read/Write Requests, one flat 4 KB
//              (Extended Config Space) region, DW-indexed by cfg_reg_num[11:2]
//              exactly the way the RC/EP TL models pack/unpack it.
`define PCIe_TL_CFGSPACE_DEPTH    1024          // 1024 DW = 4 KB

`define PCIe_TL_MEM3DW_IDX_W        10          // $clog2(PCIe_TL_MEM3DW_DEPTH)
`define PCIe_TL_MEM4DW_IDX_W        10          // $clog2(PCIe_TL_MEM4DW_DEPTH)
`define PCIe_TL_IO3DW_IDX_W         10          // $clog2(PCIe_TL_IO3DW_DEPTH)
`define PCIe_TL_CFGSPACE_IDX_W      10          // $clog2(PCIe_TL_CFGSPACE_DEPTH)

`define PCIe_TL_MEM_INIT_VALUE      32'h0000_0000
`define PCIe_TL_MEM_DUMP_DW_PER_LINE 4

//==============================================================================
// CONFIGURATION SPACE HEADER MODEL (EP TL model)                [ADDED]
//   Two independent 4 KB (1024 DW) flat mirrors are kept by the EP TL model,
//   one addressed exclusively by Configuration Type 0 Requests (CfgRd0/
//   CfgWr0) and one addressed exclusively by Configuration Type 1 Requests
//   (CfgRd1/CfgWr1) - see PCIe_EP_TL_model::cfg_access(). Only the 64 byte
//   (16 DW) Predefined Header is populated in EITHER mirror; everything else
//   up to the 4 KB boundary reads back as `PCIe_TL_CFG_INIT_VALUE and any
//   access to it completes Unsupported Request - no Capability structures
//   (PCI-SIG assigned or Extended) are modelled for either header type.
//
//   Sizing (shared by both Type 0 and Type 1):
//==============================================================================
`define PCIe_TL_CFG_SPACE_DW_DEPTH  `PCIe_TL_CFGSPACE_DEPTH   // 1024 DW = 4 KB
`define PCIe_TL_CFG_HDR_DW_DEPTH    16                        // 16 DW  = 64 B header
`define PCIe_TL_CFG_HDR_BYTES       64
`define PCIe_TL_CFG_SPACE_BYTES     (`PCIe_TL_CFG_SPACE_DW_DEPTH * 4)
`define PCIe_TL_CFG_INIT_VALUE      32'h0000_0000

//------------------------------------------------------------------------------
// DW indices - Section 7.5.1.1 : the first 4 DW (offsets 000h-00Ch) share the
// IDENTICAL layout in the Type 0 and the Type 1 Predefined Header, so both
// header initializers reuse the same four IDX macros below.
//------------------------------------------------------------------------------
`define PCIe_TL_CFG_IDX_VENDOR_DEVICE_ID    0   // 000h : Device ID | Vendor ID
`define PCIe_TL_CFG_IDX_COMMAND_STATUS      1   // 004h : Status | Command
`define PCIe_TL_CFG_IDX_REVID_CLASSCODE     2   // 008h : Class Code | Revision ID
`define PCIe_TL_CFG_IDX_CACHE_LAT_HDR_BIST  3   // 00Ch : BIST | Header Type | Latency Timer | Cache Line Size

//------------------------------------------------------------------------------
// DW indices 004h..00Fh - Type 0 Predefined Header only (Section 7.5.1.2)
//------------------------------------------------------------------------------
`define PCIe_TL_CFG_IDX_BAR0            4   // 010h
`define PCIe_TL_CFG_IDX_BAR1            5   // 014h
`define PCIe_TL_CFG_IDX_BAR2            6   // 018h
`define PCIe_TL_CFG_IDX_BAR3            7   // 01Ch
`define PCIe_TL_CFG_IDX_BAR4            8   // 020h
`define PCIe_TL_CFG_IDX_BAR5            9   // 024h
`define PCIe_TL_CFG_IDX_CARDBUS_CIS    10   // 028h
`define PCIe_TL_CFG_IDX_SUBSYS_IDS     11   // 02Ch : Subsystem ID | Subsystem Vendor ID
`define PCIe_TL_CFG_IDX_EXPROM_BAR     12   // 030h
`define PCIe_TL_CFG_IDX_CAP_PTR        13   // 034h : Reserved | Capabilities Pointer
`define PCIe_TL_CFG_IDX_RESERVED_038   14   // 038h
`define PCIe_TL_CFG_IDX_INTLINE_INTPIN 15   // 03Ch : Max_Lat | Min_Gnt | Int Pin | Int Line

// Type 0 power-on defaults (behavioural model - documented placeholder values)
`define PCIe_TL_CFG_DEFAULT_VENDOR_ID     16'h1AB8
`define PCIe_TL_CFG_DEFAULT_DEVICE_ID     16'hE000
`define PCIe_TL_CFG_DEFAULT_REVISION_ID    8'h01
`define PCIe_TL_CFG_DEFAULT_CLASS_CODE    24'hFF_0000    // "does not fit any defined class"
`define PCIe_TL_CFG_DEFAULT_HEADER_TYPE    8'h00         // Type 0, single function
`define PCIe_TL_CFG_DEFAULT_SUBSYS_VID    16'h1AB8
`define PCIe_TL_CFG_DEFAULT_SUBSYS_ID     16'h0001
`define PCIe_TL_CFG_DEFAULT_INT_PIN        8'h01         // INTA#

//------------------------------------------------------------------------------
// DW indices 004h..00Fh - Type 1 (PCI-to-PCI Bridge) Predefined Header only
// (Section 7.5.1.3 / PCI-to-PCI Bridge Architecture Spec 1.2, Figure 7-5).
// DW indices 0-3 are the shared ones defined above.
//------------------------------------------------------------------------------
`define PCIe_TL_CFG_T1_IDX_BAR0                    4  // 010h
`define PCIe_TL_CFG_T1_IDX_BAR1                    5  // 014h
`define PCIe_TL_CFG_T1_IDX_BUSNUM_SECLAT           6  // 018h : Sec Latency Timer | Subordinate Bus | Secondary Bus | Primary Bus
`define PCIe_TL_CFG_T1_IDX_SECSTATUS_IOLIMIT_BASE  7  // 01Ch : Secondary Status | I/O Limit | I/O Base
`define PCIe_TL_CFG_T1_IDX_MEM_LIMIT_BASE          8  // 020h : Memory Limit | Memory Base
`define PCIe_TL_CFG_T1_IDX_PREF_MEM_LIMIT_BASE     9  // 024h : Prefetchable Memory Limit | Prefetchable Memory Base
`define PCIe_TL_CFG_T1_IDX_PREF_BASE_UPPER32      10  // 028h : Prefetchable Base Upper 32 Bits
`define PCIe_TL_CFG_T1_IDX_PREF_LIMIT_UPPER32     11  // 02Ch : Prefetchable Limit Upper 32 Bits
`define PCIe_TL_CFG_T1_IDX_IO_LIMIT_BASE_UPPER16  12  // 030h : I/O Limit Upper 16 | I/O Base Upper 16
`define PCIe_TL_CFG_T1_IDX_CAP_PTR                13  // 034h : Reserved | Capability Pointer
`define PCIe_TL_CFG_T1_IDX_EXPROM_BAR             14  // 038h : Expansion ROM Base Address
`define PCIe_TL_CFG_T1_IDX_BRIDGE_CTRL_INTPIN     15  // 03Ch : Bridge Control | Interrupt Pin | Interrupt Line

// Type 1 power-on defaults (behavioural model - documented placeholder values).
// Class Code is the architected PCI-to-PCI Bridge class (06h/04h/00h) so any
// class-code-aware checker sees a spec-legal value behind a Type 1 header.
`define PCIe_TL_CFG_T1_DEFAULT_VENDOR_ID   16'h1AB8
`define PCIe_TL_CFG_T1_DEFAULT_DEVICE_ID   16'hB000
`define PCIe_TL_CFG_T1_DEFAULT_REVISION_ID  8'h01
`define PCIe_TL_CFG_T1_DEFAULT_CLASS_CODE  24'h06_0400    // Bridge / PCI-to-PCI bridge / Normal decode
`define PCIe_TL_CFG_T1_DEFAULT_HEADER_TYPE  8'h01         // Type 1, single function
`define PCIe_TL_CFG_T1_DEFAULT_INT_PIN      8'h01         // INTA#

//==============================================================================
// TLP DECODE HELPERS (EP TL model)                             [ADDED]
//   Byte 0 of tlp_data[] is the first byte on the wire and is the MSB of DW0.
//==============================================================================
`define PCIe_TL_DW_BYTES             4
`define PCIe_TL_MAX_PAYLOAD_DW       1024        // Length==0 encodes 1024 DW
`define PCIe_TL_LEN_1024DW           10'd0       // [FLIT_SEG] Length field value for a 1024 DW payload
`define PCIe_TL_HDR3DW               3
`define PCIe_TL_HDR4DW               4
`define PCIe_TL_OHC_A_DW             1
`define PCIe_TL_MAX_TLP_DW           (`PCIe_TL_HDR4DW + `PCIe_TL_OHC_A_DW + `PCIe_TL_MAX_PAYLOAD_DW)

//==============================================================================
// ECRC  -  PCIe Base 6.1 Section 2.7.1 / Table 2-55            [ADDED]
//   Polynomial 04C1 1DB7h, seed FFFF FFFFh, bit 0 of byte 0 first (LSB first,
//   hence the reflected polynomial below), result complemented and then
//   byte-wise bit-reversed into the TLP Digest (NFM) / Trailer (FM) per
//   Table 2-55.
//==============================================================================
`define PCIe_TL_ECRC_W               32
`define PCIe_TL_ECRC_DW               1
`define PCIe_TL_ECRC_POLY            32'h04C1_1DB7  // spec form (documentation)
`define PCIe_TL_ECRC_POLY_REFLECTED  32'hEDB8_8320  // LSB-first implementation form
`define PCIe_TL_ECRC_SEED            32'hFFFF_FFFF

// Variant bits - "All Variant bits must be treated as Set for ECRC calculations"
//   Non-Flit Mode : TLP Header symbol 0 bit 0 (Type[0]) , symbol 2 bit 6 (EP)
//   Flit Mode     : TLP Header symbol 0 bit 0 (Type[0]) , symbol 6 bit 7 (EP)
`define PCIe_TL_ECRC_VAR_SYM0         0
`define PCIe_TL_ECRC_VAR_SYM0_BIT     0
`define PCIe_TL_ECRC_NFM_VAR_SYM      2
`define PCIe_TL_ECRC_NFM_VAR_SYM_BIT  6
`define PCIe_TL_ECRC_FM_VAR_SYM       6
`define PCIe_TL_ECRC_FM_VAR_SYM_BIT   7

// TS[2:0] - Trailer Size / use, Flit Mode only (Section 2.2.1.2)
`define PCIe_TL_TS_NO_TRAILER        3'b000
`define PCIe_TL_TS_1DW_ECRC          3'b001

//==============================================================================
// COMPLETION (Cpl / CplD)  -  Section 2.2.9                    [ADDED]
//==============================================================================
`define PCIe_TL_CPL_HDR_DW            3          // 3 DW in both NFM and FM
`define PCIe_TL_CPL_BYTE_COUNT_W     12
`define PCIe_TL_CPL_LOWER_ADDR_W      7
`define PCIe_TL_CPL_BCM_W             1
`define PCIe_TL_CPL_DEFAULT_BYTE_CNT 12'd4       // all Cpl other than MemRd/AtomicOp
`define PCIe_TL_CPL_COMPLETER_ID     16'h0100    // EP completer ID used by the model
`define PCIe_TL_CPL_DEST_BDF         16'h0100    // FM: Destination BDF / BF (ARI)
`define PCIe_TL_CPL_TAG_W            14

// OHC-A5 field positions inside the single OHC DW (Figure 2-11)
`define PCIe_TL_OHCA5_DEST_SEG_HI    31
`define PCIe_TL_OHCA5_DEST_SEG_LO    24
`define PCIe_TL_OHCA5_CPL_SEG_HI     23
`define PCIe_TL_OHCA5_CPL_SEG_LO     16
`define PCIe_TL_OHCA5_DSV            15
`define PCIe_TL_OHCA5_LA_HI           4
`define PCIe_TL_OHCA5_LA_LO           3
`define PCIe_TL_OHCA5_STATUS_HI       2
`define PCIe_TL_OHCA5_STATUS_LO       0

//==============================================================================
// IDLE / NOP FLIT  -  Table 4-16 / Table 4-17                  [ADDED]
//   IDLE Flit : NOP TLPs across all 236 B, DLP0/DLP1 all 0s (Flit Seq Num 0),
//               DLP2..5 = NOP2 DLLP (all zeros, Figure 3-8)
//   NOP  Flit : NOP TLPs across all 236 B, Flit Usage 00b, Flit Seq Num =
//               NEXT_TX_FLIT_SEQ_NUM - 1 when Replay Command is 00b
//==============================================================================
`define PCIe_FLIT_NOP_TLP_DW         32'h0000_0000  // a 1 DW NOP TLP (Type 00h)
`define PCIe_FLIT_IDLE_SEQ_NUM       10'h000
`define PCIe_FLIT_IDLE_DLP0          8'h00
`define PCIe_FLIT_IDLE_DLP1          8'h00
`define PCIe_FLIT_NOP2_DLLP          32'h0000_0000  // NOP2 DLLP, Flit Mode
`define PCIe_FLIT_NOP_DLLP           32'h3100_0000  // NOP DLLP, Non-Flit Mode
`define PCIe_FLIT_TLP_REGION_DW      59            // 236 B / 4

`define PCIe_EP_BUS_NUMBER           8'h01
`define PCIe_EP_DEVICE_NUMBER        5'h00
`define PCIe_EP_FUNCTION_NUMBER      3'h0

//==============================================================================
// LTSSM SUB-STATE TIMEOUTS  (PCIe Base 6.0, Sec 4.2.7 - Detect..L0)  [ADDED]
//   Used by the RC/EP PL models to bound the time spent in each LTSSM
//   sub-state. On expiry the sub-state watchdog forces the spec-defined exit
//   transition. Only Detect..L0 are covered (Recovery is out of scope).
//   Time literals assume a 1ns/1ps timescale (1 PIPE cycle = 1ns).
//==============================================================================
`define PCIe_LTSSM_T_DETECT_QUIET            12ms
`define PCIe_LTSSM_T_POLLING_ACTIVE          24ms
`define PCIe_LTSSM_T_POLLING_CONFIGURATION   48ms
`define PCIe_LTSSM_T_CFG_LINKWIDTH_START     24ms
`define PCIe_LTSSM_T_CFG_LINKWIDTH_ACCEPT     2ms
`define PCIe_LTSSM_T_CFG_LANENUM_WAIT         2ms
`define PCIe_LTSSM_T_CFG_LANENUM_ACCEPT       2ms
`define PCIe_LTSSM_T_CFG_COMPLETE             2ms
`define PCIe_LTSSM_T_CFG_IDLE                 2ms
`define PCIe_LTSSM_T_RCVRY_RCVRLOCK          24ms
`define PCIe_LTSSM_T_RCVRY_EQ_PH1            12ms
`define PCIe_LTSSM_T_RCVRY_EQ_PH2            24ms
`define PCIe_LTSSM_T_RCVRY_EQ_PH2_64G        48ms
`define PCIe_LTSSM_T_RCVRY_EQ_PH3            32ms
`define PCIe_LTSSM_T_RCVRY_EQ_PH3_64G        64ms
`define PCIe_LTSSM_T_RCVRY_RCVRCFG           48ms
`define PCIe_LTSSM_T_RCVRY_IDLE               2ms

`endif 
// PCIe_DEFINES_SVH



//==============================================================================
// FLOW CONTROL  (PCIe Base 6.0, Sec 2.6 / 3.4)                    [FC ADDED]
// Dedicated credits only, VC0 only (default TC0 -> VC0 mapping).
//   Header credit unit = 1 per TLP header, Data credit unit = 4 DW (16 B)
//==============================================================================
`define PCIe_FC_MAX_DATA_CREDITS     2048   // advertised data credits per type
`define PCIe_FC_MAX_HDR_CREDITS      128    // advertised header credits per type
// Spec 2.6.1: max outstanding is 2^(FS-1)-1 (127 hdr / 2047 data). 128/2048
// would break the (LIMIT-REQUIRED) mod 2^FS <= 2^FS/2 gate, so the value put
// on the wire is clamped by 1 while the buffers keep 128/2048.
// Set to 0 to put 128/2048 on the wire un-clamped.
`define PCIe_FC_CLAMP_TO_SPEC_MAX    1
`define PCIe_FC_HDR_FIELD_BITS       8      // FS for header credits (scale 01b)
`define PCIe_FC_DATA_FIELD_BITS      12     // FS for data credits   (scale 01b)
`define PCIe_FC_VC0                  0
// DLLP type encodings (bits [31:30] of the 32-bit DLLP payload)
`define PCIe_FC_TYPE_INITFC1         2'b01
`define PCIe_FC_TYPE_INITFC2         2'b11
`define PCIe_FC_TYPE_UPDATEFC        2'b10
// Credit class encodings (bits [29:28])
`define PCIe_FC_CLASS_P              2'b00
`define PCIe_FC_CLASS_NP             2'b01
`define PCIe_FC_CLASS_CPL            2'b10
// HdrScale/DataScale encodings
`define PCIe_FC_SCALE_INF            2'b00  // with credit value 0 => infinite
`define PCIe_FC_SCALE_1X             2'b01
// Number of InitFC rounds sent before the DLCMSM gives up (watchdog)
`define PCIe_FC_INIT_MAX_ROUNDS 20
`define PCIe_FC_INIT_ROUND_GAP_NS    200    // pause between InitFC rounds while waiting for the peer
// UpdateFC policy
// [FC_OPT] OLD : `define PCIe_FC_UPDATE_PERIOD_NS     10000  // periodic refresh (debug 10us, Flit Mode)
// [FC_OPT] NEW : spec Sec 2.6.1.2 : in L0 an UpdateFC for each non-infinite credit type must be sent at
//                least once every 30 us (-0%/+50%). The refresh is now sent only when 30 us have passed
//                since the last UpdateFC of that type (see fc_run_periodic in the RC / EP TL models).
`define PCIe_FC_UPDATE_PERIOD_NS     30000  // max time between UpdateFCs of one type (spec : 30 us)
// [FC_OPT] Flow-control initialization : avoid sending extra (not required) DLLP flits
//   PCIe_FC_INIT_WAIT_NS : after sending one InitFC1 / InitFC2 round (6 DLLPs), wait up to this
//     long for the peer's DLLPs (FI1 / FI2) before sending the round again. Spec 3.4.1 : the
//     six DLLPs must be sent at least once every 34 us, so this MUST be < 34000.
//   PCIe_FC_SEND_INITIAL_UPDATEFC : 1 = send 6 UpdateFC (P/NP/Cpl dedicated + shared) right at
//     DL_ACTIVE, 0 = do not. They are optional : the peer sets FI2 on the received InitFC2, and the
//     periodic / mandatory UpdateFCs (Sec 2.6.1.2) are still sent.
//   With 5000 / 0 a 2-TLP test sends 1 Feature + 6 InitFC1 + 6 InitFC2 + 2 TLP = 15 flits (RC -> EP).
//   For the old behaviour (33 flits) use 100 / 1.
`define PCIe_FC_INIT_WAIT_NS            5000
`define PCIe_FC_SEND_INITIAL_UPDATEFC   0
`define PCIe_FC_HDR_WATERMARK        32     // send UpdateFC when >= this many hdr credits freed
`define PCIe_FC_DATA_WATERMARK       256    // send UpdateFC when >= this many data credits freed
// Rx_MPS_Limit expressed in data credits (256 B MPS => 16 credits)
`define PCIe_FC_MPS_CREDITS          16
// EP completion gating on RC's CplH/CplD credits (0 = off by default)
`define PCIe_FC_GATE_EP_COMPLETIONS  0


//==============================================================================
// SHARED / DEDICATED FLOW CONTROL - Flit Mode  (PCIe Base 6.0)    [FC SHARED]
//
//   Two credit pools per FC type (P / NP / Cpl) in Flit Mode :
//     DEDICATED : per VC, small. Lets every VC send at least one TLP (no deadlock)
//     SHARED    : common to all VCs, big
//   Transmitter (Sec 2.6.1.1) : SHARED gate first (Eq 2-8); if it fails,
//     DEDICATED gate (Eq 2-11); if both fail, wait for UpdateFC.
//   A TLP sent on DEDICATED credits carries the Flit Mode Local TLP Prefix
//     (Sec 2.2.10.3, Fig 2-77) : Byte0 = 8Dh, Byte1 bit7 = TLP Uses Dedicated
//     Credits. No prefix (or bit Clear) -> SHARED. Receiver accounts per prefix
//     (Sec 2.6.1.2). The prefix is not allowed on a Non-Flit TLP.
//   Only VC0 here : Table 3-2 row 3/4, note 4 -> dedicated = 0 ("Zero"),
//     all credits shared. Note 7 -> shared must not be 0 on VC0.
//
//   Pool sizes = receive buffer size in credits. Run-time override (no
//   recompile) : +FC_DED_HDR=<n> +FC_DED_DATA=<n> +FC_SHR_HDR=<n> +FC_SHR_DATA=<n>
//   Example, both pools used in one run :
//     +FC_SHR_HDR=2 +FC_SHR_DATA=32 +FC_DED_HDR=8 +FC_DED_DATA=64
//==============================================================================
`define PCIe_FC_DED_HDR_CREDITS      0                            // dedicated header credits / type (VC0 : 0)
`define PCIe_FC_DED_DATA_CREDITS     0                            // dedicated data credits / type   (VC0 : 0)
`define PCIe_FC_SHR_HDR_CREDITS      `PCIe_FC_MAX_HDR_CREDITS     // shared header credits / type
`define PCIe_FC_SHR_DATA_CREDITS     `PCIe_FC_MAX_DATA_CREDITS    // shared data credits / type

// Flit Mode Local TLP Prefix, "TLP Uses Dedicated Credits" Set (Fig 2-77)
//   byte0 = 8Dh (Type)   byte1 bit7 = TLP Uses Dedicated Credits   rest reserved
`define PCIe_FC_DED_PREFIX_BYTE1     8'h80
`define PCIe_FC_DED_PREFIX_DW        {`PCIe_FLITTYPE_PREFIX, `PCIe_FC_DED_PREFIX_BYTE1, 16'h0000}

// Pool choice of the transmitter (debug knob, run time : +FC_POOL_MODE=<n>)
//   0 = SPEC      : shared first, dedicated when shared is full  (default)
//   1 = DEDICATED : every Flit Mode TLP uses dedicated (needs dedicated credits)
//   2 = SHARED    : every TLP uses shared
//   3 = ALTERNATE : per type, TLPs take turns shared / dedicated / shared ...
`define PCIe_FC_POOL_MODE            0

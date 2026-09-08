//=========================================================================================
// File         : PCIe_sequence_item.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_sequence_item.sv
//                Unified item : TL request fields + serialized TLP/FLIT output +
//                DL/PL flit fields consumed by the DL and PL models.
// Author       : 
// Date         : 2026-08-14
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

import typedef_enums::*;

class PCIe_sequence_item extends uvm_sequence_item;

  //==========================================================================
  //                    TRANSACTION LAYER  (request description)
  //==========================================================================

  //--------------------------------------------------------------------------
  // Category / direction
  //--------------------------------------------------------------------------
  rand pcie_tl_txn_type_e txn_type;   // MEM / IO / CFG / MSG
  rand pcie_tl_dir_e      dir;        // READ / WRITE (ignored for MSG)

  //--------------------------------------------------------------------------
  // Common TLP header fields
  //--------------------------------------------------------------------------
  rand bit [`PCIe_TL_ADDR_W-1:0] address;  // Full 64-bit address (MEM/IO)
  rand bit [`PCIe_TL_LEN_W-1:0]  length;   // Length in DWs (0 => 1024 DW)

  //--------------------------------------------------------------------------
  // Memory sub-type modifiers (select MRdLk / DMWr variants of MEM category)
  //--------------------------------------------------------------------------
  rand bit        mem_locked;        // 1 => MRdLk (Memory Read Request-Locked)
  rand bit        mem_deferrable;    // 1 => DMWr  (Deferrable Memory Write)
  rand bit [`PCIe_TL_DW_BE_W-1:0]  first_dw_be;   // First DW byte enables
  rand bit [`PCIe_TL_DW_BE_W-1:0]  last_dw_be;    // Last  DW byte enables
  rand bit [`PCIe_TL_REQ_ID_W-1:0] requester_id;  // {bus, dev, fn}
       bit [`PCIe_TL_CPL_ID_W-1:0] completer_id;  // Completer ID (for CPL/CFG)
  rand bit [`PCIe_TL_TAG_W-1:0]    tag;           // Transaction tag
  rand bit [`PCIe_TL_TC_W-1:0]     tc;            // Traffic Class
  rand bit [`PCIe_TL_ATTR_W-1:0]   attr;          // Attributes {IDO, relaxed, no-snoop}
  rand bit        td;                // TLP Digest present
  rand bit        ep;                // Poisoned / Error present

  //--------------------------------------------------------------------------
  // Payload
  //--------------------------------------------------------------------------
  rand bit [`PCIe_TL_DATA_DW_W-1:0] data[];  // DW payload (writes / msg-w-data)

  //--------------------------------------------------------------------------
  // Configuration-specific
  //--------------------------------------------------------------------------
  rand bit [`PCIe_TL_CFG_REG_W-1:0]     cfg_reg_num;
  rand bit [`PCIe_TL_CFG_EXT_REG_W-1:0] cfg_ext_reg_num;
  rand bit [`PCIe_TL_CFG_BUS_W-1:0]     cfg_bus_num;
  rand bit [`PCIe_TL_CFG_DEV_W-1:0]     cfg_dev_num;
  rand bit [`PCIe_TL_CFG_FN_W-1:0]      cfg_fn_num;
  rand bit        cfg_type1;         // 0 => Type0 (CfgRd0/Wr0), 1 => Type1

  //--------------------------------------------------------------------------
  // I/O-specific
  //--------------------------------------------------------------------------
  rand bit [`PCIe_TL_DATA_DW_W-1:0] io_data;

  //--------------------------------------------------------------------------
  // Message-specific
  //--------------------------------------------------------------------------
  rand bit [`PCIe_TL_MSG_CODE_W-1:0] msg_code;
  rand pcie_msg_route_e    msg_route;
  rand bit                 msg_has_data;

  //--------------------------------------------------------------------------
  // Completion capture (populated by the EP TL model on reads)
  //--------------------------------------------------------------------------
  bit [`PCIe_TL_DATA_DW_W-1:0]    cpl_data[];
  bit [`PCIe_TL_CPL_STATUS_W-1:0] cpl_status;

  //--------------------------------------------------------------------------
  // Data-Link layer fields (stamped by the DL model)
  //--------------------------------------------------------------------------
  bit [`PCIe_DL_SEQNUM_W-1:0] dl_seq_num;   // TLP sequence number
  bit [`PCIe_DL_LCRC_W-1:0]   dl_lcrc;      // Link CRC
  pcie_dllp_type_e            dllp_type = PCIe_DLLP_NONE; // ACK/NAK when a DLLP

  //--------------------------------------------------------------------------
  // Physical layer fields (stamped by the PL model)
  //--------------------------------------------------------------------------
  bit [`PCIe_PL_FRAME_W-1:0]  pl_start_frame;  // STP token
  bit [`PCIe_PL_FRAME_W-1:0]  pl_end_frame;    // END/EDB token
  int                         hdr_dw_count;    // header DWs produced by TL

  //--------------------------------------------------------------------------
  // TL packet mode : FLIT or NON_FLIT
  //--------------------------------------------------------------------------
  rand pkt_mode_e pkt_mode;

  //--------------------------------------------------------------------------
  // FLIT OHC indication
  //   bit 0   : OHC-A
  //   bit 1   : OHC-B
  //   bit 2   : OHC-C
  //   bit 4:3 : OHC-E encoding
  //--------------------------------------------------------------------------
  rand logic [4:0] ohc;
  ohc_a_type_e     ohc_a_type;

  rand logic [2:0] ts;
  rand logic [1:0] at;

  //==========================================================================
  // Serialized complete TLP  =  Header Base + OHC + Payload
  //==========================================================================
  bit [`PCIe_TL_DATA_DW_W-1:0] serialized_tlp[];

  //--------------------------------------------------------------------------
  // Assembled FLIT TLP region : 236 bytes = 59 DW.
  // Holds the serialized TLP followed by NOP TLPs (Type 0x00) as padding.
  //--------------------------------------------------------------------------
  bit [`PCIe_TL_DATA_DW_W-1:0] flit_tlp_region[];
  int                          flit_tlp_dw_count;   // DWs used by real TLPs
  int                          flit_nop_dw_count;   // DWs used by NOP padding

  int tlp_header_dw_count;
  int tlp_payload_dw_count;
  int tlp_total_dw_count;

  //==========================================================================
  //           DATA-LINK / PHYSICAL LAYER FIELDS  (consumed by DL / PL)
  //==========================================================================

  // fields responsible for DLP creation in FLIT mode
  bit [`PCIe_DLLP_CONTENT_W-1:0]                         dllp_content;   // 4-byte DLLP (e.g. UpdateFC or NOP)
  bit [`PCIe_SEQ_NUM_W-1:0]                              TX_ACKNACK_FLIT_SEQ_NUM;
  bit [`PCIe_SEQ_NUM_W-1:0]                              NEXT_TX_FLIT_SEQ_NUM;
  bit                                                    NAK_SCHEDULED;
  bit                                                    NAK_SCHEDULED_TYPE;
  bit                                                    STANDARD_NAK;
  bit                                                    TX_ACKNAK_FLIT_SEQ_NUM;
  bit                                                    last_flit_was_payload;
  bit                                                    credit;
  bit                                                    is_payload;
  rand bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_data;      // 236 bytes handed to the DL
  bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0]      dlp_flit_out;   // 242-byte output (TLPs + DLP)
  bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0]      replayed_flit;  // to store the replayed flit
  bit [`PCIe_SEQ_NUM_W-1:0]                              seq_num;        // replayed sequence number

  bit replay_flit;    // only for debug
  bit drive_flit;     // only for debug

  // Necessary to store the data collected from ep and send to scoreboard
  bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp;

  //RC_and_Ep_phy_monitor_signals 
  bit [`PCIe_MON_DATA_W-1:0] data_q_ep_mon_rx[$];
  bit [`PCIe_MON_DATA_W-1:0] data_q_ep_mon_tx[$];
  bit [`PCIe_MON_DATA_W-1:0] data_q_rc_mon_tx[$];
  bit [`PCIe_MON_DATA_W-1:0] data_q_rc_mon_rx[$];

  //RC_controller_monitor_signals 
  bit                          tx_valid; 
  bit                          tx_elec_idle; 
  bit                          tx_detect_rx; 
  bit [`PCIe_POWERDOWN_W-1:0]  powerdown; 
  bit [`PCIe_RATE_W-1:0]       rate; 
  bit [`PCIe_MON_DATA_W-1:0]   data_q_rc_mon_con_tx[$];
  bit [`PCIe_MON_DATA_W-1:0]   data_q_rc_mon_con_rx[$];

  //EP_controller_monitor_signals 
  bit                          rx_valid; 
  bit                          rx_elec_idle; 
  bit [`PCIe_RX_STATUS_W-1:0]  rx_status; 
  bit                          phy_status; 
  bit [`PCIe_MON_DATA_W-1:0]   data_q_ep_mon_con_tx[$];
  bit [`PCIe_MON_DATA_W-1:0]   data_q_ep_mon_con_rx[$];

  //--------------------------------------------------------------------------
  // Field automation
  //--------------------------------------------------------------------------
  `uvm_object_utils_begin(PCIe_sequence_item)
    `uvm_field_enum (pkt_mode_e,         pkt_mode,     UVM_ALL_ON)
    `uvm_field_enum (pcie_tl_txn_type_e, txn_type,     UVM_ALL_ON)
    `uvm_field_enum (pcie_tl_dir_e,      dir,          UVM_ALL_ON)
    `uvm_field_int  (address,        UVM_ALL_ON | UVM_HEX)
    `uvm_field_int  (length,         UVM_ALL_ON)
    `uvm_field_int  (mem_locked,     UVM_ALL_ON)
    `uvm_field_int  (mem_deferrable, UVM_ALL_ON)
    `uvm_field_int  (first_dw_be,    UVM_ALL_ON | UVM_HEX)
    `uvm_field_int  (last_dw_be,     UVM_ALL_ON | UVM_HEX)
    `uvm_field_int  (requester_id,   UVM_ALL_ON | UVM_HEX)
    `uvm_field_int  (completer_id,   UVM_ALL_ON | UVM_HEX)
    `uvm_field_int  (tag,            UVM_ALL_ON | UVM_HEX)
    `uvm_field_int  (tc,             UVM_ALL_ON)
    `uvm_field_int  (attr,           UVM_ALL_ON)
    `uvm_field_int  (td,             UVM_ALL_ON)
    `uvm_field_int  (ep,             UVM_ALL_ON)
    `uvm_field_array_int (data,      UVM_ALL_ON | UVM_HEX)
    `uvm_field_int  (cfg_reg_num,    UVM_ALL_ON | UVM_HEX)
    `uvm_field_int  (cfg_ext_reg_num,UVM_ALL_ON | UVM_HEX)
    `uvm_field_int  (cfg_bus_num,    UVM_ALL_ON | UVM_HEX)
    `uvm_field_int  (cfg_dev_num,    UVM_ALL_ON | UVM_HEX)
    `uvm_field_int  (cfg_fn_num,     UVM_ALL_ON | UVM_HEX)
    `uvm_field_int  (cfg_type1,      UVM_ALL_ON)
    `uvm_field_int  (io_data,        UVM_ALL_ON | UVM_HEX)
    `uvm_field_int  (msg_code,       UVM_ALL_ON | UVM_HEX)
    `uvm_field_enum (pcie_msg_route_e, msg_route,      UVM_ALL_ON)
    `uvm_field_int  (msg_has_data,   UVM_ALL_ON)
    `uvm_field_array_int (cpl_data,  UVM_ALL_ON | UVM_HEX)
    `uvm_field_int  (cpl_status,     UVM_ALL_ON)
  `uvm_object_utils_end

   function void print_dlp_details(string label,  bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp  );
    bit [`PCIe_SEQ_NUM_W-1:0]  flit_seq_num;
    bit [`PCIe_BYTE_W-1:0]  dllp_type;
    bit [`PCIe_FLIT_USAGE_W-1:0]  flit_usage;
    bit [`PCIe_REPLAY_CMD_W-1:0]  replay_cmd;
    bit        prior_was_payload;
    bit        type_of_dllp_payload;
    string     flit_usage_str;
    string     replay_cmd_str;
    // Extract fields from DLP bytes
    flit_seq_num        = {dlp[0][1:0], dlp[1]};
    flit_usage          = dlp[0][7:6];
    prior_was_payload   = dlp[0][3];
    type_of_dllp_payload = dlp[0][4];
    replay_cmd          = dlp[0][3:2];
    dllp_type           = dlp[2];
    // Decode flit_usage
    case (flit_usage)
      2'b00: flit_usage_str = "IDLE/NOP";
      2'b01: flit_usage_str = "PAYLOAD";
      2'b10: flit_usage_str = "RSVD";
      2'b11: flit_usage_str = "RSVD";
      default: flit_usage_str = "UNKNOWN";
    endcase
    // Decode replay_cmd
    case (replay_cmd)
      2'b00: replay_cmd_str = "EXPLICIT_SEQ";
      2'b01: replay_cmd_str = "ACK";
      2'b10: replay_cmd_str = "STD_NAK";
      2'b11: replay_cmd_str = "SEL_NAK";
      default: replay_cmd_str = "UNKNOWN";
    endcase
    // Print in organized format
    `uvm_info("DLP_INFO", "───────────────────────────────────────────────", UVM_LOW)
    `uvm_info("DLP_INFO", $sformatf("[%s]", label), UVM_LOW)
    `uvm_info("DLP_INFO", 
      $sformatf("  Seq Num      : 10'd%0d (0x%3h)", flit_seq_num, flit_seq_num), 
      UVM_LOW)
    `uvm_info("DLP_INFO", 
      $sformatf("  Flit Usage   : 2'b%0b (%s)", flit_usage, flit_usage_str), 
      UVM_LOW)
    `uvm_info("DLP_INFO", 
      $sformatf("  Replay Cmd   : 2'b%0b (%s)", replay_cmd, replay_cmd_str), 
      UVM_LOW)
    `uvm_info("DLP_INFO", 
      $sformatf("  DLLP Type    : 8'h%2h", dllp_type), 
      UVM_LOW)
    `uvm_info("DLP_INFO", 
      $sformatf("  Prior Payload: %b | DLLP Type Bit: %b", prior_was_payload, type_of_dllp_payload), 
      UVM_LOW)
    `uvm_info("DLP_INFO", "───────────────────────────────────────────────", UVM_LOW)
  endfunction

  //--------------------------------------------------------------------------
  // Constraints
  //--------------------------------------------------------------------------
  constraint c_data_size {
     if ((txn_type == PCIe_TL_MEM && dir == PCIe_TL_WRITE) ||
         (txn_type == PCIe_TL_MSG && msg_has_data))
       data.size() == get_payload_dw();
     // IO and Configuration Writes are always exactly 1 DW (Sec 2.2.7)
     else if ((txn_type == PCIe_TL_IO  && dir == PCIe_TL_WRITE) ||
              (txn_type == PCIe_TL_CFG && dir == PCIe_TL_WRITE))
       data.size() == 1;
     else
       data.size() == 0;
  }

  constraint c_length_valid {
     if (txn_type == PCIe_TL_IO || txn_type == PCIe_TL_CFG) 
       length == `PCIe_TL_LEN_MIN;
     else 
       length inside {0, [1:`PCIe_TL_LEN_MAX]};
  }

  //--------------------------------------------------------------------------
  // IO / Configuration Request restrictions - PCIe Base 6.0 Sec 2.2.7
  //   TC[2:0] = 000b, Attr = 000b, AT = 00b, Length = 1 DW, Last DW BE = 0000b
  //--------------------------------------------------------------------------
  constraint c_io_cfg_rules {
    if (txn_type inside {PCIe_TL_IO, PCIe_TL_CFG}) {
      tc   == 3'b000;
      attr == 3'b000;
      at   == 2'b00;
    }
  }

  //--------------------------------------------------------------------------
  // Byte Enable rules - PCIe Base 6.0 Sec 2.2.5.1 / 2.2.5.2
  //--------------------------------------------------------------------------
  constraint c_byte_enable_rules {

    if (txn_type inside {PCIe_TL_MEM, PCIe_TL_IO, PCIe_TL_CFG}) {

      // ---- Length == 1 DW : Last DW BE must be 0000b -----------------------
      if (length == 10'd1) {
        last_dw_be == 4'h0;
      }

      // ---- Length > 1 DW (and length == 0 => 1024 DW) ----------------------
      else {
        first_dw_be != 4'h0;
        last_dw_be  != 4'h0;
      }

      // ---- Contiguity ------------------------------------------------------
      if ((length != 10'd1) &&
          !((length == 10'd2) && (address[2:0] == 3'b000))) {
        first_dw_be inside {4'hF, 4'hE, 4'hC, 4'h8};
        last_dw_be  inside {4'hF, 4'h7, 4'h3, 4'h1};
      }
    }
  }

  constraint flit_ohc_c {

    // Non-FLIT -> no OHC
    (pkt_mode != FLIT) ->
      (ohc == 5'b00000);

    // FLIT -> B/C/E not supported yet
    (pkt_mode == FLIT) ->
      (ohc[4:1] == 4'b0000);

    // FLIT Memory Request with explicit BE -> OHC-A1
    ((pkt_mode == FLIT) &&
     (txn_type == PCIe_TL_MEM) &&
     (
       (first_dw_be != 4'hF) ||
       (
         (length > 10'd1) &&
         (last_dw_be != 4'hF)
       )
     ))
    ->
      (ohc[0] == 1'b1);

    // FLIT Memory Request without explicit BE -> no OHC-A1
    ((pkt_mode == FLIT) &&
     (txn_type == PCIe_TL_MEM) &&
     (first_dw_be == 4'hF) &&
     (
       (length <= 10'd1) ||
       (last_dw_be == 4'hF)
     ))
    ->
      (ohc[0] == 1'b0);
  }

  constraint c_mem_subtype {
    if (txn_type != PCIe_TL_MEM) { mem_locked == 0; mem_deferrable == 0; }
    !(mem_locked && mem_deferrable);
    if (mem_locked)     dir == PCIe_TL_READ;
    if (mem_deferrable) dir == PCIe_TL_WRITE;
  }

  function new(string name="PCIE_sequence_item");
    super.new(name);
  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: is_write - true for write-direction requests / msg-with-data
  //--------------------------------------------------------------------------
  function bit is_write();
    case (txn_type)
      PCIe_TL_MSG : return msg_has_data;
      default     : return (dir == PCIe_TL_WRITE);
    endcase
  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: is_4dw - true when a 64-bit (4DW) memory header is required
  //--------------------------------------------------------------------------
  function bit is_4dw();
    if (txn_type != PCIe_TL_MEM)
        return 1'b0;
       `ifdef PCIe_FORCE_4DW
           return `PCIe_FORCE_4DW;
       `else
           return (address > `PCIe_TL_ADDR32_MAX);
       `endif
  endfunction

  function bit is_64bit_addr();
      `ifdef PCIe_FORCE_4DW
          return (txn_type == PCIe_TL_MEM) && `PCIe_FORCE_4DW;
      `else
          return (txn_type == PCIe_TL_MEM) && (address > `PCIe_TL_ADDR32_MAX);
      `endif
  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: get_fmttype - resolve the Fmt/Type encoding (Non-Flit Mode)
  //--------------------------------------------------------------------------
  function pcie_fmttype_e get_fmttype();
    case (txn_type)
      PCIe_TL_MEM : begin
        if (mem_deferrable)
          return is_4dw() ? PCIe_FMTTYPE_DMWR_64 : PCIe_FMTTYPE_DMWR_32;
        if (mem_locked)
          return is_4dw() ? PCIe_FMTTYPE_MRDLK_64 : PCIe_FMTTYPE_MRDLK_32;
        if (is_4dw())
          return (dir == PCIe_TL_WRITE) ? PCIe_FMTTYPE_MWR_64 : PCIe_FMTTYPE_MRD_64;
        else
          return (dir == PCIe_TL_WRITE) ? PCIe_FMTTYPE_MWR_32 : PCIe_FMTTYPE_MRD_32;
      end
      PCIe_TL_IO  : return (dir == PCIe_TL_WRITE) ? PCIe_FMTTYPE_IOWR : PCIe_FMTTYPE_IORD;
      PCIe_TL_CFG : begin
        if (cfg_type1)
          return (dir == PCIe_TL_WRITE) ? PCIe_FMTTYPE_CFGWR1 : PCIe_FMTTYPE_CFGRD1;
        else
          return (dir == PCIe_TL_WRITE) ? PCIe_FMTTYPE_CFGWR0 : PCIe_FMTTYPE_CFGRD0;
      end
      PCIe_TL_MSG : return msg_has_data ? PCIe_FMTTYPE_MSGD : PCIe_FMTTYPE_MSG;
      default     : return PCIe_FMTTYPE_MRD_32;
    endcase
  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: get_flit_type - resolve the Flit Type encoding
  //--------------------------------------------------------------------------
  function pcie_flit_type_e get_flit_type();
    case (txn_type)

      PCIe_TL_MEM: begin
        if (mem_deferrable) begin
          return is_64bit_addr() ? PCIe_FLITTYPE_DMWR_64 : PCIe_FLITTYPE_DMWR_32;
        end
        if (mem_locked) begin
          return is_64bit_addr() ? PCIe_FLITTYPE_MRDLK_64 : PCIe_FLITTYPE_MRDLK_32;
        end
        if (is_64bit_addr()) begin
          return (dir == PCIe_TL_WRITE) ? PCIe_FLITTYPE_MWR_64 : PCIe_FLITTYPE_MRD_64;
        end
        else begin
          return (dir == PCIe_TL_WRITE) ? PCIe_FLITTYPE_MWR_32 : PCIe_FLITTYPE_MRD_32;
        end
      end

      //----------------------------------------------------------------------
      // IO  (Table 2-5 : IORd = 8'h02, IOWr = 8'h42, 3 DW Header Base)
      //----------------------------------------------------------------------
      PCIe_TL_IO:
        return (dir == PCIe_TL_WRITE) ? PCIe_FLITTYPE_IOWR : PCIe_FLITTYPE_IORD;

      //----------------------------------------------------------------------
      // CONFIGURATION
      //----------------------------------------------------------------------
      PCIe_TL_CFG: begin
        if (cfg_type1)
          return (dir == PCIe_TL_WRITE) ? PCIe_FLITTYPE_CFGWR1 : PCIe_FLITTYPE_CFGRD1;
        else
          return (dir == PCIe_TL_WRITE) ? PCIe_FLITTYPE_CFGWR0 : PCIe_FLITTYPE_CFGRD0;
      end

      default:
        return PCIe_FLITTYPE_MRD_32;

    endcase
  endfunction

  //==========================================================================
  // Return actual payload size in DW ( length==0 encodes 1024 DW )
  //==========================================================================
  function int get_payload_dw();
    if (length == 10'd0)
      return 1024;
    else
      return length;
  endfunction

  //==========================================================================
  // Determine OHC-A subtype
  //==========================================================================
  function void determine_ohc_a();

    ohc_a_type = OHC_A_NONE;

    case (txn_type)

      PCIe_TL_MEM: begin
        // Explicit byte enables require OHC-A1
        if ((first_dw_be != 4'hF) ||
            ((get_payload_dw() > 1) && (last_dw_be != 4'hF))) begin
          ohc_a_type = OHC_A1;
        end
        else begin
          ohc_a_type = OHC_A_NONE;
        end
      end

      PCIe_TL_IO  : ohc_a_type = OHC_A2;
      PCIe_TL_CFG : ohc_a_type = OHC_A3;
      PCIe_TL_MSG : ohc_a_type = OHC_A4;
      PCIe_TL_CPL : ohc_a_type = OHC_A5;
      default     : ohc_a_type = OHC_A_NONE;

    endcase
  endfunction

  //==========================================================================
  // Generate OHC[4:0] bitmap
  //==========================================================================
  function void determine_ohc();
   `uvm_info("PCIe_SEQUENCE_ITEM", $sformatf("ENTERED_INTO_DETERMINE_OHC_FOR_%s",pkt_mode.name()), UVM_LOW)
    ohc = 5'b00000;

    determine_ohc_a();
    case (ohc_a_type)
      OHC_A1, OHC_A2, OHC_A3, OHC_A4, OHC_A5 : ohc[0] = 1'b1;
      default                                : ohc[0] = 1'b0;
    endcase
  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: convert2string - concise one-line summary
  //--------------------------------------------------------------------------
  function string convert2string();
    return $sformatf(
      "TLP %s/%s fmttype=%s addr=0x%016h len=%0d tag=0x%0h reqid=0x%04h data_dw=%0d",
      txn_type.name(),
      (txn_type == PCIe_TL_MSG) ? (msg_has_data ? "MSGD" : "MSG") : dir.name(),
      get_fmttype().name(), address, length, tag, requester_id, data.size());
  endfunction

endclass

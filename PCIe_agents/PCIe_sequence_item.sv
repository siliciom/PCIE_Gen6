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
  // RECOVERY / SEQUENTIAL RATE NEGOTIATION CONTROLS
  //   Non-rand and defaulted so that every existing sequence keeps its
  //   current behaviour without needing new randomize() constraints.
  //
  //   target_gen       : highest PCIe generation this item must reach (1..6).
  //                      1 => plain link-up, no Recovery at all.
  //   directed_recovery: 1 => start at `PCIe_RATE_GEN1 and walk
  //                      Gen1 -> Gen2 -> ... -> target_gen, entering Recovery
  //                      between every pair of generations. Traffic and the
  //                      externally visible link_up stay off until the final
  //                      (target_gen) L0.
  //--------------------------------------------------------------------------
  int unsigned  target_gen        = 1;
  bit           directed_recovery = 1'b0;

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

  //--------------------------------------------------------------------------
  // [FLIT_SEG] FLIT-mode TLP segmentation
  //   A request (or completion) whose Header + OHC + Payload (+ ECRC) does not
  //   fit in the 236 byte (59 DW) FLIT TLP region is split into several
  //   smaller TLPs, each one complete (own header) and each one sent in its
  //   own FLIT. Unused bytes of the last FLIT are NOP TLPs (all zero).
  //
  //   flit_seg_keep_ohc : the parent request needed OHC-A1, so every segment
  //                       carries OHC-A1 too (uniform per-TLP payload size:
  //                       3DW+OHC = 55 DW, 4DW+OHC = 54 DW per TLP).
  //   is_flit_segment   : this item is one segment of a bigger transaction
  //   flit_seg_idx      : 0 .. flit_seg_total-1
  //   flit_seg_parent_* : what the original (unsplit) transaction looked like
  //--------------------------------------------------------------------------
  bit                          flit_seg_keep_ohc;
  bit                          is_flit_segment;
  int unsigned                 flit_seg_idx;
  int unsigned                 flit_seg_total;
  int unsigned                 flit_seg_parent_len_dw;
  bit [`PCIe_TL_TAG_W-1:0]     flit_seg_parent_tag;

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
  bit                                                    is_valid;       // [ADDED] RC->EP flit status from EP monitor: 0 = FEC&CRC match, 1 = no match
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
  rand bit                          tx_valid; 
  rand bit                          tx_elec_idle; 
  rand bit                          electrical_idle_test; 
  rand bit                          no_receiver_test; 
  bit                          tx_detect_rx; 
  bit [`PCIe_POWERDOWN_W-1:0]  powerdown; 
  rand bit [`PCIe_RATE_W-1:0]       rate; 
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
  // Which of the three flit types this item represents (Table 4-16)
  //--------------------------------------------------------------------------
  PCIe_flit_type_e flit_type = PCIe_PAYLOAD_flit;

  //--------------------------------------------------------------------------
  // ECRC  (Section 2.7.1)
  //   ecrc_present : TD==1 in NFM, or TS==001b in FM
  //   ecrc         : the 32-bit value carried in the TLP Digest / Trailer
  //   ecrc_rx      : the value the receiver recalculated over the same bytes
  //   ecrc_state   : ABSENT / PASS / FAIL after the receive-side check
  //--------------------------------------------------------------------------
  bit                        ecrc_present;
  bit [`PCIe_TL_ECRC_W-1:0]  ecrc;
  bit [`PCIe_TL_ECRC_W-1:0]  ecrc_rx;
  pcie_ecrc_state_e          ecrc_state = PCIe_ECRC_ABSENT;

  //--------------------------------------------------------------------------
  // Completion fields (Figure 2-73 NFM / Figure 2-76 FM)
  //--------------------------------------------------------------------------
  bit                                    is_completion;
  bit [`PCIe_TL_CPL_BYTE_COUNT_W-1:0]    byte_count;
  bit [`PCIe_TL_CPL_LOWER_ADDR_W-1:0]    lower_address;
  bit                                    bcm;          // NFM only, always 0 here
  bit [`PCIe_TL_CPL_ID_W-1:0]            dest_bdf;     // FM : Destination BDF / BF
  bit                                    cpl_has_data; // CplD vs Cpl

  //--------------------------------------------------------------------------
  // FUNCTION: calc_byte_count - Table 2-40
  //   Remaining Byte Count for the Request, derived from Length and the byte
  //   enables. Returns 12 bits; 000h encodes 4096 bytes.
  //--------------------------------------------------------------------------
  function bit [`PCIe_TL_CPL_BYTE_COUNT_W-1:0] calc_byte_count();
    int unsigned len_dw;
    int          bc;

    len_dw = get_payload_dw();

    // Length == 1 DW : Last DW BE must be 0000b, count comes from First DW BE
    if ((last_dw_be == 4'h0)) begin
      casez (first_dw_be)
        4'b1??1 : bc = 4;
        4'b01?1 : bc = 3;
        4'b1?10 : bc = 3;
        4'b0011 : bc = 2;
        4'b0110 : bc = 2;
        4'b1100 : bc = 2;
        4'b0001 : bc = 1;
        4'b0010 : bc = 1;
        4'b0100 : bc = 1;
        4'b1000 : bc = 1;
        4'b0000 : bc = 1;
        default : bc = 4;
      endcase
      return bc[`PCIe_TL_CPL_BYTE_COUNT_W-1:0];
    end

    // Length > 1 DW : (Length * 4) minus the disabled leading/trailing bytes
    bc = len_dw * 4;

    casez (first_dw_be)
      4'b???1 : bc = bc - 0;
      4'b??10 : bc = bc - 1;
      4'b?100 : bc = bc - 2;
      4'b1000 : bc = bc - 3;
      default : bc = bc - 0;
    endcase

    casez (last_dw_be)
      4'b1??? : bc = bc - 0;
      4'b01?? : bc = bc - 1;
      4'b001? : bc = bc - 2;
      4'b0001 : bc = bc - 3;
      default : bc = bc - 0;
    endcase

    if (bc < 1)
      bc = 1;

    return bc[`PCIe_TL_CPL_BYTE_COUNT_W-1:0];
  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: calc_lower_address - Table 2-41
  //   Lower Address[6:0] = address[6:2] concatenated with the 2 byte-level
  //   bits implied by First DW BE.
  //--------------------------------------------------------------------------
  function bit [`PCIe_TL_CPL_LOWER_ADDR_W-1:0] calc_lower_address();
    bit [1:0] la_lo;

    casez (first_dw_be)
      4'b0000 : la_lo = 2'b00;
      4'b???1 : la_lo = 2'b00;
      4'b??10 : la_lo = 2'b01;
      4'b?100 : la_lo = 2'b10;
      4'b1000 : la_lo = 2'b11;
      default : la_lo = 2'b00;
    endcase

    return {address[6:2], la_lo};
  endfunction

  //--------------------------------------------------------------------------
  // RC -> EP 256B flit FEC/CRC check result (computed in EP controller monitor)
  // FEC/CRC addition : carries the received and calculated FEC/CRC bytes for
  // the RC->EP direction so the scoreboard can compare and report PASS/FAIL.
  //--------------------------------------------------------------------------
  bit              rc_to_ep_flit_fec_crc_check_done;            // 1 => FEC+CRC check finished for this flit
  bit              rc_to_ep_flit_fec_match;                     // calculated 6B FEC(on 250B) == received 6B FEC
  bit              rc_to_ep_flit_crc_match;                     // calculated 8B CRC(on 242B) == received 8B CRC
  bit [0:5][7:0]   rc_to_ep_flit_received_6b_fec;               // 6B FEC received in RC->EP flit
  bit [0:5][7:0]   rc_to_ep_flit_calculated_6b_fec_on_250b;     // 6B FEC calculated on 250B
  bit [63:0]       rc_to_ep_flit_received_8b_crc;               // 8B CRC received in RC->EP flit
  bit [63:0]       rc_to_ep_flit_calculated_8b_crc_on_242b;     // 8B CRC calculated on 242B

  //--------------------------------------------------------------------------
  // EP -> RC 256B flit FEC/CRC check result (computed in RC controller monitor)
  // FEC/CRC addition : carries the received and calculated FEC/CRC bytes for
  // the EP->RC direction so the scoreboard can compare and report PASS/FAIL.
  //--------------------------------------------------------------------------
  bit              ep_to_rc_flit_fec_crc_check_done;            // 1 => FEC+CRC check finished for this flit
  bit              ep_to_rc_flit_fec_match;                     // calculated 6B FEC(on 250B) == received 6B FEC
  bit              ep_to_rc_flit_crc_match;                     // calculated 8B CRC(on 242B) == received 8B CRC
  bit [0:5][7:0]   ep_to_rc_flit_received_6b_fec;               // 6B FEC received in EP->RC flit
  bit [0:5][7:0]   ep_to_rc_flit_calculated_6b_fec_on_250b;     // 6B FEC calculated on 250B
  bit [63:0]       ep_to_rc_flit_received_8b_crc;               // 8B CRC received in EP->RC flit
  bit [63:0]       ep_to_rc_flit_calculated_8b_crc_on_242b;     // 8B CRC calculated on 242B

  //--------------------------------------------------------------------------
  // 256B FLIT carry fields : scoreboard compares RC-TX vs EP-RX (RC->EP dir)
  // . rc_ep_tx_256b_flit : full 256B flit that the RC controller monitor
  //   reconstructed after full reverse process (de-precode / gray-decode /
  //   descramble) of the RC tx_data stream, sent to the scoreboard via write().
  // . rc_ep_rx_256b_flit : full 256B flit that the EP controller monitor
  //   reconstructed after full reverse process of the EP rx_data stream
  //   (the same RC->EP bytes), sent to the scoreboard via write().
  // The scoreboard compares all 256 bytes and reports INFO on match / ERROR
  // on mismatch, so the team can see the transmitted bytes on RC tx.data
  // equal the received bytes on EP rx.data.
  //--------------------------------------------------------------------------
  bit [`PCIe_BYTE_W-1:0] rc_ep_tx_256b_flit[$];
  bit [`PCIe_BYTE_W-1:0] rc_ep_rx_256b_flit[$];

  //--------------------------------------------------------------------------
  // Field automation
  //--------------------------------------------------------------------------
  `uvm_object_utils_begin(PCIe_sequence_item)
    `uvm_field_enum (pkt_mode_e,         pkt_mode,     UVM_ALL_ON)
    `uvm_field_int  (target_gen,         UVM_ALL_ON)
    `uvm_field_int  (directed_recovery,  UVM_ALL_ON)
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
    `uvm_field_int  (is_completion,  UVM_ALL_ON)
    `uvm_field_int  (byte_count,     UVM_ALL_ON | UVM_HEX)
    `uvm_field_int  (lower_address,  UVM_ALL_ON | UVM_HEX)
    `uvm_field_int  (ecrc_present,   UVM_ALL_ON)
    `uvm_field_int  (ecrc,           UVM_ALL_ON | UVM_HEX)
    `uvm_field_enum (pcie_ecrc_state_e, ecrc_state, UVM_ALL_ON)
    `uvm_field_enum (PCIe_flit_type_e,  flit_type,  UVM_ALL_ON)
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
       //data.size() == get_payload_dw();
              data.size() == ((length == 10'd0) ? 1024 : length);
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

  // Message without data : Length is Reserved and must be 0
 
  // Message Length rules
  constraint c_msg_length {
    if (txn_type == PCIe_TL_MSG) {
      if (!msg_has_data) length == 10'd0;          // Msg  : Length reserved, must be 0
      else               length inside {[1:32]};   // MsgD : must fit in one flit
    }
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

 constraint c_mem_tc { if(txn_type == PCIe_TL_MEM) {
	 tc == 3'b000;
	 }
	 }
constraint c_flit_td { (pkt_mode == FLIT) -> (td == (ts == `PCIe_TL_TS_1DW_ECRC)); }
	 

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
    // [FLIT_SEG] length == 0 encodes 1024 DW, so "more than 1 DW" is
    // (length != 1) - the old (length > 1) treated 1024 DW as 1 DW.
    ((pkt_mode == FLIT) &&
     (txn_type == PCIe_TL_MEM) &&
     (
       (first_dw_be != 4'hF) ||
       (
         (length != 10'd1) &&
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
       (length == 10'd1) ||
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

  constraint c_cfg_fields {
    if (txn_type != PCIe_TL_CFG) {
      cfg_reg_num     == '0;
      cfg_ext_reg_num == '0;
      cfg_bus_num     == '0;
      cfg_dev_num     == '0;
      cfg_fn_num      == '0;
      cfg_type1       == 1'b0;
    }
  }
  
  constraint c_io_fields {
    if (txn_type != PCIe_TL_IO) {
      io_data == '0;
    }
  }
  
  constraint c_msg_fields {
    if (txn_type != PCIe_TL_MSG) {
      msg_code      == '0;
      msg_route     == PCIe_MSG_ROUTE_TO_RC;
      msg_has_data  == 1'b0;
    }
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
      PCIe_TL_MSG:
        return msg_has_data ? PCIe_FLITTYPE_MSGD : PCIe_FLITTYPE_MSG;   // 70h : 30h

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
  // [FLIT_SEG] FLIT segmentation helpers (shared by the RC and EP TL models)
  //
  //   max payload per TLP = 59 DW region - Header Base - OHC - ECRC trailer
  //
  //     3DW        : 59 - 3         = 56 DW (224 B)  -> 1024 DW = 19 TLPs
  //     4DW        : 59 - 4         = 55 DW (220 B)  -> 1024 DW = 19 TLPs
  //     3DW + OHC  : 59 - 3 - 1     = 55 DW (220 B)  -> 1024 DW = 19 TLPs
  //     4DW + OHC  : 59 - 4 - 1     = 54 DW (216 B)  -> 1024 DW = 19 TLPs
  //==========================================================================
  static function int unsigned flit_seg_max_payload_dw(int unsigned hdr_base_dw,
                                                       int unsigned ohc_dw,
                                                       int unsigned trailer_dw);
    int unsigned used;
    used = hdr_base_dw + ohc_dw + trailer_dw;
    if (used >= `PCIe_FLIT_TLP_REGION_DW) return 0;
    return `PCIe_FLIT_TLP_REGION_DW - used;
  endfunction

  // ceil(total_dw / max_dw)
  static function int unsigned flit_seg_count(int unsigned total_dw, int unsigned max_dw);
    if (max_dw == 0) return 0;
    return (total_dw + max_dw - 1) / max_dw;
  endfunction

  //==========================================================================
  // Determine OHC-A subtype
  //==========================================================================
  function void determine_ohc_a();

    ohc_a_type = OHC_A_NONE;

    case (txn_type)

      PCIe_TL_MEM: begin
        // Explicit byte enables require OHC-A1
        // [FLIT_SEG] a segment of a request that needed OHC-A1 keeps it
        if ((first_dw_be != 4'hF) ||
            ((get_payload_dw() > 1) && (last_dw_be != 4'hF)) ||
            flit_seg_keep_ohc) begin
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


  //==========================================================================
  // FLOW CONTROL (PCIe Base 6.0 Sec 2.6 / 3.4)  -  VC0, dedicated credits
  //   The same sequence item is used for the TL <-> DL credit exchange.
  //   hdr / dat index : 0 = P (PH, PD), 1 = NP (NPH, NPD), 2 = CPL (CPLH, CPLD)
  //   Credit units    : header = 1 per TLP, data = 4 DW (16 B), n = ceil(DW/4)
  //   All the static helpers below are shared by the TL and DL models.
  //==========================================================================
  pcie_fc_kind_e fc_kind;
  string         fc_origin;              // "RC_TL", "EP_DL", ...
  string         fc_reason;              // MANDATORY / WATERMARK / PERIODIC ...
  bit [2:0]      fc_cls_mask = 3'b000;   // classes this transaction applies to
  int unsigned   fc_hdr [3];             // PH   NPH   CPLH
  int unsigned   fc_dat [3];             // PD   NPD   CPLD
  bit            fc_hdr_inf [3];
  bit            fc_dat_inf [3];

  // [FC SHARED] Flit Mode shared credit pool (same layout as the dedicated one)
  bit [2:0]      fc_cls_mask_shr = 3'b000;   // classes the shared values apply to
  int unsigned   fc_hdr_shr [3];             // shared PH   NPH   CPLH
  int unsigned   fc_dat_shr [3];             // shared PD   NPD   CPLD
  bit            fc_hdr_inf_shr [3];
  bit            fc_dat_inf_shr [3];

  function void set_fc_cls(int unsigned c, int unsigned h, int unsigned d);
    fc_hdr[c] = h;
    fc_dat[c] = d;
    fc_cls_mask[c] = 1'b1;
  endfunction

  // [FC SHARED] shared credit values of class c
  function void set_fc_cls_shr(int unsigned c, int unsigned h, int unsigned d);
    fc_hdr_shr[c] = h;
    fc_dat_shr[c] = d;
    fc_cls_mask_shr[c] = 1'b1;
  endfunction

  // Same print format on the TL and the DL side so the values can be compared by eye
  function string fc_values_str();
    return $sformatf("DED: PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d  SHR: PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d",
                     fc_hdr[0], fc_dat[0], fc_hdr[1], fc_dat[1], fc_hdr[2], fc_dat[2],
                     fc_hdr_shr[0], fc_dat_shr[0], fc_hdr_shr[1], fc_dat_shr[1], fc_hdr_shr[2], fc_dat_shr[2]);
  endfunction

  function string fc_convert2string();
    return $sformatf("%s from %s mask=%03b mask_shr=%03b reason=%s :: %s",
                     fc_kind.name(), fc_origin, fc_cls_mask, fc_cls_mask_shr, fc_reason, fc_values_str());
  endfunction

  // (a - b) mod 2^bits
  static function int unsigned fc_mod_sub(int unsigned a, int unsigned b, int unsigned bits);
    int unsigned d;
    d = a - b;
    return d & ((32'd1 << bits) - 32'd1);
  endfunction

  // (a + b) mod 2^bits
  static function int unsigned fc_mod_add(int unsigned a, int unsigned b, int unsigned bits);
    int unsigned s;
    s = a + b;
    return s & ((32'd1 << bits) - 32'd1);
  endfunction

  // Data credits needed for a payload of 'dw' double words : ceil(dw / 4)
  static function int unsigned fc_data_units(int unsigned dw);
    return (dw + 3) / 4;
  endfunction

  static function string fc_cls_name(int unsigned c);
    case (c)
      PCIE_FC_P   : return "P";
      PCIE_FC_NP  : return "NP";
      PCIE_FC_CPL : return "CPL";
      default     : return "?";
    endcase
  endfunction

  static function string fc_hdr_name(int unsigned c);
    case (c)
      PCIE_FC_P   : return "PH";
      PCIE_FC_NP  : return "NPH";
      PCIE_FC_CPL : return "CPLH";
      default     : return "?H";
    endcase
  endfunction

  static function string fc_dat_name(int unsigned c);
    case (c)
      PCIE_FC_P   : return "PD";
      PCIE_FC_NP  : return "NPD";
      PCIE_FC_CPL : return "CPLD";
      default     : return "?D";
    endcase
  endfunction

  // Value that goes on the wire for a buffer of 'max' credits.
  // Spec 2.6.1: maximum outstanding credits is 2^(FS-1)-1 (127 hdr / 2047 data).
  static function int unsigned fc_wire_credits(int unsigned max, bit clamp);
    if (clamp && max > 0) return max - 1;
    return max;
  endfunction

  // TLP -> (credit class, header credits, data credits)
  //   P  : memory write, message        NP : memory read, DMWr, IO, CFG     CPL : completion
  static function void fc_classify(pcie_tl_txn_type_e t, pcie_tl_dir_e d, bit deferrable,
                                   int payload_dw,
                                   output int unsigned c, output int unsigned h,
                                   output int unsigned dd);
    h  = 1;
    dd = fc_data_units((payload_dw < 0) ? 0 : payload_dw);
    case (t)
      PCIe_TL_MEM : c = (d == PCIe_TL_WRITE && !deferrable) ? PCIE_FC_P : PCIE_FC_NP;
      PCIe_TL_IO  : c = PCIE_FC_NP;
      PCIe_TL_CFG : c = PCIE_FC_NP;
      PCIe_TL_MSG : c = PCIE_FC_P;
      PCIe_TL_CPL : c = PCIE_FC_CPL;
      default     : c = PCIE_FC_P;
    endcase
  endfunction

  // 32-bit FC DLLP (carried in DLP2..DLP5 of a Flit)
  //   [31:30] type  01 InitFC1 / 11 InitFC2 / 10 UpdateFC
  //   [29:28] class 00 P / 01 NP / 10 Cpl     [27] 1 = dedicated, 0 = shared (spec Fig 3-9)   [26:24] VC
  //   [23:22] HdrScale  [21:16]+[15:14] HdrFC (8 bit)
  //   [13:12] DataScale [11:0] DataFC (12 bit)
  //   Scale 00b + credit 0 => infinite ; scale 01b => finite (x1)
  static function bit [31:0] fc_encode(bit [1:0] typ, bit [1:0] cls, bit shared, bit [2:0] vc,
                                       bit [1:0] hscale, bit [7:0] hfc,
                                       bit [1:0] dscale, bit [11:0] dfc);
    bit [31:0] v;
    v[31:30] = typ;
    v[29:28] = cls;
    v[27]    = ~shared;   // spec Fig 3-9 : bit3 = 1 dedicated, 0 shared
    v[26:24] = vc;
    v[23:22] = hscale;
    v[21:16] = hfc[7:2];
    v[15:14] = hfc[1:0];
    v[13:12] = dscale;
    v[11:0]  = dfc;
    return v;
  endfunction

  // 1 when the 32-bit DLLP payload is an InitFC1 / InitFC2 / UpdateFC DLLP
  // (type 00 = NOP2 / Feature DLLP is not an FC DLLP)
  static function bit fc_is_dllp(bit [31:0] v);
    return (v[31:30] != 2'b00) && (v[29:28] != 2'b11);
  endfunction

  static function void fc_decode(bit [31:0] v,
                                 output bit [1:0] typ, output bit [1:0] cls, output bit shared,
                                 output bit [2:0] vc, output bit [1:0] hscale, output bit [7:0] hfc,
                                 output bit [1:0] dscale, output bit [11:0] dfc);
    typ    = v[31:30];
    cls    = v[29:28];
    shared = ~v[27];     // spec Fig 3-9 : bit3 = 1 dedicated, 0 shared
    vc     = v[26:24];
    hscale = v[23:22];
    hfc    = {v[21:16], v[15:14]};
    dscale = v[13:12];
    dfc    = v[11:0];
  endfunction

  static function string fc_type_name(bit [1:0] typ);
    case (typ)
      `PCIe_FC_TYPE_INITFC1 : return "InitFC1";
      `PCIe_FC_TYPE_INITFC2 : return "InitFC2";
      `PCIe_FC_TYPE_UPDATEFC: return "UpdateFC";
      default               : return "NOT_FC";
    endcase
  endfunction

  static function string fc_dllp_str(bit [31:0] v);
    bit [1:0] typ, cls, hs, ds;
    bit shared;
    bit [2:0] vc;
    bit [7:0] hfc;
    bit [11:0] dfc;
    fc_decode(v, typ, cls, shared, vc, hs, hfc, ds, dfc);
    return $sformatf("DLLP=%08h  %s-%s %s VC%0d HdrScale=%0b HdrFC=%0d%s DataScale=%0b DataFC=%0d%s",
                     v, fc_type_name(typ), fc_cls_name(cls), shared ? "SHARED" : "DEDICATED", vc,
                     hs, hfc, (hs == 2'b00 && hfc == 0) ? "(INF)" : "",
                     ds, dfc, (ds == 2'b00 && dfc == 0) ? "(INF)" : "");
  endfunction

endclass



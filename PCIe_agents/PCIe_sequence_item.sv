//=========================================================================================
// File         : PCIe_sequence_item.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_sequence_item.sv
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

class PCIe_sequence_item extends uvm_sequence_item;
    
	`uvm_object_utils(PCIe_sequence_item)
  
// fileds responsibel for DLP creation in FLIT mode
    bit [`PCIe_DLLP_CONTENT_W-1:0]            dllp_content;   // 4-byte DLLP (e.g. UpdateFC or NOP)
    bit [`PCIe_SEQ_NUM_W-1:0]             TX_ACKNACK_FLIT_SEQ_NUM;
    bit [`PCIe_SEQ_NUM_W-1:0]             NEXT_TX_FLIT_SEQ_NUM;
    bit                   NAK_SCHEDULED;
    bit                   NAK_SCHEDULED_TYPE;
    bit                   STANDARD_NAK;
    bit                   TX_ACKNAK_FLIT_SEQ_NUM;
    bit                   last_flit_was_payload;
    bit                   credit;
    bit                   is_payload;
    rand bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_data;       // Incoming 236 bytes from TL
    bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0]      dlp_flit_out;    // 242-byte output (TLPs + DLP)
    bit[0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0]       replayed_flit;    // to store the replayed flit
    bit[`PCIe_SEQ_NUM_W-1:0]              seq_num;        // to store replayed sequence number

    bit replay_flit;    // only for debug
    bit drive_flit;     // only for debug

    // Necessary to store the data collected from ep and send to scoreboard
    bit[0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0]dlp;

  // RC / EP PHY monitor signals
  bit [`PCIe_MON_DATA_W-1:0]   data_q_ep_mon_rx[$];
  bit [`PCIe_MON_DATA_W-1:0]   data_q_ep_mon_tx[$];
  bit [`PCIe_MON_DATA_W-1:0]   data_q_rc_mon_tx[$];
  bit [`PCIe_MON_DATA_W-1:0]   data_q_rc_mon_rx[$];
  
  //RC_controller_monitor_signals 
   bit        tx_valid; 
   bit        tx_elec_idle; 
   bit        tx_detect_rx; 
   bit        powerdown; 
   bit        rate; 
   bit [`PCIe_MON_DATA_W-1:0] data_q_rc_mon_con_tx[$];
   bit [`PCIe_MON_DATA_W-1:0] data_q_rc_mon_con_rx[$];

  //EP_controller_monitor_signals 
   bit        rx_valid; 
   bit        rx_elec_idle; 
   bit        rx_status; 
   bit        phy_status; 
   bit [`PCIe_MON_DATA_W-1:0] data_q_ep_mon_con_tx[$];
   bit [`PCIe_MON_DATA_W-1:0] data_q_ep_mon_con_rx[$];

    
   function new(string name="PCIE_sequence_item");
     super.new(name);
   endfunction

  function void print_dlp_details(
    string label, 
    bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp
  );
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
   

        
endclass





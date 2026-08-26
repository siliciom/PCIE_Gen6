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
   bit [31:0]            dllp_content;   // 4-byte DLLP (e.g. UpdateFC or NOP)
   bit [9:0]             TX_ACKNACK_FLIT_SEQ_NUM;
   bit [9:0]             NEXT_TX_FLIT_SEQ_NUM;
   bit                   NAK_SCHEDULED;
   bit                   NAK_SCHEDULED_TYPE;
   bit                   STANDARD_NAK;
   bit                   TX_ACKNAK_FLIT_SEQ_NUM;
   bit                   last_flit_was_payload;
   bit                   credit;
   bit                   is_payload;
   rand bit [0:235][7:0] tlp_data;       // Incoming 236 bytes from TL
   bit [0:241][7:0]      dlp_flit_out;    // 242-byte output (TLPs + DLP)
   bit[0:235][7:0]       replayed_flit;    // to store the replayed flit
   bit[9:0]              seq_num;        // to store replayed sequence number

   bit replay_flit;    // only for debug
   bit drive_flit;     // only for debug

   // Necessary to store the data collected from ep and send to scoreboard
   bit[0:5][7:0]dlp;

  //RC_and_Ep_phy_monitor_signals 
   bit [31:0] data_q_ep_mon_rx[$];
   bit [31:0] data_q_ep_mon_tx[$];
   bit [31:0] data_q_rc_mon_tx[$];
   bit [31:0] data_q_rc_mon_rx[$];
  
  //RC_controller_monitor_signals 
   bit        tx_valid; 
   bit        tx_elec_idle; 
   bit        tx_detect_rx; 
   bit        powerdown; 
   bit        rate; 
   bit [31:0] data_q_rc_mon_con_tx[$];
   bit [31:0] data_q_rc_mon_con_rx[$];

  //EP_controller_monitor_signals 
   bit        rx_valid; 
   bit        rx_elec_idle; 
   bit        rx_status; 
   bit        phy_status; 
   bit [31:0] data_q_ep_mon_con_tx[$];
   bit [31:0] data_q_ep_mon_con_rx[$];
    
   function new(string name="PCIE_sequence_item");
     super.new(name);
   endfunction

        
endclass





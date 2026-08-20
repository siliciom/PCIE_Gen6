//=========================================================================================
// File         : PCIe_sequence_item.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_sequence_item.sv
// Author       : 
// Date         : 2026-08-17
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

   function new(string name="PCIe_sequence_item");
     super.new(name);
   endfunction
        
endclass





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
  
  // DLP creation fields
  bit [`PCIe_DLLP_CONTENT_W-1:0]       dllp_content;
  bit [`PCIe_SEQ_NUM_W-1:0]            TX_ACKNACK_FLIT_SEQ_NUM;
  bit [`PCIe_SEQ_NUM_W-1:0]            NEXT_TX_FLIT_SEQ_NUM;
  bit [`PCIe_NAK_SCHEDULED_W-1:0]      NAK_SCHEDULED;
  bit [`PCIe_NAK_SCHEDULED_TYPE_W-1:0] NAK_SCHEDULED_TYPE;
  bit [`PCIe_STANDARD_NAK_W-1:0]       STANDARD_NAK;
  bit [`PCIe_SEQ_NUM_W-1:0]            TX_ACKNAK_FLIT_SEQ_NUM;
  bit [`PCIe_LAST_FLIT_PAYLOAD_W-1:0]  last_flit_was_payload;
  bit [`PCIe_CREDIT_W-1:0]             credit;
  bit [`PCIe_IS_PAYLOAD_W-1:0]         is_payload;
 
  // FLIT data
  rand bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0]  tlp_data;
  bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0]       dlp_flit_out;
  bit [0:`PCIe_REPLAYED_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0]  replayed_flit;
  bit [`PCIe_SEQ_NUM_W-1:0]                               seq_num;
 
  // Debug fields
  bit  replay_flit;
  bit  drive_flit;
 
  // DLP collected from monitor
  bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp;
 
  // RC / EP PHY monitor signals
  bit [`PCIe_MON_DATA_W-1:0]   data_q_ep_mon_rx[$];
  bit [`PCIe_MON_DATA_W-1:0]   data_q_ep_mon_tx[$];
  bit [`PCIe_MON_DATA_W-1:0]   data_q_rc_mon_tx[$];
  bit [`PCIe_MON_DATA_W-1:0]   data_q_rc_mon_rx[$];
 
  // RC controller monitor signals
  bit [`PCIe_TX_VALID_W-1:0]      tx_valid;
  bit [`PCIe_TX_ELEC_IDLE_W-1:0]  tx_elec_idle;
  bit [`PCIe_TX_DETECT_RX_W-1:0]  tx_detect_rx;
  bit [`PCIe_POWERDOWN_W-1:0]     powerdown;
  bit [`PCIe_RATE_W-1:0]          rate;
  bit [`PCIe_MON_DATA_W-1:0]      data_q_rc_mon_con_tx[$];
  bit [`PCIe_MON_DATA_W-1:0]      data_q_rc_mon_con_rx[$];
 
  // EP controller monitor signals
  bit [`PCIe_RX_VALID_W-1:0]      rx_valid;
  bit [`PCIe_RX_ELEC_IDLE_W-1:0]  rx_elec_idle;
  bit [`PCIe_RX_STATUS_W-1:0]     rx_status;
  bit [`PCIe_PHY_STATUS_W-1:0]    phy_status;
  bit [`PCIe_MON_DATA_W-1:0]      data_q_ep_mon_con_tx[$];
  bit [`PCIe_MON_DATA_W-1:0]      data_q_ep_mon_con_rx[$];
       
   function new(string name="PCIE_sequence_item");
     super.new(name);
   endfunction

        
endclass





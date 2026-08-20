//=========================================================================================
// File         : PCIe_RC_phy_monitor.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_RC_phy_agent\PCIe_RC_phy_monitor.sv
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

class PCIe_RC_phy_monitor extends uvm_monitor;
  
   `uvm_component_utils(PCIe_RC_phy_monitor)
  
    PCIe_sequence_item               pcie_seq_item;
    virtual PCIe_RC_PHY_interface    rc_phy_intf_tx, rc_phy_intf_rx;	

    uvm_analysis_port #(PCIe_sequence_item) rc_phy_tx_mon_ap;	
    uvm_analysis_port #(PCIe_sequence_item) rc_phy_rx_mon_ap;	

    event rc_to_ep_bit_event;
    event ep_to_rc_bit_event;
 
    function new(string name="PCIe_RC_phy_monitor", uvm_component parent);
       super.new(name,parent);
    endfunction

    function void build_phase(uvm_phase phase);
      `uvm_info("RC_PHY","ENTERED_INTO_RC_PHY_MONITOR_BUILD_PHASE",UVM_LOW)
       super.build_phase(phase);
         rc_phy_tx_mon_ap =new("rc_phy_tx_mon_ap",this);
         rc_phy_rx_mon_ap =new("rc_phy_rx_mon_ap",this);
         pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
       
       if (!uvm_config_db#(virtual PCIe_RC_PHY_interface)::get(this, "", "PCIe_RC_PHY_INTERFACE", rc_phy_intf_tx))
        `uvm_fatal("NO_VIF", "RC_PHY_INTERFACE_not_found")

       if (!uvm_config_db#(virtual PCIe_RC_PHY_interface)::get(this, "", "PCIe_RC_PHY_INTERFACE", rc_phy_intf_rx))
        `uvm_fatal("NO_VIF", "RC_PHY_INTERFACE_not_found")
       
       if (!uvm_config_db#(event)::get(this,"","RC_TO_EP_BIT_EVENT",rc_to_ep_bit_event))
         `uvm_fatal("NO_EVENT","RC_TO_EP_BIT_EVENT_not_found")
       
       if (!uvm_config_db#(event)::get(this,"","EP_TO_RC_BIT_EVENT",ep_to_rc_bit_event))
         `uvm_fatal("NO_EVENT","EP_TO_RC_BIT_EVENT_not_found")
   
      `uvm_info("RC_PHY","EXIT_FROM_RC_PHY_MONITOR_BUILD_PHASE",UVM_LOW)
    endfunction

    task run_phase(uvm_phase phase);
       `uvm_info("RC_PHY","ENTERED_INTO_RC_PHY_MONITOR_RUN_PHASE",UVM_LOW)
       fork
        forever begin
         tx_sipo(rc_phy_intf_tx);
        end
        forever begin
         rx_sipo(rc_phy_intf_rx);
        end
       join
       `uvm_info("RC_PHY","EXIT_FROM_RC_PHY_MONITOR_RUN_PHASE",UVM_LOW)
    endtask

    task tx_sipo(virtual PCIe_RC_PHY_interface rc_phy_intf_tx);
      bit [31:0] tx_data;
      bit        tx_bit;
     
      `uvm_info("RC_PHY_MONITOR","ENTERED_INTO_TX_SIPO_RC_MONITOR", UVM_LOW)
          for(int i = 0; i < 32; i++)
          begin
              @rc_to_ep_bit_event;		  
              #15.625ps;
              tx_bit = rc_phy_intf_tx.tx_plus;
              tx_data[i] = tx_bit;
              `uvm_info("RC_PHY_MONITOR",$sformatf("TX_BIT_IN_RC_MONITOR[%0d] = %0b TIME=%0.5f",i, tx_bit,$realtime), UVM_LOW);
          end
           pcie_seq_item.data_q_rc_mon_tx.push_back(tx_data);
          `uvm_info("RC_PHY_MONITOR",$sformatf("RC_TX_32_BIT_PARALLEL_MONITOR_DATA = %08h RC_MONITOR_QUEUE_SIZE=%d", tx_data,pcie_seq_item.data_q_rc_mon_tx.size()),UVM_LOW);
          `uvm_info("RC_PHY_MONITOR","EXIT_FROM_TX_SIPO_RC_MONITOR", UVM_LOW)
           rc_phy_tx_mon_ap.write(pcie_seq_item);
    endtask
 
    task rx_sipo(virtual PCIe_RC_PHY_interface rc_phy_intf_rx);
       bit [31:0] rx_data;
       bit        rx_bit;
      `uvm_info("RC_PHY_MONITOR","ENTERED_INTO_RX_SIPO_RC_MONITOR", UVM_LOW)
         for(int i = 0; i < 32; i++)
         begin
             @ep_to_rc_bit_event;		  
             #15.625ps;
             rx_bit = rc_phy_intf_rx.rx_plus;
             rx_data[i] = rx_bit;
             `uvm_info("EP_PHY_MONITOR",$sformatf("RX_BIT_IN_RC_MONITOR[%0d] = %0b TIME=%0.5f",i, rx_bit,$realtime), UVM_LOW);
         end
          pcie_seq_item.data_q_rc_mon_rx.push_back(rx_data);
         `uvm_info("RC_PHY_MONITOR",$sformatf("RX_32_BIT_PARALLEL_RC_MONITOR_DATA = %08h RC_MONITOR_QUEUE_SIZE=%d", rx_data,pcie_seq_item.data_q_rc_mon_rx.size()),UVM_LOW);
         `uvm_info("RC_PHY_MONITOR","EXIT_FROM_RX_SIPO_RC_MONITOR", UVM_LOW)
	      rc_phy_rx_mon_ap.write(pcie_seq_item);
    endtask



endclass






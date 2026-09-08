//=========================================================================================
// File         : PCIe_EP_phy_agent.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_EP_phy_agent\PCIe_EP_phy_agent.sv
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

class PCIe_EP_phy_agent extends uvm_agent;
  
      `uvm_component_utils(PCIe_EP_phy_agent)
  
       PCIe_EP_phy_driver        ep_phy_driver;
       PCIe_EP_phy_monitor       ep_phy_monitor;
       PCIe_EP_phy_sequencer     ep_phy_sequencer;
  
      function new(string name="PCIe_EP_phy_agent",uvm_component parent);
        super.new(name,parent);
      endfunction
  
      function void build_phase(uvm_phase phase);
         `uvm_info("EP_PHY","ENTERED_INTO_EP_PHY_AGENT_BUILD_PHASE",UVM_LOW)
   	  super.build_phase(phase);   
    	    ep_phy_driver    = PCIe_EP_phy_driver::type_id::create("ep_phy_driver",this);
    	    ep_phy_monitor   = PCIe_EP_phy_monitor::type_id::create("ep_phy_monitor",this);
    	    ep_phy_sequencer = PCIe_EP_phy_sequencer::type_id::create("ep_phy_sequencer",this); 
          `uvm_info("EP_PHY","EXIT_FROM_EP_PHY_AGENT_BUILD_PHASE",UVM_LOW)
      endfunction
  
      function void connect_phase(uvm_phase phase);
        `uvm_info("EP_PHY","ENTERED_INTO_EP_PHY_AGENT_CONNECT_PHASE",UVM_LOW)
          super.connect_phase(phase);
          ep_phy_driver.seq_item_port.connect(ep_phy_sequencer.seq_item_export);
        `uvm_info("EP_PHY","EXIT_FROM_EP_PHY_AGENT_CONNECT_PHASE",UVM_LOW)
      endfunction
  
endclass
           


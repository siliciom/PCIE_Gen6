//=========================================================================================
// File         : PCIe_RC_phy_agent.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_RC_phy_agent\PCIe_RC_phy_agent.sv
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

class PCIe_RC_phy_agent extends uvm_agent;
  
      `uvm_component_utils(PCIe_RC_phy_agent)
  
       PCIe_RC_phy_driver        rc_phy_driver;
       PCIe_RC_phy_monitor       rc_phy_monitor;
       PCIe_RC_phy_sequencer     rc_phy_sequencer;
  
      function new(string name="PCIe_RC_phy_agent",uvm_component parent);
        super.new(name,parent);
      endfunction
  
      function void build_phase(uvm_phase phase);
         `uvm_info("RC_PHY","ENTERED_INTO_RC_PHY_AGENT_BUILD_PHASE",UVM_LOW)
   	  super.build_phase(phase);   
    	    rc_phy_driver    = PCIe_RC_phy_driver::type_id::create("rc_phy_driver",this);
    	    rc_phy_monitor   = PCIe_RC_phy_monitor::type_id::create("rc_phy_monitor",this);
    	    rc_phy_sequencer = PCIe_RC_phy_sequencer::type_id::create("rc_phy_sequencer",this); 
          `uvm_info("RC_PHY","EXIT_FROM_RC_PHY_AGENT_BUILD_PHASE",UVM_LOW)
      endfunction
  
      function void connect_phase(uvm_phase phase);
        `uvm_info("RC_PHY","ENTERED_INTO_RC_PHY_AGENT_CONNECT_PHASE",UVM_LOW)
          super.connect_phase(phase);
          rc_phy_driver.seq_item_port.connect(rc_phy_sequencer.seq_item_export);
        `uvm_info("RC_PHY","EXIT_FROM_RC_PHY_AGENT_CONNECT_PHASE",UVM_LOW)
      endfunction
  
endclass
           


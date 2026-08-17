//=========================================================================================
// File         : PCIe_RC_controller_agent.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_RC_controller_agent\PCIe_RC_controller_agent.sv
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

class PCIe_RC_controller_agent extends uvm_agent;
  
      `uvm_component_utils(PCIe_RC_controller_agent)
  
       PCIe_RC_controller_driver        rc_controller_driver;
       PCIe_RC_controller_monitor       rc_controller_monitor;
       PCIe_RC_controller_sequencer     rc_controller_sequencer;
  
      function new(string name="PCIe_RC_controller_agent",uvm_component parent);
        super.new(name,parent);
      endfunction
  
      function void build_phase(uvm_phase phase);
         `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_AGENT_BUILD_PHASE",UVM_LOW)
   	  super.build_phase(phase);   
    	    rc_controller_driver    = PCIe_RC_controller_driver::type_id::create("rc_controller_driver",this);
    	    rc_controller_monitor   = PCIe_RC_controller_monitor::type_id::create("rc_controller_monitor",this);
    	    rc_controller_sequencer = PCIe_RC_controller_sequencer::type_id::create("rc_controller_sequencer",this); 
          `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_AGENT_BUILD_PHASE",UVM_LOW)
      endfunction
  
      function void connect_phase(uvm_phase phase);
        `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_AGENT_CONNECT_PHASE",UVM_LOW)
          super.connect_phase(phase);
          rc_controller_driver.seq_item_port.connect(rc_controller_sequencer.seq_item_export);
        `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_AGENT_CONNECT_PHASE",UVM_LOW)
      endfunction
  
endclass
           


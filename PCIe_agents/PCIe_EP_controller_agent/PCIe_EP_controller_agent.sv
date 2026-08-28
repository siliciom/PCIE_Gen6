//=========================================================================================
// File         : PCIe_EP_controller_agent.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_EP_controller_agent\PCIe_EP_controller_agent.sv
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

class PCIe_EP_controller_agent extends uvm_agent;
   
      `uvm_component_utils(PCIe_EP_controller_agent)
   
       PCIe_EP_controller_driver        ep_controller_driver;
       PCIe_EP_controller_monitor       ep_controller_monitor;
       PCIe_EP_controller_sequencer     ep_controller_sequencer;
       
       PCIe_EP_TL_model                 ep_tl_model;
       PCIe_EP_DL_model                 ep_dl_model;
       PCIe_EP_PL_model                 ep_pl_model;

       function new(string name="PCIe_EP_controller_agent",uvm_component parent);
         super.new(name,parent);
       endfunction

       function void build_phase(uvm_phase phase);
          `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_AGENT_BUILD_PHASE",UVM_LOW)
    	  super.build_phase(phase);   
     	    ep_controller_driver    = PCIe_EP_controller_driver::type_id::create("ep_controller_driver",this);
     	    ep_controller_monitor   = PCIe_EP_controller_monitor::type_id::create("ep_controller_monitor",this);
     	    ep_controller_sequencer = PCIe_EP_controller_sequencer::type_id::create("ep_controller_sequencer",this); 
            ep_tl_model = PCIe_EP_TL_model::type_id::create("ep_tl_model", this);
            ep_dl_model = PCIe_EP_DL_model::type_id::create("ep_dl_model", this);
            ep_pl_model = PCIe_EP_PL_model::type_id::create("ep_pl_model", this);
           `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_AGENT_BUILD_PHASE",UVM_LOW)
       endfunction
  
      function void connect_phase(uvm_phase phase);
        `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_AGENT_CONNECT_PHASE",UVM_LOW)
          super.connect_phase(phase);
          ep_controller_driver.seq_item_port.connect(ep_controller_sequencer.seq_item_export);
	 ep_controller_driver.tx_ap.connect(ep_tl_model.tl_imp);
         ep_tl_model.tl_ap.connect(ep_dl_model.dl_imp);
         ep_dl_model.dl_ap.connect(ep_pl_model.pl_imp);
        `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_AGENT_CONNECT_PHASE",UVM_LOW)
      endfunction
  
endclass
           


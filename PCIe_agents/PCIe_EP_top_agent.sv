//=========================================================================================
// File         : PCIe_EP_top_agent.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_EP_top_agent.sv
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

class PCIe_EP_top_agent extends uvm_component;
  
      `uvm_component_utils(PCIe_EP_top_agent)
  
       PCIe_EP_controller_agent       ep_controller_agent;
       PCIe_EP_phy_agent              ep_phy_agent;
  
      function new(string name="PCIe_EP_top_agent",uvm_component parent);
        super.new(name,parent);
      endfunction
  
      function void build_phase(uvm_phase phase);
         `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_TOP_AGENT_BUILD_PHASE",UVM_LOW)
   	  super.build_phase(phase);
    	    ep_controller_agent    = PCIe_EP_controller_agent::type_id::create("ep_controller_agent",this);
    	    ep_phy_agent    = PCIe_EP_phy_agent::type_id::create("ep_phy_agent",this);              
          `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_TOP_AGENT_BUILD_PHASE",UVM_LOW)
      endfunction
  
endclass
           


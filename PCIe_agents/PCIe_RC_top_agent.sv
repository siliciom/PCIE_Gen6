//=========================================================================================
// File         : PCIe_RC_top_agent.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_RC_top_agent.sv
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

class PCIe_RC_top_agent extends uvm_component;
  
  `uvm_component_utils(PCIe_RC_top_agent)
  
   PCIe_RC_controller_agent        rc_controller_agent;
   PCIe_RC_phy_agent               rc_phy_agent;
  
   function new(string name="PCIe_RC_top_agent",uvm_component parent);
     super.new(name,parent);
   endfunction
  
   function void build_phase(uvm_phase phase);
    `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_TOP_AGENT_BUILD_PHASE",UVM_LOW)
     super.build_phase(phase);   
        rc_controller_agent    = PCIe_RC_controller_agent::type_id::create("rc_controller_agent",this);
        rc_phy_agent    = PCIe_RC_phy_agent::type_id::create("rc_phy_agent",this);
    `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_TOP_AGENT_BUILD_PHASE",UVM_LOW)
   endfunction
  
endclass
           


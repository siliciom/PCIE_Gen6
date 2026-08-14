//=========================================================================================
// File         : PCIe_RC_phy_monitor.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_RC_phy_agent\PCIe_RC_phy_monitor.sv
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

class PCIe_RC_phy_monitor extends uvm_monitor;
  
       `uvm_component_utils(PCIe_RC_phy_monitor)
  
 	PCIe_sequence_item     pcie_seq_item;
 
	function new(string name="PCIe_RC_phy_monitor", uvm_component parent);
           super.new(name,parent);
	endfunction

	function void build_phase(uvm_phase phase);
          `uvm_info("RC_PHY","ENTERED_INTO_RC_PHY_MONITOR_BUILD_PHASE",UVM_LOW)
	   super.build_phase(phase);
             pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
          `uvm_info("RC_PHY","EXIT_FROM_RC_PHY_MONITOR_BUILD_PHASE",UVM_LOW)
  	endfunction

 	task run_phase(uvm_phase phase);
           `uvm_info("RC_PHY","ENTERED_INTO_RC_PHY_MONITOR_RUN_PHASE",UVM_LOW)
          forever begin
           #2; 
          end
           `uvm_info("RC_PHY","EXIT_FROM_RC_PHY_MONITOR_RUN_PHASE",UVM_LOW)
         endtask

endclass






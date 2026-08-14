//=========================================================================================
// File         : PCIe_EP_controller_monitor.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_EP_controller_agent\PCIe_EP_controller_monitor.sv
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

class PCIe_EP_controller_monitor extends uvm_monitor;
  
       `uvm_component_utils(PCIe_EP_controller_monitor)
  
 	PCIe_sequence_item            pcie_seq_item;
        //PCIe_EP_replay_manager        ep_replay_mon;
        //PCIe_EP_credit_manager        ep_credit_mon;
        //PCIe_ltssm_manager            ltssm_mon;
 
	function new(string name="PCIe_EP_controller_monitor", uvm_component parent);
           super.new(name,parent);
	endfunction

	function void build_phase(uvm_phase phase);
          `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_MONITOR_BUILD_PHASE",UVM_LOW)
	   super.build_phase(phase);
             pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
          `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_MONITOR_BUILD_PHASE",UVM_LOW)
  	endfunction

 	task run_phase(uvm_phase phase);
           `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_MONITOR_RUN_PHASE",UVM_LOW)
          forever begin
          #2;
          end
           `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_MONITOR_RUN_PHASE",UVM_LOW)
         endtask

endclass






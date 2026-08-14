//=========================================================================================
// File         : PCIe_EP_controller_driver.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_EP_controller_agent\PCIe_EP_controller_driver.sv
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

class PCIe_EP_controller_driver extends uvm_driver #(PCIe_sequence_item);
  
       `uvm_component_utils(PCIe_EP_controller_driver)
  
 	PCIe_sequence_item            pcie_seq_item;
        PCIe_EP_TL_model              ep_tl_model;
        PCIe_EP_DL_model              ep_dl_model;
        PCIe_EP_PL_model              ep_pl_model;
        PCIe_ltssm_manager            ltssm_dri;
    
 
	function new(string name="PCIe_EP_controller_driver", uvm_component parent);
           super.new(name,parent);
	endfunction

	function void build_phase(uvm_phase phase);
          `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
	   super.build_phase(phase);
             pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
    	   
            `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
  	endfunction

 	task run_phase(uvm_phase phase);
           `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_DRIVER_RUN_PHASE",UVM_LOW)
          forever begin
	    seq_item_port.get_next_item(pcie_seq_item);
                
            seq_item_port.item_done(pcie_seq_item);
          end
           `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_DRIVER_RUN_PHASE",UVM_LOW)
         endtask

endclass






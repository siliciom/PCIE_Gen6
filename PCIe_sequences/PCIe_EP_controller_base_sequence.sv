//=========================================================================================
// File         : PCIe_EP_controller_base_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences\PCIe_EP_controller_base_sequence.sv
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

class PCIe_EP_controller_base_sequence extends uvm_sequence#(PCIe_sequence_item);
  
  `uvm_object_utils(PCIe_EP_controller_base_sequence)
   PCIe_sequence_item  pcie_seq_item;

   function new(string name="PCIe_EP_controller_base_sequence");
     super.new(name);
   endfunction

   task body();
      pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
     `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_BASE_SEQUENCE_TASK_BODY",UVM_LOW)
      repeat(1)
      begin
       start_item(pcie_seq_item);
         pcie_seq_item.randomize();
	     pcie_seq_item.is_payload=1;
       finish_item(pcie_seq_item);
      end
      `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_BASE_SEQUENCE_TASK_BODY",UVM_LOW)
    endtask

endclass



//=========================================================================================
// File         : PCIe_EP_electrical_idle_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_EP_electrical_idle_sequence.sv
// Author       : 
// Date         : 2026-08-20
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

////////////////////////////////////////////////////////////////
// FILE:  PCIe_EP_electrical_idle_sequence.sv
////////////////////////////////////////////////////////////////

class PCIe_EP_electrical_idle_sequence extends PCIe_EP_controller_base_sequence;

  `uvm_object_utils(PCIe_EP_electrical_idle_sequence)
  PCIe_sequence_item  pcie_seq_item;

  function new(string name="PCIe_EP_electrical_idle_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("EP_ELECTRICAL_IDLE_SEQ","ENTERED_INTO_EP_ELECTRICAL_IDLE_SEQ", UVM_LOW)
     pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
     start_item(pcie_seq_item);
      if (!pcie_seq_item.randomize() with {
       pcie_seq_item.electrical_idle_test  == 1'b1;
       pcie_seq_item.tx_elec_idle  == 1'b1;
       pcie_seq_item.tx_valid      == 1'b0;
       pcie_seq_item.rate          == 3'b000; })
      `uvm_error("EP_SEQ","randomize_failed_for_electrical_idel_seq")
     finish_item(pcie_seq_item);
    `uvm_info("EP_ELECTRICAL_IDLE_SEQ","EXIT_FROM_EP_ELECTRICAL_IDLE_SEQ", UVM_LOW)
  endtask

endclass

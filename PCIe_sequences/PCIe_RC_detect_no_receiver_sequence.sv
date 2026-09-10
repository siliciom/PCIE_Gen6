//=========================================================================================
// File         : PCIe_RC_detect_no_receiver_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_detect_no_receiver_sequence.sv
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
// FILE:  PCIe_RC_detect_no_receiver_sequence.sv
////////////////////////////////////////////////////////////////

class PCIe_RC_detect_no_receiver_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_detect_no_receiver_sequence)

  function new(string name = "PCIe_RC_detect_no_receiver_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("RC_NO_RECEIVER_SEQ","Starting_RC_Detect_No_Receiver_Sequence",UVM_LOW)
    pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
      no_receiver_test == 1'b1;
      electrical_idle_test == 1'b0;
      tx_elec_idle == 1'b1;
      tx_valid     == 1'b0;
      rate         == 3'b000;
    }) begin
      `uvm_error("RC_NO_RECEIVER_SEQ","RC_no_receiver_sequence_randomization_failed")
    end
    finish_item(pcie_seq_item);
    `uvm_info("RC_NO_RECEIVER_SEQ","RC_no_receiver_sequence_completed",UVM_LOW)
  endtask

endclass

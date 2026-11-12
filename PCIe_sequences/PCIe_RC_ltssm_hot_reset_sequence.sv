//=========================================================================================
// File         : PCIe_RC_ltssm_hot_reset_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_ltssm_hot_reset_sequence.sv
//                Drives the RC LTSSM into HOT_RESET out of
//                Configuration.Linkwidth.Start (Hot Reset control bit).
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

class PCIe_RC_ltssm_hot_reset_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_ltssm_hot_reset_sequence)

  function new(string name = "PCIe_RC_ltssm_hot_reset_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("RC_LTSSM_HOT_RESET_SEQ","Starting_RC_LTSSM_Hot_Reset_Sequence",UVM_LOW)
    pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
    pcie_seq_item.link_ctrl_hot_reset       = 1'b1;
    pcie_seq_item.hot_reset_remain_directed = 1'b0;
    // Hot Reset is entered from Recovery.Idle, so the link must go through Recovery:
    // directed speed change Gen1 -> Gen2 gives exactly one Recovery pass.
    pcie_seq_item.directed_recovery = 1'b1;
    pcie_seq_item.target_gen        = 2;
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
      electrical_idle_test == 1'b0;
      no_receiver_test     == 1'b0;
      tx_elec_idle         == 1'b1;
      tx_valid             == 1'b0;
      rate                 == 3'b000;
      pkt_mode             == FLIT;
    }) begin
      `uvm_error("RC_LTSSM_HOT_RESET_SEQ","RC_ltssm_hot_reset_sequence_randomization_failed")
    end
    finish_item(pcie_seq_item);
    `uvm_info("RC_LTSSM_HOT_RESET_SEQ","RC_LTSSM_Hot_Reset_Sequence_item_completed",UVM_LOW)
  endtask

endclass


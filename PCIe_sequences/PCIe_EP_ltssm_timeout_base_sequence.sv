//=========================================================================================
// File         : PCIe_EP_ltssm_timeout_base_sequence.sv
// Project      : PCIE_Gen6
// Description  : Base sequence for all EP LTSSM directed timeout sequences.
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

class PCIe_EP_ltssm_timeout_base_sequence extends PCIe_EP_controller_base_sequence;

  ltssm_timeout_target_e timeout_target = LTSSM_TO_NONE;
  string                 state_name     = "NONE";

  function new(string name = "PCIe_EP_ltssm_timeout_base_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("EP_LTSSM_TIMEOUT_SEQ",$sformatf("Starting_EP_LTSSM_timeout_sequence_for_%s",state_name),UVM_LOW)
    pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
    pcie_seq_item.ltssm_timeout_test   = 1'b1;
    pcie_seq_item.ltssm_timeout_target = timeout_target;
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
      electrical_idle_test      == 1'b0;
      no_receiver_test          == 1'b0;
      directed_recovery         == 1'b0;
      link_ctrl_disable_link    == 1'b0;
      link_ctrl_enter_loopback  == 1'b0;
      link_ctrl_hot_reset       == 1'b0;
      loopback_exit_directed    == 1'b0;
      hot_reset_remain_directed == 1'b0;
      tx_elec_idle              == 1'b1;
      tx_valid                  == 1'b0;
      rate                      == 3'b000;
      pkt_mode                  == FLIT;
    }) begin
      `uvm_error("EP_LTSSM_TIMEOUT_SEQ",$sformatf("%s_randomization_failed",state_name))
    end
    finish_item(pcie_seq_item);
    `uvm_info("EP_LTSSM_TIMEOUT_SEQ",$sformatf("EP_LTSSM_timeout_sequence_for_%s_completed",state_name),UVM_LOW)
  endtask

endclass

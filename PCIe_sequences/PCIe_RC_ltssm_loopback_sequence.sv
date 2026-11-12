//=========================================================================================
// File         : PCIe_RC_ltssm_loopback_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_ltssm_loopback_sequence.sv
//                Drives the RC LTSSM through
//                Configuration.Linkwidth.Start -> Loopback.Entry -> Loopback.Active
//                -> Loopback.Exit (Loopback control bit). The directed exit is
//                raised after a delay so the Active state is really exercised.
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

class PCIe_RC_ltssm_loopback_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_ltssm_loopback_sequence)

  // Directed exit is raised this long after the LTSSM run starts, i.e. while
  // the LTSSM is sitting in Loopback.Active.
  localparam time LOOPBACK_EXIT_DELAY = 10us;

  function new(string name = "PCIe_RC_ltssm_loopback_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("RC_LTSSM_LOOPBACK_SEQ","Starting_RC_LTSSM_Loopback_Sequence",UVM_LOW)
    pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
    pcie_seq_item.link_ctrl_enter_loopback = 1'b1;
    fork
      begin
        #(LOOPBACK_EXIT_DELAY);
        pcie_seq_item.loopback_exit_directed = 1'b1;
        `uvm_info("RC_LTSSM_LOOPBACK_SEQ","RC_directed_Loopback_exit_raised",UVM_LOW)
      end
    join_none
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
      electrical_idle_test == 1'b0;
      no_receiver_test     == 1'b0;
      tx_elec_idle         == 1'b1;
      tx_valid             == 1'b0;
      rate                 == 3'b000;
      pkt_mode             == FLIT;
    }) begin
      `uvm_error("RC_LTSSM_LOOPBACK_SEQ","RC_ltssm_loopback_sequence_randomization_failed")
    end
    finish_item(pcie_seq_item);
    `uvm_info("RC_LTSSM_LOOPBACK_SEQ","RC_LTSSM_Loopback_Sequence_item_completed",UVM_LOW)
  endtask

endclass


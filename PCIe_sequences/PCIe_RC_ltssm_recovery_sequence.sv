//=========================================================================================
// File         : PCIe_RC_ltssm_recovery_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_ltssm_recovery_sequence.sv
//                RC directed recovery / sequential rate negotiation sequence.
//                Starts the RC LTSSM at Gen1 and walks
//                   Gen1 L0 -> Recovery -> Gen2 L0 -> ... -> Gen<target_gen> L0
//                Every directed speed change is a real Recovery entry
//                (RcvrLock -> Equalization -> RcvrCfg -> RcvrLock -> RcvrCfg ->
//                Idle -> L0) with a TS2 Data Rate Identifier exchange.
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

////////////////////////////////////////////////////////
// FILE:  PCIe_RC_ltssm_recovery_sequence.sv
////////////////////////////////////////////////////////

class PCIe_RC_ltssm_recovery_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_ltssm_recovery_sequence)

  // Highest PCIe generation this item must reach (1..6). Set by the testcase
  // through set_target_gen(); defaults to Gen6.
  int unsigned target_gen = 6;

  function new(string name = "PCIe_RC_ltssm_recovery_sequence");
    super.new(name);
  endfunction

  // Called by the testcase so a single sequence class can serve all six
  // directed generations.
  function void set_target_gen(int unsigned gen);
    if (gen < 1 || gen > 6) begin
      `uvm_fatal("RC_RECOVERY_SEQ",$sformatf("Invalid target_gen=%0d, must be 1..6",gen))
    end
    target_gen = gen;
  endfunction

  task body();
    `uvm_info("RC_RECOVERY_SEQ",$sformatf("Starting_RC_ltssm_recovery_sequence target_gen=%0d",target_gen),UVM_LOW)
    pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
      electrical_idle_test == 1'b0;
      no_receiver_test     == 1'b0;
      tx_elec_idle         == 1'b1;
      tx_valid             == 1'b0;
      rate                 == 3'b000;
      pkt_mode             == FLIT;
      txn_type == PCIe_TL_MEM;
      length   == `PCIe_TL_LEN_MIN;   // small payload, fits in one 236 B flit
    }) begin
      `uvm_error("RC_RECOVERY_SEQ","RC_ltssm_recovery_sequence_randomization_failed")
    end
    // target_gen / directed_recovery are non-rand sequence-item fields, so they
    // are assigned directly instead of being constrained in randomize().
    pcie_seq_item.directed_recovery = 1'b1;
    pcie_seq_item.target_gen         = target_gen;
    finish_item(pcie_seq_item);
    `uvm_info("RC_RECOVERY_SEQ",$sformatf("RC_recovery_sequence_item_completed directed_recovery=1 target_gen=%0d",target_gen),UVM_LOW)
    `uvm_info("RC_RECOVERY_SEQ",$sformatf("RC_will_negotiate_Gen1_to_Gen%0d_entering_Recovery_at_every_speed_change",target_gen),UVM_LOW)
  endtask

endclass


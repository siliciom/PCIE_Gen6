//=========================================================================================
// File         : PCIe_gen6_ltssm_recovery_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_ltssm_recovery_test.sv
//                Directed Recovery / sequential rate negotiation testcase.
//
//                One test drives the complete walk
//                   Gen1 L0 -> Recovery -> Gen2 L0 -> Recovery -> Gen3 L0
//                   -> Recovery -> Gen4 L0 -> Recovery -> Gen5 L0
//                   -> Recovery -> Gen6 L0 (64.0 GT/s)
//
//                Every speed change is a real Recovery entry:
//                   Recovery.RcvrLock -> Recovery.Equalization (Gen3 and above)
//                   -> Recovery.RcvrCfg -> Recovery.RcvrLock -> Recovery.RcvrCfg
//                   -> Recovery.Idle -> L0
//                with a TS2 Data Rate Identifier exchange at each step.
//
//                link_up stays 0 through Gen1..Gen5. It is only asserted in
//                the final Gen6 L0, and DLCSSM / DL / TL traffic is released
//                only from that point.
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

//////////////////////////////////////////////////////////////////////////////////
// FILE:  PCIe_gen6_ltssm_recovery_test.sv
//////////////////////////////////////////////////////////////////////////////////

// L0 entries on the way from Gen1 to Gen6: one per generation.
function int PCIe_gen6_ltssm_recovery_expected_l0_visits(int target_gen);
  return target_gen;
endfunction

class PCIe_gen6_ltssm_recovery_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_ltssm_recovery_test)

  // Highest PCIe generation the link must reach. This testcase is the full
  // walk, so it is fixed at Gen6 (64.0 GT/s).
  int unsigned target_gen = 6;

  PCIe_RC_ltssm_recovery_sequence rc_seq;
  PCIe_EP_ltssm_recovery_sequence ep_seq;

  function new(string name = "PCIe_gen6_ltssm_recovery_test",uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info("RECOVERY_TEST","PCIe_gen6_ltssm_recovery_test_built target_gen=6",UVM_LOW)
  endfunction

  task run_phase(uvm_phase phase);
    PCIe_RC_PL_model rc_pl;
    PCIe_EP_PL_model ep_pl;
    int               expected_l0;
    bit               link_up_rc;
    bit               link_up_ep;
    int               gen_rc;
    int               gen_ep;

    phase.raise_objection(this);
    `uvm_info("RECOVERY_TEST",$sformatf("Starting_directed_recovery_target_gen=%0d",target_gen),UVM_LOW)

    rc_seq = PCIe_RC_ltssm_recovery_sequence::type_id::create("rc_seq");
    ep_seq = PCIe_EP_ltssm_recovery_sequence::type_id::create("ep_seq");
    rc_seq.set_target_gen(target_gen);
    ep_seq.set_target_gen(target_gen);

    // RC and EP negotiate in parallel.
    fork
      rc_seq.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
      ep_seq.start(pcie_environment.ep_top_agent.ep_controller_agent.ep_controller_sequencer);
    join

    //-----------------------------------------------------------------------
    // The LTSSM runs to completion before the item is handed back, so the
    // PL state is final once both sequences have returned.
    //-----------------------------------------------------------------------
    rc_pl     = pcie_environment.rc_top_agent.rc_controller_agent.rc_pl_model;
    ep_pl     = pcie_environment.ep_top_agent.ep_controller_agent.ep_pl_model;
    link_up_rc = rc_pl.link_up;
    link_up_ep = ep_pl.link_up;
    gen_rc     = rc_pl.rc_rate_gen_num(rc_pl.rc_cur_rate);
    gen_ep     = ep_pl.ep_rate_gen_num(ep_pl.ep_cur_rate);
    expected_l0 = PCIe_gen6_ltssm_recovery_expected_l0_visits(target_gen);

    `uvm_info("RECOVERY_TEST",$sformatf("RESULT target_gen=%0d RC: link_up=%0b rate=Gen%0d L0_visits=%0d | EP: link_up=%0b rate=Gen%0d L0_visits=%0d",
              target_gen, link_up_rc, gen_rc, rc_pl.rc_l0_visit_count,
                             link_up_ep, gen_ep, ep_pl.ep_l0_visit_count),UVM_LOW)

    if (link_up_rc !== 1'b1)
      `uvm_error("RECOVERY_TEST",$sformatf("RC link_up is %0b after directed recovery to Gen%0d",link_up_rc,target_gen))
    if (link_up_ep !== 1'b1)
      `uvm_error("RECOVERY_TEST",$sformatf("EP link_up is %0b after directed recovery to Gen%0d",link_up_ep,target_gen))

    if (gen_rc != target_gen)
      `uvm_error("RECOVERY_TEST",$sformatf("RC settled on Gen%0d but the test requires Gen%0d",gen_rc,target_gen))
    if (gen_ep != target_gen)
      `uvm_error("RECOVERY_TEST",$sformatf("EP settled on Gen%0d but the test requires Gen%0d",gen_ep,target_gen))

    if (gen_rc != gen_ep)
      `uvm_error("RECOVERY_TEST",$sformatf("RC and EP did not agree on the negotiated rate: RC=Gen%0d EP=Gen%0d",gen_rc,gen_ep))

    // Gen1 L0 is reached through Polling/Configuration, so only the directed
    // speed changes (Gen2 .. Gen<target>) go through Recovery.
    if (rc_pl.rc_l0_visit_count != expected_l0)
      `uvm_error("RECOVERY_TEST",$sformatf("RC visited L0 %0d time(s), expected %0d for Gen%0d",
                rc_pl.rc_l0_visit_count, expected_l0, target_gen))
    if (ep_pl.ep_l0_visit_count != expected_l0)
      `uvm_error("RECOVERY_TEST",$sformatf("EP visited L0 %0d time(s), expected %0d for Gen%0d",
                ep_pl.ep_l0_visit_count, expected_l0, target_gen))

    //-----------------------------------------------------------------------
    // Traffic must only have been released at the final Gen6 L0. If the link
    // had come up early the DL/TL models would already be active, so assert
    // the negotiated rate is Gen6 AND that both ports walked every generation.
    //-----------------------------------------------------------------------
    if ((rc_pl.rc_l0_visit_count < 6) || (ep_pl.ep_l0_visit_count < 6))
      `uvm_error("RECOVERY_TEST","The link did not visit every generation Gen1..Gen6 before coming up")

    `uvm_info("RECOVERY_TEST",$sformatf("Directed_recovery_to_Gen%0d_completed",target_gen),UVM_LOW)
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("RECOVERY_TEST",$sformatf("PCIe_gen6_ltssm_recovery_test_PASS"),UVM_LOW)
  endfunction

endclass


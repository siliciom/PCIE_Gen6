//=========================================================================================
// File         : PCIe_gen6_dll_duplicate_flit_discard_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_duplicate_flit_discard_test.sv
// Author       : Rani
// Date         : 2026-11-21
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

// Duplicate flit discard   (PCIe 6.1 Sec 4.2.3.4.2.1.5, duplicate_sequence_number -> Flit Discard 0)
//
//   Two times :
//     RC sends 1 MemWr, the EP accepts and ACKs it
//     RC sends the SAME flit again (same sequence number)   <- duplicate
//     EP must drop it : not sent to the TL, no NAK, link keeps working
//   Then 2 normal MemWr must still go through.
//
//   Checks : 2 duplicates dropped, EP TL did not get them, no NAK, traffic OK.

class PCIe_gen6_dll_duplicate_flit_discard_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_dll_duplicate_flit_discard_test)

  //--------------------------------------------------------------------------
  // Handles to the models this test looks at
  //--------------------------------------------------------------------------
  PCIe_RC_DL_model            rc_dl;
  PCIe_EP_DL_model            ep_dl;
  PCIe_RC_TL_model            rc_tl;
  PCIe_EP_TL_model            ep_tl;
  PCIe_RC_PL_model            rc_pl;
  PCIe_EP_controller_monitor  ep_mon;
  virtual PCIe_RC_interface   rc_vif;

  int unsigned pass_cnt;                         // checks passed
  int unsigned fail_cnt;                         // checks failed

  function new(string name = "PCIe_gen6_dll_duplicate_flit_discard_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //--------------------------------------------------------------------------
  // build : warm-up traffic = PCIe_RC_dll_duplicate_flit_discard_sequence with 2 MemWr (after enumeration)
  //--------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    PCIe_RC_controller_base_sequence::type_id::set_type_override(PCIe_RC_dll_duplicate_flit_discard_sequence::get_type());
    PCIe_EP_controller_base_sequence::type_id::set_type_override(PCIe_EP_3DW_flit_sequence::get_type());
    super.build_phase(phase);
    // warm-up : the base test runs this test's own sequence once after enumeration, with 2 MemWr
    begin
      PCIe_RC_dll_duplicate_flit_discard_sequence warmup_seq;
      if ($cast(warmup_seq, rc_controller_sequence)) warmup_seq.num_txn = 2;
    end
    if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_vif))
      `uvm_fatal("DLL_TEST", "PCIe_RC_INTERFACE not found")
`ifndef PCIE_GEN6_FEC_CRC
    `uvm_fatal("DLL_TEST", "compile with +define+PCIE_GEN6_FEC_CRC")
`endif
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    rc_dl  = pcie_environment.rc_top_agent.rc_controller_agent.rc_dl_model;
    rc_tl  = pcie_environment.rc_top_agent.rc_controller_agent.rc_tl_model;
    rc_pl  = pcie_environment.rc_top_agent.rc_controller_agent.rc_pl_model;
    ep_dl  = pcie_environment.ep_top_agent.ep_controller_agent.ep_dl_model;
    ep_tl  = pcie_environment.ep_top_agent.ep_controller_agent.ep_tl_model;
    ep_mon = pcie_environment.ep_top_agent.ep_controller_agent.ep_controller_monitor;
  endfunction

  //--------------------------------------------------------------------------
  // run : link up + enumeration + warm-up (PCIe_base_test), then run_dll_test()
  //--------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    uvm_event warmup_done = uvm_event_pool::get_global("dll_seq_done");

    fork
      super.run_phase(phase);              // link up + enumeration + warm-up MemWr
    join_none
    phase.raise_objection(this);

    warmup_done.wait_on();                 // warm-up sequence finished
    wait_link_idle();
    step({get_type_name(), " : START"});
    run_dll_test();
    #1us;
    step({get_type_name(), " : END"});
    phase.drop_objection(this);
  endtask

  //==========================================================================
  // THE TEST
  //==========================================================================
  // this test's own sequence (a new object for every run)
  function PCIe_RC_dll_duplicate_flit_discard_sequence new_seq();
    return PCIe_RC_dll_duplicate_flit_discard_sequence::type_id::create("duplicate_flit_discard_seq");
  endfunction

  task run_dll_test();
    int unsigned              dl_err_before;   // [DL_ERR]
    int unsigned tl_before, dup_before, nak_before;

    for (int round = 1; round <= 2; round++) begin
      dl_err_before = ep_dl.dl_error_total();   // [DL_ERR]
    step($sformatf("ROUND %0d : 1 MemWr, then the same flit again (duplicate)", round));
      run_dll_seq(new_seq());
      wait_link_idle();                               // the MemWr is ACKed

      tl_before  = ep_tl.n_tlp_rcvd;
      dup_before = ep_dl.n_rx_dup_discarded;
      nak_before = ep_dl.n_std_nak_scheduled + ep_dl.n_sel_nak_scheduled;

      rc_dl.duplicate_flit_request = 1'b1;            // RC driver sends the last flit again
      repeat (100) begin
        if (!rc_dl.duplicate_flit_request) break;
        #100ns;
      end
      #1us;                                           // EP has processed it

      check_result(ep_dl.n_rx_dup_discarded - dup_before == 1, $sformatf("ROUND%0d_DUPLICATE_DROPPED", round),
            $sformatf("EP dropped %0d duplicate flit(s), RC SEQ_NUM=%0d", ep_dl.n_rx_dup_discarded - dup_before,
                      rc_dl.last_tx_payload_flit.seq_num));
      check_result(ep_tl.n_tlp_rcvd == tl_before, $sformatf("ROUND%0d_DUPLICATE_NOT_SENT_TO_TL", round),
            $sformatf("EP TL got %0d extra TLP(s) (expected 0)", ep_tl.n_tlp_rcvd - tl_before));
      check_result(ep_dl.n_std_nak_scheduled + ep_dl.n_sel_nak_scheduled == nak_before, $sformatf("ROUND%0d_NO_NAK", round),
            "a duplicate flit is not an error : no NAK");
    end

    step("2 normal MemWr after the duplicates");
    tl_before = ep_tl.n_tlp_rcvd;
    run_dll_seq(new_seq(), 2);
    wait_ep_tl_count(tl_before + 2, "2 MemWr after the duplicates");
    wait_link_idle();
    check_result(ep_tl.n_tlp_rcvd - tl_before == 2, "TRAFFIC_OK_AFTER_DUPLICATES",
          $sformatf("EP TL got %0d TLPs (expected 2)", ep_tl.n_tlp_rcvd - tl_before));
    check_result(rc_dl.n_duplicate_flits_sent >= 2, "RC_SENT_2_DUPLICATES",
          $sformatf("RC sent %0d duplicate flit(s)", rc_dl.n_duplicate_flits_sent));

    // [DL_ERR] error logging (PCIe 6.1 Sec 6.2)
    check_result(ep_dl.dl_error_total() == dl_err_before, "NO_DL_ERROR_LOGGED",
          $sformatf("EP logged %0d DL error(s) (expected 0 : a duplicate flit is not an error)", ep_dl.dl_error_total() - dl_err_before));
  endtask

  //==========================================================================
  // HELPERS (only the ones this test uses)
  //==========================================================================

  task run_dll_seq(PCIe_RC_dll_duplicate_flit_discard_sequence seq, int unsigned n = 0);
    if (n != 0) seq.num_txn = n;
    `uvm_info("DLL_TEST", $sformatf("START SEQUENCE %s : %0d MemWr", seq.get_type_name(), seq.num_txn), UVM_NONE)
    seq.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
  endtask

  task wait_ep_tl_count(int unsigned count, string what, int unsigned max_us = 200);
    repeat (max_us) begin
      if (ep_tl.n_tlp_rcvd >= count) return;
      #1us;
    end
    `uvm_error("DLL_TEST", $sformatf("TIMEOUT (%0d us) : EP TL has %0d TLPs, expected %0d :: %s",
               max_us, ep_tl.n_tlp_rcvd, count, what))
  endtask

  function bit link_is_idle();
    return !rc_dl.REPLAY_SCHEDULED && !rc_dl.RC_REPLAY_IN_PROGRESS &&
           (rc_dl.tx_retry_buffer.size() == 0) &&
           !ep_dl.NAK_SCHEDULED && (ep_dl.rx_retry_buffer.size() == 0);
  endfunction

  task wait_link_idle(int unsigned max_us = 200);
    repeat (max_us) begin
      if (link_is_idle()) return;
      #1us;
    end
    `uvm_error("DLL_TEST", $sformatf("TIMEOUT (%0d us) : link not idle :: RC TX_RETRY=%0d REPLAY_SCHEDULED=%0b IN_PROGRESS=%0b :: EP NAK_SCHEDULED=%0b RX_RETRY=%0d",
               max_us, rc_dl.tx_retry_buffer.size(), rc_dl.REPLAY_SCHEDULED, rc_dl.RC_REPLAY_IN_PROGRESS,
               ep_dl.NAK_SCHEDULED, ep_dl.rx_retry_buffer.size()))
  endtask

  int unsigned step_no;   // [FLOW] test step counter

  function void step(string text);
    step_no++;
    `uvm_info("DLL_STEP", {"\n  ==========================================================\n",
                           "   ", text, "\n",
                           "  =========================================================="}, UVM_NONE)
    PCIe_flow_log::print($sformatf("TEST STEP %0d", step_no), text);   // [FLOW]
  endfunction

  // named check_result : 'check' is already a method of uvm_component (UVM 1.1d)
  function void check_result(bit ok, string name, string detail);
    if (ok) begin pass_cnt++; `uvm_info("DLL_CHECK", {"PASS : ", name, " : ", detail}, UVM_NONE) end
    else    begin fail_cnt++; `uvm_error("DLL_CHECK", {"FAIL : ", name, " : ", detail}) end
    if (ok) PCIe_flow_log::print("CHECK", {"PASS ", name});                     // [FLOW]
    else    PCIe_flow_log::print("CHECK", {"FAIL ", name, " : ", detail});
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (pass_cnt + fail_cnt == 0)
      `uvm_error("DLL_CHECK", "no check was run")
    `uvm_info("DLL_TEST", $sformatf("DLL_CHECK_SUMMARY : %0d PASS  %0d FAIL", pass_cnt, fail_cnt), UVM_NONE)
  endfunction

endclass

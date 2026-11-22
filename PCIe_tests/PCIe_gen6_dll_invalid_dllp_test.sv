//=========================================================================================
// File         : PCIe_gen6_dll_invalid_dllp_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_invalid_dllp_test.sv
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

// Invalid (unsupported) DLLP   (PCIe 6.1 Sec 3.6.2.3)
//   "A received DLLP that uses unsupported DLLP Type encodings is discarded
//    without further action. This is not considered an error."
//
//   RC sends 3 DLLPs with types that are Reserved in Flit Mode :
//     01h (Reserved / MRInit), 10h (Nak in Non-Flit Mode), 70h (Reserved / MRInitFC1)
//   The EP must drop them : no error, no change in the DL state, link stays up.
//   Then 2 MemWr must go through.
//
//   Checks : 3 unsupported DLLPs counted, no new UVM error, EP still DL_ACTIVE
//            with the same sequence numbers, no NAK, traffic OK.

class PCIe_gen6_dll_invalid_dllp_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_dll_invalid_dllp_test)

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

  function new(string name = "PCIe_gen6_dll_invalid_dllp_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //--------------------------------------------------------------------------
  // build : warm-up traffic = PCIe_RC_dll_invalid_dllp_sequence with 2 MemWr (after enumeration)
  //--------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    PCIe_RC_controller_base_sequence::type_id::set_type_override(PCIe_RC_dll_invalid_dllp_sequence::get_type());
    PCIe_EP_controller_base_sequence::type_id::set_type_override(PCIe_EP_3DW_flit_sequence::get_type());
    super.build_phase(phase);
    // warm-up : the base test runs this test's own sequence once after enumeration, with 2 MemWr
    begin
      PCIe_RC_dll_invalid_dllp_sequence warmup_seq;
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
  bit [31:0] invalid_dllps[$] = '{32'h0100_0000, 32'h1000_0000, 32'h7000_0000};

  // this test's own sequence (a new object for every run)
  function PCIe_RC_dll_invalid_dllp_sequence new_seq();
    return PCIe_RC_dll_invalid_dllp_sequence::type_id::create("invalid_dllp_seq");
  endfunction

  task run_dll_test();
    int unsigned              dl_err_before;   // [DL_ERR]
    int unsigned              tl_before, unsup_before, err_before, nak_before;
    bit [`PCIe_SEQ_NUM_W-1:0] exp_before, ack_before;

    unsup_before = ep_dl.n_rx_unsupported_dllp;
    err_before   = uvm_error_count();
    nak_before   = ep_dl.n_std_nak_scheduled + ep_dl.n_sel_nak_scheduled;
    exp_before   = ep_dl.NEXT_EXPECTED_RX_FLIT_SEQ_NUM;
    ack_before   = ep_dl.TX_ACKNAK_FLIT_SEQ_NUM;

    dl_err_before = ep_dl.dl_error_total();   // [DL_ERR]
    step("RC sends 3 DLLPs with unsupported (Reserved) type");
    foreach (invalid_dllps[i]) begin
      `uvm_info("DLL_TEST", $sformatf("sending unsupported DLLP %08h (type %02h)", invalid_dllps[i], invalid_dllps[i][31:24]), UVM_NONE)
      rc_dl.send_dllp_flit(invalid_dllps[i]);
    end
    #1us;

    check_result(ep_dl.n_rx_unsupported_dllp - unsup_before == 3, "UNSUPPORTED_DLLPS_DISCARDED",
          $sformatf("EP discarded %0d unsupported DLLP(s) (expected 3)", ep_dl.n_rx_unsupported_dllp - unsup_before));
    check_result(uvm_error_count() == err_before, "NOT_AN_ERROR",
          $sformatf("%0d new UVM error(s) (expected 0)", uvm_error_count() - err_before));
    check_result(ep_dl.dl_link_active && (ep_dl.DL_STATE == DL_ACTIVE), "LINK_STAYS_DL_ACTIVE",
          $sformatf("EP DL_STATE=%s", ep_dl.DL_STATE.name()));
    check_result((ep_dl.NEXT_EXPECTED_RX_FLIT_SEQ_NUM == exp_before) && (ep_dl.TX_ACKNAK_FLIT_SEQ_NUM == ack_before),
          "DL_STATE_NOT_CHANGED", $sformatf("NEXT_EXPECTED_RX %0d->%0d, TX_ACKNAK %0d->%0d",
          exp_before, ep_dl.NEXT_EXPECTED_RX_FLIT_SEQ_NUM, ack_before, ep_dl.TX_ACKNAK_FLIT_SEQ_NUM));
    check_result(ep_dl.n_std_nak_scheduled + ep_dl.n_sel_nak_scheduled == nak_before, "NO_NAK", "unsupported DLLP : no NAK");

    step("2 MemWr after the unsupported DLLPs");
    tl_before = ep_tl.n_tlp_rcvd;
    run_dll_seq(new_seq());
    wait_ep_tl_count(tl_before + 2, "2 MemWr");
    wait_link_idle();
    check_result(ep_tl.n_tlp_rcvd - tl_before == 2, "TRAFFIC_OK_AFTER_INVALID_DLLP",
          $sformatf("EP TL got %0d TLPs (expected 2)", ep_tl.n_tlp_rcvd - tl_before));

    // [DL_ERR] error logging (PCIe 6.1 Sec 6.2)
    check_result(ep_dl.dl_error_total() == dl_err_before, "NO_DL_ERROR_LOGGED",
          $sformatf("EP logged %0d DL error(s) (expected 0 : unsupported DLLP is not an error)", ep_dl.dl_error_total() - dl_err_before));
  endtask

  //==========================================================================
  // HELPERS (only the ones this test uses)
  //==========================================================================

  task run_dll_seq(PCIe_RC_dll_invalid_dllp_sequence seq, int unsigned n = 0);
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

  function int unsigned uvm_error_count();
    uvm_report_server svr = uvm_report_server::get_server();
    return svr.get_severity_count(UVM_ERROR) + svr.get_severity_count(UVM_FATAL);
  endfunction

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

//=========================================================================================
// File         : PCIe_gen6_dll_sequence_wraparound_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_sequence_wraparound_test.sv
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

// Flit sequence number wrap-around   (PCIe 6.1 Sec 4.2.3.4.2.1)
//
//   Flit sequence numbers are 10 bit and go 1, 2, ... 1023, then 1 again
//   (0 is never used : it means "IDLE / no sequence number").
//   Sending 1023 MemWr takes too long, so the test moves the sequence numbers
//   near the end while the link is idle :
//     RC : NEXT_TX_FLIT_SEQ_NUM          = 1020   (ACKD = 1019)
//     EP : NEXT_EXPECTED_RX_FLIT_SEQ_NUM = 1020   (ACK  = 1019)
//   Then 8 MemWr : sequence numbers 1020 1021 1022 1023 1 2 3 4.
//
//   Checks : RC used exactly these numbers (no 0), EP accepted all 8 in order
//            (no NAK), last ACK = 4, EP now expects 5.

class PCIe_gen6_dll_sequence_wraparound_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_dll_sequence_wraparound_test)

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

  function new(string name = "PCIe_gen6_dll_sequence_wraparound_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //--------------------------------------------------------------------------
  // build : warm-up traffic = PCIe_RC_dll_sequence_wraparound_sequence with 2 MemWr (after enumeration)
  //--------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    PCIe_RC_controller_base_sequence::type_id::set_type_override(PCIe_RC_dll_sequence_wraparound_sequence::get_type());
    PCIe_EP_controller_base_sequence::type_id::set_type_override(PCIe_EP_3DW_flit_sequence::get_type());
    super.build_phase(phase);
    // warm-up : the base test runs this test's own sequence once after enumeration, with 2 MemWr
    begin
      PCIe_RC_dll_sequence_wraparound_sequence warmup_seq;
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
  localparam bit [`PCIe_SEQ_NUM_W-1:0] START_SEQ = 10'd1020;

  // this test's own sequence (a new object for every run)
  function PCIe_RC_dll_sequence_wraparound_sequence new_seq();
    return PCIe_RC_dll_sequence_wraparound_sequence::type_id::create("sequence_wraparound_seq");
  endfunction

  task run_dll_test();
    int unsigned              tl_before, nak_before, seq_q_before;
    bit [`PCIe_SEQ_NUM_W-1:0] sent[$];
    bit [`PCIe_SEQ_NUM_W-1:0] expected[$];

    step($sformatf("move both sides to sequence number %0d", START_SEQ));
    wait_link_idle();
    rc_dl.set_tx_seq_for_test(START_SEQ);
    ep_dl.set_rx_seq_for_test(START_SEQ);

    tl_before    = ep_tl.n_tlp_rcvd;
    nak_before   = ep_dl.n_std_nak_scheduled + ep_dl.n_sel_nak_scheduled;
    seq_q_before = rc_dl.tx_payload_seq_q.size();

    step("8 MemWr across the wrap point 1023 -> 1");
    run_dll_seq(new_seq());
    wait_ep_tl_count(tl_before + 8, "8 MemWr across the wrap");
    wait_link_idle();

    for (int unsigned i = seq_q_before; i < rc_dl.tx_payload_seq_q.size(); i++) sent.push_back(rc_dl.tx_payload_seq_q[i]);
    expected = '{10'd1020, 10'd1021, 10'd1022, 10'd1023, 10'd1, 10'd2, 10'd3, 10'd4};

    check_result(sent == expected, "SEQ_NUM_WRAPS_1023_TO_1",
          $sformatf("RC sent SEQ_NUMs %p (expected %p)", sent, expected));
    check_result(!(10'd0 inside {sent}), "SEQ_NUM_0_NEVER_USED", "sequence number 0 is reserved");
    check_result(ep_tl.n_tlp_rcvd - tl_before == 8, "EP_TL_GOT_8_MEMWR",
          $sformatf("EP TL got %0d TLPs (expected 8)", ep_tl.n_tlp_rcvd - tl_before));
    check_result(ep_dl.n_std_nak_scheduled + ep_dl.n_sel_nak_scheduled == nak_before, "NO_NAK_AT_WRAP",
          "the EP must accept 1023 -> 1 as in-order");
    check_result(rc_dl.ACKD_FLIT_SEQ_NUM == 10'd4, "LAST_ACK_IS_4",
          $sformatf("RC ACKD_FLIT_SEQ_NUM=%0d (expected 4)", rc_dl.ACKD_FLIT_SEQ_NUM));
    check_result(ep_dl.NEXT_EXPECTED_RX_FLIT_SEQ_NUM == 10'd5, "EP_EXPECTS_5",
          $sformatf("EP NEXT_EXPECTED_RX_FLIT_SEQ_NUM=%0d (expected 5)", ep_dl.NEXT_EXPECTED_RX_FLIT_SEQ_NUM));
  endtask

  //==========================================================================
  // HELPERS (only the ones this test uses)
  //==========================================================================

  task run_dll_seq(PCIe_RC_dll_sequence_wraparound_sequence seq, int unsigned n = 0);
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

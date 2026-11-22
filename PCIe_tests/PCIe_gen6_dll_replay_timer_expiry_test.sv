//=========================================================================================
// File         : PCIe_gen6_dll_replay_timer_expiry_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_replay_timer_expiry_test.sv
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

// Replay timer expiry   (PCIe 6.1 Sec 4.2.3.4.2.1.6, Replay Schedule Rule 0)
//
//   The EP holds its ACKs (the flits arrive fine, but the ACK never comes).
//   RC sends 3 MemWr and keeps them in its TX retry buffer.
//   After 1500 flit times without an ACK (REPLAY_TIMEOUT_FLIT_COUNT >= 1500)
//   the RC logs a Replay Timer Timeout and does a STANDARD replay of all
//   unACKed flits, starting at ACKD_FLIT_SEQ_NUM + 1.
//   The EP already has these flits : it drops them as duplicates.
//   Then the ACKs are released : the RC TX retry buffer empties.
//
//   Checks : 1 replay timeout, replay = the 3 unACKed flits in order,
//            EP dropped them as duplicates, EP TL got the 3 MemWr only once,
//            timer counter back to 0 and buffer empty after the ACK.

class PCIe_gen6_dll_replay_timer_expiry_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_dll_replay_timer_expiry_test)

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

  function new(string name = "PCIe_gen6_dll_replay_timer_expiry_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //--------------------------------------------------------------------------
  // build : warm-up traffic = PCIe_RC_dll_replay_timer_expiry_sequence with 2 MemWr (after enumeration)
  //--------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    PCIe_RC_controller_base_sequence::type_id::set_type_override(PCIe_RC_dll_replay_timer_expiry_sequence::get_type());
    PCIe_EP_controller_base_sequence::type_id::set_type_override(PCIe_EP_3DW_flit_sequence::get_type());
    super.build_phase(phase);
    // warm-up : the base test runs this test's own sequence once after enumeration, with 2 MemWr
    begin
      PCIe_RC_dll_replay_timer_expiry_sequence warmup_seq;
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
  function PCIe_RC_dll_replay_timer_expiry_sequence new_seq();
    return PCIe_RC_dll_replay_timer_expiry_sequence::type_id::create("replay_timer_expiry_seq");
  endfunction

  task run_dll_test();
    int unsigned              dl_err_before;   // [DL_ERR]
    int unsigned              tl_before, timeout_before, dup_before, rep_q_before, seq_q_before;
    bit [`PCIe_SEQ_NUM_W-1:0] sent[$];
    bit [`PCIe_SEQ_NUM_W-1:0] replayed[$];

    tl_before      = ep_tl.n_tlp_rcvd;
    timeout_before = rc_dl.n_replay_timeouts;
    dup_before     = ep_dl.n_rx_dup_discarded;
    rep_q_before   = rc_dl.replayed_seq_q.size();
    seq_q_before   = rc_dl.tx_payload_seq_q.size();

    dl_err_before = rc_dl.err_replay_timer_timeout;   // [DL_ERR]
    step("EP holds its ACKs, RC sends 3 MemWr");
    ep_dl.set_ack_hold(1'b1);
    run_dll_seq(new_seq());
    wait_ep_tl_count(tl_before + 3, "3 MemWr");
    for (int unsigned i = seq_q_before; i < rc_dl.tx_payload_seq_q.size(); i++) sent.push_back(rc_dl.tx_payload_seq_q[i]);

    step($sformatf("wait for the replay timer (%0d flit times without ACK)", rc_dl.REPLAY_TIMEOUT_LIMIT));
    allow_link_errors(1);                              // replayed flits are extra flits for the scoreboard
    repeat (100) begin
      if (rc_dl.n_replay_timeouts > timeout_before) break;
      #1us;
    end
    wait (!rc_dl.REPLAY_SCHEDULED && !rc_dl.RC_REPLAY_IN_PROGRESS);
    #1us;
    get_replayed_since(rep_q_before, replayed);

    check_result(rc_dl.n_replay_timeouts - timeout_before == 1, "ONE_REPLAY_TIMER_TIMEOUT",
          $sformatf("RC replay timeouts : %0d", rc_dl.n_replay_timeouts - timeout_before));
    check_result((replayed == sent) && (sent.size() == 3), "TIMEOUT_REPLAYS_ALL_UNACKED_FLITS",
          $sformatf("sent SEQ_NUMs %p, replayed SEQ_NUMs %p", sent, replayed));
    check_result(ep_dl.n_rx_dup_discarded - dup_before == 3, "EP_DROPPED_REPLAYED_DUPLICATES",
          $sformatf("EP dropped %0d duplicate flit(s) (expected 3)", ep_dl.n_rx_dup_discarded - dup_before));
    check_result(ep_tl.n_tlp_rcvd - tl_before == 3, "EP_TL_GOT_3_MEMWR_ONCE",
          $sformatf("EP TL got %0d TLPs (expected 3)", ep_tl.n_tlp_rcvd - tl_before));

    step("EP releases its ACKs");
    ep_dl.set_ack_hold(1'b0);
    wait_link_idle();
    allow_link_errors(0);
    check_result((rc_dl.tx_retry_buffer.size() == 0) && (rc_dl.REPLAY_TIMEOUT_FLIT_COUNT == 0), "ACK_STOPS_REPLAY_TIMER",
          $sformatf("RC TX retry buffer=%0d REPLAY_TIMEOUT_FLIT_COUNT=%0d (expected 0 and 0)",
                    rc_dl.tx_retry_buffer.size(), rc_dl.REPLAY_TIMEOUT_FLIT_COUNT));

    // [DL_ERR] error logging (PCIe 6.1 Sec 6.2)
    check_result(rc_dl.err_replay_timer_timeout - dl_err_before == 1, "REPLAY_TIMER_TIMEOUT_ERROR_LOGGED",
          $sformatf("RC logged %0d Replay Timer Timeout error(s) (expected 1, Sec 6.2)", rc_dl.err_replay_timer_timeout - dl_err_before));
  endtask

  //==========================================================================
  // HELPERS (only the ones this test uses)
  //==========================================================================

  task run_dll_seq(PCIe_RC_dll_replay_timer_expiry_sequence seq, int unsigned n = 0);
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

  // on = 1 : expected CRC / FEC / scoreboard errors are printed as INFO
  // on = 0 : they are ERROR again
  function void allow_link_errors(bit on);
    uvm_severity sev = on ? UVM_INFO : UVM_ERROR;
    ep_mon.set_report_severity_id_override(UVM_ERROR, "EP_CONTROLLER_MONITOR", sev);
    pcie_environment.ep_top_agent.ep_controller_agent.ep_pl_model
      .set_report_severity_id_override(UVM_ERROR, "PCIe_SCOREBOARD", sev);
    pcie_environment.pcie_scoreboard.set_report_severity_id_override(UVM_ERROR, "PCIe_SCOREBOARD", sev);
  endfunction

  // RC replayed sequence numbers since index 'from' of rc_dl.replayed_seq_q
  function void get_replayed_since(int unsigned from, output bit [`PCIe_SEQ_NUM_W-1:0] q[$]);
    q.delete();
    for (int unsigned i = from; i < rc_dl.replayed_seq_q.size(); i++) q.push_back(rc_dl.replayed_seq_q[i]);
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

//=========================================================================================
// File         : PCIe_gen6_dll_reset_replay_buffer_clear_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_reset_replay_buffer_clear_test.sv
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

// Reset clears the replay (retry) buffers   (PCIe 6.1 Sec 4.2.3.4.2.1 : DL_Inactive values)
//
//   1. EP holds its ACKs, RC sends 3 MemWr -> 3 unACKed flits in the RC TX retry buffer.
//   2. Physical LinkUp = 0 -> DL_INACTIVE : the DL state is reset :
//        TX + RX retry buffers empty (the 3 unACKed flits are dropped)
//        NEXT_TX_FLIT_SEQ_NUM = 1, ACKD / TX_ACKNAK = 1023, NEXT_EXPECTED_RX = 1
//        ACK / NAK / replay flags = 0, replay timer counter = 0
//   3. Physical LinkUp = 1 -> DL_ACTIVE again, 2 MemWr work, SEQ_NUM 1 and 2.
//
//   Checks : buffer had 3 flits before, every reset value after the link down,
//            no old flit replayed after the link up, traffic OK.

class PCIe_gen6_dll_reset_replay_buffer_clear_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_dll_reset_replay_buffer_clear_test)

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

  function new(string name = "PCIe_gen6_dll_reset_replay_buffer_clear_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //--------------------------------------------------------------------------
  // build : warm-up traffic = PCIe_RC_dll_reset_replay_buffer_clear_sequence with 2 MemWr (after enumeration)
  //--------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    PCIe_RC_controller_base_sequence::type_id::set_type_override(PCIe_RC_dll_reset_replay_buffer_clear_sequence::get_type());
    PCIe_EP_controller_base_sequence::type_id::set_type_override(PCIe_EP_3DW_flit_sequence::get_type());
    super.build_phase(phase);
    // warm-up : the base test runs this test's own sequence once after enumeration, with 2 MemWr
    begin
      PCIe_RC_dll_reset_replay_buffer_clear_sequence warmup_seq;
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
  function PCIe_RC_dll_reset_replay_buffer_clear_sequence new_seq();
    return PCIe_RC_dll_reset_replay_buffer_clear_sequence::type_id::create("reset_replay_buffer_clear_seq");
  endfunction

  task run_dll_test();
    int unsigned              tl_before, seq_q_before, rep_q_before;
    bit [`PCIe_SEQ_NUM_W-1:0] sent[$];
    bit [`PCIe_SEQ_NUM_W-1:0] expected[$];

    step("EP holds its ACKs, RC sends 3 MemWr -> 3 unACKed flits");
    tl_before = ep_tl.n_tlp_rcvd;
    ep_dl.set_ack_hold(1'b1);
    run_dll_seq(new_seq());
    wait_ep_tl_count(tl_before + 3, "3 MemWr");
    #500ns;
    check_result(rc_dl.tx_retry_buffer.size() == 3, "TX_RETRY_BUFFER_HAS_3_FLITS",
          $sformatf("RC TX retry buffer holds %0d flits before the reset", rc_dl.tx_retry_buffer.size()));

    link_down();
    ep_dl.set_ack_hold(1'b0);

    check_result((rc_dl.tx_retry_buffer.size() == 0) && (rc_dl.rx_retry_buffer.size() == 0) &&
          (ep_dl.tx_retry_buffer.size() == 0) && (ep_dl.rx_retry_buffer.size() == 0), "RETRY_BUFFERS_CLEARED",
          $sformatf("RC TX/RX=%0d/%0d EP TX/RX=%0d/%0d (all must be 0)", rc_dl.tx_retry_buffer.size(),
                    rc_dl.rx_retry_buffer.size(), ep_dl.tx_retry_buffer.size(), ep_dl.rx_retry_buffer.size()));
    check_result(rc_dl.n_tx_flits_dropped_on_reset == 3, "UNACKED_FLITS_DROPPED",
          $sformatf("RC dropped %0d unACKed flit(s) at the reset (expected 3)", rc_dl.n_tx_flits_dropped_on_reset));
    check_result((rc_dl.NEXT_TX_FLIT_SEQ_NUM == 10'd1) && (rc_dl.ACKD_FLIT_SEQ_NUM == 10'h3FF) &&
          (rc_dl.TX_ACKNAK_FLIT_SEQ_NUM == 10'h3FF) && (rc_dl.NEXT_EXPECTED_RX_FLIT_SEQ_NUM == 10'd1), "RC_SEQ_NUM_RESET",
          $sformatf("RC NEXT_TX=%0d ACKD=%0d TX_ACKNAK=%0d NEXT_EXPECTED_RX=%0d", rc_dl.NEXT_TX_FLIT_SEQ_NUM,
                    rc_dl.ACKD_FLIT_SEQ_NUM, rc_dl.TX_ACKNAK_FLIT_SEQ_NUM, rc_dl.NEXT_EXPECTED_RX_FLIT_SEQ_NUM));
    check_result((ep_dl.NEXT_TX_FLIT_SEQ_NUM == 10'd1) && (ep_dl.ACKD_FLIT_SEQ_NUM == 10'h3FF) &&
          (ep_dl.TX_ACKNAK_FLIT_SEQ_NUM == 10'h3FF) && (ep_dl.NEXT_EXPECTED_RX_FLIT_SEQ_NUM == 10'd1), "EP_SEQ_NUM_RESET",
          $sformatf("EP NEXT_TX=%0d ACKD=%0d TX_ACKNAK=%0d NEXT_EXPECTED_RX=%0d", ep_dl.NEXT_TX_FLIT_SEQ_NUM,
                    ep_dl.ACKD_FLIT_SEQ_NUM, ep_dl.TX_ACKNAK_FLIT_SEQ_NUM, ep_dl.NEXT_EXPECTED_RX_FLIT_SEQ_NUM));
    check_result(!rc_dl.NAK_SCHEDULED && !rc_dl.REPLAY_SCHEDULED && !rc_dl.RC_REPLAY_IN_PROGRESS &&
          !ep_dl.NAK_SCHEDULED && !ep_dl.REPLAY_SCHEDULED && !ep_dl.EP_REPLAY_IN_PROGRESS &&
          (rc_dl.REPLAY_TIMEOUT_FLIT_COUNT == 0) && (rc_dl.FLIT_REPLAY_NUM == 0), "FLAGS_AND_TIMER_CLEARED",
          $sformatf("RC REPLAY_TIMEOUT_FLIT_COUNT=%0d FLIT_REPLAY_NUM=%0d", rc_dl.REPLAY_TIMEOUT_FLIT_COUNT, rc_dl.FLIT_REPLAY_NUM));

    rep_q_before = rc_dl.replayed_seq_q.size();
    link_up();

    step("traffic after the reset : 2 MemWr");
    tl_before    = ep_tl.n_tlp_rcvd;
    seq_q_before = rc_dl.tx_payload_seq_q.size();
    run_dll_seq(new_seq(), 2);
    wait_ep_tl_count(tl_before + 2, "2 MemWr after the reset");
    wait_link_idle();
    for (int unsigned i = seq_q_before; i < rc_dl.tx_payload_seq_q.size(); i++) sent.push_back(rc_dl.tx_payload_seq_q[i]);
    expected = '{10'd1, 10'd2};

    check_result(rc_dl.replayed_seq_q.size() == rep_q_before, "OLD_FLITS_NOT_REPLAYED",
          $sformatf("RC replayed %0d flit(s) after the reset (expected 0)", rc_dl.replayed_seq_q.size() - rep_q_before));
    check_result(sent == expected, "SEQ_NUM_STARTS_AT_1",
          $sformatf("RC sent SEQ_NUMs %p (expected %p)", sent, expected));
    check_result(ep_tl.n_tlp_rcvd - tl_before == 2, "TRAFFIC_OK_AFTER_RESET",
          $sformatf("EP TL got %0d TLPs (expected 2)", ep_tl.n_tlp_rcvd - tl_before));
  endtask

  //==========================================================================
  // HELPERS (only the ones this test uses)
  //==========================================================================

  task run_dll_seq(PCIe_RC_dll_reset_replay_buffer_clear_sequence seq, int unsigned n = 0);
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

  task link_down(int unsigned max_us = 20);
    step("LINK DOWN : Physical LinkUp = 0 on RC and EP");
    rc_dl.phy_linkup = 1'b0;
    ep_dl.phy_linkup = 1'b0;
    repeat (max_us * 1000) begin
      if ((rc_dl.DL_STATE == DL_INACTIVE) && (ep_dl.DL_STATE == DL_INACTIVE)) break;
      #1ns;
    end
    if ((rc_dl.DL_STATE != DL_INACTIVE) || (ep_dl.DL_STATE != DL_INACTIVE))
      `uvm_error("DLL_TEST", $sformatf("TIMEOUT : DL_INACTIVE not reached :: RC=%s EP=%s",
                 rc_dl.DL_STATE.name(), ep_dl.DL_STATE.name()))
    #100ns;   // DL reset is done right after DL_INACTIVE
  endtask

  task link_up(int unsigned max_us = 500);
    uvm_event rc_l0_ev = uvm_event_pool::get_global("rc_l0_to_dl_event");
    uvm_event ep_l0_ev = uvm_event_pool::get_global("ep_l0_to_dl_event");
    step("LINK UP : Physical LinkUp = 1 on RC and EP -> DL re-initialisation");
    rc_dl.phy_linkup = 1'b1;
    ep_dl.phy_linkup = 1'b1;
    rc_l0_ev.trigger();
    ep_l0_ev.trigger();
    repeat (max_us) begin
      if (rc_dl.dl_link_active && ep_dl.dl_link_active) break;
      #1us;
    end
    if (!rc_dl.dl_link_active || !ep_dl.dl_link_active)
      `uvm_error("DLL_TEST", $sformatf("TIMEOUT (%0d us) : DL_ACTIVE not reached again :: RC=%s EP=%s",
                 max_us, rc_dl.DL_STATE.name(), ep_dl.DL_STATE.name()))
    #1us;
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

//=========================================================================================
// File         : PCIe_gen6_dll_replay_buffer_limit_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_replay_buffer_limit_test.sv
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

// TX retry (replay) buffer limit   (PCIe 6.1 Sec 4.2.3.4.2.1 : max 511 unACKed flits)
//
//   The RC TX retry buffer limit is lowered to 4 flits for this test
//   (rc_dl.TX_RETRY_BUFFER_MAX_FLITS = 4) and the EP holds its ACKs.
//   RC is asked to send 8 MemWr :
//     4 MemWr go out, the buffer is full -> the RC must STOP sending new TLPs
//   The EP releases its ACKs -> the buffer empties -> the other 4 MemWr go out.
//
//   Checks : RC stopped at 4 unACKed flits, it waited for space,
//            all 8 MemWr delivered once, buffer empty at the end.

class PCIe_gen6_dll_replay_buffer_limit_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_dll_replay_buffer_limit_test)

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
  bit                       mwr_seq_busy;        // 1 while run_dll_seq_in_background() runs

  function new(string name = "PCIe_gen6_dll_replay_buffer_limit_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //--------------------------------------------------------------------------
  // build : warm-up traffic = PCIe_RC_dll_replay_buffer_limit_sequence with 2 MemWr (after enumeration)
  //--------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    PCIe_RC_controller_base_sequence::type_id::set_type_override(PCIe_RC_dll_replay_buffer_limit_sequence::get_type());
    PCIe_EP_controller_base_sequence::type_id::set_type_override(PCIe_EP_3DW_flit_sequence::get_type());
    super.build_phase(phase);
    // warm-up : the base test runs this test's own sequence once after enumeration, with 2 MemWr
    begin
      PCIe_RC_dll_replay_buffer_limit_sequence warmup_seq;
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
  localparam int unsigned BUFFER_LIMIT = 4;
  localparam int unsigned NUM_MWR      = 8;

  // this test's own sequence (a new object for every run)
  function PCIe_RC_dll_replay_buffer_limit_sequence new_seq();
    return PCIe_RC_dll_replay_buffer_limit_sequence::type_id::create("replay_buffer_limit_seq");
  endfunction

  task run_dll_test();
    int unsigned tl_before, waits_before;

    tl_before    = ep_tl.n_tlp_rcvd;
    waits_before = rc_dl.n_tx_retry_buffer_full_waits;

    step($sformatf("TX retry buffer limit = %0d flits, EP holds its ACKs, RC sends %0d MemWr", BUFFER_LIMIT, NUM_MWR));
    rc_dl.TX_RETRY_BUFFER_MAX_FLITS = BUFFER_LIMIT;
    ep_dl.set_ack_hold(1'b1);
    run_dll_seq_in_background(new_seq(), NUM_MWR);
    wait_ep_tl_count(tl_before + BUFFER_LIMIT, "MemWr up to the buffer limit");
    #3us;                                              // give the RC time to (wrongly) send more

    check_result(ep_tl.n_tlp_rcvd - tl_before == BUFFER_LIMIT, "RC_STOPPED_AT_BUFFER_LIMIT",
          $sformatf("EP TL got %0d TLPs while ACKs are held (expected %0d)", ep_tl.n_tlp_rcvd - tl_before, BUFFER_LIMIT));
    check_result(rc_dl.tx_retry_buffer.size() == BUFFER_LIMIT, "TX_RETRY_BUFFER_FULL",
          $sformatf("RC TX retry buffer holds %0d flits (limit %0d)", rc_dl.tx_retry_buffer.size(), BUFFER_LIMIT));
    check_result(rc_dl.n_tx_retry_buffer_full_waits > waits_before, "RC_WAITED_FOR_SPACE",
          $sformatf("RC waited %0d time(s) for buffer space", rc_dl.n_tx_retry_buffer_full_waits - waits_before));

    step("EP releases its ACKs -> the rest of the MemWr go out");
    ep_dl.set_ack_hold(1'b0);
    wait_mwr_seq_done();
    wait_ep_tl_count(tl_before + NUM_MWR, "all MemWr");
    wait_link_idle();

    check_result(ep_tl.n_tlp_rcvd - tl_before == NUM_MWR, "ALL_MWR_DELIVERED_ONCE",
          $sformatf("EP TL got %0d TLPs (expected %0d)", ep_tl.n_tlp_rcvd - tl_before, NUM_MWR));
    check_result(rc_dl.tx_retry_buffer.size() == 0, "TX_RETRY_BUFFER_EMPTY_AT_END",
          $sformatf("RC TX retry buffer holds %0d flits", rc_dl.tx_retry_buffer.size()));

    rc_dl.TX_RETRY_BUFFER_MAX_FLITS = `PCIe_MAX_UNACK_FLITS;   // back to the spec value
  endtask

  //==========================================================================
  // HELPERS (only the ones this test uses)
  //==========================================================================

  task run_dll_seq(PCIe_RC_dll_replay_buffer_limit_sequence seq, int unsigned n = 0);
    if (n != 0) seq.num_txn = n;
    `uvm_info("DLL_TEST", $sformatf("START SEQUENCE %s : %0d MemWr", seq.get_type_name(), seq.num_txn), UVM_NONE)
    seq.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
  endtask

  task run_dll_seq_in_background(PCIe_RC_dll_replay_buffer_limit_sequence seq, int unsigned n = 0);
    mwr_seq_busy = 1'b1;
    fork
      begin
        automatic PCIe_RC_dll_replay_buffer_limit_sequence bg_seq = seq;
        automatic int unsigned             bg_num = n;
        run_dll_seq(bg_seq, bg_num);
        mwr_seq_busy = 1'b0;
      end
    join_none
    #0;   // let the sequence start
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

  task wait_mwr_seq_done(int unsigned max_us = 200);
    repeat (max_us) begin
      if (!mwr_seq_busy) return;
      #1us;
    end
    `uvm_error("DLL_TEST", $sformatf("TIMEOUT (%0d us) : background MemWr sequence did not finish", max_us))
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

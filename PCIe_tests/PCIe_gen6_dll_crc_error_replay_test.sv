//=========================================================================================
// File         : PCIe_gen6_dll_crc_error_replay_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_crc_error_replay_test.sv
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

// CRC error -> STANDARD NAK -> STANDARD replay   (PCIe 6.1 Sec 4.2.3.4.2.1)
//
//   The EP uses Standard NAK only (USE_STANDARD_NAK_ONLY = 1).
//   RC sends 4 MemWr (A B C D), B is corrupted on the lanes (CRC error) :
//     A good  -> EP accepts A
//     B bad   -> EP drops B, waits for the next flit (NAK withdrawal)
//     C good  -> sequence number is wrong (B missing) -> STANDARD NAK(A)
//     D good  -> dropped (NAK outstanding)
//     RC      -> STANDARD replay : B and every flit after it, ORIGINAL sequence numbers
//     EP      -> accepts B C D in order, ACK
//
//   Checks : CRC error seen, 1 Standard NAK (0 Selective), 1 Standard replay that
//            starts at B and is in order, nothing stored in the RX retry buffer,
//            EP TL got the 4 MemWr exactly once.

class PCIe_gen6_dll_crc_error_replay_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_dll_crc_error_replay_test)

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
  bit [`PCIe_SEQ_NUM_W-1:0] lost_seq;            // sequence number of the first corrupted flit
  int unsigned              n_corrupted_flits;

  function new(string name = "PCIe_gen6_dll_crc_error_replay_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //--------------------------------------------------------------------------
  // build : warm-up traffic = PCIe_RC_dll_crc_error_replay_sequence with 2 MemWr (after enumeration)
  //--------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    PCIe_RC_controller_base_sequence::type_id::set_type_override(PCIe_RC_dll_crc_error_replay_sequence::get_type());
    PCIe_EP_controller_base_sequence::type_id::set_type_override(PCIe_EP_3DW_flit_sequence::get_type());
    super.build_phase(phase);
    // warm-up : the base test runs this test's own sequence once after enumeration, with 2 MemWr
    begin
      PCIe_RC_dll_crc_error_replay_sequence warmup_seq;
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
  function PCIe_RC_dll_crc_error_replay_sequence new_seq();
    return PCIe_RC_dll_crc_error_replay_sequence::type_id::create("crc_error_replay_seq");
  endfunction

  task run_dll_test();
    int unsigned              dl_err_before;   // [DL_ERR]
    int unsigned              tl_before, bad_before, std_nak_before, sel_nak_before;
    int unsigned              std_rep_before, rep_q_before, stored_before;
    bit [`PCIe_SEQ_NUM_W-1:0] replayed[$];

    ep_dl.USE_STANDARD_NAK_ONLY = 1'b1;
    tl_before      = ep_tl.n_tlp_rcvd;
    bad_before     = ep_dl.flit_rx_bad;
    std_nak_before = ep_dl.n_std_nak_scheduled;
    sel_nak_before = ep_dl.n_sel_nak_scheduled;
    std_rep_before = rc_dl.n_std_replay;
    rep_q_before   = rc_dl.replayed_seq_q.size();
    stored_before  = ep_dl.n_rx_flits_stored;

    dl_err_before = ep_dl.err_invalid_flit;   // [DL_ERR]
    step("4 MemWr, the 2nd one gets a CRC error -> STANDARD NAK -> STANDARD replay");
    allow_link_errors(1);
    fork
      run_dll_seq(new_seq());
      corrupt_rc_flits(2, 1);
    join
    wait_ep_tl_count(tl_before + 4, "4 MemWr after the replay");
    wait_link_idle();
    allow_link_errors(0);
    get_replayed_since(rep_q_before, replayed);

    check_result(ep_dl.flit_rx_bad > bad_before, "CRC_ERROR_DETECTED",
          $sformatf("EP saw %0d bad flit(s), corrupted SEQ_NUM=%0d", ep_dl.flit_rx_bad - bad_before, lost_seq));
    check_result((ep_dl.n_std_nak_scheduled - std_nak_before == 1) && (ep_dl.n_sel_nak_scheduled == sel_nak_before),
          "ONE_STANDARD_NAK", $sformatf("Standard NAK=%0d Selective NAK=%0d (expected 1 and 0)",
          ep_dl.n_std_nak_scheduled - std_nak_before, ep_dl.n_sel_nak_scheduled - sel_nak_before));
    check_result(rc_dl.n_std_replay - std_rep_before == 1, "ONE_STANDARD_REPLAY",
          $sformatf("RC started %0d Standard replay(s)", rc_dl.n_std_replay - std_rep_before));
    check_result((replayed.size() >= 2) && (replayed[0] == lost_seq) && seqs_in_order(replayed), "REPLAY_FROM_LOST_FLIT_IN_ORDER",
          $sformatf("replayed SEQ_NUMs %p, lost SEQ_NUM=%0d (B and every flit after it)", replayed, lost_seq));
    check_result(ep_dl.n_rx_flits_stored == stored_before, "NOTHING_STORED_WITH_STANDARD_NAK",
          $sformatf("EP RX retry buffer stored %0d flit(s)", ep_dl.n_rx_flits_stored - stored_before));
    check_result(ep_tl.n_tlp_rcvd - tl_before == 4, "EP_TL_GOT_4_MEMWR_ONCE",
          $sformatf("EP TL got %0d TLPs (expected 4)", ep_tl.n_tlp_rcvd - tl_before));

    ep_dl.USE_STANDARD_NAK_ONLY = 1'b0;

    // [DL_ERR] error logging (PCIe 6.1 Sec 6.2)
    check_result(ep_dl.err_invalid_flit - dl_err_before == 1, "INVALID_FLIT_ERROR_LOGGED",
          $sformatf("EP logged %0d invalid-flit error(s) (expected 1, Sec 6.2)", ep_dl.err_invalid_flit - dl_err_before));
  endtask

  //==========================================================================
  // HELPERS (only the ones this test uses)
  //==========================================================================

  task run_dll_seq(PCIe_RC_dll_crc_error_replay_sequence seq, int unsigned n = 0);
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

  task corrupt_rc_flits(int unsigned nth_payload, int unsigned n_flits,
                        bit [31:0] xor_mask = 32'h3333_3333, bit lane0_only = 1'b0);
    int unsigned payload_cnt = 0;
    while (payload_cnt < nth_payload) begin
      @(posedge rc_vif.tx_striped);                                         // new flit starts
      if (rc_pl.dl_flit_out[`PCIe_TLP_DATA_BYTE_W][7:6] == 2'b01)           // flit has a TLP
        payload_cnt++;
    end
    lost_seq = {rc_pl.dl_flit_out[`PCIe_TLP_DATA_BYTE_W][1:0],             // DLP0[1:0] + DLP1
                rc_pl.dl_flit_out[`PCIe_TLP_DATA_BYTE_W+1]};
    corrupt_current_flit(xor_mask, lane0_only);
    for (int unsigned i = 1; i < n_flits; i++) begin
      @(posedge rc_vif.tx_striped);                                         // next flit on the wire
      corrupt_current_flit(xor_mask, lane0_only);
    end
  endtask

  task corrupt_current_flit(bit [31:0] xor_mask, bit lane0_only);
    repeat (4) @(posedge rc_vif.pclk);                                      // middle of the flit
    #0.2ns;                                                                 // after driver, before PHY sample
    foreach (rc_vif.tx_data_striped[lane]) begin
      if (lane0_only && (lane != 0)) continue;
      rc_vif.tx_data_striped[lane] = rc_vif.tx_data_striped[lane] ^ xor_mask;
    end
    n_corrupted_flits++;
    `uvm_info("DLL_TEST", $sformatf("FLIT CORRUPTED on the RC lanes :: XOR=%08h %s :: flit SEQ field=%0d (first corrupted payload flit SEQ_NUM=%0d)",
              xor_mask, lane0_only ? "lane 0 only" : "all lanes",
              {rc_pl.dl_flit_out[`PCIe_TLP_DATA_BYTE_W][1:0], rc_pl.dl_flit_out[`PCIe_TLP_DATA_BYTE_W+1]}, lost_seq), UVM_NONE)
    PCIe_flow_log::print("INJECT", $sformatf("corrupt seq %0d (XOR %08h)", {rc_pl.dl_flit_out[`PCIe_TLP_DATA_BYTE_W][1:0], rc_pl.dl_flit_out[`PCIe_TLP_DATA_BYTE_W+1]}, xor_mask));   // [FLOW]
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

  // next sequence number : 1 .. 1023, then 1 again (0 is never used)
  function bit [`PCIe_SEQ_NUM_W-1:0] next_seq(bit [`PCIe_SEQ_NUM_W-1:0] s);
    return (s == 10'd1023) ? 10'd1 : s + 10'd1;
  endfunction

  // 1 when every number is the previous number + 1
  function bit seqs_in_order(bit [`PCIe_SEQ_NUM_W-1:0] q[$]);
    for (int i = 1; i < q.size(); i++)
      if (q[i] != next_seq(q[i-1])) return 1'b0;
    return 1'b1;
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

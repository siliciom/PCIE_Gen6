//=========================================================================================
// File         : PCIe_gen6_dll_ack_nak_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_ack_nak_test.sv
// Author       : Rani
// Date         : 2026-11-19
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

// Ack / Nak / Selective Replay test (PCIe 6.1 Sec 4.2.3.4.2.1)
//
//   Step 1 : RC sends 8 good MemWr           -> EP sends ACK
//   Step 2 : RC sends 4 MemWr (A B C D), B is corrupted on the RC lanes
//              A good  -> EP accepts A
//              B bad   -> EP drops B
//              C good  -> EP stores C, sends SELECTIVE NAK(A)   (= "replay only B")
//              D good  -> EP stores D
//              RC      -> replays ONLY B, with B's ORIGINAL sequence number
//              EP      -> accepts B, then gives C and D to the TL, sends ACK(D)
//
//   Checks at the end (check_phase) :
//     ACK_SENT_FOR_VALID_FLITS   EP sent ACK for step 1
//     ACK_RECEIVED               RC received ACK for step 1
//     ALL_FLITS_ACKED            last ACK sequence number = last sent sequence number
//     BAD_FLIT_DETECTED          EP saw the corrupted flit B
//     ONE_SELECTIVE_NAK          EP scheduled exactly 1 Selective NAK, 0 Standard NAK
//     NAK_RECEIVED               RC received the NAK
//     ONE_SELECTIVE_REPLAY       RC did exactly 1 Selective replay
//     REPLAYED_SEQ_IS_LOST_SEQ   RC replayed exactly 1 flit, with the sequence number of B
//     EP_STORED_AND_RELEASED     EP stored C (and D) and gave them to the TL after B
//     EP_TL_GOT_4_MEMWR          EP TL got 4 MemWr in step 2 (nothing lost, no duplicate)
//     INVALID_FLIT_ERROR_LOGGED  EP logged 1 invalid-flit error (Sec 6.2)
//     RETRY_BUFFERS_EMPTY        RC TX retry buffer and EP RX retry buffer are empty
//
// Needs +define+PCIE_GEN6_FEC_CRC

class PCIe_gen6_dll_ack_nak_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_dll_ack_nak_test)

  PCIe_RC_DL_model           rc_dl;
  PCIe_EP_DL_model           ep_dl;
  PCIe_EP_TL_model           ep_tl;
  PCIe_RC_PL_model           rc_pl;
  virtual PCIe_RC_interface  rc_vif;

  // ---- Step 1 values ----
  int unsigned ack_sent_before,  ack_sent_after;     // Acks sent by EP
  int unsigned ack_rcvd_before,  ack_rcvd_after;     // Acks received by RC
  int unsigned last_acked_seq,   last_sent_seq;      // RC sequence numbers after step 1

  // ---- Step 2 values ----
  int unsigned bad_flit_before,  bad_flit_after;     // bad flits seen by EP
  int unsigned err_flit_before,  err_flit_after;     // [DL_ERR] invalid-flit errors logged by EP
  int unsigned nak_rcvd_before,  nak_rcvd_after;     // Naks received by RC
  int unsigned sel_nak_before,   sel_nak_after;      // Selective NAKs scheduled by EP
  int unsigned std_nak_before,   std_nak_after;      // Standard NAKs scheduled by EP
  int unsigned sel_replay_before, sel_replay_after;  // Selective replays started by RC
  int unsigned std_replay_before, std_replay_after;  // Standard replays started by RC
  int unsigned replay_q_before;                      // size of rc_dl.replayed_seq_q before step 2
  int unsigned stored_before,    stored_after;       // flits stored in the EP RX retry buffer
  int unsigned released_before,  released_after;     // stored flits given to the EP TL
  int unsigned tl_mwr_before,    tl_mwr_after;       // TLPs received by the EP TL
  bit [`PCIe_SEQ_NUM_W-1:0] lost_seq;                // sequence number of the corrupted flit B
  bit [`PCIe_SEQ_NUM_W-1:0] replayed_seqs[$];        // sequence numbers RC replayed in step 2
  int unsigned rc_tx_retry_size_end, ep_rx_retry_size_end;

  int unsigned pass_cnt, fail_cnt;

  localparam int unsigned STEP2_NUM_MWR = 4;

  function new(string name = "PCIe_gen6_dll_ack_nak_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    `uvm_info("DLL_ACK_NAK_TEST", "ENTERED_INTO_DLL_ACK_NAK_TEST_BUILD_PHASE", UVM_LOW)
    PCIe_RC_controller_base_sequence::type_id::set_type_override(PCIe_RC_dll_ack_nak_sequence::get_type());
    PCIe_EP_controller_base_sequence::type_id::set_type_override(PCIe_EP_3DW_flit_sequence::get_type());
    super.build_phase(phase);
    if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_vif))
      `uvm_fatal("DLL_ACK_NAK_TEST", "PCIe_RC_INTERFACE not found")
`ifndef PCIE_GEN6_FEC_CRC
    `uvm_fatal("DLL_ACK_NAK_TEST", "compile with +define+PCIE_GEN6_FEC_CRC")
`endif
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    rc_dl = pcie_environment.rc_top_agent.rc_controller_agent.rc_dl_model;
    rc_pl = pcie_environment.rc_top_agent.rc_controller_agent.rc_pl_model;
    ep_dl = pcie_environment.ep_top_agent.ep_controller_agent.ep_dl_model;
    ep_tl = pcie_environment.ep_top_agent.ep_controller_agent.ep_tl_model;
    ep_dl.USE_STANDARD_NAK_ONLY = 1'b0;    // this test checks the SELECTIVE NAK
  endfunction

  task run_phase(uvm_phase phase);
    uvm_event seq_start = uvm_event_pool::get_global("dll_traffic_start");
    uvm_event seq_done  = uvm_event_pool::get_global("dll_traffic_done");
    PCIe_RC_dll_ack_nak_sequence step2_seq;
    int unsigned mwr_rcvd_before;

    fork
      super.run_phase(phase);              // link up + enumeration + step 1 sequence
    join_none
    phase.raise_objection(this);

    // ---------------- STEP 1 : 8 good MemWr -> Ack ----------------
    seq_start.wait_on();
    PCIe_flow_log::print("TEST STEP 1", "8 good MemWr -> ACK");   // [FLOW]
    mwr_rcvd_before = ep_tl.n_tlp_rcvd;
    ack_sent_before = ep_dl.flit_tx_cnt[PCIe_EP_DL_model::FLTC_ACK];
    ack_rcvd_before = rc_dl.flit_rx_cnt[PCIe_RC_DL_model::FLTC_ACK];

    seq_done.wait_on();
    wait_until_ep_gets(mwr_rcvd_before + 8, "step 1 : 8 MemWr");
    #2us;

    ack_sent_after = ep_dl.flit_tx_cnt[PCIe_EP_DL_model::FLTC_ACK];
    ack_rcvd_after = rc_dl.flit_rx_cnt[PCIe_RC_DL_model::FLTC_ACK];
    last_acked_seq = rc_dl.ACKD_FLIT_SEQ_NUM;
    last_sent_seq  = (rc_dl.NEXT_TX_FLIT_SEQ_NUM == 1) ? 1023 : rc_dl.NEXT_TX_FLIT_SEQ_NUM - 1;

    // ---------------- STEP 2 : 4 MemWr, 2nd one corrupted -> Selective NAK + replay ----------------
    bad_flit_before   = ep_dl.flit_rx_bad;
    err_flit_before   = ep_dl.err_invalid_flit;   // [DL_ERR]
    nak_rcvd_before   = rc_dl.flit_rx_cnt[PCIe_RC_DL_model::FLTC_NAK] + rc_dl.flit_rx_nak_piggy;
    sel_nak_before    = ep_dl.n_sel_nak_scheduled;
    std_nak_before    = ep_dl.n_std_nak_scheduled;
    sel_replay_before = rc_dl.n_sel_replay;
    std_replay_before = rc_dl.n_std_replay;
    replay_q_before   = rc_dl.replayed_seq_q.size();
    stored_before     = ep_dl.n_rx_flits_stored;
    released_before   = ep_dl.n_rx_flits_released;
    tl_mwr_before     = ep_tl.n_tlp_rcvd;

    expect_crc_errors(1);                  // CRC error is expected now -> print as INFO
    PCIe_flow_log::print("TEST STEP 2", "4 MemWr, 2nd corrupted -> SEL NAK + replay");   // [FLOW]
    step2_seq = PCIe_RC_dll_ack_nak_sequence::type_id::create("step2_seq");
    step2_seq.num_txn = STEP2_NUM_MWR;
    fork
      step2_seq.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
      corrupt_2nd_mwr_flit();
    join

    // Wait for : replay done + all 4 MemWr in the EP TL + everything ACKed
    wait_until_ep_gets(tl_mwr_before + STEP2_NUM_MWR, "step 2 : 4 MemWr after the replay");
    wait_until_all_acked();
    #1us;
    expect_crc_errors(0);                  // back to normal

    bad_flit_after   = ep_dl.flit_rx_bad;
    err_flit_after   = ep_dl.err_invalid_flit;   // [DL_ERR]
    nak_rcvd_after   = rc_dl.flit_rx_cnt[PCIe_RC_DL_model::FLTC_NAK] + rc_dl.flit_rx_nak_piggy;
    sel_nak_after    = ep_dl.n_sel_nak_scheduled;
    std_nak_after    = ep_dl.n_std_nak_scheduled;
    sel_replay_after = rc_dl.n_sel_replay;
    std_replay_after = rc_dl.n_std_replay;
    stored_after     = ep_dl.n_rx_flits_stored;
    released_after   = ep_dl.n_rx_flits_released;
    tl_mwr_after     = ep_tl.n_tlp_rcvd;
    for (int i = replay_q_before; i < rc_dl.replayed_seq_q.size(); i++)
      replayed_seqs.push_back(rc_dl.replayed_seq_q[i]);
    rc_tx_retry_size_end = rc_dl.tx_retry_buffer.size();
    ep_rx_retry_size_end = ep_dl.rx_retry_buffer.size();

    phase.drop_objection(this);
  endtask

  // wait until the EP TL received 'count' TLPs (max 200 us)
  task wait_until_ep_gets(int unsigned count, string what);
    repeat (200) begin
      if (ep_tl.n_tlp_rcvd >= count) return;
      #1us;
    end
    `uvm_error("DLL_ACK_NAK_TEST", {"TIMEOUT : EP TL did not receive ", what})
  endtask

  // wait until the RC replay is over and the EP has ACKed every RC flit (max 200 us)
  task wait_until_all_acked();
    repeat (200) begin
      if (!rc_dl.REPLAY_SCHEDULED && !rc_dl.RC_REPLAY_IN_PROGRESS &&
          (rc_dl.tx_retry_buffer.size() == 0) && !ep_dl.NAK_SCHEDULED) return;
      #1us;
    end
    `uvm_error("DLL_ACK_NAK_TEST", $sformatf("TIMEOUT : replay not finished :: RC REPLAY_SCHEDULED=%0b IN_PROGRESS=%0b TX_RETRY=%0d :: EP NAK_SCHEDULED=%0b",
               rc_dl.REPLAY_SCHEDULED, rc_dl.RC_REPLAY_IN_PROGRESS, rc_dl.tx_retry_buffer.size(), ep_dl.NAK_SCHEDULED))
  endtask

  // on = 1 : EP monitor / scoreboard CRC errors are printed as INFO
  // on = 0 : they are ERROR again
  function void expect_crc_errors(bit on);
    uvm_severity sev = on ? UVM_INFO : UVM_ERROR;
    pcie_environment.ep_top_agent.ep_controller_agent.ep_controller_monitor
      .set_report_severity_id_override(UVM_ERROR, "EP_CONTROLLER_MONITOR", sev);
    pcie_environment.ep_top_agent.ep_controller_agent.ep_pl_model
      .set_report_severity_id_override(UVM_ERROR, "PCIe_SCOREBOARD", sev);
    pcie_environment.pcie_scoreboard
      .set_report_severity_id_override(UVM_ERROR, "PCIe_SCOREBOARD", sev);
  endfunction

  // Corrupt the 2nd MemWr flit on the RC PIPE lanes (16 bytes).
  // XOR 0x33 (not ~) : lanes are precoded, a full invert cancels out and FEC fixes it.
  // The sequence number of that flit is saved in lost_seq.
  task corrupt_2nd_mwr_flit();
    int unsigned mwr_flit_cnt = 0;
    while (mwr_flit_cnt < 2) begin
      @(posedge rc_vif.tx_striped);                                         // new flit starts
      if (rc_pl.dl_flit_out[`PCIe_TLP_DATA_BYTE_W][7:6] == 2'b01)           // flit has a TLP
        mwr_flit_cnt++;
    end
    lost_seq = {rc_pl.dl_flit_out[`PCIe_TLP_DATA_BYTE_W][1:0],             // DLP0[1:0] + DLP1
                rc_pl.dl_flit_out[`PCIe_TLP_DATA_BYTE_W+1]};
    repeat (4) @(posedge rc_vif.pclk);                                      // middle of the flit
    #0.2ns;                                                                 // after driver, before PHY sample
    foreach (rc_vif.tx_data_striped[lane])
      rc_vif.tx_data_striped[lane] = rc_vif.tx_data_striped[lane] ^ 32'h3333_3333;
    `uvm_info("DLL_ACK_NAK_TEST", $sformatf("INJECTED_UNCORRECTABLE_ERROR on 2nd MemWr flit :: SEQ_NUM=%0d", lost_seq), UVM_NONE)
    PCIe_flow_log::print("INJECT", $sformatf("corrupt seq %0d (2nd MemWr)", lost_seq));   // [FLOW]
  endtask

  function void check_result(bit ok, string name, string detail);
    if (ok) begin pass_cnt++; `uvm_info("DLL_CHECK", {"PASS : ", name, " : ", detail}, UVM_NONE) end
    else    begin fail_cnt++; `uvm_error("DLL_CHECK", {"FAIL : ", name, " : ", detail}) end
    if (ok) PCIe_flow_log::print("CHECK", {"PASS ", name});                     // [FLOW]
    else    PCIe_flow_log::print("CHECK", {"FAIL ", name, " : ", detail});
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    // ---- Step 1 ----
    check_result(ack_sent_after > ack_sent_before, "ACK_SENT_FOR_VALID_FLITS",
          $sformatf("EP sent %0d Ack", ack_sent_after - ack_sent_before));
    check_result(ack_rcvd_after > ack_rcvd_before, "ACK_RECEIVED",
          $sformatf("RC received %0d Ack", ack_rcvd_after - ack_rcvd_before));
    check_result(last_acked_seq == last_sent_seq, "ALL_FLITS_ACKED",
          $sformatf("last acked seq=%0d, last sent seq=%0d", last_acked_seq, last_sent_seq));

    // ---- Step 2 ----
    check_result(bad_flit_after > bad_flit_before, "BAD_FLIT_DETECTED",
          $sformatf("EP saw %0d bad flit (corrupted SEQ_NUM=%0d)", bad_flit_after - bad_flit_before, lost_seq));
    check_result((sel_nak_after - sel_nak_before == 1) && (std_nak_after == std_nak_before), "ONE_SELECTIVE_NAK",
          $sformatf("EP scheduled %0d Selective NAK, %0d Standard NAK (expected 1 and 0)",
                    sel_nak_after - sel_nak_before, std_nak_after - std_nak_before));
    check_result(nak_rcvd_after > nak_rcvd_before, "NAK_RECEIVED",
          $sformatf("RC received %0d flit(s) carrying the NAK", nak_rcvd_after - nak_rcvd_before));
    check_result((sel_replay_after - sel_replay_before == 1) && (std_replay_after == std_replay_before), "ONE_SELECTIVE_REPLAY",
          $sformatf("RC started %0d Selective replay, %0d Standard replay (expected 1 and 0)",
                    sel_replay_after - sel_replay_before, std_replay_after - std_replay_before));
    check_result((replayed_seqs.size() == 1) && (replayed_seqs[0] == lost_seq), "REPLAYED_SEQ_IS_LOST_SEQ",
          $sformatf("RC replayed seq numbers %p, corrupted flit SEQ_NUM=%0d", replayed_seqs, lost_seq));
    // C is always stored. D is stored too, unless the replay of B reached the EP before D.
    check_result((stored_after - stored_before >= 1) && (stored_after - stored_before <= STEP2_NUM_MWR - 2) &&
                 (released_after - released_before == stored_after - stored_before),
          "EP_STORED_AND_RELEASED",
          $sformatf("EP stored %0d flit(s), released %0d flit(s) to TL (expected 1..%0d stored, all released)",
                    stored_after - stored_before, released_after - released_before, STEP2_NUM_MWR - 2));
    check_result(tl_mwr_after - tl_mwr_before == STEP2_NUM_MWR, "EP_TL_GOT_4_MEMWR",
          $sformatf("EP TL received %0d TLPs in step 2 (expected %0d : nothing lost, no duplicate)",
                    tl_mwr_after - tl_mwr_before, STEP2_NUM_MWR));
    check_result(err_flit_after - err_flit_before == 1, "INVALID_FLIT_ERROR_LOGGED",
          $sformatf("EP logged %0d invalid-flit error(s) (expected 1, Sec 6.2)", err_flit_after - err_flit_before));
    check_result((rc_tx_retry_size_end == 0) && (ep_rx_retry_size_end == 0), "RETRY_BUFFERS_EMPTY",
          $sformatf("RC TX retry buffer=%0d, EP RX retry buffer=%0d", rc_tx_retry_size_end, ep_rx_retry_size_end));

    `uvm_info("DLL_ACK_NAK_TEST", $sformatf("DLL_CHECK_SUMMARY : %0d PASS  %0d FAIL", pass_cnt, fail_cnt), UVM_NONE)
  endfunction

endclass

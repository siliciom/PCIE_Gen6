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

// Ack / Nak test (PCIe 6.1 Table 4-17)
//   Step 1 : RC sends 8 good MemWr         -> EP must send Ack
//   Step 2 : RC sends 4 MemWr, 1 corrupted -> EP must send Nak
// Needs +define+PCIE_GEN6_FEC_CRC

class PCIe_gen6_dll_ack_nak_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_dll_ack_nak_test)

  PCIe_RC_DL_model           rc_dl;
  PCIe_EP_DL_model           ep_dl;
  PCIe_EP_TL_model           ep_tl;
  PCIe_RC_PL_model           rc_pl;
  virtual PCIe_RC_interface  rc_vif;

  int unsigned ack_sent_before,  ack_sent_after;     // Acks sent by EP
  int unsigned ack_rcvd_before,  ack_rcvd_after;     // Acks received by RC
  int unsigned nak_sent_before,  nak_sent_after;     // Naks sent by EP
  int unsigned nak_rcvd_before,  nak_rcvd_after;     // Naks received by RC
  int unsigned bad_flit_before,  bad_flit_after;     // bad flits seen by EP
  int unsigned last_acked_seq,   last_sent_seq;      // RC sequence numbers after step 1
  int unsigned pass_cnt, fail_cnt;

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
    mwr_rcvd_before = ep_tl.n_tlp_rcvd;
    ack_sent_before = ep_dl.flit_tx_cnt[PCIe_EP_DL_model::FLTC_ACK];
    ack_rcvd_before = rc_dl.flit_rx_cnt[PCIe_RC_DL_model::FLTC_ACK];

    seq_done.wait_on();
    wait_until_ep_gets(mwr_rcvd_before + 8);
    #2us;

    ack_sent_after = ep_dl.flit_tx_cnt[PCIe_EP_DL_model::FLTC_ACK];
    ack_rcvd_after = rc_dl.flit_rx_cnt[PCIe_RC_DL_model::FLTC_ACK];
    last_acked_seq = rc_dl.ACKD_FLIT_SEQ_NUM;
    last_sent_seq  = (rc_dl.NEXT_TX_FLIT_SEQ_NUM == 1) ? 1023 : rc_dl.NEXT_TX_FLIT_SEQ_NUM - 1;

    // ---------------- STEP 2 : 4 MemWr, 1 corrupted -> Nak ----------------
    nak_sent_before = ep_dl.flit_tx_cnt[PCIe_EP_DL_model::FLTC_NAK] + ep_dl.flit_tx_nak_piggy;
    nak_rcvd_before = rc_dl.flit_rx_cnt[PCIe_RC_DL_model::FLTC_NAK] + rc_dl.flit_rx_nak_piggy;
    bad_flit_before = ep_dl.flit_rx_bad;

    expect_crc_errors(1);                  // CRC error is expected now -> print as INFO
    step2_seq = PCIe_RC_dll_ack_nak_sequence::type_id::create("step2_seq");
    step2_seq.num_txn = 4;
    fork
      step2_seq.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
      corrupt_2nd_mwr_flit();
    join
    #3us;
    expect_crc_errors(0);                  // back to normal

    nak_sent_after = ep_dl.flit_tx_cnt[PCIe_EP_DL_model::FLTC_NAK] + ep_dl.flit_tx_nak_piggy;
    nak_rcvd_after = rc_dl.flit_rx_cnt[PCIe_RC_DL_model::FLTC_NAK] + rc_dl.flit_rx_nak_piggy;
    bad_flit_after = ep_dl.flit_rx_bad;

    phase.drop_objection(this);
  endtask

  // wait until EP received 'count' TLPs (max 200 us)
  task wait_until_ep_gets(int unsigned count);
    repeat (200) begin
      if (ep_tl.n_tlp_rcvd >= count) return;
      #1us;
    end
    `uvm_error("DLL_ACK_NAK_TEST", "TIMEOUT : EP did not receive the 8 MemWr")
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
  task corrupt_2nd_mwr_flit();
    int unsigned mwr_flit_cnt = 0;
    while (mwr_flit_cnt < 2) begin
      @(posedge rc_vif.tx_striped);                                         // new flit starts
      if (rc_pl.dl_flit_out[`PCIe_TLP_DATA_BYTE_W][7:6] == 2'b01)           // flit has a TLP
        mwr_flit_cnt++;
    end
    repeat (4) @(posedge rc_vif.pclk);                                      // middle of the flit
    #0.2ns;                                                                 // after driver, before PHY sample
    foreach (rc_vif.tx_data_striped[lane])
      rc_vif.tx_data_striped[lane] = rc_vif.tx_data_striped[lane] ^ 32'h3333_3333;
    `uvm_info("DLL_ACK_NAK_TEST", "INJECTED_UNCORRECTABLE_ERROR on 2nd MemWr flit", UVM_NONE)
  endtask

  function void check_result(bit ok, string name, string detail);
    if (ok) begin pass_cnt++; `uvm_info("DLL_CHECK", {"PASS : ", name, " : ", detail}, UVM_NONE) end
    else    begin fail_cnt++; `uvm_error("DLL_CHECK", {"FAIL : ", name, " : ", detail}) end
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    check_result(ack_sent_after > ack_sent_before, "ACK_SENT_FOR_VALID_FLITS",
          $sformatf("EP sent %0d Ack", ack_sent_after - ack_sent_before));
    check_result(ack_rcvd_after > ack_rcvd_before, "ACK_RECEIVED",
          $sformatf("RC received %0d Ack", ack_rcvd_after - ack_rcvd_before));
    check_result(last_acked_seq == last_sent_seq, "ALL_FLITS_ACKED",
          $sformatf("last acked seq=%0d, last sent seq=%0d", last_acked_seq, last_sent_seq));
    check_result(bad_flit_after > bad_flit_before, "BAD_FLIT_DETECTED",
          $sformatf("EP saw %0d bad flit", bad_flit_after - bad_flit_before));
    check_result(nak_sent_after > nak_sent_before, "NAK_SENT_FOR_BAD_FLIT",
          $sformatf("EP sent %0d Nak", nak_sent_after - nak_sent_before));
    check_result(nak_rcvd_after > nak_rcvd_before, "NAK_RECEIVED",
          $sformatf("RC received %0d Nak", nak_rcvd_after - nak_rcvd_before));
    `uvm_info("DLL_ACK_NAK_TEST", $sformatf("DLL_CHECK_SUMMARY : %0d PASS  %0d FAIL", pass_cnt, fail_cnt), UVM_NONE)
  endfunction

endclass

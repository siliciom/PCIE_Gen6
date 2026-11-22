//=========================================================================================
// File         : PCIe_gen6_dll_base_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_base_test.sv
// Author       :
// Date         : 2026-11-21
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

// Common part of all DLL tests (Flit Mode, PCIe Base 6.0 Sec 4.2.3.4.2 / 4.2.3.4.4).
//   - turns on the real replay (RC) and the strict sequence number check (EP)
//   - runs the normal flow : link up -> enumeration -> test sequence
//   - when the test sequence starts it saves all counters, then calls
//     dll_test_body() : each test arms its error, triggers "dll_traffic_go",
//     waits and checks.
// Needs +define+PCIE_GEN6_FEC_CRC

class PCIe_gen6_dll_base_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_dll_base_test)

  PCIe_RC_DL_model            rc_dl;
  PCIe_EP_DL_model            ep_dl;
  PCIe_EP_TL_model            ep_tl;
  PCIe_EP_controller_monitor  ep_mon;

  uvm_event seq_start = uvm_event_pool::get_global("dll_traffic_start");
  uvm_event seq_go    = uvm_event_pool::get_global("dll_traffic_go");
  uvm_event seq_done  = uvm_event_pool::get_global("dll_traffic_done");

  int unsigned pass_cnt, fail_cnt;

  // counters saved when the test sequence starts (snap_counters)
  int unsigned tlp0, rx_mwr0, bad0, nak0, ack0;
  int unsigned rep_flit0, rep_ev0, stall0;
  int unsigned crc_ok0, crc_bad0, fec_cor0, fec_unc0;

  function new(string name = "PCIe_gen6_dll_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // child build_phase : set_dll_sequence(<its sequence>::get_type()) then super.build_phase()
  function void set_dll_sequence(uvm_object_wrapper seq_type);
    PCIe_RC_controller_base_sequence::type_id::set_type_override(seq_type);
    PCIe_EP_controller_base_sequence::type_id::set_type_override(PCIe_EP_3DW_flit_sequence::get_type());
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
`ifndef PCIE_GEN6_FEC_CRC
    `uvm_fatal(get_type_name(), "compile with +define+PCIE_GEN6_FEC_CRC")
`endif
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    rc_dl  = pcie_environment.rc_top_agent.rc_controller_agent.rc_dl_model;
    ep_dl  = pcie_environment.ep_top_agent.ep_controller_agent.ep_dl_model;
    ep_tl  = pcie_environment.ep_top_agent.ep_controller_agent.ep_tl_model;
    ep_mon = pcie_environment.ep_top_agent.ep_controller_agent.ep_controller_monitor;
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    rc_dl.replay_on_wire_en   = 1'b1;   // a Nak really replays the Tx retry buffer
    ep_dl.strict_rx_seq_check = 1'b1;   // only the expected sequence number is accepted
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    fork
      super.run_phase(phase);           // link up + enumeration + test sequence
    join_none
    seq_start.wait_on();                // test sequence is about to send
    snap_counters();
    `uvm_info(get_type_name(), "========== DLL TEST BODY START ==========", UVM_NONE)
    PCIe_flow_log::print("TEST", {get_type_name(), " : START"});   // [FLOW]
    dll_test_body();
    `uvm_info(get_type_name(), "========== DLL TEST BODY DONE  ==========", UVM_NONE)
    PCIe_flow_log::print("TEST", {get_type_name(), " : END"});     // [FLOW]
    #2us;
    phase.drop_objection(this);
  endtask

  // each test writes its own body
  virtual task dll_test_body();
    seq_go.trigger();
    seq_done.wait_on();
  endtask

  // ---------------------------------------------------------------------
  // helpers
  // ---------------------------------------------------------------------
  function void snap_counters();
    tlp0      = ep_tl.n_tlp_rcvd;
    rx_mwr0   = ep_dl.flit_rx_cnt[PCIe_EP_DL_model::FLTC_MWR];
    bad0      = ep_dl.flit_rx_bad;
    nak0      = naks_sent();
    ack0      = rc_dl.flit_rx_cnt[PCIe_RC_DL_model::FLTC_ACK];
    rep_flit0 = rc_dl.flit_tx_replay;
    rep_ev0   = rc_dl.n_replay_events;
    stall0    = rc_dl.n_tx_stall;
    crc_ok0   = ep_mon.n_crc_ok;
    crc_bad0  = ep_mon.n_crc_bad;
    fec_cor0  = ep_mon.fec_corrected_flit_cnt;
    fec_unc0  = ep_mon.fec_uncorrectable_flit_cnt;
  endfunction

  function int unsigned naks_sent();      // Naks sent by EP (own flit or piggy-backed)
    return ep_dl.flit_tx_cnt[PCIe_EP_DL_model::FLTC_NAK] + ep_dl.flit_tx_nak_piggy;
  endfunction

  function int unsigned tlps_rcvd();      // MemWr given to the EP TL since the start
    return ep_tl.n_tlp_rcvd - tlp0;
  endfunction

  function int unsigned flits_at_ep();    // MemWr flits that reached the EP DL (good + bad)
    return (ep_dl.flit_rx_cnt[PCIe_EP_DL_model::FLTC_MWR] - rx_mwr0) + (ep_dl.flit_rx_bad - bad0);
  endfunction

  function bit [`PCIe_SEQ_NUM_W-1:0] rc_last_sent_seq();
    return (rc_dl.NEXT_TX_FLIT_SEQ_NUM == 1) ? 10'd1023 : rc_dl.NEXT_TX_FLIT_SEQ_NUM - 1;
  endfunction

  task wait_tlps(int unsigned n);         // max 300 us
    repeat (300) begin
      if (tlps_rcvd() >= n) return;
      #1us;
    end
    `uvm_error(get_type_name(), $sformatf("TIMEOUT : EP TL got %0d of %0d MemWr", tlps_rcvd(), n))
  endtask

  task wait_flits_at_ep(int unsigned n);
    repeat (300) begin
      if (flits_at_ep() >= n) return;
      #1us;
    end
    `uvm_error(get_type_name(), $sformatf("TIMEOUT : only %0d of %0d flits reached the EP", flits_at_ep(), n))
  endtask

  task wait_retry_empty();
    repeat (300) begin
      if (rc_dl.tx_retry_buffer.size() == 0) return;
      #1us;
    end
    `uvm_error(get_type_name(), $sformatf("TIMEOUT : Tx retry buffer still has %0d flits", rc_dl.tx_retry_buffer.size()))
  endtask

  // on = 1 : injected link errors are expected -> monitor / scoreboard errors become INFO
  function void expect_link_errors(bit on);
    uvm_severity sev = on ? UVM_INFO : UVM_ERROR;
    ep_mon.set_report_severity_id_override(UVM_ERROR, "EP_CONTROLLER_MONITOR", sev);
    pcie_environment.ep_top_agent.ep_controller_agent.ep_pl_model
      .set_report_severity_id_override(UVM_ERROR, "PCIe_SCOREBOARD", sev);
    pcie_environment.pcie_scoreboard
      .set_report_severity_id_override(UVM_ERROR, "PCIe_SCOREBOARD", sev);
  endfunction

  function void dll_check(bit ok, string name, string detail);
    if (ok) begin pass_cnt++; `uvm_info("DLL_CHECK", {"PASS : ", name, " : ", detail}, UVM_NONE) end
    else    begin fail_cnt++; `uvm_error("DLL_CHECK", {"FAIL : ", name, " : ", detail}) end
    if (ok) PCIe_flow_log::print("CHECK", {"PASS ", name});                     // [FLOW]
    else    PCIe_flow_log::print("CHECK", {"FAIL ", name, " : ", detail});
  endfunction

  // checks used by every test at the end
  function void check_all_delivered(int unsigned n);
    dll_check(tlps_rcvd() == n, "ALL_TLPS_DELIVERED_ONCE",
          $sformatf("EP TL got %0d MemWr, expected %0d (no loss, no duplicate)", tlps_rcvd(), n));
    dll_check(ep_dl.n_order_err == 0, "DELIVERED_IN_ORDER",
          $sformatf("out-of-order accepts = %0d", ep_dl.n_order_err));
    dll_check(rc_dl.tx_retry_buffer.size() == 0, "TX_RETRY_BUFFER_EMPTY",
          $sformatf("%0d flits left", rc_dl.tx_retry_buffer.size()));
    dll_check(rc_dl.ACKD_FLIT_SEQ_NUM == rc_last_sent_seq(), "ALL_FLITS_ACKED",
          $sformatf("last acked seq=%0d last sent seq=%0d", rc_dl.ACKD_FLIT_SEQ_NUM, rc_last_sent_seq()));
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if ((pass_cnt + fail_cnt) == 0) `uvm_error("DLL_CHECK", "NO CHECK WAS DONE")
    `uvm_info(get_type_name(), $sformatf("DLL_CHECK_SUMMARY : %0d PASS  %0d FAIL", pass_cnt, fail_cnt), UVM_NONE)
  endfunction

endclass

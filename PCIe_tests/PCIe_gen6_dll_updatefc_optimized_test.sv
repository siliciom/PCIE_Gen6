//=========================================================================================
// File         : PCIe_gen6_dll_updatefc_optimized_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_updatefc_optimized_test.sv
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

// Optimized_Update_FC   (PCIe 6.1 Table 4-17 / Table 4-18, Sec 3.6.2.3)
//   In Flit Mode a credit update can be sent in DLP2..5 with DLP0[4] = 1 :
//     [31] 0  [30:28] VC  [27:20] Shared NPH  [19:12] Shared PH  [11:0] Shared PD
//   One Optimized_Update_FC returns the SHARED Posted (PH + PD) and NP header
//   credits together, instead of an UpdateFC DLLP.
//
//   The EP has only 4 SHARED Posted header credits and sends its credit
//   updates as Optimized_Update_FC (ep_dl.USE_OPT_UPDATE_FC = 1).
//   RC sends 8 MemWr : this is only possible if the RC understands the
//   Optimized_Update_FC and gets its Posted credits back.
//
//   Checks : EP sent Optimized_Update_FC, RC received every one, RC TL got
//            credit updates, all 8 MemWr delivered once.

class PCIe_gen6_dll_updatefc_optimized_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_dll_updatefc_optimized_test)

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

  function new(string name = "PCIe_gen6_dll_updatefc_optimized_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //--------------------------------------------------------------------------
  // build : warm-up traffic = PCIe_RC_dll_updatefc_optimized_sequence with 2 MemWr (after enumeration)
  //--------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    // small VC0 SHARED Posted header buffer in the EP : the RC runs out of credits quickly
    uvm_config_db#(int unsigned)::set(this, "*", "fc_test_p_hdr_credits", EP_P_HDR_CREDITS);
    PCIe_RC_controller_base_sequence::type_id::set_type_override(PCIe_RC_dll_updatefc_optimized_sequence::get_type());
    PCIe_EP_controller_base_sequence::type_id::set_type_override(PCIe_EP_3DW_flit_sequence::get_type());
    super.build_phase(phase);
    // warm-up : the base test runs this test's own sequence once after enumeration, with 2 MemWr
    begin
      PCIe_RC_dll_updatefc_optimized_sequence warmup_seq;
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
  // small VC0 SHARED Posted header buffer in the EP : the RC runs out of credits quickly
  localparam int unsigned EP_P_HDR_CREDITS = 4;


  // this test's own sequence (a new object for every run)
  function PCIe_RC_dll_updatefc_optimized_sequence new_seq();
    return PCIe_RC_dll_updatefc_optimized_sequence::type_id::create("updatefc_optimized_seq");
  endfunction

  task run_dll_test();
    int unsigned tl_before, opt_tx_before, opt_rx_before, peer_upd_before;

    tl_before       = ep_tl.n_tlp_rcvd;
    opt_tx_before   = ep_dl.n_opt_updfc_tx;
    opt_rx_before   = rc_dl.n_opt_updfc_rx;
    peer_upd_before = rc_tl.fc_n_peer_upd;

    step("EP returns Posted credits with Optimized_Update_FC, RC sends 8 MemWr (EP buffer = 4)");
    ep_dl.USE_OPT_UPDATE_FC = 1'b1;
    run_dll_seq_in_background(new_seq());
    wait_ep_tl_count(tl_before + 8, "8 MemWr (needs Optimized_Update_FC credits)", 100);
    wait_mwr_seq_done();
    wait_link_idle();
    #1us;

    check_result(ep_dl.n_opt_updfc_tx > opt_tx_before, "EP_SENT_OPTIMIZED_UPDATE_FC",
          $sformatf("EP sent %0d Optimized_Update_FC(s)", ep_dl.n_opt_updfc_tx - opt_tx_before));
    check_result(rc_dl.n_opt_updfc_rx - opt_rx_before == ep_dl.n_opt_updfc_tx - opt_tx_before, "RC_RECEIVED_EVERY_OPT_UPDATE_FC",
          $sformatf("EP sent %0d, RC received %0d", ep_dl.n_opt_updfc_tx - opt_tx_before, rc_dl.n_opt_updfc_rx - opt_rx_before));
    check_result(rc_tl.fc_n_peer_upd > peer_upd_before, "RC_TL_GOT_NEW_CREDITS",
          $sformatf("RC TL took %0d credit update(s)", rc_tl.fc_n_peer_upd - peer_upd_before));
    check_result(ep_tl.n_tlp_rcvd - tl_before == 8, "ALL_8_MWR_DELIVERED_ONCE",
          $sformatf("EP TL got %0d TLPs (expected 8)", ep_tl.n_tlp_rcvd - tl_before));

    ep_dl.USE_OPT_UPDATE_FC = 1'b0;
  endtask

  //==========================================================================
  // HELPERS (only the ones this test uses)
  //==========================================================================

  task run_dll_seq(PCIe_RC_dll_updatefc_optimized_sequence seq, int unsigned n = 0);
    if (n != 0) seq.num_txn = n;
    `uvm_info("DLL_TEST", $sformatf("START SEQUENCE %s : %0d MemWr", seq.get_type_name(), seq.num_txn), UVM_NONE)
    seq.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
  endtask

  task run_dll_seq_in_background(PCIe_RC_dll_updatefc_optimized_sequence seq, int unsigned n = 0);
    mwr_seq_busy = 1'b1;
    fork
      begin
        automatic PCIe_RC_dll_updatefc_optimized_sequence bg_seq = seq;
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

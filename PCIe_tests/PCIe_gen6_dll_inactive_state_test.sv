//=========================================================================================
// File         : PCIe_gen6_dll_inactive_state_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_inactive_state_test.sv
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

class PCIe_gen6_dll_inactive_state_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_dll_inactive_state_test)

  typedef enum {TR_INACTIVE, TR_FEATURE, TR_FC_INIT1, TR_FC_INIT2, TR_ACTIVE} dl_trace_e;

  PCIe_RC_DL_model                    rc_dl;
  PCIe_EP_DL_model                    ep_dl;
  virtual PCIe_RC_interface           rc_vif;
  virtual PCIe_EP_interface           ep_vif;
  PCIe_RC_basic_linkup_L0_sequence    rc_linkup_seq;
  PCIe_EP_basic_linkup_L0_sequence    ep_linkup_seq;

  localparam time DL_TEST_TIMEOUT       = 1ms;
  localparam int  LINKDOWN_SAMPLE_CYCLES = 32;

  bit test_passed;
  bit feature_exchange_expected;
  bit rc_saw_feature;
  bit rc_saw_init;
  bit rc_saw_active;
  bit ep_saw_feature;
  bit ep_saw_init;
  bit ep_saw_active;
  bit rc_illegal_transition;
  bit ep_illegal_transition;
  dl_trace_e rc_prev_state;
  dl_trace_e ep_prev_state;

  function new(string name = "PCIe_gen6_dll_inactive_state_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    run_enum_first = 1'b0;
    super.build_phase(phase);
    test_passed = 1'b1;
    if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_vif))
      `uvm_fatal("DLL_INACTIVE_TEST", "PCIe_RC_INTERFACE not found")
    if (!uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_vif))
      `uvm_fatal("DLL_INACTIVE_TEST", "PCIe_EP_INTERFACE not found")
  endfunction

  function void expect_cond(bit cond, string msg);
    if (!cond) begin
      test_passed = 1'b0;
      `uvm_error("DLL_INACTIVE_TEST", msg)
    end
    else begin
      `uvm_info("DLL_INACTIVE_TEST", {"PASS :: ", msg}, UVM_LOW)
    end
  endfunction

  task apply_dl_reset(string tag);
    rc_dl.DL_STATE                          = DL_INACTIVE;
    rc_dl.dl_init_substate                  = INIT_FC1;
    rc_dl.dl_link_active                    = 1'b0;
    rc_dl.phy_linkup                        = 1'b0;
    rc_dl.dllp_tx_pending                   = 1'b0;
    rc_dl.fc1_sent_count                    = 0;
    rc_dl.fc1_rcvd_count                    = 0;
    rc_dl.fc2_sent_count                    = 0;
    rc_dl.fc2_rcvd_count                    = 0;
    rc_dl.NEXT_TX_FLIT_SEQ_NUM              = 10'h001;
    rc_dl.TX_ACKNAK_FLIT_SEQ_NUM            = 10'h3FF;
    rc_dl.NEXT_EXPECTED_RX_FLIT_SEQ_NUM     = 10'h001;
    rc_dl.IMPLICIT_RX_FLIT_SEQ_NUM          = 10'h000;
    rc_dl.ACKD_FLIT_SEQ_NUM                 = 10'h3FF;
    rc_dl.TX_REPLAY_FLIT_SEQ_NUM            = 10'h000;
    rc_dl.NAK_IGNORE_FLIT_SEQ_NUM           = 10'h000;
    rc_dl.FLIT_REPLAY_NUM                   = '0;
    rc_dl.NAK_SCHEDULED                     = 1'b0;
    rc_dl.ACK_SCHEDULED                     = 1'b0;
    rc_dl.REPLAY_SCHEDULED                  = 1'b0;
    rc_dl.RC_REPLAY_IN_PROGRESS             = 1'b0;
    rc_dl.NAK_WITHDRAWAL_ALLOWED            = 1'b0;
    rc_dl.NON_IDLE_EXPLICIT_SEQ_NUM_FLIT_RCVD = 1'b0;
    rc_dl.RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = '0;
    rc_dl.NEXT_RX_FLIT_SEQ_NUM_TO_STORE     = '0;
    rc_dl.RX_RETRY_BUFFER_OVERFLOW          = 1'b0;
    rc_dl.ALLOW_SELECTIVE_OVERFLOW          = 1'b0;
    rc_dl.last_flit_was_payload             = 1'b0;
    rc_dl.fc_tx_allowed                     = 1'b0;
    rc_dl.tx_retry_buffer.delete();
    rc_dl.rx_retry_buffer.delete();
    rc_dl.fc_restart_init();

    ep_dl.DL_STATE                          = DL_INACTIVE;
    ep_dl.dl_init_substate                  = INIT_FC1;
    ep_dl.dl_link_active                    = 1'b0;
    ep_dl.phy_linkup                        = 1'b0;
    ep_dl.link_enabled                      = 1'b1;
    ep_dl.dllp_tx_pending                   = 1'b0;
    ep_dl.fc1_sent_count                    = 0;
    ep_dl.fc1_rcvd_count                    = 0;
    ep_dl.fc2_sent_count                    = 0;
    ep_dl.fc2_rcvd_count                    = 0;
    ep_dl.NEXT_TX_FLIT_SEQ_NUM              = 10'h001;
    ep_dl.TX_ACKNAK_FLIT_SEQ_NUM            = 10'h3FF;
    ep_dl.NEXT_EXPECTED_RX_FLIT_SEQ_NUM     = 10'h001;
    ep_dl.IMPLICIT_RX_FLIT_SEQ_NUM          = 10'h000;
    ep_dl.ACKD_FLIT_SEQ_NUM                 = 10'h3FF;
    ep_dl.TX_REPLAY_FLIT_SEQ_NUM            = 10'h000;
    ep_dl.NAK_IGNORE_FLIT_SEQ_NUM           = 10'h000;
    ep_dl.FLIT_REPLAY_NUM                   = '0;
    ep_dl.NAK_SCHEDULED                     = 1'b0;
    ep_dl.ACK_SCHEDULED                     = 1'b0;
    ep_dl.REPLAY_SCHEDULED                  = 1'b0;
    ep_dl.EP_REPLAY_IN_PROGRESS             = 1'b0;
    ep_dl.NAK_WITHDRAWAL_ALLOWED            = 1'b0;
    ep_dl.NON_IDLE_EXPLICIT_SEQ_NUM_FLIT_RCVD = 1'b0;
    ep_dl.RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = '0;
    ep_dl.NEXT_RX_FLIT_SEQ_NUM_TO_STORE     = '0;
    ep_dl.RX_RETRY_BUFFER_OVERFLOW          = 1'b0;
    ep_dl.ALLOW_SELECTIVE_OVERFLOW          = 1'b0;
    ep_dl.last_flit_was_payload             = 1'b0;
    ep_dl.fc_tx_allowed                     = 1'b1;
    ep_dl.tx_retry_buffer.delete();
    ep_dl.rx_retry_buffer.delete();
    ep_dl.fc_restart_init();

    `uvm_info("DLL_INACTIVE_TEST", $sformatf("%s :: APPLIED_DL_RESET", tag), UVM_LOW)
  endtask

  task check_reset_state(string tag);
    expect_cond(rc_dl.DL_STATE == DL_INACTIVE, $sformatf("%s :: RC entered DL_Inactive", tag));
    expect_cond(ep_dl.DL_STATE == DL_INACTIVE, $sformatf("%s :: EP entered DL_Inactive", tag));
    expect_cond(rc_dl.dl_link_active == 1'b0 && ep_dl.dl_link_active == 1'b0,
          $sformatf("%s :: DL_Down=1 and DL_Up=0 on RC and EP", tag));
    expect_cond(rc_dl.phy_linkup == 1'b0 && ep_dl.phy_linkup == 1'b0,
          $sformatf("%s :: Physical LinkUp=0 on RC and EP", tag));
    expect_cond(rc_dl.NEXT_TX_FLIT_SEQ_NUM == 10'h001 &&
          rc_dl.TX_ACKNAK_FLIT_SEQ_NUM == 10'h3FF &&
          rc_dl.ACKD_FLIT_SEQ_NUM == 10'h3FF &&
          rc_dl.NEXT_EXPECTED_RX_FLIT_SEQ_NUM == 10'h001 &&
          rc_dl.IMPLICIT_RX_FLIT_SEQ_NUM == 10'h000 &&
          rc_dl.TX_REPLAY_FLIT_SEQ_NUM == 10'h000 &&
          rc_dl.NAK_IGNORE_FLIT_SEQ_NUM == 10'h000 &&
          rc_dl.FLIT_REPLAY_NUM == '0,
          $sformatf("%s :: RC DL sequence state at defaults", tag));
    expect_cond(ep_dl.NEXT_TX_FLIT_SEQ_NUM == 10'h001 &&
          ep_dl.TX_ACKNAK_FLIT_SEQ_NUM == 10'h3FF &&
          ep_dl.ACKD_FLIT_SEQ_NUM == 10'h3FF &&
          ep_dl.NEXT_EXPECTED_RX_FLIT_SEQ_NUM == 10'h001 &&
          ep_dl.IMPLICIT_RX_FLIT_SEQ_NUM == 10'h000 &&
          ep_dl.TX_REPLAY_FLIT_SEQ_NUM == 10'h000 &&
          ep_dl.NAK_IGNORE_FLIT_SEQ_NUM == 10'h000 &&
          ep_dl.FLIT_REPLAY_NUM == '0,
          $sformatf("%s :: EP DL sequence state at defaults", tag));
    expect_cond(!rc_dl.NAK_SCHEDULED && !rc_dl.ACK_SCHEDULED && !rc_dl.REPLAY_SCHEDULED &&
          !rc_dl.RC_REPLAY_IN_PROGRESS && !rc_dl.NAK_WITHDRAWAL_ALLOWED &&
          !ep_dl.NAK_SCHEDULED && !ep_dl.ACK_SCHEDULED && !ep_dl.REPLAY_SCHEDULED &&
          !ep_dl.EP_REPLAY_IN_PROGRESS && !ep_dl.NAK_WITHDRAWAL_ALLOWED,
          $sformatf("%s :: ACK/NAK/replay flags cleared", tag));
    expect_cond(rc_dl.tx_retry_buffer.size() == 0 && rc_dl.rx_retry_buffer.size() == 0 &&
          ep_dl.tx_retry_buffer.size() == 0 && ep_dl.rx_retry_buffer.size() == 0,
          $sformatf("%s :: TX and RX retry buffers cleared", tag));
    expect_cond(ep_dl.link_enabled == 1'b1, $sformatf("%s :: TL did not disable the link", tag));
    `uvm_info("DLL_INACTIVE_TEST",
      $sformatf("%s :: RC DL_Down=%0b DL_Up=%0b | EP DL_Down=%0b DL_Up=%0b", tag,
                rc_dl.DL_STATE == DL_INACTIVE, rc_dl.dl_link_active,
                ep_dl.DL_STATE == DL_INACTIVE, ep_dl.dl_link_active), UVM_LOW)
  endtask

  task check_link_down_behavior();
    int rc_tlp_cnt;
    int rc_dllp_cnt;
    int ep_tlp_cnt;
    int ep_dllp_cnt;
    int rc_rx_cnt;
    int ep_rx_cnt;
    bit stable;

    rc_tlp_cnt = rc_vif.tx_payload_cnt;
    rc_dllp_cnt = rc_vif.tx_dllp_cnt;
    ep_tlp_cnt = ep_vif.tx_payload_cnt;
    ep_dllp_cnt = ep_vif.tx_dllp_cnt;
    rc_rx_cnt = rc_dl.flit_rx_total;
    ep_rx_cnt = ep_dl.flit_rx_total;
    stable = 1'b1;

    for (int i = 0; i < LINKDOWN_SAMPLE_CYCLES; i++) begin
      @(posedge rc_vif.pclk);
      if (rc_dl.DL_STATE != DL_INACTIVE || ep_dl.DL_STATE != DL_INACTIVE ||
          rc_dl.dl_link_active != 1'b0 || ep_dl.dl_link_active != 1'b0 ||
          rc_dl.phy_linkup != 1'b0 || ep_dl.phy_linkup != 1'b0) stable = 1'b0;
    end
    expect_cond(stable, "LINK_DOWN :: DLL remained in DL_Inactive while Physical LinkUp=0");
    expect_cond(rc_vif.tx_payload_cnt == rc_tlp_cnt && ep_vif.tx_payload_cnt == ep_tlp_cnt,
          "LINK_DOWN :: no TLP flits generated from the Transaction Layer");
    expect_cond(rc_vif.tx_dllp_cnt == rc_dllp_cnt && ep_vif.tx_dllp_cnt == ep_dllp_cnt,
          "LINK_DOWN :: no DLLP flits generated");
    expect_cond(rc_dl.flit_rx_total == rc_rx_cnt && ep_dl.flit_rx_total == ep_rx_cnt,
          "LINK_DOWN :: no flits accepted from the Physical Layer");
    expect_cond(rc_dl.tx_retry_buffer.size() == 0 && rc_dl.rx_retry_buffer.size() == 0 &&
          ep_dl.tx_retry_buffer.size() == 0 && ep_dl.rx_retry_buffer.size() == 0,
          "LINK_DOWN :: TLP and DLLP information was not retained in retry buffers");
  endtask

  function dl_trace_e map_rc_state();
    case (rc_dl.DL_STATE)
      DL_INACTIVE : return TR_INACTIVE;
      DL_FEATURE  : return TR_FEATURE;
      DL_INIT     : return (rc_dl.dl_init_substate == INIT_FC2) ? TR_FC_INIT2 : TR_FC_INIT1;
      default     : return TR_ACTIVE;
    endcase
  endfunction

  function dl_trace_e map_ep_state();
    case (ep_dl.DL_STATE)
      DL_INACTIVE : return TR_INACTIVE;
      DL_FEATURE  : return TR_FEATURE;
      DL_INIT     : return (ep_dl.dl_init_substate == INIT_FC2) ? TR_FC_INIT2 : TR_FC_INIT1;
      default     : return TR_ACTIVE;
    endcase
  endfunction

  function void check_transition(dl_trace_e from, dl_trace_e to, string side);
    bit legal;
    case (from)
      TR_INACTIVE : legal = (to == TR_INACTIVE) || (to == TR_FEATURE) ||
                            (!feature_exchange_expected && to == TR_FC_INIT1);
      TR_FEATURE  : legal = (to == TR_INACTIVE) || (to == TR_FEATURE) || (to == TR_FC_INIT1);
      TR_FC_INIT1 : legal = (to == TR_INACTIVE) || (to == TR_FC_INIT1) || (to == TR_FC_INIT2);
      TR_FC_INIT2 : legal = (to == TR_INACTIVE) || (to == TR_FC_INIT2) || (to == TR_ACTIVE);
      TR_ACTIVE   : legal = (to == TR_INACTIVE) || (to == TR_ACTIVE);
      default     : legal = 1'b0;
    endcase
    `uvm_info("DLL_INACTIVE_TEST", $sformatf("%s DLCMSM %s -> %s (%s)", side,
              from.name(), to.name(), legal ? "LEGAL" : "ILLEGAL"), UVM_LOW)
    if (!legal) begin
      test_passed = 1'b0;
      if (side == "RC") rc_illegal_transition = 1'b1;
      else ep_illegal_transition = 1'b1;
      `uvm_error("DLL_INACTIVE_TEST", $sformatf("%s illegal DLCMSM transition %s -> %s",
                 side, from.name(), to.name()))
    end
  endfunction

  task monitor_rc_transitions();
    dl_trace_e cur;
    rc_prev_state = map_rc_state();
    forever begin
      @(posedge rc_vif.pclk);
      cur = map_rc_state();
      if (cur != rc_prev_state) begin
        check_transition(rc_prev_state, cur, "RC");
        if (cur == TR_FEATURE) rc_saw_feature = 1'b1;
        if (cur == TR_FC_INIT1 || cur == TR_FC_INIT2) rc_saw_init = 1'b1;
        if (cur == TR_ACTIVE) rc_saw_active = 1'b1;
        rc_prev_state = cur;
      end
    end
  endtask

  task monitor_ep_transitions();
    dl_trace_e cur;
    ep_prev_state = map_ep_state();
    forever begin
      @(posedge ep_vif.pclk);
      cur = map_ep_state();
      if (cur != ep_prev_state) begin
        check_transition(ep_prev_state, cur, "EP");
        if (cur == TR_FEATURE) ep_saw_feature = 1'b1;
        if (cur == TR_FC_INIT1 || cur == TR_FC_INIT2) ep_saw_init = 1'b1;
        if (cur == TR_ACTIVE) ep_saw_active = 1'b1;
        ep_prev_state = cur;
      end
    end
  endtask

  task check_link_up_path();
    expect_cond(rc_dl.phy_linkup == 1'b1 && ep_dl.phy_linkup == 1'b1,
          "LINK_UP :: Physical LinkUp=1 on RC and EP");
    expect_cond(ep_dl.link_enabled == 1'b1, "LINK_UP :: Transaction Layer did not disable the link");
    rc_saw_active = rc_saw_active || (rc_dl.DL_STATE == DL_ACTIVE);
    ep_saw_active = ep_saw_active || (ep_dl.DL_STATE == DL_ACTIVE);
    expect_cond(rc_saw_active && ep_saw_active, "LINK_UP :: both DLCMSMs reached DL_Active");
    expect_cond(rc_dl.DL_STATE == DL_ACTIVE && rc_dl.dl_link_active == 1'b1,
          "LINK_UP :: RC DL_Up=1 in DL_Active");
    expect_cond(ep_dl.DL_STATE == DL_ACTIVE && ep_dl.dl_link_active == 1'b1,
          "LINK_UP :: EP DL_Up=1 in DL_Active");
    expect_cond(rc_saw_init && ep_saw_init, "LINK_UP :: both DLCMSMs passed through DL_Init");
    if (feature_exchange_expected) begin
      expect_cond(rc_saw_feature && ep_saw_feature,
            "LINK_UP :: data link feature exchange enabled, both DLCMSMs passed through DL_Feature");
    end
    else begin
      expect_cond(!rc_saw_feature && !ep_saw_feature,
            "LINK_UP :: data link feature exchange disabled, DL_Inactive -> DL_Init taken directly");
    end
    expect_cond(!rc_illegal_transition && !ep_illegal_transition,
          "LINK_UP :: all DLCMSM transitions followed PCIe Gen6 ordering");
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    rc_dl = pcie_environment.rc_top_agent.rc_controller_agent.rc_dl_model;
    ep_dl = pcie_environment.ep_top_agent.ep_controller_agent.ep_dl_model;
    feature_exchange_expected = ep_dl.link_enabled;

    apply_dl_reset("RESET");
    check_reset_state("RESET");
    check_link_down_behavior();

    rc_linkup_seq = PCIe_RC_basic_linkup_L0_sequence::type_id::create("rc_linkup_seq");
    ep_linkup_seq = PCIe_EP_basic_linkup_L0_sequence::type_id::create("ep_linkup_seq");

    fork : dl_link_up_run
      begin : rc_linkup_thread
        rc_linkup_seq.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
      end
      begin : ep_linkup_thread
        ep_linkup_seq.start(pcie_environment.ep_top_agent.ep_controller_agent.ep_controller_sequencer);
      end
      begin : dl_completion_thread
        fork : dl_wait_run
          monitor_rc_transitions();
          monitor_ep_transitions();
          begin
            wait (rc_dl.DL_STATE == DL_ACTIVE && rc_dl.dl_link_active &&
                  ep_dl.DL_STATE == DL_ACTIVE && ep_dl.dl_link_active);
            @(posedge rc_vif.pclk);
          end
          begin
            #DL_TEST_TIMEOUT;
            test_passed = 1'b0;
            `uvm_error("DLL_INACTIVE_TEST", "TIMEOUT :: DLCMSM did not reach DL_Active on RC and EP")
          end
        join_any
        disable fork;
        check_link_up_path();
      end
    join
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    if (test_passed)
      `uvm_info("DLL_INACTIVE_TEST", "PCIe_gen6_dll_inactive_state_test_PASS", UVM_NONE)
    else
      `uvm_error("DLL_INACTIVE_TEST", "PCIe_gen6_dll_inactive_state_test_FAIL")
  endfunction

endclass

//=========================================================================================
// File         : PCIe_gen6_dll_feature_negotiation_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_feature_negotiation_test.sv
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

class PCIe_gen6_dll_feature_negotiation_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_dll_feature_negotiation_test)

  PCIe_RC_DL_model                    rc_dl;
  PCIe_EP_DL_model                    ep_dl;
  virtual PCIe_RC_interface           rc_vif;
  virtual PCIe_EP_interface           ep_vif;
  PCIe_RC_basic_linkup_L0_sequence    rc_linkup_seq;
  PCIe_EP_basic_linkup_L0_sequence    ep_linkup_seq;

  localparam time DL_TEST_TIMEOUT = 1ms;

  bit test_passed;
  bit rc_seen_feature;
  bit ep_seen_feature;
  bit rc_seen_fc1;
  bit ep_seen_fc1;
  bit rc_feat_tx;
  bit rc_feat_rx;
  bit ep_feat_tx;
  bit ep_feat_rx;

  function new(string name = "PCIe_gen6_dll_feature_negotiation_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    run_enum_first = 1'b0;
    super.build_phase(phase);
    test_passed = 1'b0;
    if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_vif))
      `uvm_fatal("DLL_FEATURE_TEST", "PCIe_RC_INTERFACE not found")
    if (!uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_vif))
      `uvm_fatal("DLL_FEATURE_TEST", "PCIe_EP_INTERFACE not found")
  endfunction

  task monitor_feature_flow();
    forever begin
      @(posedge rc_vif.pclk);

      if (rc_dl.DL_STATE == DL_FEATURE) rc_seen_feature = 1'b1;
      if (ep_dl.DL_STATE == DL_FEATURE) ep_seen_feature = 1'b1;

      if (rc_seen_feature && (rc_dl.DL_STATE == DL_INIT) && (rc_dl.dl_init_substate == INIT_FC1))
        rc_seen_fc1 = 1'b1;
      if (ep_seen_feature && (ep_dl.DL_STATE == DL_INIT) && (ep_dl.dl_init_substate == INIT_FC1))
        ep_seen_fc1 = 1'b1;

      if (rc_dl.flit_tx_cnt[0] >= 1) rc_feat_tx = 1'b1; // FLTC_FEATURE
      if (rc_dl.flit_rx_cnt[0] >= 1) rc_feat_rx = 1'b1; // FLTC_FEATURE
      if (ep_dl.flit_tx_cnt[0] >= 1) ep_feat_tx = 1'b1; // FLTC_FEATURE
      if (ep_dl.flit_rx_cnt[0] >= 1) ep_feat_rx = 1'b1; // FLTC_FEATURE

      if (rc_seen_feature && ep_seen_feature &&
          rc_feat_tx && rc_feat_rx && ep_feat_tx && ep_feat_rx &&
          rc_seen_fc1 && ep_seen_fc1) begin
        `uvm_info("DLL_FEATURE_TEST",
                  $sformatf("OBSERVED :: RC feat=%0b tx=%0d rx=%0d fc1=%0b EP feat=%0b tx=%0d rx=%0d fc1=%0b RC=%s/%s EP=%s/%s",
                            rc_seen_feature, rc_dl.flit_tx_cnt[0], rc_dl.flit_rx_cnt[0], rc_seen_fc1,
                            ep_seen_feature, ep_dl.flit_tx_cnt[0], ep_dl.flit_rx_cnt[0], ep_seen_fc1,
                            rc_dl.DL_STATE.name(), rc_dl.dl_init_substate.name(),
                            ep_dl.DL_STATE.name(), ep_dl.dl_init_substate.name()),
                  UVM_LOW)
        test_passed = 1'b1;
        return;
      end
    end
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    rc_dl = pcie_environment.rc_top_agent.rc_controller_agent.rc_dl_model;
    ep_dl = pcie_environment.ep_top_agent.ep_controller_agent.ep_dl_model;

    rc_linkup_seq = PCIe_RC_basic_linkup_L0_sequence::type_id::create("rc_linkup_seq");
    ep_linkup_seq = PCIe_EP_basic_linkup_L0_sequence::type_id::create("ep_linkup_seq");

    fork
      begin : rc_linkup_thread
        rc_linkup_seq.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
      end
      begin : ep_linkup_thread
        ep_linkup_seq.start(pcie_environment.ep_top_agent.ep_controller_agent.ep_controller_sequencer);
      end
      begin : observe_thread
          monitor_feature_flow();
      end
    join_any
    disable fork;

    if (test_passed)
      `uvm_info("DLL_FEATURE_TEST", "RC and EP entered DL_FEATURE, exchanged Feature DLLPs, and reached DL_INIT.FC1 (implemented behavior)", UVM_LOW)
    else
      `uvm_error("DLL_FEATURE_TEST", "Required DL_FEATURE/Feature DLLP/FC1 sequence not fully observed")

    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    if (test_passed)
      `uvm_info("DLL_FEATURE_TEST", "PCIe_gen6_dll_feature_negotiation_test_PASS", UVM_NONE)
    else
      `uvm_error("DLL_FEATURE_TEST", "PCIe_gen6_dll_feature_negotiation_test_FAIL")
  endfunction

endclass

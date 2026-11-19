//=========================================================================================
// File         : PCIe_gen6_dll_active_state_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_active_state_test.sv
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

class PCIe_gen6_dll_active_state_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_dll_active_state_test)

  PCIe_RC_DL_model                    rc_dl;
  PCIe_EP_DL_model                    ep_dl;
  virtual PCIe_RC_interface           rc_vif;
  virtual PCIe_EP_interface           ep_vif;
  PCIe_RC_basic_linkup_L0_sequence    rc_linkup_seq;
  PCIe_EP_basic_linkup_L0_sequence    ep_linkup_seq;

  localparam time DL_TEST_TIMEOUT = 1ms;

  bit test_passed;
  bit rc_seen_inactive;
  bit rc_seen_feature;
  bit rc_seen_fc1;
  bit rc_seen_fc2;
  bit rc_seen_active;
  bit ep_seen_inactive;
  bit ep_seen_feature;
  bit ep_seen_fc1;
  bit ep_seen_fc2;
  bit ep_seen_active;

  function new(string name = "PCIe_gen6_dll_active_state_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    run_enum_first = 1'b0;
    super.build_phase(phase);
    test_passed = 1'b0;
    if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_vif))
      `uvm_fatal("DLL_ACTIVE_TEST", "PCIe_RC_INTERFACE not found")
    if (!uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_vif))
      `uvm_fatal("DLL_ACTIVE_TEST", "PCIe_EP_INTERFACE not found")
  endfunction

  task monitor_dll_states();
    forever begin
      @(posedge rc_vif.pclk);

      if (rc_dl.DL_STATE == DL_INACTIVE)
        rc_seen_inactive = 1'b1;
      if (rc_seen_inactive && (rc_dl.DL_STATE == DL_FEATURE))
        rc_seen_feature = 1'b1;
      if (rc_seen_feature && (rc_dl.DL_STATE == DL_INIT) && (rc_dl.dl_init_substate == INIT_FC1))
        rc_seen_fc1 = 1'b1;
      if (rc_seen_fc1 && (rc_dl.DL_STATE == DL_INIT) && (rc_dl.dl_init_substate == INIT_FC2))
        rc_seen_fc2 = 1'b1;
      if (rc_seen_fc2 && (rc_dl.DL_STATE == DL_ACTIVE) && rc_dl.dl_link_active)
        rc_seen_active = 1'b1;

      if (ep_dl.DL_STATE == DL_INACTIVE)
        ep_seen_inactive = 1'b1;
      if (ep_seen_inactive && (ep_dl.DL_STATE == DL_FEATURE))
        ep_seen_feature = 1'b1;
      if (ep_seen_feature && (ep_dl.DL_STATE == DL_INIT) && (ep_dl.dl_init_substate == INIT_FC1))
        ep_seen_fc1 = 1'b1;
      if (ep_seen_fc1 && (ep_dl.DL_STATE == DL_INIT) && (ep_dl.dl_init_substate == INIT_FC2))
        ep_seen_fc2 = 1'b1;
      if (ep_seen_fc2 && (ep_dl.DL_STATE == DL_ACTIVE) && ep_dl.dl_link_active)
        ep_seen_active = 1'b1;

      if (rc_seen_inactive && rc_seen_feature && rc_seen_fc1 && rc_seen_fc2 && rc_seen_active &&
          ep_seen_inactive && ep_seen_feature && ep_seen_fc1 && ep_seen_fc2 && ep_seen_active) begin
        `uvm_info("DLL_ACTIVE_TEST",
                  $sformatf("OBSERVED :: RC(inact=%0b,feat=%0b,fc1=%0b,fc2=%0b,active=%0b,dl_link_active=%0b) EP(inact=%0b,feat=%0b,fc1=%0b,fc2=%0b,active=%0b,dl_link_active=%0b) RC=%s/%s EP=%s/%s",
                            rc_seen_inactive, rc_seen_feature, rc_seen_fc1, rc_seen_fc2, rc_seen_active, rc_dl.dl_link_active,
                            ep_seen_inactive, ep_seen_feature, ep_seen_fc1, ep_seen_fc2, ep_seen_active, ep_dl.dl_link_active,
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
        fork
          monitor_dll_states();
          begin
            #DL_TEST_TIMEOUT;
            `uvm_error("DLL_ACTIVE_TEST",
                       $sformatf("TIMEOUT :: RC(inact=%0b,feat=%0b,fc1=%0b,fc2=%0b,active=%0b,dl_link_active=%0b) EP(inact=%0b,feat=%0b,fc1=%0b,fc2=%0b,active=%0b,dl_link_active=%0b) RC=%s/%s EP=%s/%s",
                                 rc_seen_inactive, rc_seen_feature, rc_seen_fc1, rc_seen_fc2, rc_seen_active, rc_dl.dl_link_active,
                                 ep_seen_inactive, ep_seen_feature, ep_seen_fc1, ep_seen_fc2, ep_seen_active, ep_dl.dl_link_active,
                                 rc_dl.DL_STATE.name(), rc_dl.dl_init_substate.name(),
                                 ep_dl.DL_STATE.name(), ep_dl.dl_init_substate.name()))
          end
        join_any
        disable fork;
      end
    join_any
    disable fork;

    if (test_passed)
      `uvm_info("DLL_ACTIVE_TEST", "RC and EP completed DL_INACTIVE->DL_FEATURE->DL_INIT.FC1->DL_INIT.FC2->DL_ACTIVE with dl_link_active asserted", UVM_LOW)
    else
      `uvm_error("DLL_ACTIVE_TEST", "RC and EP did not complete expected initialization flow to DL_ACTIVE with dl_link_active asserted")

    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    if (test_passed)
      `uvm_info("DLL_ACTIVE_TEST", "PCIe_gen6_dll_active_state_test_PASS", UVM_NONE)
    else
      `uvm_error("DLL_ACTIVE_TEST", "PCIe_gen6_dll_active_state_test_FAIL")
  endfunction

endclass

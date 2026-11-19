//=========================================================================================
// File         : PCIe_gen6_dll_initfc1_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_initfc1_test.sv
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

class PCIe_gen6_dll_initfc1_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_dll_initfc1_test)

  PCIe_RC_DL_model                    rc_dl;
  PCIe_EP_DL_model                    ep_dl;
  virtual PCIe_RC_interface           rc_vif;
  virtual PCIe_EP_interface           ep_vif;
  PCIe_RC_basic_linkup_L0_sequence    rc_linkup_seq;
  PCIe_EP_basic_linkup_L0_sequence    ep_linkup_seq;

  localparam time DL_TEST_TIMEOUT = 1ms;

  bit test_passed;
  bit rc_seen_fc1;
  bit ep_seen_fc1;

  function new(string name = "PCIe_gen6_dll_initfc1_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    run_enum_first = 1'b0;
    super.build_phase(phase);
    test_passed = 1'b0;
    if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_vif))
      `uvm_fatal("DLL_INITFC1_TEST", "PCIe_RC_INTERFACE not found")
    if (!uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_vif))
      `uvm_fatal("DLL_INITFC1_TEST", "PCIe_EP_INTERFACE not found")
  endfunction

  task monitor_fc1();
    forever begin
      @(posedge rc_vif.pclk);
      if ((rc_dl.DL_STATE == DL_INIT) && (rc_dl.dl_init_substate == INIT_FC1))
        rc_seen_fc1 = 1'b1;
      if ((ep_dl.DL_STATE == DL_INIT) && (ep_dl.dl_init_substate == INIT_FC1))
        ep_seen_fc1 = 1'b1;
      if (rc_seen_fc1 && ep_seen_fc1) begin
        `uvm_info("DLL_INITFC1_TEST",
                  $sformatf("OBSERVED :: RC_DL_STATE=%s RC_SUB=%s EP_DL_STATE=%s EP_SUB=%s",
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
          monitor_fc1();
      end
    join_any
    disable fork;

    if (test_passed)
      `uvm_info("DLL_INITFC1_TEST", "RC and EP reached DL_Init.FC1", UVM_LOW)
    else
      `uvm_error("DLL_INITFC1_TEST", "RC and EP did not both reach DL_Init.FC1")

    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    if (test_passed)
      `uvm_info("DLL_INITFC1_TEST", "PCIe_gen6_dll_initfc1_test_PASS", UVM_NONE)
    else
      `uvm_error("DLL_INITFC1_TEST", "PCIe_gen6_dll_initfc1_test_FAIL")
  endfunction

endclass

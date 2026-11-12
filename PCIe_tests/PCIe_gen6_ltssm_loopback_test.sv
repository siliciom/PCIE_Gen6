//=========================================================================================
// File         : PCIe_gen6_ltssm_loopback_test.sv
// Project      : PCIe_Gen6
// Description  : PCIe_tests/PCIe_gen6_ltssm_loopback_test.sv
//                RC/EP walk Configuration.Linkwidth.Start -> Loopback.Entry ->
//                Loopback.Active -> Loopback.Exit (TS1 with Loopback), no L0.
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

class PCIe_gen6_ltssm_loopback_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_ltssm_loopback_test)

  PCIe_RC_ltssm_loopback_sequence rc_seq;
  PCIe_EP_ltssm_loopback_sequence ep_seq;

  localparam time LTSSM_TIMEOUT = 20ms;

  function new(string name = "PCIe_gen6_ltssm_loopback_test",uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    // [ENUM_FIRST] LTSSM testcase : keep the old flow (this test's own first item
    // drives the LTSSM), so no link-up-first and no enumeration before it.
    run_enum_first = 1'b0;
    super.build_phase(phase);
    `uvm_info("LTSSM_LOOPBACK_TEST","Entered_ltssm_loopback_test_build_phase",UVM_LOW)
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("LTSSM_LOOPBACK_TEST","Starting_RC_and_EP_LTSSM_Loopback_sequences_concurrently",UVM_LOW)
    rc_seq = PCIe_RC_ltssm_loopback_sequence::type_id::create("rc_seq");
    ep_seq = PCIe_EP_ltssm_loopback_sequence::type_id::create("ep_seq");
    fork
      begin
        fork
          rc_seq.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
          ep_seq.start(pcie_environment.ep_top_agent.ep_controller_agent.ep_controller_sequencer);
        join
      end
      begin
        #(LTSSM_TIMEOUT);
        `uvm_error("LTSSM_LOOPBACK_TEST","LTSSM_Loopback_path_did_not_complete_before_timeout")
      end
    join_any
    disable fork;
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("LTSSM_LOOPBACK_TEST","PCIe_gen6_ltssm_loopback_test_DONE",UVM_LOW)
  endfunction

endclass


//=========================================================================================
// File         : PCIe_gen6_ltssm_timeout_test_defs.svh
// Project      : PCIE_Gen6
// Description  : Shared class template used by every per-state LTSSM timeout testcase.
//                Each testcase lives in its own file and only invokes this macro.
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

`ifndef PCIE_LTSSM_TIMEOUT_TEST_DEFS_SVH
`define PCIE_LTSSM_TIMEOUT_TEST_DEFS_SVH

`define PCIE_LTSSM_TIMEOUT_TEST(NAME, STATE, RC_SEQ, EP_SEQ, TMO) \
class PCIe_gen6_ltssm_timeout_``NAME``_test extends PCIe_base_test; \
  `uvm_component_utils(PCIe_gen6_ltssm_timeout_``NAME``_test) \
  PCIe_``RC_SEQ`` rc_seq; \
  PCIe_``EP_SEQ`` ep_seq; \
  localparam time LTSSM_TIMEOUT = TMO; \
  function new(string name = "PCIe_gen6_ltssm_timeout_``NAME``_test", uvm_component parent = null); \
    super.new(name, parent); \
  endfunction \
  function void build_phase(uvm_phase phase); \
    run_enum_first = 1'b0; \
    super.build_phase(phase); \
    `uvm_info("LTSSM_TIMEOUT_TEST","Entered_timeout_test_build_phase",UVM_LOW) \
  endfunction \
  task run_phase(uvm_phase phase); \
    phase.raise_objection(this); \
    `uvm_info("LTSSM_TIMEOUT_TEST","Starting_ltssm_timeout_test",UVM_LOW) \
    rc_seq = PCIe_``RC_SEQ``::type_id::create("rc_seq"); \
    ep_seq = PCIe_``EP_SEQ``::type_id::create("ep_seq"); \
    fork \
      begin \
        fork \
          rc_seq.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer); \
          ep_seq.start(pcie_environment.ep_top_agent.ep_controller_agent.ep_controller_sequencer); \
        join \
      end \
      begin \
        #(LTSSM_TIMEOUT); \
        `uvm_error("LTSSM_TIMEOUT_TEST","ltssm_timeout_test_did_not_complete_before_guard_timeout") \
      end \
    join_any \
    disable fork; \
    phase.drop_objection(this); \
  endtask \
  function void report_phase(uvm_phase phase); \
    super.report_phase(phase); \
    `uvm_info("LTSSM_TIMEOUT_TEST","PCIe_gen6_ltssm_timeout_test_DONE",UVM_LOW) \
  endfunction \
endclass

`endif


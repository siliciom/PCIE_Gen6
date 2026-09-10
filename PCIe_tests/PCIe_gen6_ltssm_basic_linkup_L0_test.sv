//=========================================================================================
// File         : PCIe_gen6_ltssm_basic_linkup_L0_test.sv
// Project      : PCIe_Gen6
// Description  : PCIe_tests/PCIe_gen6_ltssm_basic_linkup_L0_test.sv
// Author       : 
// Date         : 2026-08-21
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

//////////////////////////////////////////////////////////////////////////////////
// FILE:  PCIe_gen6_ltssm_basic_linkup_L0_test.sv
//////////////////////////////////////////////////////////////////////////////////

class PCIe_gen6_ltssm_basic_linkup_L0_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_ltssm_basic_linkup_L0_test)

   PCIe_RC_basic_linkup_L0_sequence rc_seq;
   PCIe_EP_basic_linkup_L0_sequence ep_seq;

   // Timeout (in ns) to prevent hanging if linkup never completes
   localparam time LINKUP_TIMEOUT = 100us;

   function new(string name = "PCIe_gen6_ltssm_basic_linkup_L0_test",uvm_component parent = null);
    super.new(name, parent);
   endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info("BASIC_LINKUP_L0_TEST","Entered_basic_linkup_L0_test_build_phase",UVM_LOW)
  endfunction

  task run_phase(uvm_phase phase);
    bit timed_out;
    timed_out = 1'b0;
    phase.raise_objection(this);
    `uvm_info("BASIC_LINKUP_L0_TEST","Starting_RC_and_EP_Basic_Linkup_L0_sequences_concurrently",UVM_LOW)
    rc_seq = PCIe_RC_basic_linkup_L0_sequence::type_id::create("rc_seq");
    ep_seq = PCIe_EP_basic_linkup_L0_sequence::type_id::create("ep_seq");
    fork
      rc_seq.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
      ep_seq.start(pcie_environment.ep_top_agent.ep_controller_agent.ep_controller_sequencer);
    join
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("BASIC_LINKUP_L0_TEST","PCIe_gen6_ltssm_basic_linkup_L0_test_PASS",UVM_LOW)
  endfunction

endclass

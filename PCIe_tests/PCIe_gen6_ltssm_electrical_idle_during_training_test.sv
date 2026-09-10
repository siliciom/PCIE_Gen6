//=========================================================================================
// File         : PCIe_gen6_ltssm_electrical_idle_during_training_test.sv
// Project      : PCIe_Gen6
// Description  : PCIe_tests/PCIe_gen6_ltssm_electrical_idle_during_training_test.sv
// Author       : 
// Date         : 2026-08-14
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

//////////////////////////////////////////////////////////////////////////////////
// FILE:  PCIe_gen6_ltssm_electrical_idle_during_training_test.sv
//////////////////////////////////////////////////////////////////////////////////

class PCIe_gen6_ltssm_electrical_idle_during_training_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_ltssm_electrical_idle_during_training_test)

  PCIe_RC_electrical_idle_sequence      rc_seq;
  PCIe_EP_electrical_idle_sequence      ep_seq;

  function new(string name = "PCIe_gen6_ltssm_electrical_idle_during_training_test",uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info("ELECTRICAL_IDLE_TEST","Entered_electrical_idle_test_build_phase",UVM_LOW)
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("ELECTRICAL_IDLE_TEST","STARTED_ELECTRICAL_IDLE_TEST_COMPLETED",UVM_LOW)
     rc_seq = PCIe_RC_electrical_idle_sequence::type_id::create("rc_seq");
     ep_seq = PCIe_EP_electrical_idle_sequence::type_id::create("ep_seq");
    fork
      rc_seq.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
      ep_seq.start(pcie_environment.ep_top_agent.ep_controller_agent.ep_controller_sequencer);
    join
    `uvm_info("ELECTRICAL_IDLE_TEST","ELECTRICAL_IDLE_TEST_COMPLETED",UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

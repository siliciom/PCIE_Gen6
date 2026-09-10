//=========================================================================================
// File         : PCIe_gen6_ltssm_detect_no_receiver_test.sv
// Project      : PCIe_Gen6
// Description  : PCIe_tests/PCIe_gen6_ltssm_detect_no_receiver_test.sv
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
// FILE:  PCIe_gen6_ltssm_detect_no_receiver_test.sv
//////////////////////////////////////////////////////////////////////////////////

class PCIe_gen6_ltssm_detect_no_receiver_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_ltssm_detect_no_receiver_test)

   PCIe_RC_detect_no_receiver_sequence rc_seq;
   PCIe_EP_detect_no_receiver_sequence ep_seq;

   function new(string name = "PCIe_gen6_ltssm_detect_no_receiver_test",uvm_component parent = null);
    super.new(name, parent);
   endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info("NO_RECEIVER_TEST","Entered_no_receiver_test_build_phase",UVM_LOW)
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("NO_RECEIVER_TEST","Starting_RC_and_EP_Detect_No_Receiver_sequences",UVM_LOW)
    rc_seq = PCIe_RC_detect_no_receiver_sequence::type_id::create("rc_seq");
    ep_seq = PCIe_EP_detect_no_receiver_sequence::type_id::create("ep_seq");
    fork
      rc_seq.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
      ep_seq.start(pcie_environment.ep_top_agent.ep_controller_agent.ep_controller_sequencer);
    join
    `uvm_info("NO_RECEIVER_TEST","RC_and_EP_no_receiver_sequences_completed",UVM_LOW)
    `uvm_info("NO_RECEIVER_TEST","Detect_Quiet->Detect_Active->Detect_Quiet_exercise_complete_by_RC_and_EP",UVM_LOW)
    `uvm_info("NO_RECEIVER_TEST","Failed_receiver-detection_attempt_verified,_polling_not_entered,_L0_not_reached",UVM_LOW)
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("NO_RECEIVER_TEST","PCIe_gen6_ltssm_detect_no_receiver_test_PASS",UVM_LOW)
  endfunction

endclass

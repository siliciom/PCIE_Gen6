//=========================================================================================
// File         : PCIe_gen6_enumeration_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_enumeration_test.sv
//                Runs PCIe_RC_enumeration_sequence on the RC controller sequencer.
//                Run with:  +UVM_TESTNAME=PCIe_gen6_enumeration_test
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

class PCIe_gen6_enumeration_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_enumeration_test)

  function new(string name="PCIe_gen6_enumeration_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    `uvm_info("PCIE_GEN6_ENUMERATION_TEST","ENTERED_INTO_PCIE_GEN6_ENUMERATION_TEST_BUILD_PHASE", UVM_LOW)
    // The base test's rc_controller_sequence handle will run the enumeration sequence.
    PCIe_RC_controller_base_sequence::type_id::set_type_override(
        PCIe_RC_enumeration_sequence::get_type());

    // Same EP sequence as the other Flit tests (it only brings the EP link up).
    PCIe_EP_controller_base_sequence::type_id::set_type_override(
        PCIe_EP_3DW_flit_sequence::get_type());
    super.build_phase(phase);
    `uvm_info("PCIE_GEN6_ENUMERATION_TEST","EXIT_FROM_PCIE_GEN6_ENUMERATION_TEST_BUILD_PHASE", UVM_LOW)
  endfunction

endclass




//=========================================================================================
// File         : PCIe_RC_flit_nop_test.sv
// Project      : PCIe_Gen6
// Description  : PCIe_tests/PCIe_RC_flit_nop_test.sv
// Author       :
// Date         : 2026-09-15
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

//////////////////////////////////////////////////////////////////////////////////
// FILE:  PCIe_RC_flit_nop_test.sv
// DESC:  RC -> EP.  Test that drives an RC NOP Flit (PCIe Base 6.1 Table
//        4-16). Uses a factory type-override so the base test's
//        rc_controller_sequence handle runs PCIe_RC_flit_nop_sequence::body().
//        Run with:  +UVM_TESTNAME=PCIe_RC_flit_nop_test
//////////////////////////////////////////////////////////////////////////////////

class PCIe_RC_flit_nop_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_RC_flit_nop_test)

  function new(string name="PCIe_RC_flit_nop_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    `uvm_info("PCIe_RC_FLIT_NOP_TEST","ENTERED_INTO_RC_FLIT_NOP_TEST_BUILD_PHASE", UVM_LOW)
    PCIe_RC_controller_base_sequence::type_id::set_type_override(
        PCIe_RC_flit_nop_sequence::get_type());
    PCIe_EP_controller_base_sequence::type_id::set_type_override(
        PCIe_RC_3DW_NonFlit_IORd_sequence::get_type());
    super.build_phase(phase);
    `uvm_info("PCIe_RC_FLIT_NOP_TEST","EXIT_FROM_RC_FLIT_NOP_TEST_BUILD_PHASE", UVM_LOW)
  endfunction

endclass

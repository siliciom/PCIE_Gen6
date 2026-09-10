//=========================================================================================
// File         : PCIe_3DW_flit_test.sv
// Project      : PCIe_Gen6
// Description  : PCIe_tests/PCIe_3DW_flit_test.sv
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
// FILE:  PCIe_3DW_flit_test.sv
// DESC:  Test that drives 3DW-header (32-bit address) Memory traffic. Uses a
//        factory type-override so the base test's rc_controller_sequence handle
//        runs PCIe_RC_3DW_flit_sequence::body().
//        Run with:  +UVM_TESTNAME=PCIe_3DW_flit_test
//////////////////////////////////////////////////////////////////////////////////

class PCIe_3DW_flit_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_3DW_flit_test)

  function new(string name="PCIe_3DW_flit_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    `uvm_info("PCIe_3DW_TEST","ENTERED_INTO_3DW_TEST_BUILD_PHASE", UVM_LOW)
    // Redirect the RC controller sequence to the 3DW variant before build.
    PCIe_RC_controller_base_sequence::type_id::set_type_override(
        PCIe_RC_3DW_flit_sequence::get_type());
    super.build_phase(phase);
    `uvm_info("PCIe_3DW_TEST","EXIT_FROM_3DW_TEST_BUILD_PHASE", UVM_LOW)
  endfunction

endclass

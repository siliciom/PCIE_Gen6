//=========================================================================================
// File         : PCIe_gen6_3DW_NonFlit_CFGWr0_followed_CFGRd0_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_3DW_NonFlit_CFGWr0_followed_CFGRd0_test.sv
// Author       :
// Date         : 2026-09-10
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

//////////////////////////////////////////////////////////////////////////////////
// FILE:  PCIe_gen6_3DW_NonFlit_CFGWr0_followed_CFGRd0_test.sv
// DESC:  Configuration Type0 Write immediately followed by Configuration Type0 Read, NonFlit mode.
//        Uses a factory type-override so the base test's rc_controller_sequence
//        handle runs PCIe_RC_3DW_NonFlit_CFGWr0_followed_CFGRd0_sequence::body().
//        Run with:  +UVM_TESTNAME=PCIe_gen6_3DW_NonFlit_CFGWr0_followed_CFGRd0_test
//////////////////////////////////////////////////////////////////////////////////

class PCIe_gen6_3DW_NonFlit_CFGWr0_followed_CFGRd0_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_3DW_NonFlit_CFGWr0_followed_CFGRd0_test)

  function new(string name="PCIe_gen6_3DW_NonFlit_CFGWr0_followed_CFGRd0_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    `uvm_info("PCIE_GEN6_3DW_NONFLIT_CFGWR0_FOLLOWED_CFGRD0_TEST","ENTERED_INTO_PCIE_GEN6_3DW_NONFLIT_CFGWR0_FOLLOWED_CFGRD0_TEST_BUILD_PHASE", UVM_LOW)
    // Redirect the RC controller sequence to the PCIe_RC_3DW_NonFlit_CFGWr0_followed_CFGRd0_sequence variant before build.
    PCIe_RC_controller_base_sequence::type_id::set_type_override(
        PCIe_RC_3DW_NonFlit_CFGWr0_followed_CFGRd0_sequence::get_type());
    super.build_phase(phase);
    `uvm_info("PCIE_GEN6_3DW_NONFLIT_CFGWR0_FOLLOWED_CFGRD0_TEST","EXIT_FROM_PCIE_GEN6_3DW_NONFLIT_CFGWR0_FOLLOWED_CFGRD0_TEST_BUILD_PHASE", UVM_LOW)
  endfunction

endclass

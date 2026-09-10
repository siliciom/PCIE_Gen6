//=========================================================================================
// File         : PCIe_gen6_3DW_Flit_MemWr_followed_MemRd_MaxPayload_test.sv
// Project      : PCIe_Gen6
// Description  : PCIe_tests/PCIe_gen6_3DW_Flit_MemWr_followed_MemRd_MaxPayload_test.sv
// Author       :
// Date         : 2026-09-09
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

//////////////////////////////////////////////////////////////////////////////////
// FILE:  PCIe_gen6_3DW_Flit_MemWr_followed_MemRd_MaxPayload_test.sv
// DESC:  3DW-header MemWr immediately followed by MemRd to the same address, Flit mode, maxpayload.
//        Uses a factory type-override so the base test's rc_controller_sequence
//        handle runs PCIe_RC_3DW_Flit_MemWr_followed_MemRd_MaxPayload_sequence::body().
//        Run with:  +UVM_TESTNAME=PCIe_gen6_3DW_Flit_MemWr_followed_MemRd_MaxPayload_test
//////////////////////////////////////////////////////////////////////////////////

class PCIe_gen6_3DW_Flit_MemWr_followed_MemRd_MaxPayload_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_3DW_Flit_MemWr_followed_MemRd_MaxPayload_test)

  function new(string name="PCIe_gen6_3DW_Flit_MemWr_followed_MemRd_MaxPayload_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    `uvm_info("PCIE_GEN6_3DW_FLIT_MEMWR_FOLLOWED_MEMRD_MAXPAYLOAD_TEST","ENTERED_INTO_PCIE_GEN6_3DW_FLIT_MEMWR_FOLLOWED_MEMRD_MAXPAYLOAD_TEST_BUILD_PHASE", UVM_LOW)
    // Redirect the RC controller sequence to the PCIe_RC_3DW_Flit_MemWr_followed_MemRd_MaxPayload_sequence variant before build.
    PCIe_RC_controller_base_sequence::type_id::set_type_override(
        PCIe_RC_3DW_Flit_MemWr_followed_MemRd_MaxPayload_sequence::get_type());
    super.build_phase(phase);
    `uvm_info("PCIE_GEN6_3DW_FLIT_MEMWR_FOLLOWED_MEMRD_MAXPAYLOAD_TEST","EXIT_FROM_PCIE_GEN6_3DW_FLIT_MEMWR_FOLLOWED_MEMRD_MAXPAYLOAD_TEST_BUILD_PHASE", UVM_LOW)
  endfunction

endclass

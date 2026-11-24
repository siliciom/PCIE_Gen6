//=========================================================================================
// File         : PCIe_RC_3DW_OHC_E1_Flit_MemWr_MinPayload_test.sv
// Project      : PCIe_Gen6
// Description  : PCIe_tests/PCIe_RC_3DW_OHC_E1_Flit_MemWr_MinPayload_test.sv
// Author       :
// Date         : 2026-11-24
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

//////////////////////////////////////////////////////////////////////////////////
// FILE:  PCIe_RC_3DW_OHC_E1_Flit_MemWr_MinPayload_test.sv
// DESC:  3DW-header Memory Write, Flit mode, min payload (1 DW), with OHC-E1
//        See PCIe_RC_3DW_OHC_E1_Flit_MemWr_MinPayload_sequence.sv for the OHC layout.
//        Uses a factory type-override so the base test's rc_controller_sequence
//        handle runs PCIe_RC_3DW_OHC_E1_Flit_MemWr_MinPayload_sequence::body().
//        Run with:  +UVM_TESTNAME=PCIe_RC_3DW_OHC_E1_Flit_MemWr_MinPayload_test
//////////////////////////////////////////////////////////////////////////////////

class PCIe_RC_3DW_OHC_E1_Flit_MemWr_MinPayload_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_RC_3DW_OHC_E1_Flit_MemWr_MinPayload_test)

  function new(string name="PCIe_RC_3DW_OHC_E1_Flit_MemWr_MinPayload_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    `uvm_info("PCIE_RC_3DW_OHC_E1_FLIT_MEMWR_MINPAYLOAD_TEST","ENTERED_INTO_PCIE_RC_3DW_OHC_E1_FLIT_MEMWR_MINPAYLOAD_TEST_BUILD_PHASE", UVM_LOW)
    // Redirect the RC controller sequence to PCIe_RC_3DW_OHC_E1_Flit_MemWr_MinPayload_sequence
    PCIe_RC_controller_base_sequence::type_id::set_type_override(
        PCIe_RC_3DW_OHC_E1_Flit_MemWr_MinPayload_sequence::get_type());

    // Override the EP controller sequence to run the common 3DW-Flit EP sequence.
    PCIe_EP_controller_base_sequence::type_id::set_type_override(
        PCIe_EP_3DW_flit_sequence::get_type());
    super.build_phase(phase);
    `uvm_info("PCIE_RC_3DW_OHC_E1_FLIT_MEMWR_MINPAYLOAD_TEST","EXIT_FROM_PCIE_RC_3DW_OHC_E1_FLIT_MEMWR_MINPAYLOAD_TEST_BUILD_PHASE", UVM_LOW)
  endfunction

endclass

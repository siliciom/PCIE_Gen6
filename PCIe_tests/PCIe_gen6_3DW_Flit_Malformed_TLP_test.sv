//=========================================================================================
// File         : PCIe_gen6_3DW_Flit_Malformed_TLP_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_3DW_Flit_Malformed_TLP_test.sv
// Author       :
// Date         : 2026-11-20
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

////////////////////////////////////////////////////////////////
// FILE:  PCIe_gen6_3DW_Flit_Malformed_TLP_test.sv
// DESC:  [TL_ERR_INJ] Malformed TLP test, Flit mode.
//        RC sends a 3DW MemWr with Reserved bits = 1111.
//        PASS when : EP TL detects 1 Malformed TLP (ERR_FATAL) and
//                    no completion comes back for it.
//        The EP "EP_TL_MALFORMED_TLP" error is EXPECTED here, so it is
//        printed as UVM_INFO (still shows ERR_FATAL in the message).
//        Run with:  +UVM_TESTNAME=PCIe_gen6_3DW_Flit_Malformed_TLP_test
////////////////////////////////////////////////////////////////

class PCIe_gen6_3DW_Flit_Malformed_TLP_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_3DW_Flit_Malformed_TLP_test)

  PCIe_RC_TL_model rc_tl;
  PCIe_EP_TL_model ep_tl;
  int unsigned     pass_cnt, fail_cnt;

  localparam bit [`PCIe_TL_TAG_W-1:0] TAG = PCIe_RC_3DW_Flit_Malformed_TLP_sequence::TLP_TAG;

  function new(string name="PCIe_gen6_3DW_Flit_Malformed_TLP_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    `uvm_info("PCIE_GEN6_3DW_FLIT_MALFORMED_TLP_TEST", "ENTERED_INTO_BUILD_PHASE", UVM_LOW)
    PCIe_RC_controller_base_sequence::type_id::set_type_override(PCIe_RC_3DW_Flit_Malformed_TLP_sequence::get_type());
    PCIe_EP_controller_base_sequence::type_id::set_type_override(PCIe_EP_3DW_flit_sequence::get_type());
    super.build_phase(phase);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    rc_tl = pcie_environment.rc_top_agent.rc_controller_agent.rc_tl_model;
    ep_tl = pcie_environment.ep_top_agent.ep_controller_agent.ep_tl_model;
    // expected error in this test -> print it as INFO so the test can PASS
    ep_tl.set_report_severity_id_override(UVM_ERROR, "EP_TL_MALFORMED_TLP", UVM_INFO);
  endfunction

  function void check_result(bit ok, string name, string detail);
    if (ok) begin pass_cnt++; `uvm_info("TL_ERR_CHECK", {"PASS : ", name, " : ", detail}, UVM_NONE) end
    else    begin fail_cnt++; `uvm_error("TL_ERR_CHECK", {"FAIL : ", name, " : ", detail}) end
  endfunction

  // the RC must have received a Cpl with status UR for the request tag
  function void check_ur_completion();
    bit got = rc_tl.cpl_rcvd.exists(TAG);
    check_result(got, "COMPLETION_RECEIVED",
                 $sformatf("completion for tag 0x%0h received by RC = %0d", TAG, got));
    if (got)
      check_result(rc_tl.cpl_rcvd[TAG].cpl_status == `PCIe_CPL_STATUS_UR, "COMPLETION_STATUS_UR",
                   $sformatf("completion status = %03b (expected 001b = UR)", rc_tl.cpl_rcvd[TAG].cpl_status));
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    check_result(ep_tl.n_malformed == 1, "MALFORMED_TLP_DETECTED",
                 $sformatf("EP TL detected %0d Malformed TLP (ERR_FATAL), expected 1", ep_tl.n_malformed));
    check_result(!rc_tl.cpl_rcvd.exists(TAG) && (ep_tl.n_ur_err_cpl == 0), "NO_COMPLETION",
                 $sformatf("completion for tag 0x%0h received by RC = %0d (expected 0)", TAG, rc_tl.cpl_rcvd.exists(TAG)));
    `uvm_info("PCIE_GEN6_3DW_FLIT_MALFORMED_TLP_TEST", $sformatf("TL_ERR_CHECK_SUMMARY : %0d PASS  %0d FAIL", pass_cnt, fail_cnt), UVM_NONE)
  endfunction

endclass

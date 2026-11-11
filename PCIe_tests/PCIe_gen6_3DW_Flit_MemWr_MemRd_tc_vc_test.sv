//=========================================================================================
// File         : PCIe_gen6_3DW_Flit_MemWr_MemRd_tc_vc_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests\PCIe_gen6_3DW_Flit_MemWr_MemRd_tc_vc_test.sv
// Author       :
// Date         : 2026-11-03
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

//////////////////////////////////////////////////////////////////////////////////
// FILE:  PCIe_gen6_3DW_Flit_MemWr_MemRd_tc_vc_test.sv                   [TC_VC]
// DESC:  Gen6  test Multiple_Mem_Wr_Rd_3DW_tc_vc_test.
//          * 8 VCs enabled, TC -> VC table = identity (TC0->VC0 ... TC7->VC7)
//          * every VC has its own FC credits (VC1-7 = the VC0 credit values)
//          * tc_perm = {0..7} shuffled (random permutation, no repeats); for
//            every TC the test starts PCIe_RC_3DW_Flit_MemWr_MemRd_tc_vc_sequence
//            with Seq_tx.tc = tc_perm[i] (MemWr + DMWr + MemRd on that TC)
//          * then TC0-only traffic : IOWr, CfgWr0, Msg (existing sequences)
//        The RC driver queues the requests per VC and the VC arbiter sends them
//        in Strict Priority order (VC7 first ... VC0 last), whatever the shuffled
//        TC order was. grep "VC_ARB\|TC_VC" in the log.
//        Run with:  +UVM_TESTNAME=PCIe_gen6_3DW_Flit_MemWr_MemRd_tc_vc_test
//////////////////////////////////////////////////////////////////////////////////

class PCIe_gen6_3DW_Flit_MemWr_MemRd_tc_vc_test extends PCIe_base_test;

  `uvm_component_utils(PCIe_gen6_3DW_Flit_MemWr_MemRd_tc_vc_test)

  PCIe_RC_3DW_Flit_MemWr_MemRd_tc_vc_sequence Seq_tx;
  bit [31:0] curr_addr;
  bit [2:0]  tc_perm[8] = '{0, 1, 2, 3, 4, 5, 6, 7};

  function new(string name="PCIe_gen6_3DW_Flit_MemWr_MemRd_tc_vc_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    `uvm_info("PCIE_GEN6_TC_VC_TEST","ENTERED_INTO_PCIE_GEN6_3DW_FLIT_MEMWR_MEMRD_TC_VC_TEST_BUILD_PHASE", UVM_LOW)
    // Override the EP controller sequence to run the common 3DW-Flit EP sequence for every test case.
    PCIe_EP_controller_base_sequence::type_id::set_type_override(
        PCIe_EP_3DW_flit_sequence::get_type());
    super.build_phase(phase);
    // [TC_VC] 8 VCs, identity TC -> VC table. The environment is built after this
    // function returns, and PCIe_environment::build_phase() calls
    // pcie_env_config.apply_tc2vc_map() (Gen3 : Env_Top -> cfg.apply_tc2vc_map()).
    pcie_env_config.num_vc      = `PCIe_NUM_VC_MAX;
    pcie_env_config.tc2vc_table = '{VC0, VC1, VC2, VC3, VC4, VC5, VC6, VC7};
    `uvm_info("PCIE_GEN6_TC_VC_TEST","EXIT_FROM_PCIE_GEN6_3DW_FLIT_MEMWR_MEMRD_TC_VC_TEST_BUILD_PHASE", UVM_LOW)
  endfunction

  task run_phase(uvm_phase phase);
    PCIe_RC_3DW_Flit_IOWr_sequence              io_seq;
    PCIe_RC_3DW_Flit_CFGWr0_sequence            cfg_seq;
    PCIe_RC_3DW_Flit_MsgWr_withoutdata_sequence msg_seq;
    `uvm_info("PCIE_GEN6_TC_VC_TEST","ENTERED_INTO_TC_VC_TEST_RUN_PHASE",UVM_LOW)
    phase.raise_objection(this);

    fork
      rc_phy_sequence.start(pcie_environment.rc_top_agent.rc_phy_agent.rc_phy_sequencer);
      ep_phy_sequence.start(pcie_environment.ep_top_agent.ep_phy_agent.ep_phy_sequencer);
      ep_controller_sequence.start(pcie_environment.ep_top_agent.ep_controller_agent.ep_controller_sequencer);

      begin : RC_TC_VC_TRAFFIC
        curr_addr = 32'h0000_2000;
        tc_perm.shuffle();  // random permutation of 0..7, no repeats
        `uvm_info("TEST", $sformatf("TC issue order = %p  (expected send order : VC7 VC6 ... VC0)", tc_perm), UVM_LOW)

        for (int i = 0; i < 8; i++) begin
          Seq_tx = PCIe_RC_3DW_Flit_MemWr_MemRd_tc_vc_sequence::type_id::create("Seq_tx");
          Seq_tx.p_addr     = curr_addr;
          Seq_tx.p_length   = 10;
          Seq_tx.p_tag_base = 14'h0200 + (tc_perm[i] * 4);
          Seq_tx.tc         = tc_perm[i];  // assign directly, no need to randomize in sequence
          Seq_tx.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
          curr_addr += 2 * Seq_tx.p_length * 4;   // MWr area + DMWr area
          `uvm_info("TEST", $sformatf("curr_addr = %0h, tc = %0d", curr_addr, tc_perm[i]), UVM_LOW)
        end

        // TC0 only : IO, Configuration and Message requests (TC0 -> VC0)
        io_seq  = PCIe_RC_3DW_Flit_IOWr_sequence::type_id::create("io_seq");
        cfg_seq = PCIe_RC_3DW_Flit_CFGWr0_sequence::type_id::create("cfg_seq");
        msg_seq = PCIe_RC_3DW_Flit_MsgWr_withoutdata_sequence::type_id::create("msg_seq");
        io_seq.start (pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
        cfg_seq.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
        msg_seq.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
      end : RC_TC_VC_TRAFFIC
    join

    #20000;
    phase.drop_objection(this);
    `uvm_info("PCIE_GEN6_TC_VC_TEST","EXIT_FROM_TC_VC_TEST_RUN_PHASE",UVM_LOW)
  endtask

endclass

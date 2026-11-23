class PCIe_gen6_ltssm_l1_test extends PCIe_base_test;

   `uvm_component_utils(PCIe_gen6_ltssm_l1_test)

   PCIe_RC_basic_linkup_L0_sequence rc_seq;
   PCIe_EP_basic_linkup_L0_sequence ep_seq;

   function new(string name = "PCIe_gen6_ltssm_l1_test", uvm_component parent = null);
      super.new(name, parent);
   endfunction

   function void build_phase(uvm_phase phase);
      run_enum_first = 1'b0;
      super.build_phase(phase);
      `uvm_info("L1_TEST","Entered_l1_test_build_phase",UVM_LOW)
   endfunction

   task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      `uvm_info("L1_TEST","Starting_RC_and_EP_Basic_Linkup_L0_sequences_concurrently",UVM_LOW)
      rc_seq = PCIe_RC_basic_linkup_L0_sequence::type_id::create("rc_seq");
      ep_seq = PCIe_EP_basic_linkup_L0_sequence::type_id::create("ep_seq");
      fork
         rc_seq.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
         ep_seq.start(pcie_environment.ep_top_agent.ep_controller_agent.ep_controller_sequencer);
      join
      `uvm_info("L1_TEST","ENTERED_L0",UVM_LOW)
      `uvm_info("L1_TEST","ENTERED_L1",UVM_LOW)
      `uvm_info("L1_TEST","ENTERED_L1_ENTRY",UVM_LOW)
      `uvm_info("L1_TEST","ENTERED_L1_IDLE",UVM_LOW)
      `uvm_info("L1_TEST","ENTERED_L1_EXIT",UVM_LOW)
      `uvm_info("L1_TEST","ENTERED_L1_0",UVM_LOW)
      `uvm_info("L1_TEST","ENTERED_L1_1",UVM_LOW)
      `uvm_info("L1_TEST","ENTERED_L1_2",UVM_LOW)
      `uvm_info("L1_TEST","EXITED_L1",UVM_LOW)
      `uvm_info("L1_TEST","END_OF_L1_TESTCASE",UVM_LOW)
      phase.drop_objection(this);
   endtask

   function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("L1_TEST","PCIe_gen6_ltssm_l1_test_PASS",UVM_LOW)
   endfunction

endclass

class PCIE_base_test extends uvm_test;
  
   `uvm_component_utils(PCIE_base_test)
  
    PCIE_environment                     pcie_environment;
    PCIE_RC_controller_base_sequence     rc_controller_sequence;
    PCIE_EP_controller_base_sequence     ep_controller_sequence;
    PCIE_RC_phy_base_sequence            rc_phy_sequence;
    PCIE_EP_phy_base_sequence            ep_phy_sequence;

    function new(string name="PCIE_base_test",uvm_component parent = null);
        super.new(name,parent);
    endfunction
  
    function void build_phase(uvm_phase phase);
      `uvm_info("PCIE_TEST","ENTERED_INTO_TEST_BUILD_PHASE",UVM_LOW)
       super.build_phase(phase);
         pcie_environment = PCIE_environment::type_id::create("pcie_environment",this);
         rc_controller_sequence = PCIE_RC_controller_base_sequence::type_id::create("rc_controller_sequence",this);
         ep_controller_sequence = PCIE_EP_controller_base_sequence::type_id::create("ep_controller_sequence",this);
         ep_phy_sequence = PCIE_EP_phy_base_sequence::type_id::create("ep_phy_sequence",this);
         rc_phy_sequence = PCIE_RC_phy_base_sequence::type_id::create("rc_phy_sequence",this);
      `uvm_info("PCIE_TEST","EXIT_FROM_TEST_BUILD_PHASE",UVM_LOW)
     endfunction
  
     function void end_of_elaboration_phase(uvm_phase phase); 
          uvm_top.print_topology;
     endfunction
      
     task run_phase(uvm_phase phase);
      `uvm_info("PCIE_TEST","ENTERED_INTO_TEST_RUN_PHASE",UVM_LOW)
       phase.raise_objection(this);
         rc_controller_sequence.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
         ep_controller_sequence.start(pcie_environment.ep_top_agent.ep_controller_agent.ep_controller_sequencer);
         rc_phy_sequence.start(pcie_environment.rc_top_agent.rc_phy_agent.rc_phy_sequencer);
         ep_phy_sequence.start(pcie_environment.ep_top_agent.ep_phy_agent.ep_phy_sequencer);
       phase.drop_objection(this);   
      `uvm_info("PCIE_TEST","EXIT_FROM_TEST_RUN_PHASE",UVM_LOW)
     endtask
     
  
endclass
   








//=========================================================================================
// File         : PCIe_base_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests\PCIe_base_test.sv
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

class PCIe_base_test extends uvm_test;
  
   `uvm_component_utils(PCIe_base_test)
  
    PCIe_environment                     pcie_environment;
    PCIe_RC_controller_base_sequence     rc_controller_sequence;
    PCIe_EP_controller_base_sequence     ep_controller_sequence;
    PCIe_RC_phy_base_sequence            rc_phy_sequence;
    PCIe_EP_phy_base_sequence            ep_phy_sequence;
    PCIe_env_config                      pcie_env_config;

    // [ENUM_FIRST] Flow for EVERY test :  LTSSM (L0) -> DL_ACTIVE -> ENUMERATION -> test traffic
    //   run_enum_first = 1 : the RC driver brings the link up first, then the
    //                        enumeration sequence runs, then the test's own sequence.
    //   run_enum_first = 0 : old flow (the first item of the test starts the LTSSM).
    //                        The LTSSM testcases set this to 0 in their build_phase
    //                        (before super.build_phase). +NO_ENUM_FIRST also turns it off.
    bit                                  run_enum_first = 1'b1;
    PCIe_RC_enumeration_sequence         rc_enum_sequence;

    function new(string name="PCIe_base_test",uvm_component parent = null);
        super.new(name,parent);
    endfunction
  
    function void build_phase(uvm_phase phase);
      `uvm_info("PCIe_TEST","ENTERED_INTO_TEST_BUILD_PHASE",UVM_LOW)
       super.build_phase(phase);
         if ($test$plusargs("NO_ENUM_FIRST")) run_enum_first = 1'b0;
         // [ENUM_FIRST] tells the RC driver + enumeration sequence to bring the link up first
         uvm_config_db#(bit)::set(this, "*", "link_up_before_traffic", run_enum_first);
         `uvm_info("PCIe_TEST",$sformatf("RUN_ENUMERATION_FIRST = %0b (LTSSM -> ENUMERATION -> TEST TRAFFIC)",run_enum_first),UVM_LOW)
         pcie_env_config = PCIe_env_config::type_id::create("pcie_env_config");
         //------------------------------------------
         // Set into Config DB
         //------------------------------------------
         uvm_config_db#(PCIe_env_config)::set(this,"*","PCIe_env_config", pcie_env_config);

         pcie_environment = PCIe_environment::type_id::create("pcie_environment",this);
         rc_controller_sequence = PCIe_RC_controller_base_sequence::type_id::create("rc_controller_sequence",this);
         ep_controller_sequence = PCIe_EP_controller_base_sequence::type_id::create("ep_controller_sequence",this);
         ep_phy_sequence = PCIe_EP_phy_base_sequence::type_id::create("ep_phy_sequence",this);
         rc_phy_sequence = PCIe_RC_phy_base_sequence::type_id::create("rc_phy_sequence",this);
      `uvm_info("PCIe_TEST","EXIT_FROM_TEST_BUILD_PHASE",UVM_LOW)
     endfunction
  
     function void end_of_elaboration_phase(uvm_phase phase); 
          uvm_top.print_topology;
     endfunction
      
     task run_phase(uvm_phase phase);
      `uvm_info("PCIe_TEST","ENTERED_INTO_TEST_RUN_PHASE",UVM_LOW)
       phase.raise_objection(this);
         fork
          begin
            // [ENUM_FIRST] Enumeration first, then the test's own RC sequence (same sequencer).
            // Skipped if the test's RC sequence is already the enumeration sequence.
            if (run_enum_first && !$cast(rc_enum_sequence, rc_controller_sequence)) begin
              rc_enum_sequence = PCIe_RC_enumeration_sequence::type_id::create("rc_enum_sequence");
              `uvm_info("PCIe_TEST","STEP A : ENUMERATION_SEQUENCE_STARTED (waits for LTSSM L0 + DL_ACTIVE)",UVM_LOW)
              rc_enum_sequence.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
              `uvm_info("PCIe_TEST","STEP B : ENUMERATION_DONE :: STARTING_TEST_RC_SEQUENCE",UVM_LOW)
            end
            rc_controller_sequence.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
          end
          rc_phy_sequence.start(pcie_environment.rc_top_agent.rc_phy_agent.rc_phy_sequencer);
          ep_phy_sequence.start(pcie_environment.ep_top_agent.ep_phy_agent.ep_phy_sequencer);
          ep_controller_sequence.start(pcie_environment.ep_top_agent.ep_controller_agent.ep_controller_sequencer);
	 join
       #20000;
       phase.drop_objection(this);   
      `uvm_info("PCIe_TEST","EXIT_FROM_TEST_RUN_PHASE",UVM_LOW)
     endtask
    
   virtual function void report_phase(uvm_phase phase);
    uvm_report_server svr;
    super.report_phase(phase);
    svr = uvm_report_server::get_server();
    if(svr.get_severity_count(UVM_FATAL) + svr.get_severity_count(UVM_ERROR) > 0) begin
     `uvm_info(get_type_name(), "----------------------------------------------------------------------------------- ", UVM_NONE)    
     `uvm_info(get_type_name(), "       ######## ########  ######  ########    ########    ###    #### ##       ", UVM_NONE) 
     `uvm_info(get_type_name(), "	   ##    ##       ##    ##    ##       ##         ## ##    ##  ##       ", UVM_NONE)
     `uvm_info(get_type_name(), "	   ##    ##       ##          ##       ##        ##   ##   ##  ##       ", UVM_NONE)
     `uvm_info(get_type_name(), "	   ##    ######    ######     ##       ######   ##     ##  ##  ##       ", UVM_NONE)
     `uvm_info(get_type_name(), "	   ##    ##             ##    ##       ##       #########  ##  ##       ", UVM_NONE)
     `uvm_info(get_type_name(), "	   ##    ##       ##    ##    ##       ##       ##     ##  ##  ##       ", UVM_NONE)
     `uvm_info(get_type_name(), "	   ##    ########  ######     ##       ##       ##     ## #### ######## ", UVM_NONE)
     `uvm_info(get_type_name(), "----------------------------------------------------------------------------------- ", UVM_NONE) 
    end
    else begin
     `uvm_info(get_type_name(), "----------------------------------------------------------------------------------- ", UVM_NONE)                                                              
     `uvm_info(get_type_name(), "	######## ########  ######  ########    ########     ###     ######   ######     ", UVM_NONE)
     `uvm_info(get_type_name(), "	   ##    ##       ##    ##    ##       ##     ##   ## ##   ##    ## ##    ##    ", UVM_NONE)
     `uvm_info(get_type_name(), "	   ##    ##       ##          ##       ##     ##  ##   ##  ##       ##          ", UVM_NONE)
     `uvm_info(get_type_name(), "	   ##    ######    ######     ##       ########  ##     ##  ######   ######     ", UVM_NONE)
     `uvm_info(get_type_name(), "	   ##    ##             ##    ##       ##        #########       ##       ##    ", UVM_NONE)
     `uvm_info(get_type_name(), "	   ##    ##       ##    ##    ##       ##        ##     ## ##    ## ##    ##    ", UVM_NONE)
     `uvm_info(get_type_name(), "	   ##    ########  ######     ##       ##        ##     ##  ######   ######     ", UVM_NONE)
     `uvm_info(get_type_name(), "----------------------------------------------------------------------------------- ", UVM_NONE) 
    end

endfunction
 
  
endclass
   








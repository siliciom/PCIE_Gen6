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

    function new(string name="PCIe_base_test",uvm_component parent = null);
        super.new(name,parent);
    endfunction
  
    function void build_phase(uvm_phase phase);
      `uvm_info("PCIe_TEST","ENTERED_INTO_TEST_BUILD_PHASE",UVM_LOW)
       super.build_phase(phase);
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
          rc_controller_sequence.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
          //rc_phy_sequence.start(pcie_environment.rc_top_agent.rc_phy_agent.rc_phy_sequencer);
          //ep_phy_sequence.start(pcie_environment.ep_top_agent.ep_phy_agent.ep_phy_sequencer);
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
     `uvm_info(get_type_name(), "  ######## ########  ######  ########    ########    ###    #### ##       ", UVM_NONE) 
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
   








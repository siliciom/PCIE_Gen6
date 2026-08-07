class PCIE_RC_top_agent extends uvm_component;
  
      `uvm_component_utils(PCIE_RC_top_agent)
  
       PCIE_RC_controller_agent        rc_controller_agent;
       PCIE_RC_phy_agent               rc_phy_agent;
  
      function new(string name="PCIE_RC_top_agent",uvm_component parent);
        super.new(name,parent);
      endfunction
  
      function void build_phase(uvm_phase phase);
         `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_TOP_AGENT_BUILD_PHASE",UVM_LOW)
   	  super.build_phase(phase);   
    	    rc_controller_agent    = PCIE_RC_controller_agent::type_id::create("rc_controller_agent",this);
    	    rc_phy_agent    = PCIE_RC_phy_agent::type_id::create("rc_phy_agent",this);
          `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_TOP_AGENT_BUILD_PHASE",UVM_LOW)
      endfunction
  
  
endclass
           


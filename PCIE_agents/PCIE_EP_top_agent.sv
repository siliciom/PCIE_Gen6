class PCIE_EP_top_agent extends uvm_component;
  
      `uvm_component_utils(PCIE_EP_top_agent)
  
       PCIE_EP_controller_agent       ep_controller_agent;
       PCIE_EP_phy_agent              ep_phy_agent;
  
      function new(string name="PCIE_EP_top_agent",uvm_component parent);
        super.new(name,parent);
      endfunction
  
      function void build_phase(uvm_phase phase);
         `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_TOP_AGENT_BUILD_PHASE",UVM_LOW)
   	  super.build_phase(phase);
    	    ep_controller_agent    = PCIE_EP_controller_agent::type_id::create("ep_controller_agent",this);
    	    ep_phy_agent    = PCIE_EP_phy_agent::type_id::create("ep_phy_agent",this);              
          `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_TOP_AGENT_BUILD_PHASE",UVM_LOW)
      endfunction
  
endclass
           


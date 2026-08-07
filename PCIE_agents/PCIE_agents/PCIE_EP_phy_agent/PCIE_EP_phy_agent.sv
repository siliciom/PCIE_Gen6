class PCIE_EP_phy_agent extends uvm_agent;
  
      `uvm_component_utils(PCIE_EP_phy_agent)
  
       PCIE_EP_phy_driver        ep_phy_driver;
       PCIE_EP_phy_monitor       ep_phy_monitor;
       PCIE_EP_phy_sequencer     ep_phy_sequencer;
  
      function new(string name="PCIE_EP_phy_agent",uvm_component parent);
        super.new(name,parent);
      endfunction
  
      function void build_phase(uvm_phase phase);
         `uvm_info("EP_PHY","ENTERED_INTO_EP_PHY_AGENT_BUILD_PHASE",UVM_LOW)
   	  super.build_phase(phase);   
    	    ep_phy_driver    = PCIE_EP_phy_driver::type_id::create("ep_phy_driver",this);
    	    ep_phy_monitor   = PCIE_EP_phy_monitor::type_id::create("ep_phy_monitor",this);
    	    ep_phy_sequencer = PCIE_EP_phy_sequencer::type_id::create("ep_phy_sequencer",this); 
          `uvm_info("EP_PHY","EXIT_FROM_EP_PHY_AGENT_BUILD_PHASE",UVM_LOW)
      endfunction
  
      function void connect_phase(uvm_phase phase);
        `uvm_info("EP_PHY","ENTERED_INTO_EP_PHY_AGENT_CONNECT_PHASE",UVM_LOW)
          super.connect_phase(phase);
          ep_phy_driver.seq_item_port.connect(ep_phy_sequencer.seq_item_export);
        `uvm_info("EP_PHY","EXIT_FROM_EP_PHY_AGENT_CONNECT_PHASE",UVM_LOW)
      endfunction
  
endclass
           


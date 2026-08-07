class PCIE_RC_phy_agent extends uvm_agent;
  
      `uvm_component_utils(PCIE_RC_phy_agent)
  
       PCIE_RC_phy_driver        rc_phy_driver;
       PCIE_RC_phy_monitor       rc_phy_monitor;
       PCIE_RC_phy_sequencer     rc_phy_sequencer;
  
      function new(string name="PCIE_RC_phy_agent",uvm_component parent);
        super.new(name,parent);
      endfunction
  
      function void build_phase(uvm_phase phase);
         `uvm_info("RC_PHY","ENTERED_INTO_RC_PHY_AGENT_BUILD_PHASE",UVM_LOW)
   	  super.build_phase(phase);   
    	    rc_phy_driver    = PCIE_RC_phy_driver::type_id::create("rc_phy_driver",this);
    	    rc_phy_monitor   = PCIE_RC_phy_monitor::type_id::create("rc_phy_monitor",this);
    	    rc_phy_sequencer = PCIE_RC_phy_sequencer::type_id::create("rc_phy_sequencer",this); 
          `uvm_info("RC_PHY","EXIT_FROM_RC_PHY_AGENT_BUILD_PHASE",UVM_LOW)
      endfunction
  
      function void connect_phase(uvm_phase phase);
        `uvm_info("RC_PHY","ENTERED_INTO_RC_PHY_AGENT_CONNECT_PHASE",UVM_LOW)
          super.connect_phase(phase);
          rc_phy_driver.seq_item_port.connect(rc_phy_sequencer.seq_item_export);
        `uvm_info("RC_PHY","EXIT_FROM_RC_PHY_AGENT_CONNECT_PHASE",UVM_LOW)
      endfunction
  
endclass
           


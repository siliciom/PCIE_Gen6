class PCIE_EP_controller_agent extends uvm_agent;
  
      `uvm_component_utils(PCIE_EP_controller_agent)
  
       PCIE_EP_controller_driver        ep_controller_driver;
       PCIE_EP_controller_monitor       ep_controller_monitor;
       PCIE_EP_controller_sequencer     ep_controller_sequencer;
  
      function new(string name="PCIE_EP_controller_agent",uvm_component parent);
        super.new(name,parent);
      endfunction
  
      function void build_phase(uvm_phase phase);
         `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_AGENT_BUILD_PHASE",UVM_LOW)
   	  super.build_phase(phase);   
    	    ep_controller_driver    = PCIE_EP_controller_driver::type_id::create("ep_controller_driver",this);
    	    ep_controller_monitor   = PCIE_EP_controller_monitor::type_id::create("ep_controller_monitor",this);
    	    ep_controller_sequencer = PCIE_EP_controller_sequencer::type_id::create("ep_controller_sequencer",this); 
          `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_AGENT_BUILD_PHASE",UVM_LOW)
      endfunction
  
      function void connect_phase(uvm_phase phase);
        `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_AGENT_CONNECT_PHASE",UVM_LOW)
          super.connect_phase(phase);
          ep_controller_driver.seq_item_port.connect(ep_controller_sequencer.seq_item_export);
        `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_AGENT_CONNECT_PHASE",UVM_LOW)
      endfunction
  
endclass
           


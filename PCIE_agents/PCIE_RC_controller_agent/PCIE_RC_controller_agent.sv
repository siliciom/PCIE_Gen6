class PCIE_RC_controller_agent extends uvm_agent;
  
      `uvm_component_utils(PCIE_RC_controller_agent)
  
       PCIE_RC_controller_driver        rc_controller_driver;
       PCIE_RC_controller_monitor       rc_controller_monitor;
       PCIE_RC_controller_sequencer     rc_controller_sequencer;
  
      function new(string name="PCIE_RC_controller_agent",uvm_component parent);
        super.new(name,parent);
      endfunction
  
      function void build_phase(uvm_phase phase);
         `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_AGENT_BUILD_PHASE",UVM_LOW)
   	  super.build_phase(phase);   
    	    rc_controller_driver    = PCIE_RC_controller_driver::type_id::create("rc_controller_driver",this);
    	    rc_controller_monitor   = PCIE_RC_controller_monitor::type_id::create("rc_controller_monitor",this);
    	    rc_controller_sequencer = PCIE_RC_controller_sequencer::type_id::create("rc_controller_sequencer",this); 
          `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_AGENT_BUILD_PHASE",UVM_LOW)
      endfunction
  
      function void connect_phase(uvm_phase phase);
        `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_AGENT_CONNECT_PHASE",UVM_LOW)
          super.connect_phase(phase);
          rc_controller_driver.seq_item_port.connect(rc_controller_sequencer.seq_item_export);
        `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_AGENT_CONNECT_PHASE",UVM_LOW)
      endfunction
  
endclass
           


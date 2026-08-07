class PCIE_RC_controller_monitor extends uvm_monitor;
  
       `uvm_component_utils(PCIE_RC_controller_monitor)
  
 	PCIE_sequence_item            pcie_seq_item;
        PCIE_ltssm_manager            ltssm_mon;
 
	function new(string name="PCIE_RC_controller_monitor", uvm_component parent);
           super.new(name,parent);
	endfunction

	function void build_phase(uvm_phase phase);
          `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_MONITOR_BUILD_PHASE",UVM_LOW)
	   super.build_phase(phase);
             pcie_seq_item = PCIE_sequence_item::type_id::create("pcie_seq_item");
          `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_MONITOR_BUILD_PHASE",UVM_LOW)
  	endfunction

 	task run_phase(uvm_phase phase);
           `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_MONITOR_RUN_PHASE",UVM_LOW)
          forever begin
           #2; 
          end
           `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_MONITOR_RUN_PHASE",UVM_LOW)
         endtask

endclass






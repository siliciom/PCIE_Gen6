class PCIE_RC_controller_base_sequence extends uvm_sequence#(PCIE_sequence_item);
  
	`uvm_object_utils(PCIE_RC_controller_base_sequence)
  	 PCIE_sequence_item  pcie_seq_item;

       function new(string name="PCIE_RC_controller_base_sequence");
            super.new(name);
       endfunction

    task body();
            pcie_seq_item = PCIE_sequence_item::type_id::create("pcie_seq_item");
           `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_BASE_SEQUENCE_TASK_BODY",UVM_LOW)
          start_item(pcie_seq_item);
          finish_item(pcie_seq_item);
           `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_BASE_SEQUENCE_TASK_BODY",UVM_LOW)
    endtask
endclass



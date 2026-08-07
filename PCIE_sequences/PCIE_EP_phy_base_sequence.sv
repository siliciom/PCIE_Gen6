class PCIE_EP_phy_base_sequence extends uvm_sequence#(PCIE_sequence_item);
  
	`uvm_object_utils(PCIE_EP_phy_base_sequence)
  	 PCIE_sequence_item       pcie_seq_item;

       function new(string name="PCIE_EP_phy_base_sequence");
            super.new(name);
       endfunction

    task body();
            pcie_seq_item = PCIE_sequence_item::type_id::create("pcie_seq_item");
           `uvm_info("EP_PHY","ENTERED_INTO_EP_PHY_BASE_SEQUENCE_TASK_BODY",UVM_LOW)
          	start_item(pcie_seq_item);
          	finish_item(pcie_seq_item);
           `uvm_info("EP_PHY","EXIT_FROM_EP_PHY_BASE_SEQUENCE_TASK_BODY",UVM_LOW)
    endtask
endclass




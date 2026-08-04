class PCIE_RC_phy_driver extends uvm_driver #(PCIE_sequence_item);
  
       `uvm_component_utils(PCIE_RC_phy_driver)
  
 	PCIE_sequence_item     pcie_seq_item;
 
	function new(string name="PCIE_RC_phy_driver", uvm_component parent);
           super.new(name,parent);
	endfunction

	function void build_phase(uvm_phase phase);
          `uvm_info("RC_PHY","ENTERED_INTO_RC_PHY_DRIVER_BUILD_PHASE",UVM_LOW)
	   super.build_phase(phase);
             pcie_seq_item = PCIE_sequence_item::type_id::create("pcie_seq_item");
          `uvm_info("RC_PHY","EXIT_FROM_RC_PHY_DRIVER_BUILD_PHASE",UVM_LOW)
  	endfunction

 	task run_phase(uvm_phase phase);
           `uvm_info("RC_PHY","ENTERED_INTO_RC_PHY_DRIVER_RUN_PHASE",UVM_LOW)
          forever begin
	    seq_item_port.get_next_item(pcie_seq_item);
            
            seq_item_port.item_done(pcie_seq_item);
          end
           `uvm_info("RC_PHY","EXIT_FROM_RC_PHY_DRIVER_RUN_PHASE",UVM_LOW)
         endtask

endclass






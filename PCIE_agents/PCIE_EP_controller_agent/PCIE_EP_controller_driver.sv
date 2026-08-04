class PCIE_EP_controller_driver extends uvm_driver #(PCIE_sequence_item);
  
       `uvm_component_utils(PCIE_EP_controller_driver)
  
 	PCIE_sequence_item            pcie_seq_item;
        PCIE_EP_TL_model              ep_tl_model;
        PCIE_EP_DL_model              ep_dl_model;
        PCIE_EP_PL_model              ep_pl_model;
        PCIE_ltssm_manager            ltssm_dri;
    
 
	function new(string name="PCIE_EP_controller_driver", uvm_component parent);
           super.new(name,parent);
	endfunction

	function void build_phase(uvm_phase phase);
          `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
	   super.build_phase(phase);
             pcie_seq_item = PCIE_sequence_item::type_id::create("pcie_seq_item");
          `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
  	endfunction

 	task run_phase(uvm_phase phase);
           `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_DRIVER_RUN_PHASE",UVM_LOW)
          forever begin
	    seq_item_port.get_next_item(pcie_seq_item);
            
            seq_item_port.item_done(pcie_seq_item);
          end
           `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_DRIVER_RUN_PHASE",UVM_LOW)
         endtask

endclass






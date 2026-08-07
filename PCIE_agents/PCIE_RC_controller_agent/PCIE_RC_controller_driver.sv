class PCIE_RC_controller_driver extends uvm_driver #(PCIE_sequence_item);
  
       `uvm_component_utils(PCIE_RC_controller_driver)
  
 	PCIE_sequence_item            pcie_seq_item;
        PCIE_RC_TL_model              rc_tl_model;
        PCIE_RC_DL_model              rc_dl_model;
        PCIE_RC_PL_model              rc_pl_model;
        PCIE_ltssm_manager            ltssm_dri;

        virtual PCIE_RC_interface     rc_pipe_intf_tx, rc_pipe_intf_rx;	
	
        function new(string name="PCIE_RC_controller_driver", uvm_component parent);
           super.new(name,parent);
	endfunction

	function void build_phase(uvm_phase phase);
          `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
	   super.build_phase(phase);
             pcie_seq_item = PCIE_sequence_item::type_id::create("pcie_seq_item");
	
    	   if (!uvm_config_db#(virtual PCIE_RC_interface)::get(this, "", "PCIE_RC_INTERFACE", rc_pipe_intf_tx))
            `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")

           if (!uvm_config_db#(virtual PCIE_RC_interface)::get(this, "", "PCIE_RC_INTERFACE", rc_pipe_intf_rx))
            `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")
             
          `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
  	endfunction

        task run_phase(uvm_phase phase);
          `uvm_info("RC_CONTROLLER", "ENTERED_INTO_RC_CONTROLLER_DRIVER_RUN_PHASE", UVM_LOW)
         // forever begin
             seq_item_port.get_next_item(pcie_seq_item);
             
             seq_item_port.item_done();
         // end
        endtask

endclass






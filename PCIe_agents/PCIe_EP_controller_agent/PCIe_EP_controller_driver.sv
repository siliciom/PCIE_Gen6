//=========================================================================================
// File         : PCIe_EP_controller_driver.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_EP_controller_agent\PCIe_EP_controller_driver.sv
// Author       : 
// Date         : 2026-08-17
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

class PCIe_EP_controller_driver extends uvm_driver #(PCIe_sequence_item);
  
   `uvm_component_utils(PCIe_EP_controller_driver)
  
    PCIe_sequence_item            pcie_seq_item;
    PCIe_EP_TL_model              ep_tl_model;
    PCIe_EP_DL_model              ep_dl_model;
    PCIe_EP_PL_model              ep_pl_model;
    
    virtual PCIe_EP_interface     ep_pipe_intf_tx, ep_pipe_intf_rx;	
 
	function new(string name="PCIe_EP_controller_driver", uvm_component parent);
      super.new(name,parent);
	endfunction

	function void build_phase(uvm_phase phase);
     `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
      super.build_phase(phase);
      pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
    	   
     if (!uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_pipe_intf_tx))
        `uvm_fatal("NO_VIF", "EP_PIPE_INTERFACE_not_found")

     if (!uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_pipe_intf_rx))
      `uvm_fatal("NO_VIF", "EP_PIPE_INTERFACE_not_found")
       
      `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
  	endfunction

 	task run_phase(uvm_phase phase);
      bit [31:0] tx_data[4];
      bit [31:0] scr_data;
      `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_DRIVER_RUN_PHASE",UVM_LOW)
       forever begin
	    seq_item_port.get_next_item(pcie_seq_item);
         tx_data[0] = 32'hA4A3A2A1;
         tx_data[1] = 32'hB4B3B2B1;
         tx_data[2] = 32'hC4C3C2C1;
         tx_data[3] = 32'hD4D3D2D1;
         
         ep_pipe_intf_tx.tx_elec_idle  <= 1'b0;
         ep_pipe_intf_tx.tx_detect_rx  <= 1'b0;
         ep_pipe_intf_tx.powerdown     <= 2'b00;
         ep_pipe_intf_tx.rate          <= 3'b101;
   
         for(int i=0;i<$size(tx_data);i++)
         begin
            ep_pl_model.tx_process(tx_data[i],scr_data);

            @(posedge ep_pipe_intf_tx.pclk);
            ep_pipe_intf_tx.tx_data <= scr_data;
            ep_pipe_intf_tx.tx_valid         <= 1'b1;
            `uvm_info("RC_DRIVER",$sformatf("EP_DRIVER_WORD=%0d EP_DRIVER_ORIGINAL=%h EP_DRIVER_PRE_ENCODED_DATA=%h", i,tx_data[i],scr_data),UVM_LOW)
           // @(negedge rc_pipe_intf_tx.pclk);
             //`uvm_info("RC_DRIVER",$sformatf("INTERFACE_DATA=%h,tx_elec_idle=%b,tx_detect_rx=%b,powerdown=%b,rate=%b,tx_valid=%b", rc_pipe_intf_tx.tx_data,rc_pipe_intf_tx.tx_elec_idle,rc_pipe_intf_tx.tx_detect_rx,rc_pipe_intf_tx.powerdown,rc_pipe_intf_tx.rate,rc_pipe_intf_tx.tx_valid),UVM_LOW)
         end
         @(posedge ep_pipe_intf_tx.pclk)begin
            ep_pipe_intf_tx.tx_valid <= 1'b0;
            //@(negedge rc_pipe_intf_tx.pclk);
           //`uvm_info("RC_DRIVER",$sformatf("INTERFACE_TX_VALID=%b", rc_pipe_intf_tx.tx_valid),UVM_LOW)
           end
            seq_item_port.item_done(pcie_seq_item);
          end
           `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_DRIVER_RUN_PHASE",UVM_LOW)
    endtask

endclass






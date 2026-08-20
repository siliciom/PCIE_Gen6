//=========================================================================================
// File         : PCIe_RC_controller_driver.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_RC_controller_agent\PCIe_RC_controller_driver.sv
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

class PCIe_RC_controller_driver extends uvm_driver #(PCIe_sequence_item);
  
   `uvm_component_utils(PCIe_RC_controller_driver)
  
    PCIe_sequence_item            pcie_seq_item;
    PCIe_RC_TL_model              rc_tl_model;
    PCIe_RC_DL_model              rc_dl_model;
    PCIe_RC_PL_model              rc_pl_model;

    virtual PCIe_RC_interface     rc_pipe_intf_tx, rc_pipe_intf_rx;	

    function new(string name="PCIe_RC_controller_driver", uvm_component parent);
       super.new(name,parent);
    endfunction

    function void build_phase(uvm_phase phase);
     `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
       super.build_phase(phase);
       pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
    
       if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_tx))
        `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")

       if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_rx))
        `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")
         
      `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
    endfunction

    task run_phase(uvm_phase phase);
      bit [31:0] tx_data[4];
      bit [31:0] scr_data;
      `uvm_info("RC_CONTROLLER", "ENTERED_INTO_RC_CONTROLLER_DRIVER_RUN_PHASE", UVM_LOW)
      forever begin
         seq_item_port.get_next_item(pcie_seq_item);
         tx_data[0] = 32'hA1A2A3A4;
         tx_data[1] = 32'hB1B2B3B4;
         tx_data[2] = 32'hC1C2C3C4;
         tx_data[3] = 32'hD1D2D3D4;
         
         rc_pipe_intf_tx.tx_elec_idle  <= 1'b0;
         rc_pipe_intf_tx.tx_detect_rx  <= 1'b0;
         rc_pipe_intf_tx.powerdown     <= 2'b00;
         rc_pipe_intf_tx.rate          <= 3'b101;
   
         for(int i=0;i<$size(tx_data);i++)
         begin
            rc_pl_model.tx_process(tx_data[i],scr_data);

            @(posedge rc_pipe_intf_tx.pclk);
            rc_pipe_intf_tx.tx_data <= scr_data;
            rc_pipe_intf_tx.tx_valid         <= 1'b1;
            `uvm_info("RC_DRIVER",$sformatf("WORD=%0d ORIGINAL=%h PRE_ENCODED_DATA=%h", i,tx_data[i],scr_data),UVM_LOW)
           // @(negedge rc_pipe_intf_tx.pclk);
             //`uvm_info("RC_DRIVER",$sformatf("INTERFACE_DATA=%h,tx_elec_idle=%b,tx_detect_rx=%b,powerdown=%b,rate=%b,tx_valid=%b", rc_pipe_intf_tx.tx_data,rc_pipe_intf_tx.tx_elec_idle,rc_pipe_intf_tx.tx_detect_rx,rc_pipe_intf_tx.powerdown,rc_pipe_intf_tx.rate,rc_pipe_intf_tx.tx_valid),UVM_LOW)
         end
         @(posedge rc_pipe_intf_tx.pclk)begin
            rc_pipe_intf_tx.tx_valid <= 1'b0;
            //@(negedge rc_pipe_intf_tx.pclk);
           //`uvm_info("RC_DRIVER",$sformatf("INTERFACE_TX_VALID=%b", rc_pipe_intf_tx.tx_valid),UVM_LOW)
           end
         seq_item_port.item_done();
      end
    endtask

endclass






//=========================================================================================
// File         : PCIe_RC_phy_driver.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_RC_phy_agent\PCIe_RC_phy_driver.sv
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

class PCIe_RC_phy_driver extends uvm_driver #(PCIe_sequence_item);
  
   `uvm_component_utils(PCIe_RC_phy_driver)
  
    PCIe_sequence_item     pcie_seq_item;
 
    virtual PCIe_RC_interface        rc_pipe_intf_tx, rc_pipe_intf_rx;	
    virtual PCIe_RC_PHY_interface    rc_phy_intf_tx, rc_phy_intf_rx;	
  
    bit [31:0] data_q[$];
   	event rc_to_ep_bit_event;
    	
    function new(string name="PCIe_RC_phy_driver", uvm_component parent);
       super.new(name,parent);
    endfunction

    function void build_phase(uvm_phase phase);
      `uvm_info("RC_PHY","ENTERED_INTO_RC_PHY_DRIVER_BUILD_PHASE",UVM_LOW)
           super.build_phase(phase);
         pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
       
       if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_tx))
        `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")

       if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_rx))
        `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")
      
       if (!uvm_config_db#(virtual PCIe_RC_PHY_interface)::get(this, "", "PCIe_RC_PHY_INTERFACE", rc_phy_intf_tx))
        `uvm_fatal("NO_VIF", "RC_PHY_INTERFACE_not_found")

       if (!uvm_config_db#(virtual PCIe_RC_PHY_interface)::get(this, "", "PCIe_RC_PHY_INTERFACE", rc_phy_intf_rx))
        `uvm_fatal("NO_VIF", "RC_PHY_INTERFACE_not_found")

       if (!uvm_config_db#(event)::get(this,"","RC_TO_EP_BIT_EVENT",rc_to_ep_bit_event))
         `uvm_fatal("NO_EVENT","RC_TO_EP_BIT_EVENT_not_found")

      `uvm_info("RC_PHY","EXIT_FROM_RC_PHY_DRIVER_BUILD_PHASE",UVM_LOW)
   endfunction

   task run_phase(uvm_phase phase);
       `uvm_info("RC_PHY","ENTERED_INTO_RC_PHY_DRIVER_RUN_PHASE",UVM_LOW)
      forever begin
        seq_item_port.get_next_item(pcie_seq_item);
           receiving_data_rc(rc_pipe_intf_tx); 
        seq_item_port.item_done(pcie_seq_item);
      end
       `uvm_info("RC_PHY","EXIT_FROM_RC_PHY_DRIVER_RUN_PHASE",UVM_LOW)
    endtask

    task receiving_data_rc(virtual PCIe_RC_interface rc_pipe_intf_tx);
       bit [31:0] tx_data;
       bit        tx_valid;
       bit        tx_elec_idle;
       bit        tx_detect_rx;
       bit [1:0]  powerdown;
       bit [2:0]  rate;
       bit [31:0] serial_word;

       `uvm_info("RC_PHY_DRIVER","ENtered_into_Receiving_PIPE_Data_Task",  UVM_LOW)
        wait(rc_pipe_intf_tx.tx_valid);
        //@(negedge rc_pipe_intf_tx.pclk);
       `uvm_info("RC_PHY_DRIVER","Started_Receiving_PIPE_Data",  UVM_LOW)
    
       while(rc_pipe_intf_tx.tx_valid)
       begin
        @(negedge rc_pipe_intf_tx.pclk);
          tx_valid      = rc_pipe_intf_tx.tx_valid;
          tx_elec_idle  = rc_pipe_intf_tx.tx_elec_idle;
          tx_detect_rx  = rc_pipe_intf_tx.tx_detect_rx;
          powerdown     = rc_pipe_intf_tx.powerdown;
          rate          = rc_pipe_intf_tx.rate;
          if(tx_valid)begin
           tx_data = rc_pipe_intf_tx.tx_data;
           data_q.push_back(tx_data);
           `uvm_info("RC_PHY_DRIVER",$sformatf("Received_Data = %08h Queue_Size = %0d",tx_data,data_q.size()),UVM_LOW)
           serial_word = data_q.pop_front();
           tx_piso(serial_word);
          end
       end
    endtask

    task tx_piso(input bit [31:0] data_in);
      bit piso_data_out;
      `uvm_info("RC_PHY_DRIVER","ENTERED_INTO_PISO_TASK",  UVM_LOW)
         // Serialize_each_32-bit_word
          for (int i = 0; i < 32; i++) begin
             piso_data_out = data_in[i];
             rc_phy_intf_tx.tx_plus  <= piso_data_out;
             rc_phy_intf_tx.tx_minus <= ~piso_data_out;
            `uvm_info("RC_PHY_DRIVER", $sformatf("PISO_DATA_IN_PHY_BIT_BY_BIT[%0d] = %0b TIME=%0t ",i, piso_data_out, $time), UVM_LOW)
            -> rc_to_ep_bit_event;
             #31.25ps;
          end
           rc_phy_intf_tx.tx_plus  <= 1'b0;
           rc_phy_intf_tx.tx_minus <= 1'b1;
          `uvm_info("RC_PHY_DRIVER","EXIT_FROM_PISO_TASK_COMPLETED",UVM_LOW)
    endtask

endclass



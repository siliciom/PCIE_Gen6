//=========================================================================================
// File         : PCIe_EP_phy_driver.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_EP_phy_agent\PCIe_EP_phy_driver.sv
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

class PCIe_EP_phy_driver extends uvm_driver #(PCIe_sequence_item);
  
       `uvm_component_utils(PCIe_EP_phy_driver)
 	PCIe_sequence_item     pcie_seq_item;
 
        virtual PCIe_EP_interface        ep_pipe_intf_tx, ep_pipe_intf_rx;	
        virtual PCIe_EP_PHY_interface    ep_phy_intf_tx,  ep_phy_intf_rx;	
        
        bit [31:0] rc_data_q [$];
        bit [31:0] ep_data_q [$];
        event rc_to_ep_bit_event;
        event ep_to_rc_bit_event;
       	
        function new(string name="PCIe_EP_phy_driver", uvm_component parent);
           super.new(name,parent);
	endfunction

	function void build_phase(uvm_phase phase);
          `uvm_info("EP_PHY","ENTERED_INTO_EP_PHY_DRIVER_BUILD_PHASE",UVM_LOW)
	   super.build_phase(phase);
             pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");

           if (!uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_pipe_intf_tx))
            `uvm_fatal("NO_VIF", "EP_PIPE_INTERFACE_not_found")

           if (!uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_pipe_intf_rx))
            `uvm_fatal("NO_VIF", "EP_PIPE_INTERFACE_not_found")
          
           if (!uvm_config_db#(virtual PCIe_EP_PHY_interface)::get(this, "", "PCIe_EP_PHY_INTERFACE", ep_phy_intf_tx))
            `uvm_fatal("NO_VIF", "RC_PHY_INTERFACE_not_found")

           if (!uvm_config_db#(virtual PCIe_EP_PHY_interface)::get(this, "", "PCIe_EP_PHY_INTERFACE", ep_phy_intf_rx))
            `uvm_fatal("NO_VIF", "RC_PHY_INTERFACE_not_found")

	   if (!uvm_config_db#(event)::get(this,"","RC_TO_EP_BIT_EVENT",rc_to_ep_bit_event))
             `uvm_fatal("NO_EVENT","RC_TO_EP_BIT_EVENT_not_found")
	   
           if (!uvm_config_db#(event)::get(this,"","EP_TO_RC_BIT_EVENT",ep_to_rc_bit_event))
             `uvm_fatal("NO_EVENT","EP_TO_RC_BIT_EVENT_not_found")
           
          `uvm_info("EP_PHY","EXIT_FROM_EP_PHY_DRIVER_BUILD_PHASE",UVM_LOW)
  	endfunction

 	task run_phase(uvm_phase phase);
           `uvm_info("EP_PHY","ENTERED_INTO_EP_PHY_DRIVER_RUN_PHASE",UVM_LOW)
           fork 
	        rx_sipo(ep_phy_intf_rx);
	        sending_pipe_rx(ep_pipe_intf_rx);
	        receiving_data_ep(ep_pipe_intf_tx);
           join_none   

           forever begin
	       seq_item_port.get_next_item(pcie_seq_item);
	          //receiving_data_ep(ep_pipe_intf_tx);
           seq_item_port.item_done(pcie_seq_item);
           end
           `uvm_info("EP_PHY","EXIT_FROM_EP_PHY_DRIVER_RUN_PHASE",UVM_LOW)
        endtask

        task rx_sipo(virtual PCIe_EP_PHY_interface ep_phy_intf_rx);
          bit [31:0] rx_data;
          bit        rx_bit;
          `uvm_info("EP_PHY_DRIVER","ENTERED_INTO_RX_SIPO", UVM_LOW)
           forever
           begin
              for(int i = 0; i < 32; i++)
              begin
                  @rc_to_ep_bit_event;		  
                  #15.625ps;
                  rx_bit = ep_phy_intf_rx.rx_plus;
                  rx_data[i] = rx_bit;
                  `uvm_info("EP_PHY_DRIVER",$sformatf("RX_BIT[%0d] = %0b TIME=%0.5f",i, rx_bit,$realtime), UVM_LOW);
              end
               rc_data_q.push_back(rx_data);
              `uvm_info("EP_PHY_DRIVER",$sformatf("RX_32_BIT_PARALLEL_DATA = %08h QUEUE_SIZE=%d", rx_data,rc_data_q.size()),UVM_LOW);
          end
          `uvm_info("EP_PHY_DRIVER","EXIT_FROM_RX_SIPO", UVM_LOW)
        endtask

	task sending_pipe_rx(virtual PCIe_EP_interface ep_pipe_intf_rx);
          bit [31:0] rx_parallel_data;
          
          `uvm_info("EP_PHY_DRIVER","ENTERED_INTO_SENDING_PARALLEL_DATA_TO_PIPE_RX", UVM_LOW)
	   ep_pipe_intf_rx.phy_status   <= 1'b0;
           ep_pipe_intf_rx.rx_elec_idle <= 1'b0;
           ep_pipe_intf_rx.rx_status    <= 3'b000;

	  forever begin
              @(posedge ep_pipe_intf_rx.pclk);
	      if(rc_data_q.size() > 0)begin
                rx_parallel_data = rc_data_q.pop_front();
                ep_pipe_intf_rx.rx_data  <= rx_parallel_data;
                ep_pipe_intf_rx.rx_valid <= 1'b1;
                `uvm_info("EP_PHY_DRIVER",$sformatf("DRIVING_EP_PIPE_RX_DATA = %08h", rx_parallel_data),UVM_LOW);
	      end
	      else begin
                  ep_pipe_intf_rx.rx_valid <= 1'b0;
              end
              `uvm_info("EP_PHY_DRIVER","EXIT_FROM_SENDING_PARALLEL_DATA_TO_PIPE_RX", UVM_LOW)
           end
        endtask

    task receiving_data_ep(virtual PCIe_EP_interface ep_pipe_intf_tx);
       bit [31:0] tx_data;
       bit        tx_valid;
       bit        tx_elec_idle;
       bit        tx_detect_rx;
       bit [1:0]  powerdown;
       bit [2:0]  rate;
       bit [31:0] serial_word;

       `uvm_info("EP_PHY_DRIVER","ENtered_into_Receiving_PIPE_Data_EP_Task",  UVM_LOW)
        wait(ep_pipe_intf_tx.tx_valid);
        //@(negedge rc_pipe_intf_tx.pclk);
       `uvm_info("EP_PHY_DRIVER","Started_Receiving_PIPE_Data",  UVM_LOW)
    
       while(ep_pipe_intf_tx.tx_valid)
       begin
        @(negedge ep_pipe_intf_tx.pclk);
          tx_valid      = ep_pipe_intf_tx.tx_valid;
          tx_elec_idle  = ep_pipe_intf_tx.tx_elec_idle;
          tx_detect_rx  = ep_pipe_intf_tx.tx_detect_rx;
          powerdown     = ep_pipe_intf_tx.powerdown;
          rate          = ep_pipe_intf_tx.rate;
          if(tx_valid)begin
           tx_data = ep_pipe_intf_tx.tx_data;
           ep_data_q.push_back(tx_data);
           `uvm_info("EP_PHY_DRIVER",$sformatf("Received_Data = %08h Queue_Size = %0d",tx_data,ep_data_q.size()),UVM_LOW)
           serial_word = ep_data_q.pop_front();
           tx_piso(serial_word);
          end
       end
    endtask

    task tx_piso(input bit [31:0] data_in);
      bit piso_data_out;
      `uvm_info("EP_PHY_DRIVER","ENTERED_INTO_PISO_TASK_EP",  UVM_LOW)
         // Serialize_each_32-bit_word
          for (int i = 0; i < 32; i++) begin
             piso_data_out = data_in[i];
             ep_phy_intf_tx.tx_plus  <= piso_data_out;
             ep_phy_intf_tx.tx_minus <= ~piso_data_out;
            `uvm_info("EP_PHY_DRIVER", $sformatf("EP_PHY_DRIVER_PISO_DATA_IN_PHY_BIT_BY_BIT[%0d] = %0b TIME=%0t ",i, piso_data_out, $time), UVM_LOW)
            -> ep_to_rc_bit_event;
             #31.25ps;
          end
           ep_phy_intf_tx.tx_plus  <= 1'b0;
           ep_phy_intf_tx.tx_minus <= 1'b1;
          `uvm_info("EP_PHY_DRIVER","EXIT_FROM_PISO_TASK_COMPLETED",UVM_LOW)
    endtask


endclass






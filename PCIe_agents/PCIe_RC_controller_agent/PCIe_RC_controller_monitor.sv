//=========================================================================================
// File         : PCIe_RC_controller_monitor.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_RC_controller_agent\PCIe_RC_controller_monitor.sv
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

class PCIe_RC_controller_monitor extends uvm_monitor;
  
  `uvm_component_utils(PCIe_RC_controller_monitor)
  
   PCIe_sequence_item            pcie_seq_item;
   PCIe_RC_PL_model              rc_pl_model;
   
   virtual PCIe_RC_interface     rc_pipe_intf_tx, rc_pipe_intf_rx;	
   uvm_analysis_port #(PCIe_sequence_item) rc_con_tx_mon_ap;	
  
   bit [1:0]  rx_previous_symbol;
   bit [22:0] lfsr;
   bit [22:0] polynomial;
   bit tx_parity;
   bit rx_parity;

   function new(string name="PCIe_RC_controller_monitor", uvm_component parent);
      super.new(name,parent);
   endfunction
  
   function void build_phase(uvm_phase phase);
     `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_MONITOR_BUILD_PHASE",UVM_LOW)
      super.build_phase(phase);
	  rc_con_tx_mon_ap =new("rc_con_tx_mon_ap",this);

       if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_tx))
          `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")

       if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_rx))
          `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")

           pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
           rx_previous_symbol = 2'b11;
           polynomial = 23'b101000010000000100100101;
           lfsr = 23'h7FFFFF;
       `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_MONITOR_BUILD_PHASE",UVM_LOW)
   endfunction
  
   task run_phase(uvm_phase phase);
      `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_MONITOR_RUN_PHASE",UVM_LOW)
      forever begin
       receiving_pipe_tx(rc_pipe_intf_tx);
      end
      `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_MONITOR_RUN_PHASE",UVM_LOW)
   endtask

   task receiving_pipe_tx(virtual PCIe_RC_interface rc_pipe_intf_tx);
      bit [31:0] tx_data;
      bit [31:0] deprecoded_data;
      bit [31:0] gray_decoded_data;
      bit [31:0] descrambled_data;
      bit        calculated_parity;
      
      `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_MONITOR_RECEIVING_PIPE_TX_DATA",UVM_LOW)
        wait(rc_pipe_intf_tx.tx_valid);
        
           while(rc_pipe_intf_tx.tx_valid)
           begin
            @(negedge rc_pipe_intf_tx.pclk);
              pcie_seq_item.tx_valid      = rc_pipe_intf_tx.tx_valid;
              pcie_seq_item.tx_elec_idle  = rc_pipe_intf_tx.tx_elec_idle;
              pcie_seq_item.tx_detect_rx  = rc_pipe_intf_tx.tx_detect_rx;
              pcie_seq_item.powerdown     = rc_pipe_intf_tx.powerdown;
              pcie_seq_item.rate          = rc_pipe_intf_tx.rate;
              if(pcie_seq_item.tx_valid)begin
               tx_data = rc_pipe_intf_tx.tx_data;
              
                de_precoder(tx_data, deprecoded_data);
               `uvm_info("RC_CONTROLLER_MON",$sformatf("AFTER_DEPRECODING = %08h",deprecoded_data),UVM_LOW);
               // parity_check(deprecoded_data);
                gray_decode(deprecoded_data,gray_decoded_data);
               `uvm_info("RC_CONTROLLER_MON",$sformatf("AFTER_GRAY_DECODE = %08h", gray_decoded_data),UVM_LOW);
                descrambler(gray_decoded_data,descrambled_data);
               `uvm_info("RC_CONTROLLER",$sformatf("FINAL_DESCRAMBLED_DATA = %08h", descrambled_data),UVM_LOW);
                pcie_seq_item.data_q_rc_mon_con.push_back(descrambled_data);
               `uvm_info("RC_PHY_DRIVER",$sformatf("RECEIVED_DATA_IN_RC_CONTROLLER_MONITOR = %08h RC_CONTROLLER_MON_Queue_Size = %0d",descrambled_data,pcie_seq_item.data_q_rc_mon_con.size()),UVM_LOW)
              rc_con_tx_mon_ap.write(pcie_seq_item);
              end
           end
           `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_MONITOR_RECEIVING_PIPE_TX_DATA",UVM_LOW)
   endtask

   task de_precoder(input bit [31:0] data_in, output bit [31:0] decoder_out);
     bit [1:0] current,dec;
         
     `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_MONITOR_DE_PRECODE_TASK",UVM_LOW)
      for(int i=0;i<32;i+=2) begin
        current = data_in[i+:2];
        dec = current^rx_previous_symbol;
        decoder_out[i+:2] = dec;
        rx_previous_symbol = current;
      end
     `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_MONITOR_DE_PRECODE_TASK",UVM_LOW)
   endtask
  
   task parity_check(input bit [31:0] gray_data);

     rx_parity = ^gray_data;
     if (rc_pl_model.tx_parity_q.size() == 0)
     begin
      `uvm_error("PARITY_CHECK", "TX PARITY_QUEUE_IS_EMPTY");
       return;
     end
     tx_parity = rc_pl_model.tx_parity_q.pop_front();
     `uvm_info("PARITY_CHECK",$sformatf("GRAY_DATA = %08h",gray_data),UVM_LOW)
     `uvm_info("PARITY_CHECK",$sformatf("TX_PARITY = %0b",tx_parity),UVM_LOW)
     `uvm_info("PARITY_CHECK",$sformatf("RX_PARITY = %0b",rx_parity),UVM_LOW)
   
     if (tx_parity == rx_parity)
     begin
      `uvm_info("PARITY_CHECK",$sformatf("********RC_CONTROLLER_MON_PARITY_PASS******** TX=%0b RX=%0b",tx_parity,rx_parity),UVM_LOW);
     end
     else
     begin
      `uvm_error("PARITY_CHECK",$sformatf("********RC_CONTROLLER_MON_PARITY_FAIL******** TX=%0b RX=%0b",tx_parity,rx_parity));
     end
   endtask

   task gray_decode(input  bit [31:0] data_in,output bit [31:0] gray_out);
     bit [1:0] symbol;
     `uvm_info("RC_CONTROLLE_MON", "ENTERED_INTO_RC_MON_GRAY_DECODE_TASK",UVM_LOW)
     
      for (int i = 0; i < 32; i += 2) begin
        symbol = data_in[i +: 2];
        case (symbol)
            2'b00: 
                  gray_out[i +: 2] = 2'b00;
            2'b01:
                  gray_out[i +: 2] = 2'b01;
            2'b11:
                  gray_out[i +: 2] = 2'b10;
            2'b10:
                  gray_out[i +: 2] = 2'b11;
            default:
                  gray_out[i +: 2] = 2'b00;
        endcase
     end
     `uvm_info("RC_CONTROLLE_MON", "EXIT_FROM_RC_MON_GRAY_DECODE_TASK",UVM_LOW)
   endtask

   task descrambler(input  bit [31:0] data_in,output bit [31:0] data_out);
     bit descramble_bit;
     data_out = data_in;
    
     `uvm_info("RC_CONTROLLER_MON","ENTERED_INTO_DESCRAMBLER_TASK",UVM_LOW)
        for (int i = 0; i < 32; i++) begin
          descramble_bit = lfsr[22];
          data_out[i] = data_in[i] ^ descramble_bit;
          if (descramble_bit) begin
              lfsr = (lfsr << 1) ^ polynomial;
          end
          else begin
              lfsr = (lfsr << 1);
          end
       end
       `uvm_info("PCIe_RC_CONTROLLER_MON",$sformatf("DESCRAMBLED_DATA = %08h",data_out), UVM_LOW)
       `uvm_info("PCIe_RC_CONTROLLER_MON","EXIT_FROM_DESCRAMBLER_TASK",UVM_LOW )
   endtask

endclass






   /*task parity_check(input bit [31:0] data_in,input bit  received_parity);
     bit calculated_parity;
     calculated_parity = 1'b0;
     `uvm_info("PARITY_CHECK", "ENTERED_INTO_RC_MON_PARITY_CHECK_TASK",UVM_LOW)
      for (int i = 31; i >= 0; i--) begin
        calculated_parity ^= data_in[i];
       `uvm_info("PARITY_CHECK",$sformatf("Bit[%0d]=%0b Running_Parity=%0b", i,data_in[i], calculated_parity),UVM_LOW)
      end
      `uvm_info("PARITY_CHECK",$sformatf("Calculated_Parity = %0b",calculated_parity), UVM_LOW)
      `uvm_info("PARITY_CHECK",$sformatf("Received_Parity = %0b", received_parity), UVM_LOW)

      if (calculated_parity == received_parity) begin
         `uvm_info("PARITY_CHECK","****** PARITY_PASS ********",UVM_LOW)
      end
      else begin
        `uvm_error("PARITY_CHECK","****** PARITY_FAIL ********")
      end
     `uvm_info("PARITY_CHECK", "EXIT_FROM_RC_MON_PARITY_CHECK_TASK",UVM_LOW)
   endtask*/


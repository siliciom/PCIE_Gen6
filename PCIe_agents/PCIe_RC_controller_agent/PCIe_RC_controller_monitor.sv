//=========================================================================================
// File         : PCIe_RC_controller_monitor.sv
// Project      : PCIe_Gen6
// Description  : PCIe_agents\PCIe_RC_controller_agent\PCIe_RC_controller_monitor.sv
// Author       :
// Date         : 2026-08-14
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

   PCIe_sequence_item pcie_seq_item;
   PCIe_RC_DL_model rc_dl_model;
   PCIe_EP_PL_model ep_pl_model;

   uvm_analysis_port #(PCIe_sequence_item) rc_mon_ap_dl;

   bit[`PCIe_MON_DATA_W-1:0]                        dl_flit_in[$];
   bit[0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0]      dlp;
   bit[0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp;
   bit is_valid=1;
   bit[`PCIe_PL_SYMBOL_W-1:0]                       rx_previous_symbol;
   bit[`PCIe_PL_SCRAMBLER_LFSR_W-1:0]               rx_lfsr;
   bit[`PCIe_PL_SCRAMBLER_LFSR_W-1:0]               rx_polynomial;
   bit[`PCIe_PL_SYMBOL_W-1:0]                       tx_previous_symbol;
   bit[`PCIe_PL_SCRAMBLER_LFSR_W-1:0]               tx_lfsr;
   bit[`PCIe_PL_SCRAMBLER_LFSR_W-1:0]               tx_polynomial;
   bit tx_parity;
   bit rx_parity;

   virtual PCIe_RC_interface rc_pipe_intf_tx,rc_pipe_intf_rx;
   uvm_analysis_port #(PCIe_sequence_item) rc_con_tx_mon_ap;
   uvm_analysis_port #(PCIe_sequence_item) rc_con_rx_mon_ap;

   function new(string name="PCIe_RC_controller_monitor",uvm_component parent);
      super.new(name,parent);
      rc_mon_ap_dl=new("rc_mon_ap_dl",this);
   endfunction

   function void build_phase(uvm_phase phase);
      `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_MONITOR_BUILD_PHASE",UVM_LOW)
      super.build_phase(phase);
      rc_con_tx_mon_ap=new("rc_con_tx_mon_ap",this);
      rc_con_rx_mon_ap=new("rc_con_rx_mon_ap",this);

      if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this,"","PCIe_RC_INTERFACE",rc_pipe_intf_tx))
         `uvm_fatal("NO_VIF","RC_PIPE_INTERFACE_not_found")

      if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this,"","PCIe_RC_INTERFACE",rc_pipe_intf_rx))
         `uvm_fatal("NO_VIF","RC_PIPE_INTERFACE_not_found")

      pcie_seq_item=PCIe_sequence_item::type_id::create("pcie_seq_item");
      rx_previous_symbol={`PCIe_PL_SYMBOL_W{1'b1}};
      rx_polynomial=`PCIe_PL_SCRAMBLER_POLYNOMIAL;
      rx_lfsr=`PCIe_PL_SCRAMBLER_SEED;

      tx_previous_symbol={`PCIe_PL_SYMBOL_W{1'b1}};
      tx_polynomial=`PCIe_PL_SCRAMBLER_POLYNOMIAL;
      tx_lfsr=`PCIe_PL_SCRAMBLER_SEED;
      `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_MONITOR_BUILD_PHASE",UVM_LOW)
   endfunction

   task run_phase(uvm_phase phase);
      `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_MONITOR_RUN_PHASE",UVM_LOW)
      forever begin
         fork
            receiving_pipe_tx(rc_pipe_intf_tx);
            receiving_pipe_rx(rc_pipe_intf_rx);
         join
      end
      `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_MONITOR_RUN_PHASE",UVM_LOW)
   endtask

   task receiving_pipe_tx(virtual PCIe_RC_interface rc_pipe_intf_tx);
      bit[`PCIe_MON_DATA_W-1:0] tx_data;
      bit[`PCIe_MON_DATA_W-1:0] deprecoded_data;
      bit[`PCIe_MON_DATA_W-1:0] gray_decoded_data;
      bit[`PCIe_MON_DATA_W-1:0] descrambled_data;
      bit calculated_parity;

      `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_MONITOR_RECEIVING_PIPE_TX_DATA",UVM_LOW)
      wait(rc_pipe_intf_tx.tx_valid);

      while(rc_pipe_intf_tx.tx_valid)
      begin
         @(negedge rc_pipe_intf_tx.pclk);
         pcie_seq_item.tx_valid=rc_pipe_intf_tx.tx_valid;
         pcie_seq_item.tx_elec_idle=rc_pipe_intf_tx.tx_elec_idle;
         pcie_seq_item.tx_detect_rx=rc_pipe_intf_tx.tx_detect_rx;
         pcie_seq_item.powerdown=rc_pipe_intf_tx.powerdown;
         pcie_seq_item.rate=rc_pipe_intf_tx.rate;

         if(pcie_seq_item.tx_valid)begin
            tx_data=rc_pipe_intf_tx.tx_data;

            de_precoder_tx(tx_data,deprecoded_data);
            `uvm_info("RC_CONTROLLER_MON",$sformatf("AFTER_DEPRECODING = %08h",deprecoded_data),UVM_LOW)

            gray_decode_tx(deprecoded_data,gray_decoded_data);
            `uvm_info("RC_CONTROLLER_MON",$sformatf("AFTER_GRAY_DECODE = %08h",gray_decoded_data),UVM_LOW)

            descrambler_tx(gray_decoded_data,descrambled_data);
            `uvm_info("RC_CONTROLLER",$sformatf("FINAL_DESCRAMBLED_DATA = %08h",descrambled_data),UVM_LOW)

            pcie_seq_item.data_q_rc_mon_con_tx.push_back(descrambled_data);
            `uvm_info("RC_PHY_DRIVER",$sformatf("RECEIVED_TX_DATA_IN_RC_CONTROLLER_MONITOR = %08h RC_CONTROLLER_MON_Queue_Size = %0d",descrambled_data,pcie_seq_item.data_q_rc_mon_con_tx.size()),UVM_LOW)

            rc_con_tx_mon_ap.write(pcie_seq_item);
         end
      end

      // send DLP data from here to scoreboard (RC--->EP)
      collect_dlp(dlp,pcie_seq_item);
      pcie_seq_item.dlp=dlp;
      rc_mon_ap_dl.write(pcie_seq_item);

      `uvm_info("RC_CON_MONITOR","The DLP packet sent to scoreboard",UVM_LOW)
      `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_MONITOR_RECEIVING_PIPE_TX_DATA",UVM_LOW)
   endtask

   task receiving_pipe_rx(virtual PCIe_RC_interface rc_pipe_intf_rx);
      bit[`PCIe_MON_DATA_W-1:0] rx_data;
      bit[`PCIe_MON_DATA_W-1:0] deprecoded_data;
      bit[`PCIe_MON_DATA_W-1:0] gray_decoded_data;
      bit[`PCIe_MON_DATA_W-1:0] descrambled_data;
      bit calculated_parity;

      `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_MONITOR_RECEIVING_PIPE_RX_DATA",UVM_LOW)
      wait(rc_pipe_intf_rx.rx_valid);

      while(rc_pipe_intf_rx.rx_valid)
      begin
         @(negedge rc_pipe_intf_rx.pclk);
         pcie_seq_item.rx_valid=rc_pipe_intf_rx.rx_valid;
         pcie_seq_item.rx_elec_idle=rc_pipe_intf_rx.rx_elec_idle;
         pcie_seq_item.rx_status=rc_pipe_intf_rx.rx_status;
         pcie_seq_item.phy_status=rc_pipe_intf_rx.phy_status;

         if(pcie_seq_item.rx_valid)begin
            rx_data=rc_pipe_intf_rx.rx_data;

            de_precoder_rx(rx_data,deprecoded_data);
            `uvm_info("RC_CONTROLLER_MON",$sformatf("AFTER_DEPRECODING = %08h",deprecoded_data),UVM_LOW)

            //parity_check_rx(deprecoded_data);

            gray_decode_rx(deprecoded_data,gray_decoded_data);
            `uvm_info("RC_CONTROLLER_MON",$sformatf("AFTER_GRAY_DECODE = %08h",gray_decoded_data),UVM_LOW)

            descrambler_rx(gray_decoded_data,descrambled_data);
            `uvm_info("RC_CONTROLLER",$sformatf("FINAL_DESCRAMBLED_DATA = %08h",descrambled_data),UVM_LOW)

            pcie_seq_item.data_q_rc_mon_con_rx.push_back(descrambled_data);
            `uvm_info("RC_CON_MONITOR",$sformatf("RECEIVED_RX_DATA_IN_RC_CONTROLLER_MONITOR = %08h RC_CONTROLLER_MON_Queue_Size = %0d",descrambled_data,pcie_seq_item.data_q_rc_mon_con_rx.size()),UVM_LOW)

            rc_con_rx_mon_ap.write(pcie_seq_item);
         end
      end

      `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_MONITOR_RECEIVING_PIPE_RX_DATA",UVM_LOW)
   endtask

   task de_precoder_tx(input bit[`PCIe_MON_DATA_W-1:0] data_in,output bit[`PCIe_MON_DATA_W-1:0] decoder_out);
      bit[`PCIe_PL_SYMBOL_W-1:0] current,dec;

      `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_MONITOR_DE_PRECODE_TASK",UVM_LOW)

      for(int i=0;i<`PCIe_MON_DATA_W;i+=`PCIe_PL_SYMBOL_W) begin
         current=data_in[i+:`PCIe_PL_SYMBOL_W];
         dec=current^tx_previous_symbol;
         decoder_out[i+:`PCIe_PL_SYMBOL_W]=dec;
         tx_previous_symbol=current;
      end

      `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_MONITOR_DE_PRECODE_TASK",UVM_LOW)
   endtask

   task gray_decode_tx(input bit[`PCIe_MON_DATA_W-1:0] data_in,output bit[`PCIe_MON_DATA_W-1:0] gray_out);
      bit[`PCIe_PL_SYMBOL_W-1:0] symbol;

      `uvm_info("RC_CONTROLLE_MON","ENTERED_INTO_RC_MON_GRAY_DECODE_TASK",UVM_LOW)

      for(int i=0;i<`PCIe_MON_DATA_W;i+=`PCIe_PL_SYMBOL_W) begin
         symbol=data_in[i+:`PCIe_PL_SYMBOL_W];
         case(symbol)
            2'b00:
               gray_out[i+:`PCIe_PL_SYMBOL_W]=2'b00;
            2'b01:
               gray_out[i+:`PCIe_PL_SYMBOL_W]=2'b01;
            2'b11:
               gray_out[i+:`PCIe_PL_SYMBOL_W]=2'b10;
            2'b10:
               gray_out[i+:`PCIe_PL_SYMBOL_W]=2'b11;
            default:
               gray_out[i+:`PCIe_PL_SYMBOL_W]=2'b00;
         endcase
      end

      `uvm_info("RC_CONTROLLE_MON","EXIT_FROM_RC_MON_GRAY_DECODE_TASK",UVM_LOW)
   endtask

   task descrambler_tx(input bit[`PCIe_MON_DATA_W-1:0] data_in,output bit[`PCIe_MON_DATA_W-1:0] data_out);
      bit descramble_bit;
      data_out=data_in;

      `uvm_info("RC_CONTROLLER_MON","ENTERED_INTO_DESCRAMBLER_TASK",UVM_LOW)

      for(int i=0;i<`PCIe_MON_DATA_W;i++) begin
         descramble_bit=tx_lfsr[`PCIe_PL_SCRAMBLER_LFSR_W-1];
         data_out[i]=data_in[i]^descramble_bit;

         if(descramble_bit) begin
            tx_lfsr=(tx_lfsr<<1)^tx_polynomial;
         end
         else begin
            tx_lfsr=(tx_lfsr<<1);
         end
      end

      `uvm_info("PCIe_RC_CONTROLLER_MON",$sformatf("DESCRAMBLED_DATA = %08h",data_out),UVM_LOW)
      `uvm_info("PCIe_RC_CONTROLLER_MON","EXIT_FROM_DESCRAMBLER_TASK",UVM_LOW)
   endtask

   task de_precoder_rx(input bit[`PCIe_MON_DATA_W-1:0] data_in,output bit[`PCIe_MON_DATA_W-1:0] decoder_out);
      bit[`PCIe_PL_SYMBOL_W-1:0] current,dec;

      `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_MONITOR_DE_PRECODE_RX_TASK",UVM_LOW)

      for(int i=0;i<`PCIe_MON_DATA_W;i+=`PCIe_PL_SYMBOL_W) begin
         current=data_in[i+:`PCIe_PL_SYMBOL_W];
         dec=current^rx_previous_symbol;
         decoder_out[i+:`PCIe_PL_SYMBOL_W]=dec;
         rx_previous_symbol=current;
      end

      `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_MONITOR_DE_PRECODE_RX_TASK",UVM_LOW)
   endtask

   task gray_decode_rx(input bit[`PCIe_MON_DATA_W-1:0] data_in,output bit[`PCIe_MON_DATA_W-1:0] gray_out);
      bit[`PCIe_PL_SYMBOL_W-1:0] symbol;

      `uvm_info("RC_CONTROLLE_MON","ENTERED_INTO_RC_MON_GRAY_DECODE_RX_TASK",UVM_LOW)

      for(int i=0;i<`PCIe_MON_DATA_W;i+=`PCIe_PL_SYMBOL_W) begin
         symbol=data_in[i+:`PCIe_PL_SYMBOL_W];
         case(symbol)
            2'b00:
               gray_out[i+:`PCIe_PL_SYMBOL_W]=2'b00;
            2'b01:
               gray_out[i+:`PCIe_PL_SYMBOL_W]=2'b01;
            2'b11:
               gray_out[i+:`PCIe_PL_SYMBOL_W]=2'b10;
            2'b10:
               gray_out[i+:`PCIe_PL_SYMBOL_W]=2'b11;
            default:
               gray_out[i+:`PCIe_PL_SYMBOL_W]=2'b00;
         endcase
      end

      `uvm_info("RC_CONTROLLE_MON","EXIT_FROM_RC_MON_GRAY_DECODE_RX_TASK",UVM_LOW)
   endtask

   task descrambler_rx(input bit[`PCIe_MON_DATA_W-1:0] data_in,output bit[`PCIe_MON_DATA_W-1:0] data_out);
      bit descramble_bit;
      data_out=data_in;

      `uvm_info("RC_CONTROLLER_MON","ENTERED_INTO_DESCRAMBLER_RX_TASK",UVM_LOW)

      for(int i=0;i<`PCIe_MON_DATA_W;i++) begin
         descramble_bit=rx_lfsr[`PCIe_PL_SCRAMBLER_LFSR_W-1];
         data_out[i]=data_in[i]^descramble_bit;

         if(descramble_bit) begin
            rx_lfsr=(rx_lfsr<<1)^rx_polynomial;
         end
         else begin
            rx_lfsr=(rx_lfsr<<1);
         end
      end

      `uvm_info("PCIe_RC_CONTROLLER_MON",$sformatf("DESCRAMBLED_DATA = %08h",data_out),UVM_LOW)
      `uvm_info("PCIe_RC_CONTROLLER_MON","EXIT_FROM_DESCRAMBLER_RX_TASK",UVM_LOW)
   endtask

   /*task parity_check_rx(input bit[`PCIe_MON_DATA_W-1:0] gray_data);

     rx_parity=^gray_data;
     if(ep_pl_model.tx_parity_q.size()==0)
     begin
      `uvm_error("RC_CONTROLLER_MON_PARITY_CHECK","RX_PARITY_QUEUE_IS_EMPTY");
      return;
     end

     tx_parity=ep_pl_model.tx_parity_q.pop_front();

     `uvm_info("RC_CONTROLLER_MON_PARITY_CHECK",$sformatf("GRAY_DATA = %08h",gray_data),UVM_LOW)
     `uvm_info("RC_CONTROLLER_MON_PARITY_CHECK",$sformatf("TX_PARITY = %0b",tx_parity),UVM_LOW)
     `uvm_info("RC_CONTROLLER_MON_PARITY_CHECK",$sformatf("RX_PARITY = %0b",rx_parity),UVM_LOW)

     if(tx_parity==rx_parity)
     begin
      `uvm_info("RC_CONTROLLER_MON_PARITY_CHECK",$sformatf("********RC_CONTROLLR_MON_PARITY_PASS******** TX=%0b RX=%0b",tx_parity,rx_parity),UVM_LOW);
     end
     else
     begin
      `uvm_error("RC_CONTROLLER_MON_PARITY_CHECK",$sformatf("********RC_CONTROLLER_MON_PARITY_FAIL******** TX=%0b RX=%0b",tx_parity,rx_parity));
     end
   endtask*/

   // collect the flit 242 bytes from the pipe interface
   task collect_dlp(output bit[0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp,ref PCIe_sequence_item item);
      if(item==null) begin
         `uvm_fatal("NULL_ITEM","collect_dlp() received NULL PCIe_sequence_item")
      end

      // Form tlp to send to scoreboard
      for(int i=0;i<`PCIe_TLP_DATA_BYTE_W;i++) begin
         tlp[i]=item.data_q_rc_mon_con_tx[i];
      end

      // Last 6 bytes = DLP
      for(int i=0;i<`PCIe_DLP_BYTE_W;i++) begin
         dlp[i]=item.data_q_rc_mon_con_tx[`PCIe_TLP_DATA_BYTE_W+i];
      end

      `uvm_info("RC_CON_MONITOR",$sformatf("collected tlp from rc monitor is tlp=%p",tlp),UVM_LOW);
      `uvm_info("RC_CON_MONITOR",$sformatf("collected tlp from rc monitor is dlp=%p",dlp),UVM_LOW);
   endtask

endclass

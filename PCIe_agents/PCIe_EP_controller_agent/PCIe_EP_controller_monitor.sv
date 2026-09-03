//=========================================================================================
// File         : PCIe_EP_controller_monitor.sv
// Project      : PCIe_Gen6
// Description  : PCIe_agents\PCIe_EP_controller_agent\PCIe_EP_controller_monitor.sv
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

class PCIe_EP_controller_monitor extends uvm_monitor;
  
   `uvm_component_utils(PCIe_EP_controller_monitor)
  
   uvm_analysis_port #(PCIe_sequence_item) ep_ap_mon_dl; //RC to EP DLP
   uvm_analysis_port #(PCIe_sequence_item) ep_rc_ap_mon_dl; //EP to RC DLP

   PCIe_sequence_item            pcie_seq_item;
   PCIe_EP_TL_model              ep_tl_model;
   PCIe_EP_DL_model              ep_dl_model;
   PCIe_EP_PL_model              ep_pl_model;

    bit tx_parity;
    bit rx_parity;
  
    bit[`PCIe_MON_DATA_W-1:0]dl_flit_in[$];
    bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp_ep_tx;
    bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_ep_tx;
    bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp_ep_rx;
    bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_ep_rx;
    bit is_valid=1;
     
    virtual PCIe_EP_interface     ep_pipe_intf_tx, ep_pipe_intf_rx;	
    uvm_analysis_port #(PCIe_sequence_item) ep_con_rx_mon_ap;	
    uvm_analysis_port #(PCIe_sequence_item) ep_con_tx_mon_ap;	
     
    bit [1:0]  rx_previous_symbol;
    bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] rx_lfsr;
    bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] rx_polynomial;
    bit [1:0]  tx_previous_symbol;
    bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] tx_lfsr;
    bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] tx_polynomial;

   function new(string name="PCIe_EP_controller_monitor", uvm_component parent);
      super.new(name,parent);
    ep_ap_mon_dl=new("ep_ap_mon_dl",this);
    ep_rc_ap_mon_dl=new("ep_rc_ap_mon_dl",this);
   endfunction

function void build_phase(uvm_phase phase);
       `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_MONITOR_BUILD_PHASE",UVM_LOW)
        super.build_phase(phase);
 	   ep_con_rx_mon_ap =new("ep_con_rx_mon_ap",this);
 	   ep_con_tx_mon_ap =new("ep_con_tx_mon_ap",this);
            ep_pl_model = PCIe_EP_PL_model::type_id::create("ep_pl_model", this);
        if (!uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_pipe_intf_tx))
           `uvm_fatal("NO_VIF", "EP_PIPE_INTERFACE_not_found")
        if (!uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_pipe_intf_rx))
           `uvm_fatal("NO_VIF", "EP_PIPE_INTERFACE_not_found")
            pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
            rx_previous_symbol = `PCIe_INIT_PREVIOUS_SYMBOL;
            rx_polynomial = `PCIe_PL_SCRAMBLER_POLYNOMIAL;
            rx_lfsr = `PCIe_PL_SCRAMBLER_SEED;

            tx_previous_symbol = `PCIe_INIT_PREVIOUS_SYMBOL;
            tx_polynomial = `PCIe_PL_SCRAMBLER_POLYNOMIAL;
            tx_lfsr = `PCIe_PL_SCRAMBLER_SEED;

       `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_MONITOR_BUILD_PHASE",UVM_LOW)
    endfunction

task run_phase(uvm_phase phase);
       `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_MONITOR_RUN_PHASE",UVM_LOW)
       fork
         forever begin
            receiving_pipe_rx(ep_pipe_intf_rx);
         end
         forever begin
            receiving_pipe_tx(ep_pipe_intf_tx);
         end
       join
       `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_MONITOR_RUN_PHASE",UVM_LOW)
    endtask

 
task receiving_pipe_rx(virtual PCIe_EP_interface ep_pipe_intf_rx);
         bit [31:0] rx_data;
         bit [31:0] deprecoded_data;
         bit [31:0] gray_decoded_data;
         bit [31:0] descrambled_data;
         bit        calculated_parity;
         int        rx_dword_count;
         int        os_count;
         int        dword_in_os;
         bit        in_os_burst;
         `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_MONITOR_RECEIVING_PIPE_RX_DATA",UVM_LOW)
            wait(ep_pipe_intf_rx.rx_valid);
            rx_dword_count = 0;
            os_count = 0;
            dword_in_os = 0;

            while(ep_pipe_intf_rx.rx_valid)
            begin
               @(negedge ep_pipe_intf_rx.pclk);
               pcie_seq_item.rx_valid      = ep_pipe_intf_rx.rx_valid;
               pcie_seq_item.rx_elec_idle  = ep_pipe_intf_rx.rx_elec_idle;
               pcie_seq_item.rx_status     = ep_pipe_intf_rx.rx_status;
               pcie_seq_item.phy_status    = ep_pipe_intf_rx.phy_status;
  	      
               in_os_burst = (ep_pl_model.ep_main_state == POLLING);

               if(pcie_seq_item.rx_valid)begin
                  rx_data = ep_pipe_intf_rx.rx_data;
                  rx_dword_count++;
                  de_precoder_rx(rx_data, deprecoded_data);
                  `uvm_info("EP_CONTROLLER_MON",$sformatf("AFTER_DEPRECODING = %08h",deprecoded_data),UVM_LOW);
                  gray_decode_rx(deprecoded_data,gray_decoded_data);
                  `uvm_info("EP_CONTROLLER_MON",$sformatf("AFTER_GRAY_DECODE = %08h", gray_decoded_data),UVM_LOW);
                  
                  if (in_os_burst && (dword_in_os == 0) && (os_count == 0 || os_count == 8 || os_count == 15)) begin
                     descrambled_data = gray_decoded_data;
                     `uvm_info("EP_CONTROLLER",$sformatf("OS_BURST OS=%0d DWORD=0 DESCRAMBLE_BYPASSED FINAL_DATA=%08h",os_count,descrambled_data),UVM_LOW);
                  end
                  else begin
                     descrambler_rx(gray_decoded_data,descrambled_data);
                     `uvm_info("EP_CONTROLLER",$sformatf("DESCRAMBLED FINAL_DATA=%08h (IN_OS_BURST=%0b OS=%0d DW=%0d)",descrambled_data,in_os_burst,os_count,dword_in_os),UVM_LOW);
                  end
                  
                  pcie_seq_item.data_q_ep_mon_con_rx.push_back(descrambled_data);
                  `uvm_info("EP_CON_MONITOR",$sformatf("RECEIVED_RX_DATA_IN_EP_CONTROLLER_MONITOR = %08h EP_CONTROLLER_MON_Queue_Size = %0d",descrambled_data,pcie_seq_item.data_q_ep_mon_con_rx.size()),UVM_LOW)
                  //ep_con_rx_mon_ap.write(pcie_seq_item);
                  dword_in_os++;
                  if (dword_in_os == 4) begin
                     dword_in_os = 0;
                     os_count++;
                  end
               end
            end
   // (Packet collected sent by RC here :: Expected Packet)
   if(ep_pl_model.link_up==1) begin  
    collect_dlp_EP_rx(dlp_ep_rx,pcie_seq_item);
    ep_dl_model.handle_incoming_flit(dlp_ep_rx,is_valid);
    //if(ep_dl_model.success) begin
      pcie_seq_item.dlp=dlp_ep_rx;
      `uvm_info("EP_CON_MONITOR",$sformatf("RECEIVED_DATA_IN_EP_CONTROLLER_MONITOR_FOR_DLP = %0p",pcie_seq_item.dlp),UVM_LOW)
       ep_ap_mon_dl.write(pcie_seq_item);
      end
         `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_MONITOR_RECEIVING_PIPE_RX_DATA",UVM_LOW)
      endtask

task receiving_pipe_tx(virtual PCIe_EP_interface ep_pipe_intf_tx);
    bit [31:0] tx_data;
    bit [31:0] deprecoded_data;
    bit [31:0] gray_decoded_data;
    bit [31:0] descrambled_data;
    int        tx_dword_count;
    int        os_count;
    int        dword_in_os;
    bit        in_os_burst;

    `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_MONITOR_RECEIVING_PIPE_TX_DATA",UVM_LOW)
       wait(ep_pipe_intf_tx.tx_valid);
       tx_dword_count = 0;
       os_count = 0;
       dword_in_os = 0;

       while (ep_pipe_intf_tx.tx_valid) begin
          @(negedge ep_pipe_intf_tx.pclk);
          pcie_seq_item.tx_valid      = ep_pipe_intf_tx.tx_valid;
          pcie_seq_item.tx_elec_idle  = ep_pipe_intf_tx.tx_elec_idle;
          pcie_seq_item.tx_detect_rx  = ep_pipe_intf_tx.tx_detect_rx;
          pcie_seq_item.powerdown     = ep_pipe_intf_tx.powerdown;
          pcie_seq_item.rate          = ep_pipe_intf_tx.rate;

          in_os_burst = (ep_pl_model.ep_main_state == POLLING);

          if (pcie_seq_item.tx_valid) begin
             tx_data = ep_pipe_intf_tx.tx_data;
             de_precoder_tx(tx_data, deprecoded_data);
             `uvm_info("EP_CONTROLLER_MON",$sformatf("AFTER_DEPRECODING = %08h",deprecoded_data),UVM_LOW);

             gray_decode_tx(deprecoded_data, gray_decoded_data);
             `uvm_info("EP_CONTROLLER_MON",$sformatf("AFTER_GRAY_DECODE = %08h", gray_decoded_data),UVM_LOW);

             if (in_os_burst && (dword_in_os == 0) && (os_count == 0 || os_count == 8 || os_count == 15)) begin
                descrambled_data = gray_decoded_data;
                `uvm_info("EP_CONTROLLER",$sformatf("OS_BURST OS=%0d DWORD=0 DESCRAMBLE_BYPASSED FINAL_DATA=%08h",os_count,descrambled_data),UVM_LOW);
             end
             else begin
                descrambler_tx(gray_decoded_data, descrambled_data);
                `uvm_info("EP_CONTROLLER",$sformatf("DESCRAMBLED FINAL_DATA=%08h (IN_OS_BURST=%0b OS=%0d DW=%0d)",descrambled_data,in_os_burst,os_count,dword_in_os),UVM_LOW);
             end

             pcie_seq_item.data_q_ep_mon_con_tx.push_back(descrambled_data);
             `uvm_info("EP_PHY_DRIVER",$sformatf("RECEIVED_TX_DATA_IN_EP_CONTROLLER_MONITOR = %08h EP_CONTROLLER_MON_Queue_Size = %0d",descrambled_data,pcie_seq_item.data_q_ep_mon_con_tx.size()),UVM_LOW)
             //ep_con_tx_mon_ap.write(pcie_seq_item);

             tx_dword_count++;
             dword_in_os++;
             if (dword_in_os == 4) begin
                dword_in_os = 0;
                os_count++;
             end
          end
       end
       //(when EP sends the packet to RC :: Actual Packet)
       if(ep_pl_model.link_up == 1)begin
     collect_dlp_EP_tx(dlp_ep_tx,pcie_seq_item);
      pcie_seq_item.dlp=dlp_ep_tx;
      `uvm_info("EP_CON_MONITOR",$sformatf("RECEIVED_TX_DATA_IN_EP_CONTROLLER_MONITOR_FOR_DLP = %0p",pcie_seq_item.dlp),UVM_LOW)
       ep_rc_ap_mon_dl.write(pcie_seq_item);
      end
    `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_MONITOR_RECEIVING_PIPE_TX_DATA",UVM_LOW)
 endtask

task de_precoder_rx(input bit [`PCIe_MON_DATA_W-1:0] data_in, output bit [`PCIe_MON_DATA_W-1:0] decoder_out);
      bit [1:0] current,dec;
      `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_MONITOR_DE_PRECODE_TASK",UVM_LOW)
       for(int i=0;i<`PCIe_MON_DATA_W;i+=2) begin
         current = data_in[i+:2];
         dec = current^rx_previous_symbol;
         decoder_out[i+:2] = dec;
         rx_previous_symbol = current;
       end
      `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_MONITOR_DE_PRECODE_TASK",UVM_LOW)
    endtask
   
    task gray_decode_rx(input  bit [`PCIe_MON_DATA_W-1:0] data_in,output bit [`PCIe_MON_DATA_W-1:0] gray_out);
      bit [1:0] symbol;
      `uvm_info("EP_CONTROLLE_MON", "ENTERED_INTO_EP_MON_GRAY_DECODE_TASK",UVM_LOW)
      
       for (int i = 0; i < `PCIe_MON_DATA_W; i += 2) begin
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
        `uvm_info("EP_CONTROLLE_MON", "EXIT_FROM_EP_MON_GRAY_DECODE_TASK",UVM_LOW)
    endtask

    task descrambler_rx(input  bit [`PCIe_MON_DATA_W-1:0] data_in,output bit [`PCIe_MON_DATA_W-1:0] data_out);
      bit descramble_bit;
      data_out = data_in;
     
      `uvm_info("EP_CONTROLLER_MON","ENTERED_INTO_DESCRAMBLER_TASK",UVM_LOW)
         for (int i = 0; i < `PCIe_MON_DATA_W; i++) begin
           descramble_bit = rx_lfsr[`PCIe_PL_SCRAMBLER_LFSR_W-1];
           data_out[i] = data_in[i] ^ descramble_bit;
           if (descramble_bit) begin
               rx_lfsr = (rx_lfsr << 1) ^ rx_polynomial;
           end
           else begin
               rx_lfsr = (rx_lfsr << 1);
           end
        end
        `uvm_info("PCIe_EP_CONTROLLER_MON",$sformatf("DESCRAMBLED_DATA = %08h",data_out), UVM_LOW)
        `uvm_info("PCIe_EP_CONTROLLER_MON","EXIT_FROM_DESCRAMBLER_RX_TASK",UVM_LOW )
    endtask

    task de_precoder_tx(input bit [`PCIe_MON_DATA_W-1:0] data_in, output bit [`PCIe_MON_DATA_W-1:0] decoder_out);
        bit [1:0] current,dec;
       `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_MONITOR_DE_PRECODE_TX_TASK",UVM_LOW)
        for(int i=0;i<`PCIe_MON_DATA_W;i+=2) begin
          current = data_in[i+:2];
          dec = current^tx_previous_symbol;
          decoder_out[i+:2] = dec;
          tx_previous_symbol = current;
        end
       `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_MONITOR_DE_PRECODE_TX_TASK",UVM_LOW)
    endtask
  
    /*task parity_check_rx(input bit [31:0] gray_data);
       rx_parity = ^gray_data;
       if (rc_pl_model.tx_parity_q.size() == 0)
       begin
        `uvm_error("EP_CONTROLLER_MON_PARITY_CHECK", "TX_PARITY_QUEUE_IS_EMPTY");
         return;
       end
       tx_parity = rc_pl_model.tx_parity_q.pop_front();
       `uvm_info("EP_CONTROLLER_MON_PARITY_CHECK",$sformatf("GRAY_DATA = %08h",gray_data),UVM_LOW)
       `uvm_info("EP_CONTROLLER_MON_PARITY_CHECK",$sformatf("TX_PARITY = %0b",tx_parity),UVM_LOW)
       `uvm_info("EP_CONTROLLER_MON_PARITY_CHECK",$sformatf("RX_PARITY = %0b",rx_parity),UVM_LOW)
   
       if (tx_parity == rx_parity)
       begin
        `uvm_info("EP_CONTROLLER_MON_PARITY_CHECK",$sformatf("********EP_CONTROLLR_MON_PARITY_PASS******** TX=%0b RX=%0b",tx_parity,rx_parity),UVM_LOW);
       end
       else
       begin
        `uvm_error("EP_CONTROLLER_MON_PARITY_CHECK",$sformatf("********EP_CONTROLLER_MON_PARITY_FAIL******** TX=%0b RX=%0b",tx_parity,rx_parity));
       end
    endtask*/
  
task gray_decode_tx(input  bit [`PCIe_MON_DATA_W-1:0] data_in,output bit [`PCIe_MON_DATA_W-1:0] gray_out);
        bit [1:0] symbol;
        `uvm_info("EP_CONTROLLE_MON", "ENTERED_INTO_EP_MON_GRAY_DECODE_TX_TASK",UVM_LOW)
        
         for (int i = 0; i < `PCIe_MON_DATA_W; i += 2) begin
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
        `uvm_info("EP_CONTROLLE_MON", "EXIT_FROM_EP_MON_GRAY_DECODE_TX_TASK",UVM_LOW)
    endtask

    task descrambler_tx(input  bit [`PCIe_MON_DATA_W-1:0] data_in,output bit [`PCIe_MON_DATA_W-1:0] data_out);
      bit descramble_bit;
      data_out = data_in;
      `uvm_info("EP_CONTROLLER_MON","ENTERED_INTO_DESCRAMBLER_TX_TASK",UVM_LOW)
        for (int i = 0; i < `PCIe_MON_DATA_W; i++) begin
          descramble_bit = tx_lfsr[`PCIe_PL_SCRAMBLER_LFSR_W-1];
          data_out[i] = data_in[i] ^ descramble_bit;
          if (descramble_bit) begin
              tx_lfsr = (tx_lfsr << 1) ^ tx_polynomial;
          end
          else begin
              tx_lfsr = (tx_lfsr << 1);
          end
       end
        `uvm_info("PCIe_EP_CONTROLLER_MON",$sformatf("DESCRAMBLED_DATA = %08h",data_out), UVM_LOW)
        `uvm_info("PCIe_EP_CONTROLLER_MON","EXIT_FROM_DESCRAMBLER_TX_TASK",UVM_LOW )
      endtask
      
  // Collect the FLIT DLP from the PIPE interface.
  task collect_dlp_EP_tx(output bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp_ep_tx,ref PCIe_sequence_item item);
    //`uvm_info("EP_CON_MONITOR",$sformatf("PCIE_SEQ_ITEM =%p",item),UVM_LOW)

    if(item==null) begin
      `uvm_fatal("NULL_ITEM","collect_dlp() received NULL PCIe_sequence_item")
    end

    // Form TLP to send to scoreboard.
    for(int i=0;i<`PCIe_TLP_DATA_BYTE_W;i++) begin
      tlp_ep_tx[i]=item.data_q_ep_mon_con_tx[i];
    end

    // Last 6 bytes = DLP.
    for(int i=0;i<`PCIe_DLP_BYTE_W;i++) begin
      dlp_ep_tx[i]=item.data_q_ep_mon_con_tx[`PCIe_TLP_DATA_BYTE_W+i];
    end

    ep_dl_model.rx_retry_buffer.push_back(dlp_ep_tx);

    `uvm_info("EP_CON_MONITOR",$sformatf("collected tlp_ep_tx from ep monitor is tlp=%p",tlp_ep_tx),UVM_LOW)
    `uvm_info("EP_CON_MONITOR",$sformatf("collected dlp_ep_tx ep monitor is dlp=%p",dlp_ep_tx),UVM_LOW)
  endtask

  // Collect the FLIT DLP from the PIPE interface.
  task collect_dlp_EP_rx(output bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp_ep_rx,ref PCIe_sequence_item item);
    //`uvm_info("EP_CON_MONITOR",$sformatf("PCIE_SEQ_ITEM =%p",item),UVM_LOW)

    if(item==null) begin
      `uvm_fatal("NULL_ITEM","collect_dlp() received NULL PCIe_sequence_item")
    end

    // Form TLP to send to scoreboard.
    for(int i=0;i<`PCIe_TLP_DATA_BYTE_W;i++) begin
      tlp_ep_rx[i]=item.data_q_ep_mon_con_rx[i];
    end

    // Last 6 bytes = DLP.
    for(int i=0;i<`PCIe_DLP_BYTE_W;i++) begin
      dlp_ep_rx[i]=item.data_q_ep_mon_con_rx[`PCIe_TLP_DATA_BYTE_W+i];
    end

    ep_dl_model.rx_retry_buffer.push_back(dlp_ep_rx);

    `uvm_info("EP_CON_MONITOR",$sformatf("collected tlp_ep_rx from ep monitor is tlp=%p",tlp_ep_rx),UVM_LOW)
    `uvm_info("EP_CON_MONITOR",$sformatf("collected dlp_ep_rx from ep monitor is dlp=%p",dlp_ep_rx),UVM_LOW)
  endtask


endclass

	

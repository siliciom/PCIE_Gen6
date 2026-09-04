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
  
   PCIe_sequence_item            pcie_seq_item;
   PCIe_RC_TL_model              rc_tl_model;
   PCIe_RC_DL_model              rc_dl_model;
   PCIe_RC_PL_model              rc_pl_model;

   uvm_analysis_port #(PCIe_sequence_item) rc_mon_ap;
	
    bit[`PCIe_MON_DATA_W-1:0]       dl_flit_in[$];
    bit[0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0]   dlp;
    bit[0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp;
    bit             is_valid=1;
    bit [1:0]       rx_previous_symbol;
    bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0]      rx_lfsr;
    bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0]      rx_polynomial;
    bit [1:0]       tx_previous_symbol;
    bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0]      tx_lfsr;
    bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0]      tx_polynomial;
    bit             tx_parity;
    bit             rx_parity;

    // OS-mode tracking: replaces broken link_up-based bypass.
    // The monitor's PL model instance never runs the LTSSM, so link_up
    // was always 0 — keeping bypass active even during FLIT data.
    // We use a DWORD counter instead: bypass active for the first 232
    // training DWORDs, then OFF permanently (full descramble).
    bit             tx_in_os;
    int             tx_os_dword_count;
    bit             rx_in_os;
    int             rx_os_dword_count;

    virtual PCIe_RC_interface     rc_pipe_intf_tx, rc_pipe_intf_rx;
    uvm_analysis_port #(PCIe_sequence_item) rc_con_tx_mon_ap;
    uvm_analysis_port #(PCIe_sequence_item) rc_con_rx_mon_ap;	
 
    function new(string name="PCIe_RC_controller_monitor", uvm_component parent);
     super.new(name,parent);
     rc_mon_ap=new("rc_mon_ap",this);
    endfunction

    function void build_phase(uvm_phase phase);
     `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_MONITOR_BUILD_PHASE",UVM_LOW)
      super.build_phase(phase);
 	  rc_con_tx_mon_ap =new("rc_con_tx_mon_ap",this);
 	  rc_con_rx_mon_ap =new("rc_con_rx_mon_ap",this);
      rc_pl_model = PCIe_RC_PL_model::type_id::create("rc_pl_model", this);
    
      if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_tx))
            `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")
      if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_rx))
             `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")
      
       pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
       rx_previous_symbol = `PCIe_INIT_PREVIOUS_SYMBOL;
       rx_polynomial = `PCIe_PL_SCRAMBLER_POLYNOMIAL;
       rx_lfsr = `PCIe_PL_SCRAMBLER_SEED;
       tx_previous_symbol = `PCIe_INIT_PREVIOUS_SYMBOL;
       tx_polynomial = `PCIe_PL_SCRAMBLER_POLYNOMIAL;
       tx_lfsr = `PCIe_PL_SCRAMBLER_SEED;
       tx_in_os         = 1'b1;
       tx_os_dword_count = 0;
       rx_in_os         = 1'b1;
       rx_os_dword_count = 0;
        `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_MONITOR_BUILD_PHASE",UVM_LOW)
    endfunction
  
    task run_phase(uvm_phase phase);
       `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_MONITOR_RUN_PHASE",UVM_LOW)
       fork
         forever begin
            receiving_pipe_tx(rc_pipe_intf_tx);
         end
         forever begin
            receiving_pipe_rx(rc_pipe_intf_rx);
         end
       join
       `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_MONITOR_RUN_PHASE",UVM_LOW)
    endtask

    task receiving_pipe_tx(virtual PCIe_RC_interface rc_pipe_intf_tx);
      bit [`PCIe_MON_DATA_W-1:0] tx_data;
      bit [`PCIe_MON_DATA_W-1:0] deprecoded_data;
      bit [`PCIe_MON_DATA_W-1:0] gray_decoded_data;
      bit [`PCIe_MON_DATA_W-1:0] descrambled_data;
      bit [`PCIe_MON_DATA-1:0]  decoded_symbol;
      bit [`PCIe_MON_DATA-1:0]  original_symbol;
      bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] lfsr_before;

      int        dword_in_os;
      int        byte_idx;
      int        symbol_idx;

      `uvm_info("RC_CONTROLLER", "ENTERED_INTO_RC_CONTROLLER_MONITOR_RECEIVING_PIPE_TX_DATA", UVM_LOW)
      wait(rc_pipe_intf_tx.tx_valid);

      dword_in_os = 0;

      while (rc_pipe_intf_tx.tx_valid) begin
         @(negedge rc_pipe_intf_tx.pclk);
         pcie_seq_item.tx_valid     = rc_pipe_intf_tx.tx_valid;
         pcie_seq_item.tx_elec_idle = rc_pipe_intf_tx.tx_elec_idle;
         pcie_seq_item.tx_detect_rx = rc_pipe_intf_tx.tx_detect_rx;
         pcie_seq_item.powerdown    = rc_pipe_intf_tx.powerdown;
         pcie_seq_item.rate         = rc_pipe_intf_tx.rate;

         if (pcie_seq_item.tx_valid) begin
            tx_data = rc_pipe_intf_tx.tx_data;

            `uvm_info("RC_CONTROLLER", $sformatf(
               "[TX_DBG] LTSSM=%s IN_OS=%0b DWORD_CNT=%0d DWORD_IN_OS=%0d LFSR=%06h PIPE=%08h",
               rc_pl_model.rc_main_state.name(), tx_in_os,
               tx_os_dword_count, dword_in_os, tx_lfsr, tx_data), UVM_LOW)

            // 1. Reverse PRECODING
            de_precoder_tx(tx_data, deprecoded_data);
            `uvm_info("RC_CONTROLLER", $sformatf("TX DWORD=%0d PIPE=%08h DEPRECODED=%08h",
                       tx_os_dword_count, tx_data, deprecoded_data), UVM_LOW)

            // 2. Reverse GRAY ENCODING
            gray_decode_tx(deprecoded_data, gray_decoded_data);
            `uvm_info("RC_CONTROLLER", $sformatf("TX DWORD=%0d GRAY_DECODED=%08h",
                       tx_os_dword_count, gray_decoded_data), UVM_LOW)

            descrambled_data = gray_decoded_data;

            // 3. Reverse SCRAMBLING SYMBOL BY SYMBOL
            for (byte_idx = 0; byte_idx < 4; byte_idx++) begin
               symbol_idx = (dword_in_os * 4) + byte_idx;
               decoded_symbol = gray_decoded_data[(byte_idx * 8) +: 8];
               lfsr_before = tx_lfsr;

               if (tx_in_os && ((symbol_idx == 0) || (symbol_idx == 8) || (symbol_idx == 15))) begin
                  // BYPASS — training ordered-set bypass symbols
                  original_symbol = decoded_symbol;
                  `uvm_info("RC_CONTROLLER", $sformatf(
                     "[TX_DBG] BYPASS DWORD=%0d SYM=%0d LFSR_NA=%06h DATA=%02h",
                     tx_os_dword_count, symbol_idx, tx_lfsr, original_symbol), UVM_LOW)
               end
               else begin
                  // NORMAL DESCRAMBLING
                  descrambler_tx(decoded_symbol, original_symbol);
                  `uvm_info("RC_CONTROLLER", $sformatf(
                     "[TX_DBG] DESCR DWORD=%0d SYM=%0d LFSR_B=%06h LFSR_A=%06h IN=%02h OUT=%02h",
                     tx_os_dword_count, symbol_idx, lfsr_before, tx_lfsr,
                     decoded_symbol, original_symbol), UVM_LOW)
               end
               descrambled_data[(byte_idx * 8) +: 8] = original_symbol;
            end

            `uvm_info("RC_CONTROLLER", $sformatf(
               "[TX_DBG] FINAL DWORD=%0d DATA=%08h LFSR=%06h IN_OS=%0b",
               tx_os_dword_count, descrambled_data, tx_lfsr, tx_in_os), UVM_LOW)

            pcie_seq_item.data_q_rc_mon_con_tx.push_back(descrambled_data);
            `uvm_info("RC_CON_MONITOR", $sformatf(
               "RECEIVED_TX_DATA_IN_RC_CONTROLLER_MONITOR = %08h RC_CONTROLLER_MON_Queue_Size = %0d",
               descrambled_data, pcie_seq_item.data_q_rc_mon_con_tx.size()), UVM_LOW)
            rc_con_tx_mon_ap.write(pcie_seq_item);

            tx_os_dword_count++;
            dword_in_os++;

            if (dword_in_os == (`PCIe_TS_OS_SIZE / 4))
               dword_in_os = 0;

            // After 232 training DWORDs, exit OS mode permanently
            if (tx_in_os && (tx_os_dword_count >= 232)) begin
               tx_in_os = 1'b0;
               `uvm_info("RC_CONTROLLER", $sformatf(
                  "[TX_DBG] *** EXITED_OS_MODE *** TOTAL_DWORDS=%0d LFSR=%06h — full descramble from now on",
                  tx_os_dword_count, tx_lfsr), UVM_LOW)
            end
         end
      end
      `uvm_info("RC_CONTROLLER", "EXIT_FROM_RC_CONTROLLER_MONITOR_RECEIVING_PIPE_TX_DATA", UVM_LOW)
    endtask

    task receiving_pipe_rx(virtual PCIe_RC_interface rc_pipe_intf_rx);
      bit [`PCIe_MON_DATA_W-1:0] rx_data;
      bit [`PCIe_MON_DATA_W-1:0] deprecoded_data;
      bit [`PCIe_MON_DATA_W-1:0] gray_decoded_data;
      bit [`PCIe_MON_DATA_W-1:0] descrambled_data;
      bit [`PCIe_MON_DATA-1:0]  decoded_symbol;
      bit [`PCIe_MON_DATA-1:0]  original_symbol;
      bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] lfsr_before;

      int        dword_in_os;
      int        byte_idx;
      int        symbol_idx;

      `uvm_info("RC_CONTROLLER", "ENTERED_INTO_RC_CONTROLLER_MONITOR_RECEIVING_PIPE_RX_DATA", UVM_LOW)
      wait(rc_pipe_intf_rx.rx_valid);

      dword_in_os = 0;

      while (rc_pipe_intf_rx.rx_valid) begin
         @(negedge rc_pipe_intf_rx.pclk);

         pcie_seq_item.rx_valid     = rc_pipe_intf_rx.rx_valid;
         pcie_seq_item.rx_elec_idle = rc_pipe_intf_rx.rx_elec_idle;
         pcie_seq_item.rx_status    = rc_pipe_intf_rx.rx_status;
         pcie_seq_item.phy_status   = rc_pipe_intf_rx.phy_status;

         if (pcie_seq_item.rx_valid) begin
            rx_data = rc_pipe_intf_rx.rx_data;

            `uvm_info("RC_CONTROLLER", $sformatf(
               "[RX_DBG] LTSSM=%s IN_OS=%0b DWORD_CNT=%0d DWORD_IN_OS=%0d LFSR=%06h PIPE=%08h",
               rc_pl_model.rc_main_state.name(), rx_in_os,
               rx_os_dword_count, dword_in_os, rx_lfsr, rx_data), UVM_LOW)

            // 1. Reverse PRECODING
            de_precoder_rx(rx_data, deprecoded_data);
            `uvm_info("RC_CONTROLLER", $sformatf("RX DWORD=%0d PIPE=%08h DEPRECODED=%08h",
                       rx_os_dword_count, rx_data, deprecoded_data), UVM_LOW)

            // 2. Reverse GRAY CODING
            gray_decode_rx(deprecoded_data, gray_decoded_data);
            `uvm_info("RC_CONTROLLER", $sformatf("RX DWORD=%0d GRAY_DECODED=%08h",
                       rx_os_dword_count, gray_decoded_data), UVM_LOW)

            descrambled_data = gray_decoded_data;

            // 3. Reverse SCRAMBLING SYMBOL-BY-SYMBOL
            for (byte_idx = 0; byte_idx < 4; byte_idx++) begin
               symbol_idx     = (dword_in_os * 4) + byte_idx;
               decoded_symbol = gray_decoded_data[(byte_idx * 8) +: 8];
               lfsr_before    = rx_lfsr;

               if (rx_in_os && ((symbol_idx == 0) || (symbol_idx == 8) || (symbol_idx == 15))) begin
                  // BYPASS — training ordered-set bypass symbols
                  original_symbol = decoded_symbol;
                  `uvm_info("RC_CONTROLLER", $sformatf(
                     "[RX_DBG] BYPASS DWORD=%0d SYM=%0d LFSR_NA=%06h DATA=%02h",
                     rx_os_dword_count, symbol_idx, rx_lfsr, original_symbol), UVM_LOW)
               end
               else begin
                  // NORMAL DESCRAMBLING
                  descrambler_rx(decoded_symbol, original_symbol);
                  `uvm_info("RC_CONTROLLER", $sformatf(
                     "[RX_DBG] DESCR DWORD=%0d SYM=%0d LFSR_B=%06h LFSR_A=%06h IN=%02h OUT=%02h",
                     rx_os_dword_count, symbol_idx, lfsr_before, rx_lfsr,
                     decoded_symbol, original_symbol), UVM_LOW)
               end
               descrambled_data[(byte_idx * 8) +: 8] = original_symbol;
            end

            `uvm_info("RC_CONTROLLER", $sformatf(
               "[RX_DBG] FINAL DWORD=%0d DATA=%08h LFSR=%06h IN_OS=%0b",
               rx_os_dword_count, descrambled_data, rx_lfsr, rx_in_os), UVM_LOW)

            pcie_seq_item.data_q_rc_mon_con_rx.push_back(descrambled_data);
            `uvm_info("RC_CON_MONITOR", $sformatf(
               "RECEIVED_RX_DATA_IN_RC_CONTROLLER_MONITOR=%08h RC_CONTROLLER_MON_Queue_Size=%0d",
               descrambled_data, pcie_seq_item.data_q_rc_mon_con_rx.size()), UVM_LOW)
            rc_con_rx_mon_ap.write(pcie_seq_item);

            rx_os_dword_count++;
            dword_in_os++;

            if (dword_in_os == (`PCIe_TS_OS_SIZE / 4))
               dword_in_os = 0;

            // After 232 training DWORDs, exit OS mode permanently
            if (rx_in_os && (rx_os_dword_count >= 232)) begin
               rx_in_os = 1'b0;
               `uvm_info("RC_CONTROLLER", $sformatf(
                  "[RX_DBG] *** EXITED_OS_MODE *** TOTAL_DWORDS=%0d LFSR=%06h — full descramble from now on",
                  rx_os_dword_count, rx_lfsr), UVM_LOW)
            end
         end
      end
      `uvm_info("RC_CONTROLLER", "EXIT_FROM_RC_CONTROLLER_MONITOR_RECEIVING_PIPE_RX_DATA", UVM_LOW)
    endtask

    task de_precoder_tx(input bit [`PCIe_MON_DATA_W-1:0] data_in, output bit [`PCIe_MON_DATA_W-1:0] decoder_out);
      bit [1:0] current,dec;
          
      `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_MONITOR_DE_PRECODE_TASK",UVM_LOW)
       for(int i=0;i<`PCIe_MON_DATA_W;i+=2) begin
         current = data_in[i+:2];
         dec = current^tx_previous_symbol;
         decoder_out[i+:2] = dec;
         tx_previous_symbol = current;
       end
      `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_MONITOR_DE_PRECODE_TASK",UVM_LOW)
    endtask
   
    
    task gray_decode_tx(input  bit [`PCIe_MON_DATA_W-1:0] data_in,output bit [`PCIe_MON_DATA_W-1:0] gray_out);
      bit [1:0] symbol;
      `uvm_info("RC_CONTROLLE_MON", "ENTERED_INTO_RC_MON_GRAY_DECODE_TASK",UVM_LOW)
      
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
      `uvm_info("RC_CONTROLLE_MON", "EXIT_FROM_RC_MON_GRAY_DECODE_TASK",UVM_LOW)
    endtask

    task descrambler_tx(input  bit [`PCIe_MON_DATA-1:0] data_in,output bit [`PCIe_MON_DATA-1:0] data_out);
      bit descramble_bit;
      data_out = data_in;
     
      `uvm_info("RC_CONTROLLER_MON","ENTERED_INTO_DESCRAMBLER_TASK",UVM_LOW)
         for (int i = 0; i < `PCIe_MON_DATA; i++) begin
           descramble_bit = tx_lfsr[`PCIe_PL_SCRAMBLER_LFSR_W-1];
           data_out[i] = data_in[i] ^ descramble_bit;
           if (descramble_bit) begin
               tx_lfsr = (tx_lfsr << 1) ^ tx_polynomial;
           end
           else begin
               tx_lfsr = (tx_lfsr << 1);
           end
        end
        `uvm_info("PCIe_RC_CONTROLLER_MON",$sformatf("DESCRAMBLED_DATA = %08h",data_out), UVM_LOW)
        `uvm_info("PCIe_RC_CONTROLLER_MON","EXIT_FROM_DESCRAMBLER_TASK",UVM_LOW )
    endtask

    task de_precoder_rx(input bit [`PCIe_MON_DATA_W-1:0] data_in, output bit [`PCIe_MON_DATA_W-1:0] decoder_out);
      bit [1:0] current,dec;
      `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_MONITOR_DE_PRECODE_RX_TASK",UVM_LOW)
       for(int i=0;i<`PCIe_MON_DATA_W;i+=2) begin
         current = data_in[i+:2];
         dec = current^rx_previous_symbol;
         decoder_out[i+:2] = dec;
         rx_previous_symbol = current;
       end
      `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_MONITOR_DE_PRECODE_RX_TASK",UVM_LOW)
    endtask
   
    task gray_decode_rx(input  bit [`PCIe_MON_DATA_W-1:0] data_in,output bit [`PCIe_MON_DATA_W-1:0] gray_out);
      bit [1:0] symbol;
      `uvm_info("RC_CONTROLLE_MON", "ENTERED_INTO_RC_MON_GRAY_DECODE_RX_TASK",UVM_LOW)
      
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
      `uvm_info("RC_CONTROLLE_MON", "EXIT_FROM_RC_MON_GRAY_DECODE_RX_TASK",UVM_LOW)
    endtask

    task descrambler_rx(input  bit [`PCIe_MON_DATA-1:0] data_in,output bit [`PCIe_MON_DATA-1:0] data_out);
      bit descramble_bit;
      data_out = data_in;
     
      `uvm_info("RC_CONTROLLER_MON","ENTERED_INTO_DESCRAMBLER_RX_TASK",UVM_LOW)
         for (int i = 0; i < `PCIe_MON_DATA; i++) begin
           descramble_bit = rx_lfsr[`PCIe_PL_SCRAMBLER_LFSR_W-1];
           data_out[i] = data_in[i] ^ descramble_bit;
           if (descramble_bit) begin
               rx_lfsr = (rx_lfsr << 1) ^ rx_polynomial;
           end
           else begin
               rx_lfsr = (rx_lfsr << 1);
           end
        end
        `uvm_info("PCIe_RC_CONTROLLER_MON",$sformatf("DESCRAMBLED_DATA = %08h",data_out), UVM_LOW)
        `uvm_info("PCIe_RC_CONTROLLER_MON","EXIT_FROM_DESCRAMBLER_RX_TASK",UVM_LOW )
    endtask
  
   /*task parity_check_rx(input bit [31:0] gray_data);

     rx_parity = ^gray_data;
     if (ep_pl_model.tx_parity_q.size() == 0)
     begin
      `uvm_error("RC_CONTROLLER_MON_PARITY_CHECK", "RX_PARITY_QUEUE_IS_EMPTY");
       return;
     end
     tx_parity = ep_pl_model.tx_parity_q.pop_front();
     `uvm_info("RC_CONTROLLER_MON_PARITY_CHECK",$sformatf("GRAY_DATA = %08h",gray_data),UVM_LOW)
     `uvm_info("RC_CONTROLLER_MON_PARITY_CHECK",$sformatf("TX_PARITY = %0b",tx_parity),UVM_LOW)
     `uvm_info("RC_CONTROLLER_MON_PARITY_CHECK",$sformatf("RX_PARITY = %0b",rx_parity),UVM_LOW)
   
     if (tx_parity == rx_parity)
     begin
      `uvm_info("RC_CONTROLLER_MON_PARITY_CHECK",$sformatf("********RC_CONTROLLR_MON_PARITY_PASS******** TX=%0b RX=%0b",tx_parity,rx_parity),UVM_LOW);
     end
     else
     begin
      `uvm_error("RC_CONTROLLER_MON_PARITY_CHECK",$sformatf("********RC_CONTROLLER_MON_PARITY_FAIL******** TX=%0b RX=%0b",tx_parity,rx_parity));
     end
   endtask*/
     
endclass




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

   // [ADDED] 236 byte TLP region only (the 6 DLP bytes are stripped off) on its
   // way from this monitor to the EP TL model. Works for FLIT and NON-FLIT.
   uvm_analysis_port #(PCIe_sequence_item) ep_mon_tl_ap;
   PCIe_sequence_item            pcie_seq_item;
   PCIe_RC_PL_model              rc_pl_model;
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

    // OS-mode tracking: replaces broken link_up-based bypass.
    // The monitor's PL model instance never runs the LTSSM, so link_up
    // was always 0 — keeping bypass active even during FLIT data.
    // We use a DWORD counter instead: bypass active for the first 232
    // training DWORDs, then OFF permanently (full descramble).
    bit             tx_in_os;
    int             tx_os_dword_count;
    bit             rx_in_os;
    int             rx_os_dword_count;
   function new(string name="PCIe_EP_controller_monitor", uvm_component parent);
      super.new(name,parent);
    ep_ap_mon_dl=new("ep_ap_mon_dl",this);
    ep_rc_ap_mon_dl=new("ep_rc_ap_mon_dl",this);
    ep_mon_tl_ap=new("ep_mon_tl_ap",this);   // [ADDED] 236 B TLP -> EP TL model
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
         tx_in_os         = 1'b1;
         tx_os_dword_count = 0;
         rx_in_os         = 1'b1;
         rx_os_dword_count = 0;
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
       bit [`PCIe_MON_DATA_W-1:0] rx_data;
       bit [`PCIe_MON_DATA_W-1:0] deprecoded_data;
       bit [`PCIe_MON_DATA_W-1:0] gray_decoded_data;
       bit [`PCIe_MON_DATA_W-1:0] descrambled_data;
       bit [`PCIe_MON_DATA-1:0]  decoded_symbol;
       bit [`PCIe_MON_DATA-1:0]  original_symbol;
       bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] lfsr_before;

       int dword_in_os;
       int byte_idx;
       int symbol_idx;

       `uvm_info("EP_CONTROLLER", "ENTERED_INTO_EP_CONTROLLER_MONITOR_RECEIVING_PIPE_RX_DATA", UVM_LOW)
       wait(ep_pipe_intf_rx.rx_valid);

       dword_in_os = 0;

       while (ep_pipe_intf_rx.rx_valid) begin
         @(negedge ep_pipe_intf_rx.pclk);
         pcie_seq_item.rx_valid     = ep_pipe_intf_rx.rx_valid;
         pcie_seq_item.rx_elec_idle = ep_pipe_intf_rx.rx_elec_idle;
         pcie_seq_item.rx_status    = ep_pipe_intf_rx.rx_status;
         pcie_seq_item.phy_status   = ep_pipe_intf_rx.phy_status;

         if (pcie_seq_item.rx_valid) begin
            rx_data = ep_pipe_intf_rx.rx_data;

            `uvm_info("EP_CONTROLLER", $sformatf(
               "[RX_DBG] LTSSM=%s IN_OS=%0b DWORD_CNT=%0d DWORD_IN_OS=%0d LFSR=%06h PIPE=%08h",
               ep_pl_model.ep_main_state.name(), rx_in_os,
               rx_os_dword_count, dword_in_os, rx_lfsr, rx_data), UVM_LOW)

            // 1. Reverse PRECODING
            de_precoder_rx(rx_data, deprecoded_data);
            `uvm_info("EP_CONTROLLER", $sformatf("RX DWORD=%0d PIPE=%08h DEPRECODED=%08h",
                       rx_os_dword_count, rx_data, deprecoded_data), UVM_LOW)

            // 2. Reverse GRAY CODING
            gray_decode_rx(deprecoded_data, gray_decoded_data);
            `uvm_info("EP_CONTROLLER", $sformatf("RX DWORD=%0d GRAY_DECODED=%08h",
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
                  `uvm_info("EP_CONTROLLER", $sformatf(
                     "[RX_DBG] BYPASS DWORD=%0d SYM=%0d LFSR_NA=%06h DATA=%02h",
                     rx_os_dword_count, symbol_idx, rx_lfsr, original_symbol), UVM_LOW)
               end
               else begin
                  // NORMAL DESCRAMBLING
                  descrambler_rx(decoded_symbol, original_symbol);
                  `uvm_info("EP_CONTROLLER", $sformatf(
                     "[RX_DBG] DESCR DWORD=%0d SYM=%0d LFSR_B=%06h LFSR_A=%06h IN=%02h OUT=%02h",
                     rx_os_dword_count, symbol_idx, lfsr_before, rx_lfsr,
                     decoded_symbol, original_symbol), UVM_LOW)
               end
               descrambled_data[(byte_idx * 8) +: 8] = original_symbol;
            end

            `uvm_info("EP_CONTROLLER", $sformatf(
               "[RX_DBG] FINAL DWORD=%0d DATA=%08h LFSR=%06h IN_OS=%0b",
               rx_os_dword_count, descrambled_data, rx_lfsr, rx_in_os), UVM_LOW)

            pcie_seq_item.data_q_ep_mon_con_rx.push_back(descrambled_data);
            `uvm_info("EP_CON_MONITOR", $sformatf(
               "RECEIVED_RX_DATA_IN_EP_CONTROLLER_MONITOR=%08h EP_CONTROLLER_MON_Queue_Size=%0d",
               descrambled_data, pcie_seq_item.data_q_ep_mon_con_rx.size()), UVM_LOW)
            `ifdef PCIE_GEN6_FEC_CRC
            // ===== SINGLE FEC/CRC CHECK (RC->EP flit only) =====
            // FEC/CRC addition : 256B flit received from RC PHY -> EP controller
            // monitor after all reverse process. FEC and CRC are computed HERE
            // (FEC logic and CRC logic each kept at one place) and the
            // received/calculated values are carried to the scoreboard. The
            // comparison (received vs calculated) and the PASS/FAIL report are
            // done ONLY in the scoreboard.
            check_rc_to_ep_flit_fec_crc(pcie_seq_item.data_q_ep_mon_con_rx, rx_os_dword_count);
            `endif
            ep_con_rx_mon_ap.write(pcie_seq_item);

            rx_os_dword_count++;
            dword_in_os++;

            if (dword_in_os == (`PCIe_TS_OS_SIZE / 4))
               dword_in_os = 0;

            // After 232 training DWORDs, exit OS mode permanently
            if (rx_in_os && (rx_os_dword_count >= 232)) begin
               rx_in_os = 1'b0;
               `uvm_info("EP_CONTROLLER", $sformatf(
                  "[RX_DBG] *** EXITED_OS_MODE *** TOTAL_DWORDS=%0d LFSR=%06h — full descramble from now on",
                  rx_os_dword_count, rx_lfsr), UVM_LOW)
            end
         end
   // (Packet collected sent by RC here :: Expected Packet)
   if(ep_pl_model.link_up == 1 && pcie_seq_item.data_q_ep_mon_con_rx.size() > 292 )begin  
    collect_dlp_EP_rx(dlp_ep_rx,pcie_seq_item);
    ep_dl_model.handle_incoming_flit(dlp_ep_rx,is_valid);
      pcie_seq_item.dlp=dlp_ep_rx;

      // ---- LCRC addition: recompute LCRC over the ACTUAL reconstructed flit bytes ----
      begin
        bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] mon_full_flit;
        for (int k = 0; k < `PCIe_TLP_DATA_BYTE_W; k++) mon_full_flit[k] = tlp_ep_rx[k];
        for (int k = 0; k < `PCIe_DLP_BYTE_W; k++) mon_full_flit[`PCIe_TLP_DATA_BYTE_W+k] = dlp_ep_rx[k];
        pcie_seq_item.dl_lcrc = ep_dl_model.generate_lcrc_flit(mon_full_flit);
        `uvm_info("LCRC_MON_EP_RX",$sformatf("EP_MON_RX_COMPUTED_LCRC=%08h",pcie_seq_item.dl_lcrc),UVM_LOW)
      end
      // -------------------------------------------------------------------------------

      ep_ap_mon_dl.write(pcie_seq_item);
       end
       end
       `uvm_info("EP_CONTROLLER", "EXIT_FROM_EP_CONTROLLER_MONITOR_RECEIVING_PIPE_RX_DATA", UVM_LOW)
    endtask
     
   task receiving_pipe_tx(virtual PCIe_EP_interface ep_pipe_intf_tx);
      bit [`PCIe_MON_DATA_W-1:0] tx_data;
      bit [`PCIe_MON_DATA_W-1:0] deprecoded_data;
      bit [`PCIe_MON_DATA_W-1:0] gray_decoded_data;
      bit [`PCIe_MON_DATA_W-1:0] descrambled_data;
      bit [`PCIe_MON_DATA-1:0]  decoded_symbol;
      bit [`PCIe_MON_DATA-1:0]  original_symbol;
      bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] lfsr_before;

      int dword_in_os;
      int byte_idx;
      int symbol_idx;

      `uvm_info("EP_CONTROLLER", "ENTERED_INTO_EP_CONTROLLER_MONITOR_RECEIVING_PIPE_TX_DATA", UVM_LOW)
      wait(ep_pipe_intf_tx.tx_valid);

      dword_in_os = 0;

      while (ep_pipe_intf_tx.tx_valid) begin
         @(negedge ep_pipe_intf_tx.pclk);
         pcie_seq_item.tx_valid      = ep_pipe_intf_tx.tx_valid;
         pcie_seq_item.tx_elec_idle  = ep_pipe_intf_tx.tx_elec_idle;
         pcie_seq_item.tx_detect_rx  = ep_pipe_intf_tx.tx_detect_rx;
         pcie_seq_item.powerdown     = ep_pipe_intf_tx.powerdown;
         pcie_seq_item.rate          = ep_pipe_intf_tx.rate;

         if (pcie_seq_item.tx_valid) begin
            tx_data = ep_pipe_intf_tx.tx_data;

            `uvm_info("EP_CONTROLLER", $sformatf(
               "[TX_DBG] LTSSM=%s IN_OS=%0b DWORD_CNT=%0d DWORD_IN_OS=%0d LFSR=%06h PIPE=%08h",
               ep_pl_model.ep_main_state.name(), tx_in_os,
               tx_os_dword_count, dword_in_os, tx_lfsr, tx_data), UVM_LOW)

            // 1. Reverse PRECODING
            de_precoder_tx(tx_data, deprecoded_data);
            `uvm_info("EP_CONTROLLER", $sformatf("TX DWORD=%0d PIPE=%08h DEPRECODED=%08h",
                       tx_os_dword_count, tx_data, deprecoded_data), UVM_LOW)

            // 2. Reverse GRAY CODING
            gray_decode_tx(deprecoded_data, gray_decoded_data);
            `uvm_info("EP_CONTROLLER", $sformatf("TX DWORD=%0d GRAY_DECODED=%08h",
                       tx_os_dword_count, gray_decoded_data), UVM_LOW)

            descrambled_data = gray_decoded_data;

            // 3. Reverse SCRAMBLING SYMBOL-BY-SYMBOL
            for (byte_idx = 0; byte_idx < 4; byte_idx++) begin
               symbol_idx     = (dword_in_os * 4) + byte_idx;
               decoded_symbol = gray_decoded_data[(byte_idx * 8) +: 8];
               lfsr_before    = tx_lfsr;

               if (tx_in_os && ((symbol_idx == 0) || (symbol_idx == 8) || (symbol_idx == 15))) begin
                  // BYPASS — training ordered-set bypass symbols
                  original_symbol = decoded_symbol;
                  `uvm_info("EP_CONTROLLER", $sformatf(
                     "[TX_DBG] BYPASS DWORD=%0d SYM=%0d LFSR_NA=%06h DATA=%02h",
                     tx_os_dword_count, symbol_idx, tx_lfsr, original_symbol), UVM_LOW)
               end
               else begin
                  // NORMAL DESCRAMBLING
                  descrambler_tx(decoded_symbol, original_symbol);
                  `uvm_info("EP_CONTROLLER", $sformatf(
                     "[TX_DBG] DESCR DWORD=%0d SYM=%0d LFSR_B=%06h LFSR_A=%06h IN=%02h OUT=%02h",
                     tx_os_dword_count, symbol_idx, lfsr_before, tx_lfsr,
                     decoded_symbol, original_symbol), UVM_LOW)
               end
               descrambled_data[(byte_idx * 8) +: 8] = original_symbol;
            end

            `uvm_info("EP_CONTROLLER", $sformatf(
               "[TX_DBG] FINAL DWORD=%0d DATA=%08h LFSR=%06h IN_OS=%0b",
               tx_os_dword_count, descrambled_data, tx_lfsr, tx_in_os), UVM_LOW)

            pcie_seq_item.data_q_ep_mon_con_tx.push_back(descrambled_data);
            `uvm_info("EP_CONTROLLER", $sformatf(
               "RECEIVED_TX_DATA_IN_EP_CONTROLLER_MONITOR=%08h EP_CONTROLLER_MON_Queue_Size=%0d",
               descrambled_data, pcie_seq_item.data_q_ep_mon_con_tx.size()), UVM_LOW)
            ep_con_tx_mon_ap.write(pcie_seq_item);

            tx_os_dword_count++;
            dword_in_os++;

            if (dword_in_os == (`PCIe_TS_OS_SIZE / 4))
               dword_in_os = 0;

            // After 232 training DWORDs, exit OS mode permanently
            if (tx_in_os && (tx_os_dword_count >= 232)) begin
               tx_in_os = 1'b0;
               `uvm_info("EP_CONTROLLER", $sformatf(
                  "[TX_DBG] *** EXITED_OS_MODE *** TOTAL_DWORDS=%0d LFSR=%06h — full descramble from now on",
                  tx_os_dword_count, tx_lfsr), UVM_LOW)
            end
         end
       //(when EP sends the packet to RC :: Actual Packet)
      if(ep_pl_model.link_up ==1 && pcie_seq_item.data_q_ep_mon_con_tx.size() > 292)begin
     collect_dlp_EP_tx(dlp_ep_tx,pcie_seq_item);
      pcie_seq_item.dlp=dlp_ep_tx;

      // ---- LCRC addition: recompute LCRC over the ACTUAL reconstructed flit bytes ----
      begin
        bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] mon_full_flit;
        for (int k = 0; k < `PCIe_TLP_DATA_BYTE_W; k++) mon_full_flit[k] = tlp_ep_tx[k];
        for (int k = 0; k < `PCIe_DLP_BYTE_W; k++) mon_full_flit[`PCIe_TLP_DATA_BYTE_W+k] = dlp_ep_tx[k];
        pcie_seq_item.dl_lcrc = ep_dl_model.generate_lcrc_flit(mon_full_flit);
        `uvm_info("LCRC_MON_EP_TX",$sformatf("EP_MON_TX_COMPUTED_LCRC=%08h",pcie_seq_item.dl_lcrc),UVM_LOW)
      end
      // -------------------------------------------------------------------------------

      ep_rc_ap_mon_dl.write(pcie_seq_item);
     end
     end
      `uvm_info("EP_CONTROLLER", "EXIT_FROM_EP_CONTROLLER_MONITOR_RECEIVING_PIPE_TX_DATA", UVM_LOW)
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

    task descrambler_rx(input  bit [`PCIe_MON_DATA-1:0] data_in,output bit [`PCIe_MON_DATA-1:0] data_out);
      bit descramble_bit;
      data_out = data_in;
     
      `uvm_info("EP_CONTROLLER_MON","ENTERED_INTO_DESCRAMBLER_TASK",UVM_LOW)
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

    task descrambler_tx(input  bit [`PCIe_MON_DATA-1:0] data_in,output bit [`PCIe_MON_DATA-1:0] data_out);
      bit descramble_bit;
      data_out = data_in;
      `uvm_info("EP_CONTROLLER_MON","ENTERED_INTO_DESCRAMBLER_TX_TASK",UVM_LOW)
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
        `uvm_info("PCIe_EP_CONTROLLER_MON",$sformatf("DESCRAMBLED_DATA = %08h",data_out), UVM_LOW)
        `uvm_info("PCIe_EP_CONTROLLER_MON","EXIT_FROM_DESCRAMBLER_TX_TASK",UVM_LOW )
      endtask
     
  // Collect the FLIT DLP from the PIPE interface.
  task collect_dlp_EP_tx(output bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp_ep_tx,ref PCIe_sequence_item item);
    bit[31:0]word;

    // remove first 232 elements in queue.
   do begin
	   item.data_q_ep_mon_con_tx.pop_front();
   end
   while(item.data_q_ep_mon_con_tx.size() > 61 );

   for(int i=0;i<`PCIe_TLP_DATA_BYTE_W;i++) begin
      word = item.data_q_ep_mon_con_tx[i/4];
   `uvm_info("WORD",$sformatf("word=%h",word),UVM_LOW);
      tlp_ep_tx[i] = word[8*(i%4) +: 8];
   `uvm_info("TLP_EP_TX",$sformatf("tlp_ep_tx=%h",tlp_ep_tx[i]),UVM_LOW);
   end

   for(int i=0;i<`PCIe_DLP_BYTE_W;i++) begin
      int idx = `PCIe_TLP_DATA_BYTE_W + i;
      word = item.data_q_ep_mon_con_tx[idx/4];
      dlp_ep_tx[i] = word[8*(idx%4) +: 8];
   end
    
    ep_dl_model.rx_retry_buffer.push_back(dlp_ep_tx);

    `uvm_info("EP_CON_MONITOR",$sformatf("collected tlp_ep_tx from ep monitor is tlp=%p",tlp_ep_tx),UVM_LOW)
    `uvm_info("EP_CON_MONITOR",$sformatf("collected dlp_ep_tx ep monitor is dlp=%p",dlp_ep_tx),UVM_LOW)
  endtask

  // Collect the FLIT DLP from the PIPE interface.
  task collect_dlp_EP_rx(output bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp_ep_rx,ref PCIe_sequence_item item);
	  bit[31:0]word;
    
    // remove first 232 elements in queue.
   do begin
	   item.data_q_ep_mon_con_rx.pop_front();
   end
   while(item.data_q_ep_mon_con_rx.size() > 61 );
   
     // Form tlp to send to scoreboard
      for(int i=0;i<`PCIe_TLP_DATA_BYTE_W;i++) begin
         word = item.data_q_ep_mon_con_rx[i/4];
         tlp_ep_rx[i]=word[8*(i%4) +: 8];
      end

      // Last 6 bytes = DLP
      for(int i=0;i<`PCIe_DLP_BYTE_W;i++) begin
      int idx = `PCIe_TLP_DATA_BYTE_W + i;
      word = item.data_q_ep_mon_con_rx[idx/4];
      dlp_ep_rx[i] = word[8*(idx%4) +: 8];
   end

    ep_dl_model.rx_retry_buffer.push_back(dlp_ep_rx);

    `uvm_info("EP_CON_MONITOR",$sformatf("collected tlp_ep_rx from ep monitor is tlp=%p",tlp_ep_rx),UVM_LOW)
    `uvm_info("EP_CON_MONITOR",$sformatf("collected dlp_ep_rx from ep monitor is dlp=%p",dlp_ep_rx),UVM_LOW)

    // [ADDED] 242 B flit -> keep only the 236 TLP bytes and hand them to the
    // EP TL model through the analysis port.
    send_tlp_to_ep_tl(tlp_ep_rx, "RC_TO_EP_RX");
  endtask
      
  //==========================================================================
  // [ADDED] send_tlp_to_ep_tl
  //
  //   The flit reconstructed off the PIPE interface is 242 bytes:
  //         [  0 .. 235 ]  TLP region   (236 B)
  //         [236 .. 241 ]  DLP          (  6 B)
  //   Only the 236 TLP bytes belong to the Transaction Layer, so they are
  //   copied into a fresh sequence item and published on ep_mon_tl_ap using
  //   the UVM analysis mechanism.  The DLP bytes stay with the DL model.
  //
  //   The same path is used for NON-FLIT traffic: a non-flit TLP
  //   (3 DW or 4 DW header, optional OHC, 0 to 1024 DW of payload) is carried
  //   in the very same 236 byte region by this testbench, and the EP TL model
  //   recovers its true length from the header it decodes.
  //==========================================================================
  function void send_tlp_to_ep_tl(
      input bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_bytes,
      input string direction);

    PCIe_sequence_item tl_item;
    string             dump;
    string             line;
    int                b;

    tl_item = PCIe_sequence_item::type_id::create("ep_mon_to_tl_item");

    for (b = 0; b < `PCIe_TLP_DATA_BYTE_W; b++) begin
      tl_item.tlp_from_mon[b] = tlp_bytes[b];
      tl_item.tlp_data[b]     = tlp_bytes[b];
    end

    //tl_item.pkt_mode   = mon_pkt_mode;
    tl_item.is_payload = 1'b1;
    //tl_item.drive_flit = (mon_pkt_mode == FLIT);

   // `uvm_info("EP_MON_TO_TL",$sformatf("PUBLISHING_%0d_TLP_BYTES_TO_EP_TL_MODEL dir=%s mode=%s (242 B flit minus %0d B DLP)",`PCIe_TLP_DATA_BYTE_W, direction, mon_pkt_mode.name(), `PCIe_DLP_BYTE_W), UVM_LOW)

    dump = "\n";
    line = "";
    for (b = 0; b < `PCIe_TLP_DATA_BYTE_W; b++) begin
      if ((b % `PCIe_FLIT_DUMP_BPL) == 0)
        line = $sformatf("  [%3d] :", b);
      line = {line, $sformatf(" %02h", tl_item.tlp_from_mon[b])};
      if (((b % `PCIe_FLIT_DUMP_BPL) == `PCIe_FLIT_DUMP_BPL-1) ||
          (b == `PCIe_TLP_DATA_BYTE_W-1))
        dump = {dump, line, "\n"};
    end
    `uvm_info("EP_MON_TO_TL_236B", dump, UVM_LOW)

    ep_mon_tl_ap.write(tl_item);

  endfunction

   `ifdef PCIE_GEN6_FEC_CRC
// ============================================================================
   // FEC LOGIC (kept in one place)
   // ----------------------------------------------------------------------------
   // Gen6 Flit FEC : Reed-Solomon-style ECC over the 250-byte flit body
   // (242B payload + 8B CRC). Output = 6B FEC (3 check bytes + 3 parity bytes).
   // ============================================================================
   static const bit [`PCIe_BYTE_W-1:0] fec_exp_table [0:255] = '{
     8'h01, 8'h02, 8'h04, 8'h08, 8'h10, 8'h20, 8'h40, 8'h80,
     8'h1d, 8'h3a, 8'h74, 8'he8, 8'hcd, 8'h87, 8'h13, 8'h26,
     8'h4c, 8'h98, 8'h2d, 8'h5a, 8'hb4, 8'h75, 8'hea, 8'hc9,
     8'h8f, 8'h03, 8'h06, 8'h0c, 8'h18, 8'h30, 8'h60, 8'hc0,
     8'h9d, 8'h27, 8'h4e, 8'h9c, 8'h25, 8'h4a, 8'h94, 8'h35,
     8'h6a, 8'hd4, 8'hb5, 8'h77, 8'hee, 8'hc1, 8'h9f, 8'h23,
     8'h46, 8'h8c, 8'h05, 8'h0a, 8'h14, 8'h28, 8'h50, 8'ha0,
     8'h5d, 8'hba, 8'h69, 8'hd2, 8'hb9, 8'h6f, 8'hde, 8'ha1,
     8'h5f, 8'hbe, 8'h61, 8'hc2, 8'h99, 8'h2f, 8'h5e, 8'hbc,
     8'h65, 8'hca, 8'h89, 8'h0f, 8'h1e, 8'h3c, 8'h78, 8'hf0,
     8'hfd, 8'he7, 8'hd3, 8'hbb, 8'h6b, 8'hd6, 8'hb1, 8'h7f,
     8'hfe, 8'he1, 8'hdf, 8'ha3, 8'h5b, 8'hb6, 8'h71, 8'he2,
     8'hd9, 8'haf, 8'h43, 8'h86, 8'h11, 8'h22, 8'h44, 8'h88,
     8'h0d, 8'h1a, 8'h34, 8'h68, 8'hd0, 8'hbd, 8'h67, 8'hce,
     8'h81, 8'h1f, 8'h3e, 8'h7c, 8'hf8, 8'hed, 8'hc7, 8'h93,
     8'h3b, 8'h76, 8'hec, 8'hc5, 8'h97, 8'h33, 8'h66, 8'hcc,
     8'h85, 8'h17, 8'h2e, 8'h5c, 8'hb8, 8'h6d, 8'hda, 8'ha9,
     8'h4f, 8'h9e, 8'h21, 8'h42, 8'h84, 8'h15, 8'h2a, 8'h54,
     8'ha8, 8'h4d, 8'h9a, 8'h29, 8'h52, 8'ha4, 8'h55, 8'haa,
     8'h49, 8'h92, 8'h39, 8'h72, 8'he4, 8'hd5, 8'hb7, 8'h73,
     8'he6, 8'hd1, 8'hbf, 8'h63, 8'hc6, 8'h91, 8'h3f, 8'h7e,
     8'hfc, 8'he5, 8'hd7, 8'hb3, 8'h7b, 8'hf6, 8'hf1, 8'hff,
     8'he3, 8'hdb, 8'hab, 8'h4b, 8'h96, 8'h31, 8'h62, 8'hc4,
     8'h95, 8'h37, 8'h6e, 8'hdc, 8'ha5, 8'h57, 8'hae, 8'h41,
     8'h82, 8'h19, 8'h32, 8'h64, 8'hc8, 8'h8d, 8'h07, 8'h0e,
     8'h1c, 8'h38, 8'h70, 8'he0, 8'hdd, 8'ha7, 8'h53, 8'ha6,
     8'h51, 8'ha2, 8'h59, 8'hb2, 8'h79, 8'hf2, 8'hf9, 8'hef,
     8'hc3, 8'h9b, 8'h2b, 8'h56, 8'hac, 8'h45, 8'h8a, 8'h09,
     8'h12, 8'h24, 8'h48, 8'h90, 8'h3d, 8'h7a, 8'hf4, 8'hf5,
     8'hf7, 8'hf3, 8'hfb, 8'heb, 8'hcb, 8'h8b, 8'h0b, 8'h16,
     8'h2c, 8'h58, 8'hb0, 8'h7d, 8'hfa, 8'he9, 8'hcf, 8'h83,
     8'h1b, 8'h36, 8'h6c, 8'hd8, 8'had, 8'h47, 8'h8e, 8'h01
   };

   // GF(2^8) discrete log table for FEC field
   static const bit [`PCIe_BYTE_W-1:0] fec_log_table [0:255] = '{
     8'hff, 8'h00, 8'h01, 8'h19, 8'h02, 8'h32, 8'h1a, 8'hc6,
     8'h03, 8'hdf, 8'h33, 8'hee, 8'h1b, 8'h68, 8'hc7, 8'h4b,
     8'h04, 8'h64, 8'he0, 8'h0e, 8'h34, 8'h8d, 8'hef, 8'h81,
     8'h1c, 8'hc1, 8'h69, 8'hf8, 8'hc8, 8'h08, 8'h4c, 8'h71,
     8'h05, 8'h8a, 8'h65, 8'h2f, 8'he1, 8'h24, 8'h0f, 8'h21,
     8'h35, 8'h93, 8'h8e, 8'hda, 8'hf0, 8'h12, 8'h82, 8'h45,
     8'h1d, 8'hb5, 8'hc2, 8'h7d, 8'h6a, 8'h27, 8'hf9, 8'hb9,
     8'hc9, 8'h9a, 8'h09, 8'h78, 8'h4d, 8'he4, 8'h72, 8'ha6,
     8'h06, 8'hbf, 8'h8b, 8'h62, 8'h66, 8'hdd, 8'h30, 8'hfd,
     8'he2, 8'h98, 8'h25, 8'hb3, 8'h10, 8'h91, 8'h22, 8'h88,
     8'h36, 8'hd0, 8'h94, 8'hce, 8'h8f, 8'h96, 8'hdb, 8'hbd,
     8'hf1, 8'hd2, 8'h13, 8'h5c, 8'h83, 8'h38, 8'h46, 8'h40,
     8'h1e, 8'h42, 8'hb6, 8'ha3, 8'hc3, 8'h48, 8'h7e, 8'h6e,
     8'h6b, 8'h3a, 8'h28, 8'h54, 8'hfa, 8'h85, 8'hba, 8'h3d,
     8'hca, 8'h5e, 8'h9b, 8'h9f, 8'h0a, 8'h15, 8'h79, 8'h2b,
     8'h4e, 8'hd4, 8'he5, 8'hac, 8'h73, 8'hf3, 8'ha7, 8'h57,
     8'h07, 8'h70, 8'hc0, 8'hf7, 8'h8c, 8'h80, 8'h63, 8'h0d,
     8'h67, 8'h4a, 8'hde, 8'hed, 8'h31, 8'hc5, 8'hfe, 8'h18,
     8'he3, 8'ha5, 8'h99, 8'h77, 8'h26, 8'hb8, 8'hb4, 8'h7c,
     8'h11, 8'h44, 8'h92, 8'hd9, 8'h23, 8'h20, 8'h89, 8'h2e,
     8'h37, 8'h3f, 8'hd1, 8'h5b, 8'h95, 8'hbc, 8'hcf, 8'hcd,
     8'h90, 8'h87, 8'h97, 8'hb2, 8'hdc, 8'hfc, 8'hbe, 8'h61,
     8'hf2, 8'h56, 8'hd3, 8'hab, 8'h14, 8'h2a, 8'h5d, 8'h9e,
     8'h84, 8'h3c, 8'h39, 8'h53, 8'h47, 8'h6d, 8'h41, 8'ha2,
     8'h1f, 8'h2d, 8'h43, 8'hd8, 8'hb7, 8'h7b, 8'ha4, 8'h76,
     8'hc4, 8'h17, 8'h49, 8'hec, 8'h7f, 8'h0c, 8'h6f, 8'hf6,
     8'h6c, 8'ha1, 8'h3b, 8'h52, 8'h29, 8'h9d, 8'h55, 8'haa,
     8'hfb, 8'h60, 8'h86, 8'hb1, 8'hbb, 8'hcc, 8'h3e, 8'h5a,
     8'hcb, 8'h59, 8'h5f, 8'hb0, 8'h9c, 8'ha9, 8'ha0, 8'h51,
     8'h0b, 8'hf5, 8'h16, 8'heb, 8'h7a, 8'h75, 8'h2c, 8'hd7,
     8'h4f, 8'hae, 8'hd5, 8'he9, 8'he6, 8'he7, 8'had, 8'he8,
     8'h74, 8'hd6, 8'hf4, 8'hea, 8'ha8, 8'h50, 8'h58, 8'haf
   };

   // GF(2^8) multiply via log/antilog tables for the FEC field
   function automatic bit [`PCIe_BYTE_W-1:0] fec_gf_mul(
     input bit [`PCIe_BYTE_W-1:0] a,
     input bit [`PCIe_BYTE_W-1:0] b
   );
     int unsigned s;
     if(a == 8'h00 || b == 8'h00)
       return 8'h00;
     s = (int'(fec_log_table[a]) + int'(fec_log_table[b])) % 255;
     return fec_exp_table[s];
   endfunction : fec_gf_mul

   // Encode one 84-byte ECC group -> Check Byte + Parity Byte
   function automatic void fec_encode_group(
     input  bit [`PCIe_BYTE_W-1:0] info [0:83],
     output bit [`PCIe_BYTE_W-1:0] check,
     output bit [`PCIe_BYTE_W-1:0] parity
   );
     bit [`PCIe_BYTE_W-1:0] c, p;
     c = 8'h00;
     p = 8'h00;
     for(int k = 0; k < 84; k++)
     begin
       c ^= fec_gf_mul(info[k], fec_exp_table[(84 - k) % 255]);
       p ^= info[k];
     end
     check  = c;
     parity = p;
   endfunction : fec_encode_group

   // Compute 6B FEC for the 250-byte (242B payload + 8B CRC) flit body
   function void calculate_fec_on_250b_body(
     input  bit [`PCIe_BYTE_W-1:0] fec_body_250b [$],
     output bit [`PCIe_BYTE_W-1:0] fec_6b_out [6]
   );
     bit [`PCIe_BYTE_W-1:0] grp0 [0:83], grp1 [0:83], grp2 [0:83];
     bit [`PCIe_BYTE_W-1:0] c0, p0, c1, p1, c2, p2;

     if(fec_body_250b.size() < (`PCIe_DLP_FLIT_BYTE_W + 8))
     begin
       `uvm_error(get_type_name(),
                  $sformatf("calculate_fec_on_250b_body: need >= %0d Bytes, got %0d",
                            `PCIe_DLP_FLIT_BYTE_W + 8, fec_body_250b.size()))
       foreach(fec_6b_out[i]) fec_6b_out[i] = '0;
       return;
     end

     grp1[83] = 8'h00;
     grp2[83] = 8'h00;

     for(int i = 0; i <= 249; i++)
     begin
       int grp = i % 3;
       int off = i / 3;
       case(grp)
         0: grp0[off] = fec_body_250b[i];
         1: grp1[off] = fec_body_250b[i];
         2: grp2[off] = fec_body_250b[i];
       endcase
     end

     fec_encode_group(grp0, c0, p0);
     fec_encode_group(grp1, c1, p1);
     fec_encode_group(grp2, c2, p2);

     fec_6b_out[0] = c1; fec_6b_out[1] = c2; fec_6b_out[2] = c0;
     fec_6b_out[3] = p1; fec_6b_out[4] = p2; fec_6b_out[5] = p0;
   endfunction : calculate_fec_on_250b_body

   // ============================================================================
   // CRC LOGIC (kept in one place)
   // ----------------------------------------------------------------------------
   // Gen6 Flit CRC : 8B CRC (GF(2^8), reduction 8'h2B) generated over the
   // 242B flit payload with generator polynomial bytes g[0..7].
   // ============================================================================
   // GF(2^8) multiply for CRC field (reduction 8'h2B)
   function automatic bit [`PCIe_BYTE_W-1:0] crc_gf_mul(
     input bit [`PCIe_BYTE_W-1:0] a,
     input bit [`PCIe_BYTE_W-1:0] b
   );
     bit [`PCIe_BYTE_W-1:0] p, aa, bb;
     p  = 8'h00;
     aa = a;
     bb = b;
     for(int i = 0; i < `PCIe_BYTE_W; i++)
     begin
       if(bb[0])
         p = p ^ aa;
       if(aa[7])
         aa = (aa << 1) ^ 8'h2B;
       else
         aa = (aa << 1);
       bb = bb >> 1;
     end
     return p;
   endfunction : crc_gf_mul

   // Compute 8-byte CRC over the 242-byte flit payload
   function bit [63:0] calculate_crc_on_242b_payload(input bit [`PCIe_BYTE_W-1:0] flit_payload_242b[$]);
     bit [`PCIe_BYTE_W-1:0] g[8];
     bit [`PCIe_BYTE_W-1:0] rem[8];
     bit [`PCIe_BYTE_W-1:0] fb;
     bit [63:0]             crc_result;

     g[0] = 8'hD5; g[1] = 8'h68; g[2] = 8'hFE; g[3] = 8'hD5;
     g[4] = 8'h33; g[5] = 8'h41; g[6] = 8'h4D; g[7] = 8'h69;

     if(flit_payload_242b.size() < `PCIe_DLP_FLIT_BYTE_W)
     begin
       `uvm_error(get_type_name(),
                  $sformatf("calculate_crc_on_242b_payload: need >= %0d Bytes, got %0d",
                            `PCIe_DLP_FLIT_BYTE_W, flit_payload_242b.size()))
       return '0;
     end

     foreach(rem[i]) rem[i] = 8'h00;

     for(int i = 0; i < `PCIe_DLP_FLIT_BYTE_W; i++)
     begin
       fb = rem[0] ^ flit_payload_242b[i];
       for(int k = 0; k < 7; k++)
         rem[k] = rem[k+1];
       rem[7] = 8'h00;
       if(fb != 8'h00)
       begin
         for(int k = 0; k < 8; k++)
           rem[k] = rem[k] ^ crc_gf_mul(fb, g[k]);
       end
     end

     crc_result = {rem[0], rem[1], rem[2], rem[3], rem[4], rem[5], rem[6], rem[7]};
     return crc_result;
   endfunction : calculate_crc_on_242b_payload

   // ============================================================================
   // SINGLE FEC/CRC CALCULATION : 256B FLIT RECEIVED FROM RC PHY -> EP MONITOR
   // ----------------------------------------------------------------------------
   // FEC/CRC addition : executed at every RX pipe dword, but only ONE full 256B
   // flit boundary (after the 232 training DWORDs) performs the check.
   // STEP 1 (FEC first) : 6B FEC calculated over the 250B body
   //                      (242B payload + 8B received CRC).
   // STEP 2 (CRC next)  : 8B CRC calculated over the received 242B payload.
   // Received AND calculated values are carried in pcie_seq_item.
   // The comparison (received vs calculated) is done ONLY in the scoreboard,
   // which prints all 6 FEC bytes + all 8 CRC bytes with PASS/FAIL once per flit.
   // ============================================================================
   task check_rc_to_ep_flit_fec_crc(input bit [`PCIe_MON_DATA_W-1:0] rc_flit_dword_q[$],
                                    input int total_dword_count);
      int  flit_dwords = `PCIe_FLIT_DWORDS + 3;                      // 64 dwords = 256B flit
      int  flit_start;
      bit [`PCIe_BYTE_W-1:0] ep_mon_256b_flit_received_from_rc[$];   // 256B flit after reverse process
      bit [`PCIe_BYTE_W-1:0] received_242b_payload_from_rc[$];       // 242B payload of received flit
      bit [`PCIe_BYTE_W-1:0] received_8b_crc_from_rc_flit [0:7];     // 8B CRC received in the RC->EP flit
      bit [`PCIe_BYTE_W-1:0] received_6b_fec_from_rc_flit [0:5];     // 6B FEC received in the RC->EP flit
      bit [`PCIe_BYTE_W-1:0] fec_body_250b_payload_plus_rc_crc[$];   // FEC input : 242B payload + 8B received CRC
      bit [`PCIe_BYTE_W-1:0] calculated_6b_fec_on_250b [0:5];        // 6B FEC calculated over the 250B body
      bit [63:0]             calculated_8b_crc_on_242b;              // 8B CRC calculated over the 242B payload

      // --- reset the check status for this pipeline event ---
      pcie_seq_item.rc_to_ep_flit_fec_crc_check_done = 1'b0;

      // --- gating : check a complete 256B flit, exactly once per flit ---
      // Flit N occupies dwords (232 + (N-1)*64) .. (232 + N*64 - 1). Its last dword
      // is reached when (rx_os_dword_count + 1 - 232) % 64 == 0. The DLP collector
      // may front-pop the capture queue down to 61 dwords, so use the trailing
      // 64 dwords of the queue -> always the just-finished flit.
      if (total_dword_count <= 232) return;                      // still inside the 232 training DWORDs
      if (((total_dword_count + 1 - 232) % 64) != 0) return;     // fire only at each 64-dword flit boundary
      if (rc_flit_dword_q.size() < 64) return;                   // full 256B flit not captured yet
      flit_start = rc_flit_dword_q.size() - 64;                  // current flit = last 64 dwords

      // ---- step 0 : rebuild the received 256B flit (4 bytes per dword, little-endian) ----
      ep_mon_256b_flit_received_from_rc.delete();
      for(int i = flit_start; i < flit_start + flit_dwords; i++) begin
         bit [31:0] dword = rc_flit_dword_q[i];
         ep_mon_256b_flit_received_from_rc.push_back(dword[7:0]);
         ep_mon_256b_flit_received_from_rc.push_back(dword[15:8]);
         ep_mon_256b_flit_received_from_rc.push_back(dword[23:16]);
         ep_mon_256b_flit_received_from_rc.push_back(dword[31:24]);
      end

      // ---- split received 256B flit : 242B payload + 8B CRC + 6B FEC ----
      received_242b_payload_from_rc.delete();
      for(int i = 0; i < `PCIe_DLP_FLIT_BYTE_W; i++)
         received_242b_payload_from_rc.push_back(ep_mon_256b_flit_received_from_rc[i]);
      for(int i = 0; i < `PCIe_FLIT_CRC_BYTES; i++)
         received_8b_crc_from_rc_flit[i] = ep_mon_256b_flit_received_from_rc[`PCIe_DLP_FLIT_BYTE_W + i];
      for(int i = 0; i < `PCIe_FLIT_FEC_BYTES; i++)
         received_6b_fec_from_rc_flit[i] = ep_mon_256b_flit_received_from_rc[`PCIe_DLP_FLIT_BYTE_W + `PCIe_FLIT_CRC_BYTES + i];

      // ==== STEP 1 : FEC CHECK (first) - FEC calculated over the 250B body ====
      fec_body_250b_payload_plus_rc_crc.delete();
      for(int i = 0; i < `PCIe_DLP_FLIT_BYTE_W; i++)
         fec_body_250b_payload_plus_rc_crc.push_back(received_242b_payload_from_rc[i]);
      for(int i = 0; i < `PCIe_FLIT_CRC_BYTES; i++)
         fec_body_250b_payload_plus_rc_crc.push_back(received_8b_crc_from_rc_flit[i]);
      calculate_fec_on_250b_body(fec_body_250b_payload_plus_rc_crc, calculated_6b_fec_on_250b);

      // NOTE : FEC comparison (received 6B vs calculated 6B) is done ONLY in the
      // SCOREBOARD. Here we only calculate the 6B FEC and carry the received +
      // calculated FEC values in pcie_seq_item.

      // ==== STEP 2 : CRC CHECK (next) - CRC calculated over the 242B payload ====
      calculated_8b_crc_on_242b = calculate_crc_on_242b_payload(received_242b_payload_from_rc);

      // NOTE : CRC comparison (received 8B vs calculated 8B on 242B) is also done
      // ONLY in the SCOREBOARD. Here we only carry the received + calculated CRC.

      // ---- carry received / calculated values to the scoreboard (report once per flit) ----
      for(int i = 0; i < `PCIe_FLIT_FEC_BYTES; i++) begin
         pcie_seq_item.rc_to_ep_flit_received_6b_fec[i]          = received_6b_fec_from_rc_flit[i];
         pcie_seq_item.rc_to_ep_flit_calculated_6b_fec_on_250b[i] = calculated_6b_fec_on_250b[i];
      end
      pcie_seq_item.rc_to_ep_flit_received_8b_crc           = {received_8b_crc_from_rc_flit[0], received_8b_crc_from_rc_flit[1],
                                                         received_8b_crc_from_rc_flit[2], received_8b_crc_from_rc_flit[3],
                                                         received_8b_crc_from_rc_flit[4], received_8b_crc_from_rc_flit[5],
                                                         received_8b_crc_from_rc_flit[6], received_8b_crc_from_rc_flit[7]};
      pcie_seq_item.rc_to_ep_flit_calculated_8b_crc_on_242b = calculated_8b_crc_on_242b;
      pcie_seq_item.rc_to_ep_flit_fec_crc_check_done         = 1'b1;
   endtask : check_rc_to_ep_flit_fec_crc
   `endif

endclass

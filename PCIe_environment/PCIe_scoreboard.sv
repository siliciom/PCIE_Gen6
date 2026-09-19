//=========================================================================================
// File         : PCIe_scoreboard.sv
// Project      : PCIE_Gen6
// Description  : PCIe_environment\PCIe_scoreboard.sv
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
`uvm_analysis_imp_decl(_rc_phy_tx)
`uvm_analysis_imp_decl(_ep_phy_rx)
`uvm_analysis_imp_decl(_rc_phy_rx)
`uvm_analysis_imp_decl(_ep_phy_tx)

`uvm_analysis_imp_decl(_rc_controller_tx)
`uvm_analysis_imp_decl(_ep_controller_rx)
`uvm_analysis_imp_decl(_rc_controller_rx)
`uvm_analysis_imp_decl(_ep_controller_tx)

`uvm_analysis_imp_decl(_rc_con_tx_256b)
`uvm_analysis_imp_decl(_ep_con_rx_256b)

`uvm_analysis_imp_decl(_rc_controller_dl_RC_EP)
`uvm_analysis_imp_decl(_ep_controller_dl_RC_EP)
`uvm_analysis_imp_decl(_rc_controller_dl_EP_RC)
`uvm_analysis_imp_decl(_ep_controller_dl_EP_RC)

class PCIe_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(PCIe_scoreboard)
  uvm_analysis_imp_rc_phy_tx #(PCIe_sequence_item,PCIe_scoreboard) rc_phy_tx_imp;
  uvm_analysis_imp_ep_phy_rx #(PCIe_sequence_item,PCIe_scoreboard) ep_phy_rx_imp;
  uvm_analysis_imp_rc_phy_rx #(PCIe_sequence_item,PCIe_scoreboard) rc_phy_rx_imp;
  uvm_analysis_imp_ep_phy_tx #(PCIe_sequence_item,PCIe_scoreboard) ep_phy_tx_imp;

  uvm_analysis_imp_rc_controller_tx #(PCIe_sequence_item,PCIe_scoreboard) rc_con_tx_imp;
  uvm_analysis_imp_ep_controller_rx #(PCIe_sequence_item,PCIe_scoreboard) ep_con_rx_imp;
  uvm_analysis_imp_rc_controller_rx #(PCIe_sequence_item,PCIe_scoreboard) rc_con_rx_imp;
  uvm_analysis_imp_ep_controller_tx #(PCIe_sequence_item,PCIe_scoreboard) ep_con_tx_imp;

  // [ADDED] RC->EP 256B flit : RC controller monitor (tx.data) vs EP controller
  // monitor (rx.data). The RC monitor sends the 256B flit it transmitted, the EP
  // monitor sends the matching 256B flit it received; the scoreboard compares all
  // 256 bytes and reports INFO on match / ERROR on mismatch.
  uvm_analysis_imp_rc_con_tx_256b #(PCIe_sequence_item,PCIe_scoreboard) rc_con_tx_256b_imp;
  uvm_analysis_imp_ep_con_rx_256b #(PCIe_sequence_item,PCIe_scoreboard) ep_con_rx_256b_imp;


  uvm_analysis_imp_rc_controller_dl_RC_EP #(PCIe_sequence_item,PCIe_scoreboard) rc_con_dl_rcep_imp;
  uvm_analysis_imp_ep_controller_dl_RC_EP #(PCIe_sequence_item,PCIe_scoreboard) ep_con_dl_rcep_imp;
  uvm_analysis_imp_rc_controller_dl_EP_RC #(PCIe_sequence_item,PCIe_scoreboard) rc_con_dl_eprc_imp;
  uvm_analysis_imp_ep_controller_dl_EP_RC#(PCIe_sequence_item,PCIe_scoreboard) ep_con_dl_eprc_imp;

  bit [31:0] rc_phy_tx_q[$];
  bit [31:0] ep_phy_rx_q[$];
  bit [31:0] rc_phy_rx_q[$];
  bit [31:0] ep_phy_tx_q[$];

  bit [31:0] rc_controller_tx_q[$];
  bit [31:0] ep_controller_rx_q[$];
  bit [31:0] rc_controller_rx_q[$];
  bit [31:0] ep_controller_tx_q[$];

  // [ADDED] 256B flit queues : RC->EP direction (tx.data vs rx.data)
  bit [`PCIe_BYTE_W-1:0] rc_ep_tx_256b_q[$];   // 256B flits transmitted by RC (from RC controller monitor)
  bit [`PCIe_BYTE_W-1:0] rc_ep_rx_256b_q[$];   // 256B flits received at EP (from EP controller monitor)
  int  rc_ep_256b_flits_compared = 0;          // number of 256B flits compared so far
  int  rc_ep_256b_flits_matched   = 0;         // number of flits with all 256 bytes matched
  int  rc_ep_256b_flits_mismatched= 0;         // number of flits with at least one byte mismatch


  bit[0:5][7:0]dlp_ep_q[$]; // RC-->EP
  bit[0:5][7:0]dlp_rc_q[$]; // RC-->EP
  bit[0:5][7:0]dlp_ep_qu[$]; // EP-->RC
  bit[0:5][7:0]dlp_rc_qu[$]; // EP-->RC

  function new(string name="PCIe_scoreboard",uvm_component parent);
    super.new(name,parent);
  endfunction

  function void build_phase(uvm_phase phase);
   `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_BUILD_PHASE",UVM_HIGH)
    super.build_phase(phase);
       rc_phy_tx_imp = new("rc_phy_tx_imp",this);
       ep_phy_rx_imp = new("ep_phy_rx_imp",this);
       rc_phy_rx_imp = new("rc_phy_rx_imp",this);
       ep_phy_tx_imp = new("ep_phy_tx_imp",this);
       
       rc_con_tx_imp = new("rc_con_tx_imp",this);
       ep_con_rx_imp = new("ep_con_rx_imp",this);
       rc_con_rx_imp = new("rc_con_rx_imp",this);
       ep_con_tx_imp = new("ep_con_tx_imp",this);

       // [ADDED] RC->EP 256B flit compare handles
       rc_con_tx_256b_imp = new("rc_con_tx_256b_imp",this);
       ep_con_rx_256b_imp = new("ep_con_rx_256b_imp",this);


       rc_con_dl_rcep_imp = new("rc_con_dl_rcep_imp",this);
       ep_con_dl_rcep_imp = new("ep_con_dl_rcep_imp",this);
       rc_con_dl_eprc_imp = new("rc_con_dl_eprc_imp",this);
       ep_con_dl_eprc_imp = new("ep_con_dl_eprc_imp",this);
       //set_report_id_verbosity("PCIe_SCOREBOARD","UVM_"); 
   `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_BUILD_PHASE",UVM_HIGH)
  endfunction

  function void write_rc_phy_tx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_RC_PHY_TX_DATA",UVM_HIGH)
    foreach(pkt.data_q_rc_mon_tx[i])begin
       rc_phy_tx_q.push_back(pkt.data_q_rc_mon_tx[i]);
       //`uvm_info("PCIe_SBOREBOARD",$sformatf("RC_PHY_TX_PARALLEL_DATA[%0d] = %08h, RC_PHY_SB_QUEUE_SIZE = %0d",i, pkt.data_q_rc_mon_tx[i], rc_phy_tx_q.size()),UVM_HIGH)
       `uvm_info("PCIe_SBOREBOARD",$sformatf("RC_PHY_TX_PARALLEL_DATA = %0p, RC_PHY_SB_QUEUE_SIZE = %0d", pkt.data_q_rc_mon_tx, rc_phy_tx_q.size()),UVM_HIGH)
     end
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_RC_PHY_TX_DATA",UVM_HIGH)
     compare_phy_rc_to_ep_data();
  endfunction

  function void write_ep_phy_rx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_EP_PHY_RX_DATA",UVM_HIGH)
     foreach(pkt.data_q_ep_mon_rx[i])begin
       ep_phy_rx_q.push_back(pkt.data_q_ep_mon_rx[i]);
       //`uvm_info("PCIe_SBOREBOARD",$sformatf("EP_PHY_RX_PARALLEL_DATA[%0d] = %08h, EP_PHY_SB_QUEUE_SIZE = %0d",i, pkt.data_q_ep_mon_rx[i], ep_phy_rx_q.size()),UVM_HIGH)
       `uvm_info("PCIe_SBOREBOARD",$sformatf("EP_PHY_RX_PARALLEL_DATA = %0p, EP_PHY_SB_QUEUE_SIZE = %0d", pkt.data_q_ep_mon_rx, ep_phy_rx_q.size()),UVM_HIGH)
      end
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_EP_PHY_RX_DATA",UVM_HIGH)
     compare_phy_rc_to_ep_data();
  endfunction
  

  function void compare_phy_rc_to_ep_data();
      bit [31:0] rc_phy_tx_data;
      bit [31:0] ep_phy_rx_data;

     `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_COMPARE_PHY_DATA",UVM_HIGH)
      while ((rc_phy_tx_q.size() > 0) && (ep_phy_rx_q.size() > 0)) begin
           rc_phy_tx_data = rc_phy_tx_q.pop_front();
           ep_phy_rx_data = ep_phy_rx_q.pop_front();
`uvm_info("PCIe_SCOREBOARD", $sformatf("COMPARING_RC_PHY_TX = %08h  EP_PHY_RX = %08h",  rc_phy_tx_data, ep_phy_rx_data), UVM_HIGH)
             if (rc_phy_tx_data == ep_phy_rx_data) begin
            `uvm_info("PCIe_SCOREBOARD",$sformatf("************PASS******************: PASS_RC_PHY_TX_TO_EP_PHY_RX_EXPECTED_DATA = %08h  EP_PHY_RX_ACTUAL_DATA = %08h", rc_phy_tx_data, ep_phy_rx_data), UVM_HIGH)
            end
            else begin
            `uvm_error("PCIe_SCOREBOARD",$sformatf("***********FAIL*****************:FAIL_RC_PHY_TX_TO_EP_PHY_RX_EXPECTED_DATA = %08h  EP_PHY_RX_ACTUAL_DATA = %08h", rc_phy_tx_data,ep_phy_rx_data))
            end
        end
        `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_COMPARE_PHY_DATA",UVM_HIGH)
  endfunction

  function void write_rc_phy_rx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_RC_PHY_RX_DATA",UVM_HIGH)
    foreach(pkt.data_q_rc_mon_rx[i])begin
       rc_phy_rx_q.push_back(pkt.data_q_rc_mon_rx[i]);
       //`uvm_info("PCIe_SBOREBOARD",$sformatf("RC_PHY_RX_PARALLEL_DATA[%0d] = %08h, RC_PHY_SB_QUEUE_SIZE = %0d",i, pkt.data_q_rc_mon_rx[i], rc_phy_rx_q.size()),UVM_HIGH)
       `uvm_info("PCIe_SBOREBOARD",$sformatf("RC_PHY_RX_PARALLEL_DATA = %0p, RC_PHY_SB_QUEUE_SIZE = %0d", pkt.data_q_rc_mon_rx, rc_phy_rx_q.size()),UVM_HIGH)
     end
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_RC_PHY_RX_DATA",UVM_HIGH)
     compare_phy_ep_to_rc_data();
  endfunction

  function void write_ep_phy_tx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_EP_PHY_TX_DATA",UVM_HIGH)
     foreach(pkt.data_q_ep_mon_tx[i])begin
       ep_phy_tx_q.push_back(pkt.data_q_ep_mon_tx[i]);
       `uvm_info("PCIe_SBOREBOARD",$sformatf("EP_PHY_TX_PARALLEL_DATA = %0p, EP_PHY_SB_QUEUE_SIZE = %0d", pkt.data_q_ep_mon_tx, ep_phy_tx_q.size()),UVM_HIGH)
      end
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_EP_PHY_TX_DATA",UVM_HIGH)
     compare_phy_ep_to_rc_data();
  endfunction

  function void compare_phy_ep_to_rc_data();
      bit [31:0] rc_phy_rx_data;
      bit [31:0] ep_phy_tx_data;

     `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_COMPARE_PHY_DATA",UVM_HIGH)
      while ((rc_phy_rx_q.size() > 0) && (ep_phy_tx_q.size() > 0)) begin
           rc_phy_rx_data = rc_phy_rx_q.pop_front();
           ep_phy_tx_data = ep_phy_tx_q.pop_front();
`uvm_info("PCIe_SCOREBOARD", $sformatf("COMPARING_RC_PHY_TX = %08h  EP_PHY_RX = %08h",  rc_phy_rx_data, ep_phy_tx_data), UVM_HIGH)
             if (rc_phy_rx_data == ep_phy_tx_data) begin
            `uvm_info("PCIe_SCOREBOARD",$sformatf("************PASS******************: PASS_EP_PHY_TX_TO_RC_PHY_RX_EXPECTED_DATA = %08h  EP_PHY_RX_ACTUAL_DATA = %08h", rc_phy_rx_data, ep_phy_tx_data), UVM_HIGH)
            end
            else begin
            `uvm_error("PCIe_SCOREBOARD",$sformatf("***********FAIL*****************:FAIL_EP_PHY_TX_TO_RC_PHY_RX_EXPECTED_DATA = %08h  EP_PHY_RX_ACTUAL_DATA = %08h", rc_phy_rx_data,ep_phy_tx_data))
            end
        end
        `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_COMPARE_PHY_DATA",UVM_HIGH)
  endfunction

  function void write_rc_controller_tx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_RC_CONTROLLER_TX_DATA",UVM_HIGH)
    foreach(pkt.data_q_rc_mon_con_tx[i])begin
       rc_controller_tx_q.push_back(pkt.data_q_rc_mon_con_tx[i]);
       //`uvm_info("PCIe_SBOREBOARD",$sformatf("RC_CONTROLLER_TX_PARALLEL_DATA[%0d] = %08h, RC_CON_SB_QUEUE_SIZE = %0d",i, pkt.data_q_rc_mon_con_tx[i], rc_controller_tx_q.size()),UVM_HIGH)
       `uvm_info("PCIe_SBOREBOARD",$sformatf("RC_CONTROLLER_TX_PARALLEL_DATA = %0p, RC_CON_SB_QUEUE_SIZE = %0d", pkt.data_q_rc_mon_con_tx, rc_controller_tx_q.size()),UVM_HIGH)
     end
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_RC_CONTROLLER_TX_DATA",UVM_HIGH)
     compare_controller_rc_to_ep_data();
  endfunction

  function void write_ep_controller_rx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_EP_CONTROLLER_RX_DATA",UVM_HIGH)
     foreach(pkt.data_q_ep_mon_con_rx[i])begin
       ep_controller_rx_q.push_back(pkt.data_q_ep_mon_con_rx[i]);
       //`uvm_info("PCIe_SBOREBOARD",$sformatf("EP_CONTROLLER_RX_PARALLEL_DATA[%0d] = %08h, EP_CON_SB_QUEUE_SIZE = %0d",i, pkt.data_q_ep_mon_con_rx[i], ep_controller_rx_q.size()),UVM_HIGH)
       `uvm_info("PCIe_SBOREBOARD",$sformatf("EP_CONTROLLER_RX_PARALLEL_DATA = %0p, EP_CON_SB_QUEUE_SIZE = %0d", pkt.data_q_ep_mon_con_rx, ep_controller_rx_q.size()),UVM_HIGH)
      end
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_EP_CONTROLLER_RX_DATA",UVM_HIGH)
     compare_controller_rc_to_ep_data();
  endfunction

  function void compare_controller_rc_to_ep_data();
      bit [31:0] rc_controller_tx_data;
      bit [31:0] ep_controller_rx_data;

     `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_COMPARE_CONTROLLER_DATA",UVM_HIGH)
      while ((rc_controller_tx_q.size() > 0) && (ep_controller_rx_q.size() > 0)) begin
           rc_controller_tx_data = rc_controller_tx_q.pop_front();
           ep_controller_rx_data = ep_controller_rx_q.pop_front();
           `uvm_info("PCIe_SCOREBOARD", $sformatf("COMPARING_RC_CONTROLLER_TX = %08h  EP_CONTROLLER_RX = %08h",  rc_controller_tx_data, ep_controller_rx_data), UVM_HIGH)
            if (rc_controller_tx_data == ep_controller_rx_data) begin
            `uvm_info("PCIe_SCOREBOARD",$sformatf("************PASS******************: PASS_RC_CONTROLLER_TX_TO_EP_CONTROLLER_RX_EXPECTED_DATA = %08h  EP_CONTROLLER_RX ACTUAL_DATA = %08h", rc_controller_tx_data, ep_controller_rx_data), UVM_HIGH)
            end
            else begin
            `uvm_error("PCIe_SCOREBOARD",$sformatf("***********FAIL*****************:FAIL_RC_CONTROLLER_TX_TO_EP_CONTROLLER_RX_EXPECTED_DATA = %08h  EP_CONTROLLER_RX ACTUAL_DATA = %08h", rc_controller_tx_data,ep_controller_rx_data))
            end
        end
        `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_COMPARE_CONTROLLER_DATA",UVM_HIGH)
  endfunction

  function void write_rc_controller_rx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_RC_CONTROLLER_RX_DATA",UVM_HIGH)
    foreach(pkt.data_q_rc_mon_con_rx[i])begin
       rc_controller_rx_q.push_back(pkt.data_q_rc_mon_con_rx[i]);
       //`uvm_info("PCIe_SBOREBOARD",$sformatf("RC_CONTROLLER_RX_PARALLEL_DATA[%0d] = %08h, RC_CON_SB_QUEUE_SIZE = %0d",i, pkt.data_q_rc_mon_con_rx[i], rc_controller_rx_q.size()),UVM_HIGH)
       `uvm_info("PCIe_SBOREBOARD",$sformatf("RC_CONTROLLER_RX_PARALLEL_DATA = %0p, RC_CON_SB_QUEUE_SIZE = %0d", pkt.data_q_rc_mon_con_rx, rc_controller_rx_q.size()),UVM_HIGH)
     end
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_RC_CONTROLLER_RX_DATA",UVM_HIGH)
     compare_controller_ep_to_rc_data();
  endfunction

  function void write_ep_controller_tx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_EP_CONTROLLER_TX_DATA",UVM_HIGH)
     foreach(pkt.data_q_ep_mon_con_tx[i])begin
       ep_controller_tx_q.push_back(pkt.data_q_ep_mon_con_tx[i]);
       //`uvm_info("PCIe_SBOREBOARD",$sformatf("EP_CONTROLLER_TX_PARALLEL_DATA[%0d] = %08h, EP_CON_SB_QUEUE_SIZE = %0d",i, pkt.data_q_ep_mon_con_tx[i], ep_controller_tx_q.size()),UVM_HIGH)
       `uvm_info("PCIe_SBOREBOARD",$sformatf("EP_CONTROLLER_TX_PARALLEL_DATA = %0p, EP_CON_SB_QUEUE_SIZE = %0d", pkt.data_q_ep_mon_con_tx, ep_controller_tx_q.size()),UVM_HIGH)
      end
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_EP_CONTROLLER_RX_DATA",UVM_HIGH)
     compare_controller_ep_to_rc_data();
  endfunction

  function void compare_controller_ep_to_rc_data();
      bit [31:0] rc_controller_rx_data;
      bit [31:0] ep_controller_tx_data;

     `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_COMPARE_CONTROLLER_DATA",UVM_HIGH)
      while ((rc_controller_rx_q.size() > 0) && (ep_controller_tx_q.size() > 0)) begin
           rc_controller_rx_data = rc_controller_rx_q.pop_front();
           ep_controller_tx_data = ep_controller_tx_q.pop_front();
           `uvm_info("PCIe_SCOREBOARD", $sformatf("COMPARING_RC_CONTROLLER_TX = %08h  EP_CONTROLLER_RX = %08h",  rc_controller_rx_data, ep_controller_tx_data), UVM_HIGH)
            if (rc_controller_rx_data == ep_controller_tx_data) begin
            `uvm_info("PCIe_SCOREBOARD",$sformatf("************PASS******************: PASS_EP_CONTROLLER_TX_TO_RC_CONTROLLER_RX_EXPECTED_DATA = %08h  EP_CONTROLLER_RX ACTUAL_DATA = %08h", rc_controller_rx_data, ep_controller_tx_data), UVM_HIGH)
            end
            else begin
            `uvm_error("PCIe_SCOREBOARD",$sformatf("***********FAIL*****************:FAIL_EP_CONTROLLER_TX_TO_RC_CONTROLLER_RX_EXPECTED_DATA = %08h  EP_CONTROLLER_RX ACTUAL_DATA = %08h", rc_controller_rx_data,ep_controller_tx_data))
            end
        end
        `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_COMPARE_CONTROLLER_DATA",UVM_HIGH)
  endfunction

  // RC to EP

  // Packet going from the RC Controller to Scoreboard
  function void write_rc_controller_dl_RC_EP(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ACTUAL_PACKET_RC_TO_EP_DLP",UVM_HIGH)
    `uvm_info("PCIe_SCOREBOARD",$sformatf("pkt.dlp=%p", pkt.dlp), UVM_HIGH)
    dlp_rc_q.push_back(pkt.dlp);
    compare_rc_ep_dl(pkt);
  endfunction

  // Packet going from the EP Controller to Scoreboard
  function void write_ep_controller_dl_RC_EP(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","EXPECTED_PACKET_RC_TO_EP_DLP",UVM_HIGH)
    `uvm_info("PCIe_SCOREBOARD",$sformatf("pkt.dlp=%p", pkt.dlp), UVM_HIGH)
    dlp_ep_q.push_back(pkt.dlp);
    compare_rc_ep_dl(pkt);
  endfunction

  // EP TO RC
 
  // Packet going from the RC Controller to Scoreboard
  function void write_rc_controller_dl_EP_RC(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","EXPECTED_PACKET_EP_TO_RC",UVM_HIGH)
    `uvm_info("PCIe_SCOREBOARD",$sformatf("pkt.dlp=%p", pkt.dlp), UVM_HIGH)
    dlp_rc_qu.push_back(pkt.dlp);
    compare_ep_rc_dl(pkt);
  endfunction

  // Packet going from the EP Controller to Scoreboard
  function void write_ep_controller_dl_EP_RC(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ACTUAL_PACKET_EP_TO_RC",UVM_HIGH)
    `uvm_info("PCIe_SCOREBOARD",$sformatf("pkt.dlp=%p", pkt.dlp), UVM_HIGH)
    dlp_ep_qu.push_back(pkt.dlp);
    compare_ep_rc_dl(pkt);
  endfunction
  

  function compare_rc_ep_dl(PCIe_sequence_item item);

	  bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] expected_dlp_rc_ep;
          bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] actual_dlp_rc_ep;

	  `uvm_info("PCIe_SCOREBOARD",$sformatf("Queues: Expected=%0d, Actual=%0d", dlp_ep_q.size(), dlp_rc_q.size()), UVM_HIGH)

	  while((dlp_ep_q.size() > 0) && (dlp_rc_q.size() >0))
          begin
		  expected_dlp_rc_ep = dlp_ep_q.pop_front();
                  actual_dlp_rc_ep   = dlp_rc_q.pop_front();
          
	  if(expected_dlp_rc_ep == actual_dlp_rc_ep)
	  begin
		  `uvm_info("PCIE_SCOREBOARD","PASS_DLP_PACKETS_MATCHED_RC_TO_EP",UVM_HIGH)
		  `uvm_info("PCIE_SCOREBOARD",$sformatf("PASS_RC_EP :: expected=%p :: actual=%p",expected_dlp_rc_ep,actual_dlp_rc_ep),UVM_HIGH)
	           item.print_dlp_details("MATCHED_PACKET", actual_dlp_rc_ep);
	   end
	  else
	  begin
		  `uvm_info("PCIE_SCOREBOARD","FAIL_DLP_PACKETS_MATCHED_RC_TO_EP",UVM_HIGH)
		  `uvm_info("PCIE_SCOREBOARD",$sformatf("FAIL_RC_EP :: expected=%p :: actual=%p",expected_dlp_rc_ep,actual_dlp_rc_ep),UVM_HIGH)
		  item.print_dlp_details("EXPECTED_DLP", expected_dlp_rc_ep);
		  item.print_dlp_details("ACTUAL_DLP", actual_dlp_rc_ep);
	  end
          end
  endfunction

  function compare_ep_rc_dl(PCIe_sequence_item item);

	  bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] expected_dlp_ep_rc;
          bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] actual_dlp_ep_rc;

	  `uvm_info("PCIe_SCOREBOARD",$sformatf("Queues: Expected=%0d, Actual=%0d", dlp_ep_qu.size(), dlp_rc_qu.size()), UVM_HIGH)

	  while((dlp_ep_qu.size() > 0) && (dlp_rc_qu.size() >0))
          begin
		  expected_dlp_ep_rc = dlp_ep_qu.pop_front();
                  actual_dlp_ep_rc   = dlp_rc_qu.pop_front();

	  if(expected_dlp_ep_rc == actual_dlp_ep_rc)
	  begin
		  `uvm_info("PCIE_SCOREBOARD","PASS_DLP_PACKETS_MATCHED_EP_TO_RC",UVM_HIGH)
		  `uvm_info("PCIE_SCOREBOARD",$sformatf("PASS_EP_RC :: expected=%p :: actual=%p",expected_dlp_ep_rc,actual_dlp_ep_rc),UVM_HIGH)
	           item.print_dlp_details("MATCHED_PACKET", actual_dlp_ep_rc);
	   end
	  else 
	  begin
		  `uvm_info("PCIE_SCOREBOARD","FAIL_DLP_PACKETS_MATCHED_EP_TO_RC",UVM_HIGH)
		  `uvm_info("PCIE_SCOREBOARD",$sformatf("FAIL_EP_RC :: expected=%p :: actual=%p",expected_dlp_ep_rc,actual_dlp_ep_rc),UVM_HIGH)
		  item.print_dlp_details("EXPECTED_DLP", expected_dlp_ep_rc);
		  item.print_dlp_details("ACTUAL_DLP", actual_dlp_ep_rc);
	  end
          end
  endfunction

// [ADDED] RC controller monitor -> scoreboard :: 256B RC->EP flit on tx.data
  // Written once per flit by the RC controller monitor after the full reverse
  // process (de-precode / gray-decode / descramble) of the RC tx_data stream.
  function void write_rc_con_tx_256b(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_RC_CON_TX_256B_FLIT",UVM_HIGH)
    foreach(pkt.rc_ep_tx_256b_flit[i])
      rc_ep_tx_256b_q.push_back(pkt.rc_ep_tx_256b_flit[i]);
    `uvm_info("PCIe_SCOREBOARD",$sformatf("RC_TX_256B_FLIT : SENT 256 BYTES FROM RC tx.data TO SCOREBOARD (rc_ep_tx_256b_q_size=%0d)", rc_ep_tx_256b_q.size()),UVM_LOW)
    compare_rc_ep_256b_flit(pkt);
  endfunction

  // [ADDED] EP controller monitor -> scoreboard :: 256B RC->EP flit on rx.data
  // Written once per flit by the EP controller monitor after the full reverse
  // process (de-precode / gray-decode / descramble) of the EP rx_data stream.
  function void write_ep_con_rx_256b(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_EP_CON_RX_256B_FLIT",UVM_HIGH)
    foreach(pkt.rc_ep_rx_256b_flit[i])
      rc_ep_rx_256b_q.push_back(pkt.rc_ep_rx_256b_flit[i]);
    `uvm_info("PCIe_SCOREBOARD",$sformatf("EP_RX_256B_FLIT : SENT 256 BYTES RECEIVED AT EP FROM rx.data TO SCOREBOARD (rc_ep_rx_256b_q_size=%0d)", rc_ep_rx_256b_q.size()),UVM_LOW)
    compare_rc_ep_256b_flit(pkt);
  endfunction

  // [ADDED] Compare all 256 bytes of every RC->EP flit : RC tx.data (transmitted
  // by RC controller monitor) vs EP rx.data (received by EP controller monitor).
  // INFO when all 256 bytes match; ERROR when any byte does not match.
  // Prints the compared bytes (hex, both directions) and explains to the team
  // that the same 256 bytes sent on RC tx.data arrived at EP rx.data.
  function compare_rc_ep_256b_flit(PCIe_sequence_item pkt);
    bit [`PCIe_BYTE_W-1:0] tx_256b [256];
    bit [`PCIe_BYTE_W-1:0] rx_256b [256];
    int  byte_mismatch_count;
    string tx_dec;
    string rx_dec;
    int  i;

    while ((rc_ep_tx_256b_q.size() >= 256) && (rc_ep_rx_256b_q.size() >= 256)) begin
      // pop one full 256B flit from each side (all 256 bytes)
      for(i = 0; i < 256; i++) begin
        tx_256b[i] = rc_ep_tx_256b_q.pop_front();
        rx_256b[i] = rc_ep_rx_256b_q.pop_front();
      end
      rc_ep_256b_flits_compared++;

      // byte-by-byte comparison over all 256 bytes
      byte_mismatch_count = 0;
      for(i = 0; i < 256; i++)
        if (tx_256b[i] !== rx_256b[i])
          byte_mismatch_count++;

      tx_dec = "";
      rx_dec = "";
      for(i = 0; i < 256; i++)
        tx_dec = $sformatf("%s%0d ", tx_dec, tx_256b[i]);
      for(i = 0; i < 256; i++)
        rx_dec = $sformatf("%s%0d ", rx_dec, rx_256b[i]);

      if (byte_mismatch_count == 0) begin
        rc_ep_256b_flits_matched++;
        `uvm_info("PCIe_SCOREBOARD",
                  $sformatf("RC_EP_256B_FLIT_COMPARE :: FLIT[%0d] MATCH_IS_THERE : ALL_256_BYTES_MATCHED : SAME_DECIMAL_BYTES_SENT_ON_RC_TX_DATA_ARRIVED_ON_EP_RX_DATA (RC_TX_BYTE_0=%0d EP_RX_BYTE_0=%0d) : RC_TX_256B_DECIMAL=%s : EP_RX_256B_DECIMAL=%s",
                            rc_ep_256b_flits_compared, tx_256b[0], rx_256b[0], tx_dec, rx_dec), UVM_LOW)
      end
      else begin
        rc_ep_256b_flits_mismatched++;
        `uvm_error("PCIe_SCOREBOARD",
                   $sformatf("RC_EP_256B_FLIT_COMPARE :: FLIT[%0d] 256B_MATCH_NOT_THERE : %0d_OF_256_BYTES_MISMATCHED : RC_TX_256B_DECIMAL=%s : EP_RX_256B_DECIMAL=%s",
                             rc_ep_256b_flits_compared, byte_mismatch_count, tx_dec, rx_dec))
      end
    end

    // [ADDED] summary understanding message for the team : how many 256B flits
    // were compared and that RX data == TX data (RC->EP).
    if (rc_ep_256b_flits_compared > 0)
      `uvm_info("PCIe_SCOREBOARD",
                $sformatf("RC_EP_256B_FLIT_SUMMARY : TOTAL_256B_FLITS_COMPARED=%0d ALL_256_BYTES_MATCHED_FLITS=%0d MISMATCHED_FLITS=%0d : UNDERSTANDING : THE_SAME_256_BYTES_SENT_ON_RC_tx.data_ARE_RECEIVED_ON_EP_rx.data (RC->EP direction checked)",
                          rc_ep_256b_flits_compared, rc_ep_256b_flits_matched, rc_ep_256b_flits_mismatched), UVM_LOW)
  endfunction

endclass

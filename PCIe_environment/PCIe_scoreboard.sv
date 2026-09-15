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


  bit[0:5][7:0]dlp_ep_q[$]; // RC-->EP
  bit[0:5][7:0]dlp_rc_q[$]; // RC-->EP
  bit[0:5][7:0]dlp_ep_qu[$]; // EP-->RC
  bit[0:5][7:0]dlp_rc_qu[$]; // EP-->RC

  // ---- LCRC additions: parallel queues for TX-side-computed vs RX-side-computed LCRC ----
  bit [`PCIe_DL_LCRC_W-1:0] lcrc_ep_q[$]; // RC-->EP
  bit [`PCIe_DL_LCRC_W-1:0] lcrc_rc_q[$]; // RC-->EP
  bit [`PCIe_DL_LCRC_W-1:0] lcrc_ep_qu[$]; // EP-->RC
  bit [`PCIe_DL_LCRC_W-1:0] lcrc_rc_qu[$]; // EP-->RC
  

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
     `ifdef PCIE_GEN6_FEC_CRC
     // ---- FEC/CRC addition : single report for the RC->EP 256B flit ----
     // The EP controller monitor computes FEC(on 250B body) and CRC(on 242B
     // payload) for the RC->EP flit; report PASS/FAIL here once per flit.
     report_rc_to_ep_flit_fec_crc(pkt);
     `endif
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
     `ifdef PCIE_GEN6_FEC_CRC
     // ---- FEC/CRC addition : single report for the EP->RC 256B flit ----
     // The RC controller monitor computes FEC(on 250B body) and CRC(on 242B
     // payload) for the EP->RC flit; report PASS/FAIL here once per flit.
     report_ep_to_rc_flit_fec_crc(pkt);
     `endif
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
    lcrc_rc_q.push_back(pkt.dl_lcrc);          // ---- LCRC addition ----
    compare_rc_ep_dl(pkt);
    compare_lcrc_rc_ep();                      // ---- LCRC addition ----
  endfunction

  // Packet going from the EP Controller to Scoreboard
  function void write_ep_controller_dl_RC_EP(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","EXPECTED_PACKET_RC_TO_EP_DLP",UVM_HIGH)
    `uvm_info("PCIe_SCOREBOARD",$sformatf("pkt.dlp=%p", pkt.dlp), UVM_HIGH)
    dlp_ep_q.push_back(pkt.dlp);
    lcrc_ep_q.push_back(pkt.dl_lcrc);          // ---- LCRC addition ----
    compare_rc_ep_dl(pkt);
    compare_lcrc_rc_ep();                      // ---- LCRC addition ----
  endfunction

  // EP TO RC
 
  // Packet going from the RC Controller to Scoreboard
  function void write_rc_controller_dl_EP_RC(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","EXPECTED_PACKET_EP_TO_RC",UVM_HIGH)
    `uvm_info("PCIe_SCOREBOARD",$sformatf("pkt.dlp=%p", pkt.dlp), UVM_HIGH)
    dlp_rc_qu.push_back(pkt.dlp);
    lcrc_rc_qu.push_back(pkt.dl_lcrc);         // ---- LCRC addition ----
    compare_ep_rc_dl(pkt);
    compare_lcrc_ep_rc();                      // ---- LCRC addition ----
     
  endfunction

  // Packet going from the EP Controller to Scoreboard
  function void write_ep_controller_dl_EP_RC(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ACTUAL_PACKET_EP_TO_RC",UVM_HIGH)
    `uvm_info("PCIe_SCOREBOARD",$sformatf("pkt.dlp=%p", pkt.dlp), UVM_HIGH)
    dlp_ep_qu.push_back(pkt.dlp);
    lcrc_ep_qu.push_back(pkt.dl_lcrc);         // ---- LCRC addition ----
    compare_ep_rc_dl(pkt);
    compare_lcrc_ep_rc();                      // ---- LCRC addition ----
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

  // ---- LCRC additions: compare functions, mirroring compare_rc_ep_dl / compare_ep_rc_dl ----

  function compare_lcrc_rc_ep();
     bit [`PCIe_DL_LCRC_W-1:0] expected_lcrc_rc_ep;
     bit [`PCIe_DL_LCRC_W-1:0] actual_lcrc_rc_ep;

     `uvm_info("PCIe_SCOREBOARD",$sformatf("LCRC_Queues_RC_EP: Expected=%0d, Actual=%0d", lcrc_ep_q.size(), lcrc_rc_q.size()), UVM_HIGH)

     while((lcrc_ep_q.size() > 0) && (lcrc_rc_q.size() > 0)) begin
        expected_lcrc_rc_ep = lcrc_ep_q.pop_front();
        actual_lcrc_rc_ep   = lcrc_rc_q.pop_front();

        if(expected_lcrc_rc_ep == actual_lcrc_rc_ep) begin
           `uvm_info("PCIE_SCOREBOARD",$sformatf("PASS_LCRC_RC_TO_EP :: expected=%08h :: actual=%08h",expected_lcrc_rc_ep,actual_lcrc_rc_ep),UVM_HIGH)
        end
        else begin
           `uvm_error("PCIE_SCOREBOARD",$sformatf("FAIL_LCRC_RC_TO_EP :: expected=%08h :: actual=%08h",expected_lcrc_rc_ep,actual_lcrc_rc_ep))
        end
     end
  endfunction

  function compare_lcrc_ep_rc();
     bit [`PCIe_DL_LCRC_W-1:0] expected_lcrc_ep_rc;
     bit [`PCIe_DL_LCRC_W-1:0] actual_lcrc_ep_rc;

     `uvm_info("PCIe_SCOREBOARD",$sformatf("LCRC_Queues_EP_RC: Expected=%0d, Actual=%0d", lcrc_ep_qu.size(), lcrc_rc_qu.size()), UVM_HIGH)

     while((lcrc_ep_qu.size() > 0) && (lcrc_rc_qu.size() > 0)) begin
        expected_lcrc_ep_rc = lcrc_ep_qu.pop_front();
        actual_lcrc_ep_rc   = lcrc_rc_qu.pop_front();

        if(expected_lcrc_ep_rc == actual_lcrc_ep_rc) begin
           `uvm_info("PCIE_SCOREBOARD",$sformatf("PASS_LCRC_EP_TO_RC :: expected=%08h :: actual=%08h",expected_lcrc_ep_rc,actual_lcrc_ep_rc),UVM_HIGH)
        end
        else begin
           `uvm_error("PCIE_SCOREBOARD",$sformatf("FAIL_LCRC_EP_TO_RC :: expected=%08h :: actual=%08h",expected_lcrc_ep_rc,actual_lcrc_ep_rc))
        end
     end
  endfunction

   `ifdef PCIE_GEN6_FEC_CRC
   // ============================================================================
   // ---- FEC/CRC addition : compare + report for the RC->EP 256B flit ---------
   // The EP controller monitor computes FEC(on 250B body) and CRC(on 242B
   // payload) on the 256B flit received from RC PHY, and carries the received
   // and calculated values here via pcie_seq_item. THE COMPARISON IS DONE ONLY
   // HERE (this scoreboard).
   // FEC: compares all 6 bytes of received FEC vs calculated FEC, prints all
   //      6 bytes of each side + FEC_MATCH (PASS/FAIL).
   // CRC: compares all 8 bytes of received CRC vs calculated CRC (on 242B),
   //      prints all 8 bytes of each side + CRC_MATCH (PASS/FAIL).
   // Reported once per flit.
   // ============================================================================
   function void report_rc_to_ep_flit_fec_crc(PCIe_sequence_item pkt);
      bit             fec_6b_match;                        // 1 = all 6 received FEC bytes == calculated FEC bytes
      bit             crc_8b_match;                        // 1 = all 8 received CRC bytes == calculated CRC bytes
      string          fec_received_bytes_log;              // all 6 received FEC bytes as hex (byte[0]..byte[5])
      string          fec_calculated_bytes_log;            // all 6 calculated FEC bytes as hex (byte[0]..byte[5])
      string          crc_received_bytes_log;              // all 8 received CRC bytes as hex (byte[0]..byte[7])
      string          crc_calculated_bytes_log;            // all 8 calculated CRC bytes as hex (byte[0]..byte[7])

      if(!pkt.rc_to_ep_flit_fec_crc_check_done) return;    // report only once per flit
      pkt.rc_to_ep_flit_fec_crc_check_done = 1'b0;

      // ---- FEC : compare all 6 bytes (received vs calculated on 250B body) ----
      fec_6b_match            = 1'b1;
      fec_received_bytes_log  = "";
      fec_calculated_bytes_log = "";
      for(int i = 0; i < `PCIe_FLIT_FEC_BYTES; i++) begin
         fec_received_bytes_log   = $sformatf("%s FEC6_BYTE[%0d]=0x%02h",
                                              fec_received_bytes_log, i,
                                              pkt.rc_to_ep_flit_received_6b_fec[i]);
         fec_calculated_bytes_log = $sformatf("%s FEC6_BYTE[%0d]=0x%02h",
                                              fec_calculated_bytes_log, i,
                                              pkt.rc_to_ep_flit_calculated_6b_fec_on_250b[i]);
         if(pkt.rc_to_ep_flit_received_6b_fec[i] !== pkt.rc_to_ep_flit_calculated_6b_fec_on_250b[i])
            fec_6b_match = 1'b0;
      end

      if(fec_6b_match)
         `uvm_info("PCIe_SCOREBOARD",
                   $sformatf("RC_TO_EP_FLIT_FEC_CHECK : PASS : RECEIVED_6B_FEC{%s } CALCULATED_6B_FEC_ON_250B{%s } | FEC_MATCH=1",
                             fec_received_bytes_log, fec_calculated_bytes_log), UVM_LOW)
      else
         `uvm_error("PCIe_SCOREBOARD",
                    $sformatf("RC_TO_EP_FLIT_FEC_CHECK : FAIL : RECEIVED_6B_FEC{%s } CALCULATED_6B_FEC_ON_250B{%s } | FEC_MATCH=0",
                              fec_received_bytes_log, fec_calculated_bytes_log))

      // ---- CRC : compare all 8 bytes (received vs calculated on 242B payload) ----
      crc_8b_match            = 1'b1;
      crc_received_bytes_log  = "";
      crc_calculated_bytes_log = "";
      for(int b = 0; b < `PCIe_FLIT_CRC_BYTES; b++) begin
         crc_received_bytes_log   = $sformatf("%s CRC8_BYTE[%0d]=0x%02h",
                                              crc_received_bytes_log, b,
                                              pkt.rc_to_ep_flit_received_8b_crc[((7-b)*8) +: 8]);
         crc_calculated_bytes_log = $sformatf("%s CRC8_BYTE[%0d]=0x%02h",
                                              crc_calculated_bytes_log, b,
                                              pkt.rc_to_ep_flit_calculated_8b_crc_on_242b[((7-b)*8) +: 8]);
         if(pkt.rc_to_ep_flit_received_8b_crc[((7-b)*8) +: 8] !==
            pkt.rc_to_ep_flit_calculated_8b_crc_on_242b[((7-b)*8) +: 8])
            crc_8b_match = 1'b0;
      end

      if(crc_8b_match)
         `uvm_info("PCIe_SCOREBOARD",
                   $sformatf("RC_TO_EP_FLIT_CRC_CHECK : PASS : RECEIVED_8B_CRC{%s } CALCULATED_8B_CRC_ON_242B{%s } | CRC_MATCH=1",
                             crc_received_bytes_log, crc_calculated_bytes_log), UVM_LOW)
      else
         `uvm_error("PCIe_SCOREBOARD",
                    $sformatf("RC_TO_EP_FLIT_CRC_CHECK : FAIL : RECEIVED_8B_CRC{%s } CALCULATED_8B_CRC_ON_242B{%s } | CRC_MATCH=0",
                              crc_received_bytes_log, crc_calculated_bytes_log))
   endfunction : report_rc_to_ep_flit_fec_crc

   // ============================================================================
   // ---- FEC/CRC addition : compare + report for the EP->RC 256B flit ---------
   // The RC controller monitor computes FEC(on 250B body) and CRC(on 242B
   // payload) on the 256B flit received from EP PHY, and carries the received
   // and calculated values here via pcie_seq_item. THE COMPARISON IS DONE ONLY
   // HERE (this scoreboard).
   // FEC: compares all 6 bytes of received FEC vs calculated FEC, prints all
   //      6 bytes of each side + FEC_MATCH (PASS/FAIL).
   // CRC: compares all 8 bytes of received CRC vs calculated CRC (on 242B),
   //      prints all 8 bytes of each side + CRC_MATCH (PASS/FAIL).
   // Reported once per flit.
   // ============================================================================
   function void report_ep_to_rc_flit_fec_crc(PCIe_sequence_item pkt);
      bit             fec_6b_match;                        // 1 = all 6 received FEC bytes == calculated FEC bytes
      bit             crc_8b_match;                        // 1 = all 8 received CRC bytes == calculated CRC bytes
      string          fec_received_bytes_log;              // all 6 received FEC bytes as hex (byte[0]..byte[5])
      string          fec_calculated_bytes_log;            // all 6 calculated FEC bytes as hex (byte[0]..byte[5])
      string          crc_received_bytes_log;              // all 8 received CRC bytes as hex (byte[0]..byte[7])
      string          crc_calculated_bytes_log;            // all 8 calculated CRC bytes as hex (byte[0]..byte[7])

      if(!pkt.ep_to_rc_flit_fec_crc_check_done) return;    // report only once per flit
      pkt.ep_to_rc_flit_fec_crc_check_done = 1'b0;

      // ---- FEC : compare all 6 bytes (received vs calculated on 250B body) ----
      fec_6b_match            = 1'b1;
      fec_received_bytes_log  = "";
      fec_calculated_bytes_log = "";
      for(int i = 0; i < `PCIe_FLIT_FEC_BYTES; i++) begin
         fec_received_bytes_log   = $sformatf("%s FEC6_BYTE[%0d]=0x%02h",
                                              fec_received_bytes_log, i,
                                              pkt.ep_to_rc_flit_received_6b_fec[i]);
         fec_calculated_bytes_log = $sformatf("%s FEC6_BYTE[%0d]=0x%02h",
                                              fec_calculated_bytes_log, i,
                                              pkt.ep_to_rc_flit_calculated_6b_fec_on_250b[i]);
         if(pkt.ep_to_rc_flit_received_6b_fec[i] !== pkt.ep_to_rc_flit_calculated_6b_fec_on_250b[i])
            fec_6b_match = 1'b0;
      end

      if(fec_6b_match)
         `uvm_info("PCIe_SCOREBOARD",
                   $sformatf("EP_TO_RC_FLIT_FEC_CHECK : PASS : RECEIVED_6B_FEC{%s } CALCULATED_6B_FEC_ON_250B{%s } | FEC_MATCH=1",
                             fec_received_bytes_log, fec_calculated_bytes_log), UVM_LOW)
      else
         `uvm_error("PCIe_SCOREBOARD",
                    $sformatf("EP_TO_RC_FLIT_FEC_CHECK : FAIL : RECEIVED_6B_FEC{%s } CALCULATED_6B_FEC_ON_250B{%s } | FEC_MATCH=0",
                              fec_received_bytes_log, fec_calculated_bytes_log))

      // ---- CRC : compare all 8 bytes (received vs calculated on 242B payload) ----
      crc_8b_match            = 1'b1;
      crc_received_bytes_log  = "";
      crc_calculated_bytes_log = "";
      for(int b = 0; b < `PCIe_FLIT_CRC_BYTES; b++) begin
         crc_received_bytes_log   = $sformatf("%s CRC8_BYTE[%0d]=0x%02h",
                                              crc_received_bytes_log, b,
                                              pkt.ep_to_rc_flit_received_8b_crc[((7-b)*8) +: 8]);
         crc_calculated_bytes_log = $sformatf("%s CRC8_BYTE[%0d]=0x%02h",
                                              crc_calculated_bytes_log, b,
                                              pkt.ep_to_rc_flit_calculated_8b_crc_on_242b[((7-b)*8) +: 8]);
         if(pkt.ep_to_rc_flit_received_8b_crc[((7-b)*8) +: 8] !==
            pkt.ep_to_rc_flit_calculated_8b_crc_on_242b[((7-b)*8) +: 8])
            crc_8b_match = 1'b0;
      end

      if(crc_8b_match)
         `uvm_info("PCIe_SCOREBOARD",
                   $sformatf("EP_TO_RC_FLIT_CRC_CHECK : PASS : RECEIVED_8B_CRC{%s } CALCULATED_8B_CRC_ON_242B{%s } | CRC_MATCH=1",
                             crc_received_bytes_log, crc_calculated_bytes_log), UVM_LOW)
      else
         `uvm_error("PCIe_SCOREBOARD",
                    $sformatf("EP_TO_RC_FLIT_CRC_CHECK : FAIL : RECEIVED_8B_CRC{%s } CALCULATED_8B_CRC_ON_242B{%s } | CRC_MATCH=0",
                              crc_received_bytes_log, crc_calculated_bytes_log))
   endfunction : report_ep_to_rc_flit_fec_crc
   `endif

endclass


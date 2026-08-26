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

  bit [31:0] rc_phy_tx_q[$];
  bit [31:0] ep_phy_rx_q[$];
  bit [31:0] rc_phy_rx_q[$];
  bit [31:0] ep_phy_tx_q[$];

  bit [31:0] rc_controller_tx_q[$];
  bit [31:0] ep_controller_rx_q[$];
  bit [31:0] rc_controller_rx_q[$];
  bit [31:0] ep_controller_tx_q[$];
  

  function new(string name="PCIe_scoreboard",uvm_component parent);
    super.new(name,parent);
  endfunction

  function void build_phase(uvm_phase phase);
   `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_BUILD_PHASE",UVM_LOW)
    super.build_phase(phase);
       rc_phy_tx_imp = new("rc_phy_tx_imp",this);
       ep_phy_rx_imp = new("ep_phy_rx_imp",this);
       rc_phy_rx_imp = new("rc_phy_rx_imp",this);
       ep_phy_tx_imp = new("ep_phy_tx_imp",this);
       
       rc_con_tx_imp = new("rc_con_tx_imp",this);
       ep_con_rx_imp = new("ep_con_rx_imp",this);
       rc_con_rx_imp = new("rc_con_rx_imp",this);
       ep_con_tx_imp = new("ep_con_tx_imp",this);
    
   `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_BUILD_PHASE",UVM_LOW)
  endfunction

  function void write_rc_phy_tx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_RC_PHY_TX_DATA",UVM_LOW)
    foreach(pkt.data_q_rc_mon_tx[i])begin
       rc_phy_tx_q.push_back(pkt.data_q_rc_mon_tx[i]);
       `uvm_info("PCIe_SB",$sformatf("RC_PHY_TX_PARALLEL_DATA[%0d] = %08h, RC_PHY_SB_QUEUE_SIZE = %0d",i, pkt.data_q_rc_mon_tx[i], rc_phy_tx_q.size()),UVM_LOW)
     end
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_RC_PHY_TX_DATA",UVM_LOW)
     compare_phy_rc_to_ep_data();
  endfunction

  function void write_ep_phy_rx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_EP_PHY_RX_DATA",UVM_LOW)
     foreach(pkt.data_q_ep_mon_rx[i])begin
       ep_phy_rx_q.push_back(pkt.data_q_ep_mon_rx[i]);
       `uvm_info("PCIe_SB",$sformatf("EP_PHY_RX_PARALLEL_DATA[%0d] = %08h, EP_PHY_SB_QUEUE_SIZE = %0d",i, pkt.data_q_ep_mon_rx[i], ep_phy_rx_q.size()),UVM_LOW)
      end
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_EP_PHY_RX_DATA",UVM_LOW)
     compare_phy_rc_to_ep_data();
  endfunction
  

  function void compare_phy_rc_to_ep_data();
      bit [31:0] rc_phy_tx_data;
      bit [31:0] ep_phy_rx_data;

     `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_COMPARE_PHY_DATA",UVM_LOW)
      while ((rc_phy_tx_q.size() > 0) && (ep_phy_rx_q.size() > 0)) begin
           rc_phy_tx_data = rc_phy_tx_q.pop_front();
           ep_phy_rx_data = ep_phy_rx_q.pop_front();
           `uvm_info("PCIe_SCOREBOARD", $sformatf("COMPARING_RC_PHY_TX = %08h  EP_PHY_RX = %08h",  rc_phy_tx_data, ep_phy_rx_data), UVM_LOW)
            if (rc_phy_tx_data == ep_phy_rx_data) begin
            `uvm_info("PCIe_SCOREBOARD",$sformatf("************PASS******************: PASS_RC_PHY_TX_TO_EP_PHY_RX_EXPECTED_DATA = %08h  EP_PHY_RX_ACTUAL_DATA = %08h", rc_phy_tx_data, ep_phy_rx_data), UVM_LOW)
            end
            else begin
            `uvm_error("PCIe_SCOREBOARD",$sformatf("***********FAIL*****************:FAIL_RC_PHY_TX_TO_EP_PHY_RX_EXPECTED_DATA = %08h  EP_PHY_RX_ACTUAL_DATA = %08h", rc_phy_tx_data,ep_phy_rx_data))
            end
        end
        `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_COMPARE_PHY_DATA",UVM_LOW)
  endfunction

  function void write_rc_phy_rx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_RC_PHY_RX_DATA",UVM_LOW)
    foreach(pkt.data_q_rc_mon_rx[i])begin
       rc_phy_rx_q.push_back(pkt.data_q_rc_mon_rx[i]);
       `uvm_info("PCIe_SB",$sformatf("RC_PHY_RX_PARALLEL_DATA[%0d] = %08h, RC_PHY_SB_QUEUE_SIZE = %0d",i, pkt.data_q_rc_mon_rx[i], rc_phy_rx_q.size()),UVM_LOW)
     end
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_RC_PHY_RX_DATA",UVM_LOW)
     compare_phy_ep_to_rc_data();
  endfunction

  function void write_ep_phy_tx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_EP_PHY_TX_DATA",UVM_LOW)
     foreach(pkt.data_q_ep_mon_tx[i])begin
       ep_phy_tx_q.push_back(pkt.data_q_ep_mon_tx[i]);
       `uvm_info("PCIe_SB",$sformatf("EP_PHY_TX_PARALLEL_DATA[%0d] = %08h, EP_PHY_SB_QUEUE_SIZE = %0d",i, pkt.data_q_ep_mon_tx[i], ep_phy_tx_q.size()),UVM_LOW)
      end
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_EP_PHY_TX_DATA",UVM_LOW)
     compare_phy_ep_to_rc_data();
  endfunction

  function void compare_phy_ep_to_rc_data();
      bit [31:0] rc_phy_rx_data;
      bit [31:0] ep_phy_tx_data;

     `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_COMPARE_PHY_DATA",UVM_LOW)
      while ((rc_phy_rx_q.size() > 0) && (ep_phy_tx_q.size() > 0)) begin
           rc_phy_rx_data = rc_phy_rx_q.pop_front();
           ep_phy_tx_data = ep_phy_tx_q.pop_front();
           `uvm_info("PCIe_SCOREBOARD", $sformatf("COMPARING_RC_PHY_TX = %08h  EP_PHY_RX = %08h",  rc_phy_rx_data, ep_phy_tx_data), UVM_LOW)
            if (rc_phy_rx_data == ep_phy_tx_data) begin
            `uvm_info("PCIe_SCOREBOARD",$sformatf("************PASS******************: PASS_EP_PHY_TX_TO_RC_PHY_RX_EXPECTED_DATA = %08h  EP_PHY_RX_ACTUAL_DATA = %08h", rc_phy_rx_data, ep_phy_tx_data), UVM_LOW)
            end
            else begin
            `uvm_error("PCIe_SCOREBOARD",$sformatf("***********FAIL*****************:FAIL_EP_PHY_TX_TO_RC_PHY_RX_EXPECTED_DATA = %08h  EP_PHY_RX_ACTUAL_DATA = %08h", rc_phy_rx_data,ep_phy_tx_data))
            end
        end
        `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_COMPARE_PHY_DATA",UVM_LOW)
  endfunction

  function void write_rc_controller_tx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_RC_CONTROLLER_TX_DATA",UVM_LOW)
    foreach(pkt.data_q_rc_mon_con_tx[i])begin
       rc_controller_tx_q.push_back(pkt.data_q_rc_mon_con_tx[i]);
       `uvm_info("PCIe_SB",$sformatf("RC_CONTROLLER_TX_PARALLEL_DATA[%0d] = %08h, RC_CON_SB_QUEUE_SIZE = %0d",i, pkt.data_q_rc_mon_con_tx[i], rc_controller_tx_q.size()),UVM_LOW)
     end
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_RC_CONTROLLER_TX_DATA",UVM_LOW)
     compare_controller_rc_to_ep_data();
  endfunction

  function void write_ep_controller_rx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_EP_CONTROLLER_RX_DATA",UVM_LOW)
     foreach(pkt.data_q_ep_mon_con_rx[i])begin
       ep_controller_rx_q.push_back(pkt.data_q_ep_mon_con_rx[i]);
       `uvm_info("PCIe_SB",$sformatf("EP_CONTROLLER_RX_PARALLEL_DATA[%0d] = %08h, EP_CON_SB_QUEUE_SIZE = %0d",i, pkt.data_q_ep_mon_con_rx[i], ep_controller_rx_q.size()),UVM_LOW)
      end
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_EP_CONTROLLER_RX_DATA",UVM_LOW)
     compare_controller_rc_to_ep_data();
  endfunction

  function void compare_controller_rc_to_ep_data();
      bit [31:0] rc_controller_tx_data;
      bit [31:0] ep_controller_rx_data;

     `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_COMPARE_CONTROLLER_DATA",UVM_LOW)
      while ((rc_controller_tx_q.size() > 0) && (ep_controller_rx_q.size() > 0)) begin
           rc_controller_tx_data = rc_controller_tx_q.pop_front();
           ep_controller_rx_data = ep_controller_rx_q.pop_front();
           `uvm_info("PCIe_SCOREBOARD", $sformatf("COMPARING_RC_CONTROLLER_TX = %08h  EP_CONTROLLER_RX = %08h",  rc_controller_tx_data, ep_controller_rx_data), UVM_LOW)
            if (rc_controller_tx_data == ep_controller_rx_data) begin
            `uvm_info("PCIe_SCOREBOARD",$sformatf("************PASS******************: PASS_RC_CONTROLLER_TX_TO_EP_CONTROLLER_RX_EXPECTED_DATA = %08h  EP_CONTROLLER_RX ACTUAL_DATA = %08h", rc_controller_tx_data, ep_controller_rx_data), UVM_LOW)
            end
            else begin
            `uvm_error("PCIe_SCOREBOARD",$sformatf("***********FAIL*****************:FAIL_RC_CONTROLLER_TX_TO_EP_CONTROLLER_RX_EXPECTED_DATA = %08h  EP_CONTROLLER_RX ACTUAL_DATA = %08h", rc_controller_tx_data,ep_controller_rx_data))
            end
        end
        `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_COMPARE_CONTROLLER_DATA",UVM_LOW)
  endfunction

  function void write_rc_controller_rx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_RC_CONTROLLER_RX_DATA",UVM_LOW)
    foreach(pkt.data_q_rc_mon_con_rx[i])begin
       rc_controller_rx_q.push_back(pkt.data_q_rc_mon_con_rx[i]);
       `uvm_info("PCIe_SB",$sformatf("RC_CONTROLLER_RX_PARALLEL_DATA[%0d] = %08h, RC_CON_SB_QUEUE_SIZE = %0d",i, pkt.data_q_rc_mon_con_rx[i], rc_controller_rx_q.size()),UVM_LOW)
     end
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_RC_CONTROLLER_RX_DATA",UVM_LOW)
     compare_controller_ep_to_rc_data();
  endfunction

  function void write_ep_controller_tx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_EP_CONTROLLER_TX_DATA",UVM_LOW)
     foreach(pkt.data_q_ep_mon_con_tx[i])begin
       ep_controller_tx_q.push_back(pkt.data_q_ep_mon_con_tx[i]);
       `uvm_info("PCIe_SB",$sformatf("EP_CONTROLLER_TX_PARALLEL_DATA[%0d] = %08h, EP_CON_SB_QUEUE_SIZE = %0d",i, pkt.data_q_ep_mon_con_tx[i], ep_controller_tx_q.size()),UVM_LOW)
      end
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_EP_CONTROLLER_RX_DATA",UVM_LOW)
     compare_controller_ep_to_rc_data();
  endfunction

  function void compare_controller_ep_to_rc_data();
      bit [31:0] rc_controller_rx_data;
      bit [31:0] ep_controller_tx_data;

     `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_COMPARE_CONTROLLER_DATA",UVM_LOW)
      while ((rc_controller_rx_q.size() > 0) && (ep_controller_tx_q.size() > 0)) begin
           rc_controller_rx_data = rc_controller_rx_q.pop_front();
           ep_controller_tx_data = ep_controller_tx_q.pop_front();
           `uvm_info("PCIe_SCOREBOARD", $sformatf("COMPARING_RC_CONTROLLER_TX = %08h  EP_CONTROLLER_RX = %08h",  rc_controller_rx_data, ep_controller_tx_data), UVM_LOW)
            if (rc_controller_rx_data == ep_controller_tx_data) begin
            `uvm_info("PCIe_SCOREBOARD",$sformatf("************PASS******************: PASS_EP_CONTROLLER_TX_TO_RC_CONTROLLER_RX_EXPECTED_DATA = %08h  EP_CONTROLLER_RX ACTUAL_DATA = %08h", rc_controller_rx_data, ep_controller_tx_data), UVM_LOW)
            end
            else begin
            `uvm_error("PCIe_SCOREBOARD",$sformatf("***********FAIL*****************:FAIL_EP_CONTROLLER_TX_TO_RC_CONTROLLER_RX_EXPECTED_DATA = %08h  EP_CONTROLLER_RX ACTUAL_DATA = %08h", rc_controller_rx_data,ep_controller_tx_data))
            end
        end
        `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_COMPARE_CONTROLLER_DATA",UVM_LOW)
  endfunction

endclass




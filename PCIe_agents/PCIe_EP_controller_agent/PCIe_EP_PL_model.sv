//=========================================================================================
// File         : PCIe_EP_PL_model.sv
// Project      : PCIe_Gen6
// Description  : PCIe_environment\PCIe_EP_PL_model.sv
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

import typedef_enums :: *;
class PCIe_EP_PL_model extends uvm_component;

  `uvm_component_utils(PCIe_EP_PL_model)
   // Input from RC DL model.
   uvm_analysis_imp #(PCIe_sequence_item, PCIe_EP_PL_model) pl_imp;
   
   PCIe_env_config   pcie_ecfg;
   PCIe_sequence_item     pcie_seq_item;
   virtual PCIe_EP_interface     ep_pipe_intf_tx,ep_pipe_intf_rx;

   //EP
   main_state_e    ep_main_state;
   detect_state_e  ep_detect_state;
   polling_state_e ep_poll_state;
   config_state_e  ep_cfg_state;
   bit ep_present;   
   bit[0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] dl_flit_out;
   bit[`PCIe_BYTE_W-1:0]        pl_qu[$];
   bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0]      lfsr;
   bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0]      polynomial;
   bit [1:0]       previous_symbol;
   bit             tx_parity_q[$];
   bit	           pl_sent;
   bit [7:0]       ep_ts1_os [`PCIe_TS_OS_SIZE];
   bit [7:0]       ep_ts2_os [`PCIe_TS_OS_SIZE];
   bit [7:0]       ep_idle_os [`PCIe_TS_OS_SIZE];
   int             ts1_tx_count;
   int             ts2_tx_count;
   event           rc_to_ep_ts1_8;
   event           rc_to_ep_ts1_10;
   event           rc_to_ep_ts2_16;
   bit             link_up;
   event           ep_l0_to_dl_event;
   bit[`PCIe_MON_DATA_W-1:0]       scr_data;
   bit [7:0]        ep_link_num = 8'hFF;   // PAD until learned from RC in LinkWidth.Start
   bit [7:0]        ep_lane_num = 8'hFF;   // PAD until assigned in LinkWidth.Accept
   localparam bit [7:0] EP_ASSIGNED_LANE_NUM = 8'h00;
   localparam bit [7:0] PAD_BYTE              = 8'hFF;
bit            tx_process_executed;
    bit            electrical_idle_test_done;
    bit            no_receiver_test;
    int            detect_fail_count;

   function new(string name="PCIe_EP_PL_model",uvm_component parent);
     super.new(name,parent);
      pl_imp=new("pl_imp",this);
   endfunction

   function void build_phase(uvm_phase phase);
    `uvm_info("PCIe_PL_MODEL","ENTERED_INTO_PL_MODEL_BUILD_PHASE",UVM_LOW)
      super.build_phase(phase);
       pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
      if(!uvm_config_db#(PCIe_env_config)::get(this,"","PCIe_env_config",pcie_ecfg))
      `uvm_fatal("PL_MODEL","Cannot_get_PCIe_env_config");
      if (!uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_pipe_intf_tx))
            `uvm_fatal("NO_VIF", "EC_PIPE_INTERFACE_not_found")
      if (!uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_pipe_intf_rx))
            `uvm_fatal("NO_VIF", "EC_PIPE_INTERFACE_not_found")
      if (!uvm_config_db#(event)::get(this, "", "PCIE_ep_l0_to_dl_event",ep_l0_to_dl_event))
             `uvm_fatal("EVENT", "event not found")
       //if(pcie_ecfg.mode == FLIT)
      `uvm_info("PCIe_PL_MODEL","EXIT_FROM_PL_MODEL_BUILD_PHASE",UVM_LOW)
    endfunction
   
   task reset_phase(uvm_phase phase);
     phase.raise_objection(this);
   
     `uvm_info("PCIE_EP_PL_MODEL",
               "Entering RESET phase", UVM_LOW)
        polynomial = `PCIe_PL_SCRAMBLER_POLYNOMIAL;
       // polynomial = 23'b01000010000000100100101;
        reset_scrambler();
        electrical_idle_test_done = 1'b0;
        no_receiver_test   = 1'b0;
        detect_fail_count  = 0;
        previous_symbol = `PCIe_INIT_PREVIOUS_SYMBOL;

        `uvm_info("PCIE_EP_PL_MODEL","Reset deasserted", UVM_LOW)
        phase.drop_objection(this);
   
   endtask
task ep_ltssm( PCIe_sequence_item pcie_seq_item);
       if(pcie_seq_item.pkt_mode == FLIT)
       `uvm_info("RC_PL_MODEL","Configured_in_FLIT_MODE",UVM_LOW)
       else
       `uvm_info("RC_PL_MODEL","Configured_in_NON_FLIT_MODE", UVM_LOW)
        no_receiver_test = pcie_seq_item.no_receiver_test;
        forever begin
           case (ep_main_state)
              DETECT: begin
                 `uvm_info("EP_LTSSM","EP_LTSSM_STATE_DETECT",UVM_LOW)
                 case (ep_detect_state)
                    DETECT_QUIET: begin
                       `uvm_info("EP_LTSSM","EP_SUBSTATE_DETECT_QUIET",UVM_LOW)
 	         	       ep_state_detect_quiet(pcie_seq_item);
                       //ep_detect_state = DETECT_ACTIVE;
                    end
                    DETECT_ACTIVE: begin
                       `uvm_info("EP_LTSSM","EP_SUBSTATE_DETECT_ACTIVE",UVM_LOW)
 		               ep_state_detect_active();
                       //ep_main_state = POLLING;
                       //ep_poll_state = POLLING_ACTIVE;
                    end
                 endcase
                 if (electrical_idle_test_done) break;
                 if (no_receiver_test && detect_fail_count >= 1) begin
                    `uvm_info("EP_LTSSM","EP_NO_RECEIVER_TEST_FAILED_RECEIVER_DETECTION",UVM_LOW)
                    break;
                 end
              end
             POLLING: begin
                `uvm_info("EP_LTSSM","EP_LTSSM_STATE_POLLING",UVM_LOW)
                case (ep_poll_state)
                   POLLING_ACTIVE: begin
                      `uvm_info("EP_LTSSM","EP_SUBSTATE_POLLING_Active",UVM_LOW)
		               ep_state_polling_active();
                      //ep_poll_state = POLLING_CONFIGURATION;
                   end
                   POLLING_CONFIGURATION: begin
                      `uvm_info("EP_LTSSM","EP_SUBSTATE_POLLING_Configuration",UVM_LOW)
		              ep_state_polling_configuration();
                      // ep_main_state = CONFIGURATION;
                      // ep_cfg_state  = LINKWIDTH_START;
                   end
                   POLLING_COMPLIANCE: begin
                      `uvm_info("EP_LTSSM","EP_SUBSTATE_POLLING_Compliance",UVM_LOW)
                   end
                endcase
             end
CONFIGURATION: begin
                 `uvm_info("EP_LTSSM","EP_LTSSM_STATE_CONFIGURATION",UVM_LOW)
                 case (ep_cfg_state)
                    LINKWIDTH_START: begin
                       `uvm_info("EP_LTSSM","EP_SUBSTATE_CONFIGURATION_LinkWidth_Start",UVM_LOW)
 		                ep_state_config_linkwidth_start();
                    end
                    LINKWIDTH_ACCEPT: begin
                       `uvm_info("EP_LTSSM","EP_SUBSTATE_CONFIGURATION_LinkWidth_Accept",UVM_LOW)
 		               ep_state_config_linkwidth_accept();
                    end
                    LANENUM_WAIT: begin
                       `uvm_info("EP_LTSSM","EP_SUBSTATE_CONFIGURATION_LaneNum_Wait",UVM_LOW)
 		                ep_state_config_lanenum_wait();
                    end
                    LANENUM_ACCEPT: begin
                       `uvm_info("EP_LTSSM","EP_SUBSTATE_CONFIGURATION_LaneNum_Accept",UVM_LOW)
 		               ep_state_config_lanenum_accept();
                    end
                    CONFIG_COMPLETE: begin
                       `uvm_info("EP_LTSSM","EP_SUBSTATE_CONFIGURATION_Complete",UVM_LOW)
 		              ep_state_config_complete();
                    end
                    CONFIG_IDLE: begin
                       `uvm_info("EP_LTSSM","EP_SUBSTATE_CONFIGURATION_Idle",UVM_LOW)
 		               ep_state_config_idle();
                    end
                 endcase
              end
             L0: begin
                `uvm_info("EP_LTSSM","EP_LTSSM_STATE_L0",UVM_LOW)
		         ep_state_l0(pcie_seq_item);
		         break;
             end
             default: begin
                `uvm_error("EP_LTSSM","INVALID_EP_LTSSM_STATE")
             end
          endcase
       end
    endtask

   //=======================DETECT.QUIET==========================================
    task ep_state_detect_quiet(PCIe_sequence_item item);
       `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
       `uvm_info("EP_LTSSM","LTSSM_STATE_DETECT",UVM_LOW)
       `uvm_info("EP_LTSSM","SUB_STATE_DETECT_Quiet",UVM_LOW)
       `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
       //================Drive Default PIPE Signals=======================
       ep_pipe_intf_tx.tx_elec_idle   <= item.tx_elec_idle;
       ep_pipe_intf_tx.tx_valid      <= item.tx_valid;
       ep_pipe_intf_tx.rate          <= item.rate;
       `uvm_info("EP_LTSSM","Driving_PIPE_Signals",UVM_LOW)
       `uvm_info("EP_LTSSM",$sformatf("TxElecIdle  = %0b",item.tx_elec_idle),UVM_LOW)
       `uvm_info("EP_LTSSM",$sformatf("TxDataValid = %0b",item.tx_valid),UVM_LOW)
       `uvm_info("EP_LTSSM",$sformatf("Rate        = %0b",item.rate),UVM_LOW)
       if (item.electrical_idle_test) begin
          electrical_idle_test_done = 1'b1;
          `uvm_info("EP_LTSSM","EP_Electrical_Idle_Test_EP_entering_DETECT_QUIET",UVM_LOW)
          `uvm_info("EP_LTSSM",$sformatf("EP Verify: tx_elec_idle=%0b tx_valid=%0b rate=%02b",item.tx_elec_idle, item.tx_valid, item.rate),UVM_LOW)
          `uvm_info("EP_LTSSM","EP Electrical Idle Test: Intentionally remaining in DETECT.QUIET",UVM_LOW)
           return;
       end
       //===============Inform PHY to Start Receiver Detection==============
       `uvm_info("EP_LTSSM","Request_sent_to_PHY_to_Start_Receiver_Detection",UVM_LOW)
       `uvm_info("EP_LTSSM","Transition_DETECT_Quiet_DETECT_Active",UVM_LOW)
        ep_detect_state = DETECT_ACTIVE;
       `uvm_info("EP_LTSSM",$sformatf("STATE=%s",ep_detect_state),UVM_LOW)
    endtask

    //=======================DETECT.ACTIVE=============================================
    task ep_state_detect_active();
        `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
        `uvm_info("EP_LTSSM","LTSSM_STATE_DETECT",UVM_LOW)
        `uvm_info("EP_LTSSM","SUB_STATE_DETECT_Active",UVM_LOW)
        `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
        //===================Wait for PHY to Start Receiver Detection===================
        // `uvm_info("EP_LTSSM","Waiting for PHY to Assert TxDetectRx...",UVM_LOW)
        // wait(ep_pipe_intf_tx.tx_detect_rx == 1'b1);
        //Request PHY to perform receiver detection
         ep_present =1;
        `uvm_info("EP_LTSSM",$sformatf("EP_PRESENT=%0d",ep_present),UVM_LOW)
         ep_pipe_intf_tx.tx_detect_rx <= 1'b1;
        `uvm_info("EP_LTSSM","RC_MAC_Asserted_TxDetectRx",UVM_LOW)
        //==================Wait for Receiver Detection Completion======================
        `uvm_info("EP_LTSSM","Waiting_for_PHY_Receiver_Detection_Result...",UVM_LOW)
        wait(ep_pipe_intf_tx.phy_status == 1'b1);
        `uvm_info("EP_LTSSM",$sformatf("phy_status = %0b  rx_status = %03b",ep_pipe_intf_tx.phy_status,ep_pipe_intf_tx.rx_status),UVM_LOW)
        //=================Receiver Found===================================
        if(ep_pipe_intf_tx.rx_status == 3'b011)
         begin
           `uvm_info("EP_LTSSM","Receiver_Detection_SUCCESS",UVM_LOW)
            ep_pipe_intf_tx.tx_elec_idle <= 1'b0;
            ep_main_state    = POLLING;
            ep_poll_state    = POLLING_ACTIVE;
           `uvm_info("EP_LTSSM","LTSSM_Transition_DETECT_Active_POLLING_Active",UVM_LOW)
         end
        //=================Receiver Not Found===============================
        else
         begin
           `uvm_info("EP_LTSSM","Receiver_Detection_FAILED",UVM_LOW)
            ep_detect_state = DETECT_QUIET;
            if (no_receiver_test) begin
               detect_fail_count = detect_fail_count + 1;
               `uvm_info("EP_LTSSM",$sformatf("EP_No_Receiver_Test_detect_fail_count=%0d",detect_fail_count),UVM_LOW)
            end
           `uvm_info("EP_LTSSM","LTSSM_Transition_DETECT_Active_TO_DETECT_Quiet",UVM_LOW)
         end
    endtask

    task ep_state_polling_active();
        bit tx_ts1_10_done;
        bit rx_ts1_8_done;
        `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
        `uvm_info("EP_LTSSM","LTSSM_STATE_POLLING",UVM_LOW)
        `uvm_info("EP_LTSSM","SUB_STATE_POLLING_ACTIVE",UVM_LOW)
        `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
         ep_pipe_intf_tx.tx_elec_idle <= 1'b0;
         build_ep_ts1();
         //print_ts1();
         fork : EP_POLLING_THREADS
           // THREAD 1 : RC -> EP 8 TS1 CHECKER
           begin
              `uvm_info("EP_LTSSM","STARTING_RC_8_TS1_CHECKER",UVM_LOW)
               ep_check_rc_ts1(`PCIe_TS1_RX_COUNT,rx_ts1_8_done);
              `uvm_info("EP_LTSSM",$sformatf("RC_8_TS1_CHECKER_DONE_RX_DONE=%0b",rx_ts1_8_done),UVM_LOW)
           end
           // THREAD 2 : EP -> RC 10 TS1
           begin
              @(posedge ep_pipe_intf_rx.pclk);
              `uvm_info("EP_LTSSM","STARTING_EP_10_TS1_TRANSMISSION",UVM_LOW)
               send_ordered_set(ep_ts1_os,`PCIe_TS1_TX_COUNT,"TS1");
               tx_ts1_10_done = 1'b1;
              `uvm_info("EP_LTSSM","EP_10_TS1_TRANSMISSION_COMPLETED",UVM_LOW)
           end
        join
        `uvm_info("EP_LTSSM",$sformatf("FINAL_CHECK_TX_10_DONE=%0b_RX_8_DONE=%0b",tx_ts1_10_done,rx_ts1_8_done),UVM_LOW)
        if ((tx_ts1_10_done == 1'b1) && (rx_ts1_8_done  == 1'b1)) begin
           `uvm_info("EP_LTSSM","10_TS1_TX_AND_8_TS1_RX_CONDITIONS_SATISFIED",UVM_LOW)
           `uvm_info("EP_LTSSM","POLLING_ACTIVE_TO_POLLING_CONFIGURATION",UVM_LOW)
           ep_poll_state = POLLING_CONFIGURATION;
        end
    endtask

    task ep_state_polling_configuration();
        bit tx_ts2_16_done;
        bit rx_ts2_8_done;
        `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
        `uvm_info("EP_LTSSM","LTSSM_STATE_POLLING",UVM_LOW)
        `uvm_info("EP_LTSSM","SUB_STATE_POLLING_Configuration",UVM_LOW)
        `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
         // Build TS2
        build_ep_ts2();
         //print_ts2();
        // EP TX 16 TS2
        // AND
        // RC -> EP RX 8 TS2
        fork
           // THREAD 1 : EP TRANSMITS 16 TS2
           begin
              `uvm_info("EP_LTSSM","STARTING_RC_16_TS2_TRANSMISSION",UVM_LOW)
               send_ordered_set(ep_ts2_os,`PCIe_TS2_TX_COUNT,"TS2");
               ts2_tx_count += `PCIe_TS2_TX_COUNT;
               tx_ts2_16_done = 1'b1;
              `uvm_info("EP_LTSSM",$sformatf("RC_TS2_TX_COMPLETED_COUNT=%0d",ts2_tx_count),UVM_LOW)
           end
           // THREAD 2 : WAIT FOR EP 8 TS2
           begin
              `uvm_info("EP_LTSSM","WAITING_FOR_8_CONSECUTIVE_TS2_FROM_EP",UVM_LOW)
              ep_check_rc_ts2(`PCIe_TS2_RX_COUNT,rx_ts2_8_done);
              `uvm_info("EP_LTSSM","EP_8_TS2_RECEIVED",UVM_LOW)
           end
        join
        if ((tx_ts2_16_done == 1'b1) && (rx_ts2_8_done  == 1'b1)) begin
           `uvm_info("EP_LTSSM","16_TS2_TX_AND_8_TS2_RX_CONDITIONS_SATISFIED",UVM_LOW)
           // Check Training Control
           if (ep_ts2_os[6] == 8'h01) begin
              `uvm_info("EP_LTSSM","TRAINING_CONTROL=1",UVM_LOW)
              `uvm_info("EP_LTSSM","LTSSM_TRANSITION_POLLING.Configuration_TO_POLLING_Compliance",UVM_LOW)
               ep_poll_state = POLLING_COMPLIANCE;
           end
           else begin
              `uvm_info("EP_LTSSM","TRAINING_CONTROL=0",UVM_LOW)
              `uvm_info("EP_LTSSM","LTSSM_TRANSITION_POLLING.Configuration_TO_CONFIGURATION_LinkWidth_Start",UVM_LOW)
               ep_main_state = CONFIGURATION;
               ep_cfg_state  = LINKWIDTH_START;
           end
           // Reset counters
           ts2_tx_count       = 0;
           rx_ts2_8_done  = 1'b0;
           `uvm_info("EP_LTSSM","TS2_COUNTER_AND_RX_FLAG_RESET",UVM_LOW)
        end
    endtask

    task ep_state_config_linkwidth_start();
       bit tx_ts1_8_done;
       bit rx_ts1_8_done;
       tx_ts1_8_done = 1'b0;
       rx_ts1_8_done = 1'b0;
       `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
       `uvm_info("EP_LTSSM","LTSSM_STATE_CONFIGURATION",UVM_LOW)
       `uvm_info("EP_LTSSM","SUB_STATE_CONFIGURATION_LinkWidth_Start",UVM_LOW)
       `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
       // Reset precoder state for reliable TS1 K-symbol detection
       previous_symbol = 2'b11;
       // EP transmits PAD/PAD while still discovering RC's selected Link number.
       ep_link_num = PAD_BYTE;
       ep_lane_num = PAD_BYTE;
       build_ep_ts1();
       //print_ts1();
       fork : EP_CFG_LWSTART_THREADS
          begin
             `uvm_info("EP_LTSSM","STARTING_RC_8_TS1_CHECKER",UVM_LOW)
             ep_check_rc_ts1(8, rx_ts1_8_done);
             `uvm_info("EP_LTSSM",$sformatf("RC_8_TS1_CHECKER_DONE_RX_DONE=%0b",rx_ts1_8_done),UVM_LOW)
          end
          begin
             `uvm_info("EP_LTSSM","STARTING_EP_8_TS1_TRANSMISSION",UVM_LOW)
             send_ordered_set(ep_ts1_os,8,"TS1");
             ts1_tx_count += 8;
             tx_ts1_8_done = 1'b1;
             `uvm_info("EP_LTSSM",$sformatf("LINKWIDTH_START_8_TS1_TX_COMPLETED_COUNT=%0d",ts1_tx_count),UVM_LOW)
          end
       join
       `uvm_info("EP_LTSSM",$sformatf("FINAL_CHECK_TX_8_DONE=%0b_RX_8_DONE=%0b",tx_ts1_8_done,rx_ts1_8_done),UVM_LOW)
       if ((tx_ts1_8_done == 1'b1) && (rx_ts1_8_done == 1'b1)) begin
          `uvm_info("EP_LTSSM","8_TS1_TX_AND_8_TS1_RX_CONDITIONS_SATISFIED",UVM_LOW)
          `uvm_info("EP_LTSSM",$sformatf("ADOPTED_LINK_NUM=0x%02h",ep_link_num),UVM_LOW)
          `uvm_info("EP_LTSSM","LTSSM_TRANSITION_CONFIGURATION_LinkWidth_Start_CONFIGURATION_LinkWidth_Accept",UVM_LOW)
          ts1_tx_count = 0;
          ep_cfg_state = LINKWIDTH_ACCEPT;
       end
    endtask

    task ep_state_config_linkwidth_accept();
       bit tx_ts1_2_done;
       bit rx_ts1_2_done;
       `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
       `uvm_info("EP_LTSSM","LTSSM_STATE_CONFIGURATION",UVM_LOW)
       `uvm_info("EP_LTSSM","SUB_STATE_CONFIGURATION_LinkWidth_Accept",UVM_LOW)
       `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
       // Reset precoder state for reliable TS1 K-symbol detection
       previous_symbol = 2'b11;
       `uvm_info("EP_LTSSM",$sformatf("ASSIGNED_LANE_NUM=0x%02h_ON_LINK=0x%02h",ep_lane_num,ep_link_num),UVM_LOW)
       build_ep_ts1();
       //print_ts1();
       fork : EP_CFG_LWACCEPT_THREADS
          begin
             `uvm_info("EP_LTSSM","STARTING_RC_2_TS1_CHECKER",UVM_LOW)
              ep_check_rc_ts1(2,rx_ts1_2_done);
          end
          begin
             `uvm_info("EP_LTSSM","STARTING_EP_2_TS1_TRANSMISSION",UVM_LOW)
             send_ordered_set(ep_ts1_os,2,"TS1");
             ts1_tx_count += 2;
             tx_ts1_2_done = 1'b1;
             `uvm_info("EP_LTSSM",$sformatf("LINKWIDTH_ACCEPT_2_TS1_TX_COMPLETED_COUNT=%0d",ts1_tx_count),UVM_LOW)
          end
       join
       if ((tx_ts1_2_done == 1'b1) && (rx_ts1_2_done == 1'b1)) begin
          `uvm_info("EP_LTSSM","2_TS1_TX_AND_2_TS1_RX_CONDITIONS_SATISFIED",UVM_LOW)
          `uvm_info("EP_LTSSM","LTSSM_TRANSITION_CONFIGURATION_LinkWidth_Accept_CONFIGURATION_LaneNum_Wait",UVM_LOW)
          ts1_tx_count = 0;
          ep_cfg_state = LANENUM_WAIT;
       end
    endtask

    task ep_state_config_lanenum_wait();
       bit tx_ts1_2_done;
       bit rx_ts1_2_done;
       tx_ts1_2_done = 1'b0;
       rx_ts1_2_done = 1'b0;
       `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
       `uvm_info("EP_LTSSM","LTSSM_STATE_CONFIGURATION",UVM_LOW)
       `uvm_info("EP_LTSSM","SUB_STATE_CONFIGURATION_LaneNum_Wait",UVM_LOW)
       `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
       // Reset precoder state for reliable TS1 K-symbol detection
       previous_symbol = 2'b11;
       // Link/Lane unchanged from LinkWidth.Accept.
       build_ep_ts1();
       //print_ts1();
       fork : EP_CFG_LNWAIT_THREADS
          begin
             `uvm_info("EP_LTSSM","STARTING_RC_2_TS1_CHECKER",UVM_LOW)
              ep_check_rc_ts1(2, rx_ts1_2_done);
          end
          begin
             `uvm_info("EP_LTSSM","STARTING_EP_2_TS1_TRANSMISSION",UVM_LOW)
             send_ordered_set(ep_ts1_os,2,"TS1");
             ts1_tx_count += 2;
             tx_ts1_2_done = 1'b1;
             `uvm_info("EP_LTSSM",$sformatf("LANENUM_WAIT_2_TS1_TX_COMPLETED_COUNT=%0d",ts1_tx_count),UVM_LOW)
          end
       join
       if ((tx_ts1_2_done == 1'b1) && (rx_ts1_2_done == 1'b1)) begin
          `uvm_info("EP_LTSSM","2_TS1_TX_AND_2_TS1_RX_CONDITIONS_SATISFIED",UVM_LOW)
          `uvm_info("EP_LTSSM","LTSSM_TRANSITION_CONFIGURATION_LaneNum_Wait_CONFIGURATION_LaneNum_Accept",UVM_LOW)
          ts1_tx_count = 0;
          ep_cfg_state = LANENUM_ACCEPT;
       end
    endtask

    task ep_state_config_lanenum_accept();
       bit tx_ts1_2_done;
       bit rx_ts1_2_done;
       tx_ts1_2_done = 1'b0;
       rx_ts1_2_done = 1'b0;
       `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
       `uvm_info("EP_LTSSM","LTSSM_STATE_CONFIGURATION",UVM_LOW)
       `uvm_info("EP_LTSSM","SUB_STATE_CONFIGURATION_LaneNum_Accept",UVM_LOW)
       `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
       // Reset precoder state for reliable TS1 K-symbol detection
       previous_symbol = 2'b11;
       build_ep_ts1();
       //print_ts1();
       fork : EP_CFG_LNACCEPT_THREADS
          begin
             `uvm_info("EP_LTSSM","STARTING_RC_2_TS1_CHECKER",UVM_LOW)
             ep_check_rc_ts1(2, rx_ts1_2_done);
          end
          begin
             `uvm_info("EP_LTSSM","STARTING_EP_2_TS1_TRANSMISSION",UVM_LOW)
             send_ordered_set(ep_ts1_os,2,"TS1");
             ts1_tx_count += 2;
             tx_ts1_2_done = 1'b1;
             `uvm_info("EP_LTSSM",$sformatf("LANENUM_ACCEPT_2_TS1_TX_COMPLETED_COUNT=%0d",ts1_tx_count),UVM_LOW)
          end
       join
       if ((tx_ts1_2_done == 1'b1) && (rx_ts1_2_done == 1'b1)) begin
          `uvm_info("EP_LTSSM","2_TS1_TX_AND_2_TS1_RX_CONDITIONS_SATISFIED",UVM_LOW)
          `uvm_info("EP_LTSSM","LTSSM_TRANSITION_CONFIGURATION_LaneNum_Accept_CONFIGURATION_Complete",UVM_LOW)
          ts1_tx_count = 0;
          ep_cfg_state = CONFIG_COMPLETE;
       end
    endtask

task ep_state_config_complete();
       bit tx_ts2_16_done;
       bit rx_ts2_8_done;
       tx_ts2_16_done = 1'b0;
       rx_ts2_8_done  = 1'b0;
       `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
       `uvm_info("EP_LTSSM","LTSSM_STATE_CONFIGURATION",UVM_LOW)
       `uvm_info("EP_LTSSM","SUB_STATE_CONFIGURATION_Complete",UVM_LOW)
       `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
       // Reset precoder state for reliable TS2 K-symbol detection
       previous_symbol = 2'b11;
       build_ep_ts2();
         //print_ts2();
         fork : EP_CFG_COMPLETE_THREADS
           begin
              `uvm_info("EP_LTSSM","WAITING_FOR_8_CONSECUTIVE_TS2_FROM_RC",UVM_LOW)
               ep_check_rc_ts2(`PCIe_TS2_RX_COUNT, rx_ts2_8_done);
           end
           begin
              `uvm_info("EP_LTSSM","STARTING_EP_16_TS2_TRANSMISSION",UVM_LOW)
              send_ordered_set(ep_ts2_os,`PCIe_TS2_TX_COUNT,"TS2");
              ts2_tx_count += `PCIe_TS2_TX_COUNT;
              tx_ts2_16_done = 1'b1;
              `uvm_info("EP_LTSSM",$sformatf("CONFIG_COMPLETE_16_TS2_TX_COMPLETED_COUNT=%0d",ts2_tx_count),UVM_LOW)
           end
        join
        if ((tx_ts2_16_done == 1'b1) && (rx_ts2_8_done == 1'b1)) begin
           `uvm_info("EP_LTSSM","16_TS2_TX_AND_8_TS2_RX_CONDITIONS_SATISFIED",UVM_LOW)
           `uvm_info("EP_LTSSM","LTSSM_TRANSITION_CONFIGURATION_Complete_CONFIGURATION_Idle",UVM_LOW)
           ts2_tx_count = 0;
           ep_cfg_state = CONFIG_IDLE;
        end
    endtask

    task ep_state_config_idle();
       bit tx_idle_2_done;
       bit rx_idle_2_done;
       tx_idle_2_done = 1'b0;
       rx_idle_2_done = 1'b0;
       `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
       `uvm_info("EP_LTSSM","LTSSM_STATE_CONFIGURATION",UVM_LOW)
       `uvm_info("EP_LTSSM","SUB_STATE_CONFIGURATION_Idle",UVM_LOW)
       `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
       // Reset precoder state for reliable IDLE K-symbol detection
       previous_symbol = 2'b11;
       build_ep_idle();
       print_idle();
       fork : EP_CFG_IDLE_THREADS
          begin
             `uvm_info("EP_LTSSM","WAITING_FOR_2_CONSECUTIVE_IDLE_FROM_RC",UVM_LOW)
              ep_check_rc_idle(2, rx_idle_2_done);
             `uvm_info("EP_LTSSM",$sformatf("RC_2_IDLE_CHECKER_DONE_RX_DONE=%0b",rx_idle_2_done),UVM_LOW)
          end
          begin
             `uvm_info("EP_LTSSM","STARTING_EP_2_IDLE_FLIT_TRANSMISSION",UVM_LOW)
             send_ordered_set(ep_idle_os,2,"IDLE_FLIT");
             tx_idle_2_done = 1'b1;
             `uvm_info("EP_LTSSM","CONFIG_IDLE_2_IDLE_FLIT_TX_COMPLETED",UVM_LOW)
          end
       join
       `uvm_info("EP_LTSSM",$sformatf("FINAL_CHECK_TX_2_IDLE_DONE=%0b_RX_2_IDLE_DONE=%0b",tx_idle_2_done,rx_idle_2_done),UVM_LOW)
       if ((tx_idle_2_done == 1'b1) && (rx_idle_2_done == 1'b1)) begin
          `uvm_info("EP_LTSSM","2_IDLE_TX_AND_2_IDLE_RX_CONDITIONS_SATISFIED",UVM_LOW)
          `uvm_info("EP_LTSSM","LTSSM_TRANSITION_CONFIGURATION_Idle_L0",UVM_LOW)
          ep_main_state = L0;
       end
    endtask

    task ep_state_l0(PCIe_sequence_item item);

        `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
        `uvm_info("EP_LTSSM","LTSSM_STATE=L0",UVM_LOW)
        `uvm_info("EP_LTSSM","ENTERING_L0_STATE",UVM_LOW)
        `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
        // LINK UP
        link_up = 1'b1;
        `uvm_info("EP_LTSSM","LINK_UP=1",UVM_LOW)
        // INFORM DL THAT LINK IS UP
        -> ep_l0_to_dl_event;
        `uvm_info("EP_LTSSM","EP_L0_TO_DL_EVENT_TRIGGERED",UVM_LOW)
        // SELECT FLIT / NON-FLIT MODE
        //case (pcie_ecfg.mode)
        case (item.pkt_mode)
           NON_FLIT: begin
              `uvm_info("EP_LTSSM","L0_MODE=NON_FLIT_MODE",UVM_LOW)
               //ep_l0_non_flit_mode();
           end
           FLIT: begin
              `uvm_info("EP_LTSSM","L0_MODE=FLIT_MODE",UVM_LOW)
           end
           default: begin
              `uvm_error("EP_LTSSM","INVALID_PCIE_MODE")
           end
        endcase
    endtask

    task ep_check_rc_ts1(input int count,output bit rx_done);
       bit [1:0] rx_symbol;
       int ts1_count;
       rx_done   = 1'b0;
       ts1_count = 0;
       `uvm_info("EP_LTSSM",$sformatf("WAITING_FOR_%0d_TS1_FROM_RC",count),UVM_LOW)
       forever begin
          @(negedge ep_pipe_intf_rx.pclk);
          if (ep_pipe_intf_rx.rx_valid) begin
             rx_symbol = ep_pipe_intf_rx.rx_data[1:0];
             if (rx_symbol == 2'b11) begin
                ts1_count++;
                `uvm_info("EP_LTSSM",$sformatf("TS1_FIRST_SYMBOL_DETECTED = %02b COUNT = %0d",rx_symbol, ts1_count),UVM_LOW)
             end
             if (ts1_count >= count) begin
                `uvm_info("EP_LTSSM",$sformatf("%0d_TS1_RECEIVED_FROM_RC",count),UVM_LOW)
                rx_done = 1'b1;
                break;
             end
          end
       end
    endtask
    
    task ep_check_rc_ts2(input int count,output bit rx_done);
       bit [1:0] rx_symbol;
       int ts2_count;
       rx_done   = 1'b0;
       ts2_count = 0;
       `uvm_info("EP_LTSSM",$sformatf("WAITING_FOR_%0d_TS2_FROM_RC",count),UVM_LOW)
       forever begin
          @(negedge ep_pipe_intf_rx.pclk);
          if (ep_pipe_intf_rx.rx_valid) begin
             rx_symbol = ep_pipe_intf_rx.rx_data[1:0];
             if (rx_symbol == 2'b10) begin
                ts2_count++;
                `uvm_info("EP_LTSSM",$sformatf("TS2_FIRST_SYMBOL_DETECTED = %02b COUNT = %0d",rx_symbol,ts2_count),UVM_LOW)
             end
             if (ts2_count >= count) begin
                `uvm_info("EP_LTSSM",$sformatf("%0d_TS2_RECEIVED_FROM_RC",count),UVM_LOW)
                rx_done = 1'b1;
                break;
             end
          end
       end
    endtask

    task ep_check_rc_idle(input int count, output bit rx_done);
       bit [1:0] rx_symbol;
       int idle_count;
       rx_done    = 1'b0;
       idle_count = 0;
       `uvm_info("EP_LTSSM",$sformatf("WAITING_FOR_%0d_IDLE_FROM_RC", count),UVM_LOW)
       forever begin
          @(negedge ep_pipe_intf_rx.pclk);
          if (ep_pipe_intf_rx.rx_valid) begin
             rx_symbol = ep_pipe_intf_rx.rx_data[1:0];
             if (rx_symbol == 2'b00) begin
                idle_count++;
                `uvm_info("EP_LTSSM",$sformatf("IDLE_FIRST_SYMBOL_DETECTED = %02b COUNT = %0d",rx_symbol,idle_count),UVM_LOW)
             end
             if (idle_count >= count) begin
                `uvm_info("EP_LTSSM",$sformatf("%0d_IDLE_RECEIVED_FROM_RC", count),UVM_LOW)
                rx_done = 1'b1;
                break;
             end
          end
       end
    endtask

    task send_ordered_set(input bit [7:0] ordered_set [`PCIe_TS_OS_SIZE],input int count,input string os_name = "ORDERED_SET");
       bit [`PCIe_MON_DATA_W-1:0] raw_data;
       bit [`PCIe_MON_DATA_W-1:0] gray_data;
       bit [`PCIe_MON_DATA_W-1:0] pre_data;
       bit [7:0] processed_symbol;
       bit parity;
       int os_count;
       int dword;
       int byte_idx;
       int symbol_idx;
   
       for (os_count = 0; os_count < count; os_count++) begin
           `uvm_info("EP_LTSSM",$sformatf("EP_TX %s OS_COUNT=%0d/%0d START",os_name, os_count+1, count),UVM_LOW)
           for (dword = 0;dword < (`PCIe_TS_OS_SIZE / 4);dword++) begin
            raw_data = '0;
            for (byte_idx = 0; byte_idx < 4; byte_idx++) begin
                symbol_idx = (dword * 4) + byte_idx;
                if ((symbol_idx == 0) || (symbol_idx == 8) || (symbol_idx == 15)) begin
                    processed_symbol = ordered_set[symbol_idx];
                    `uvm_info("EP_LTSSM",$sformatf("EP_TX_ODERED_SET %s OS=%0d SYMBOL=%0d BYPASS_ORIGINAL=%02h AFTER=%02h",
                              os_name, os_count,symbol_idx,ordered_set[symbol_idx],processed_symbol), UVM_LOW)
                end
                else begin
                    scramble(ordered_set[symbol_idx], processed_symbol);
                    `uvm_info("EP_LTSSM",$sformatf("EP_TX_ODERED_SET %s OS=%0d SYMBOL=%0d SCRAMBLED_ORIGINAL=%02h AFTER=%02h",
                              os_name,os_count,symbol_idx, ordered_set[symbol_idx], processed_symbol), UVM_LOW)
                end
                raw_data[(byte_idx * 8) +: 8] = processed_symbol;
            end
            `uvm_info("EP_LTSSM",$sformatf("EP_TX %s OS=%0d DWORD=%0d DATA_AFTER_SCRAMBLING=%08h", os_name, os_count, dword,raw_data),UVM_LOW)
            tx_gray_encode(raw_data, gray_data);
            `uvm_info("EP_LTSSM",$sformatf("EP_TX_DATA_AFTER_GRAYCODE =%08h",gray_data),UVM_LOW)
            tx_parity_generate(gray_data, parity);
            tx_parity_q.push_back(parity);
            tx_precoder(gray_data, pre_data);
            `uvm_info("EP_LTSSM",$sformatf("EP_TX_DATA_AFTER_PRECODE =%08h",pre_data),UVM_LOW)
            ep_pipe_intf_tx.tx_data  <= pre_data;
            ep_pipe_intf_tx.tx_valid <= 1'b1;
            `uvm_info("EP_LTSSM",$sformatf("EP_TX %s OS=%0d DWORD=%0d PIPE_DATA=%08h TX_VALID=1",os_name,os_count,dword,pre_data),UVM_LOW)
            @(posedge ep_pipe_intf_tx.pclk);
         end
      end
       ep_pipe_intf_tx.tx_data  <= 32'h00000000;
       ep_pipe_intf_tx.tx_valid <= 1'b0;
       `uvm_info("EP_LTSSM",$sformatf("EP_TX %s TRANSMISSION_COMPLETED ORDERED_SETS=%0d",os_name,count),UVM_LOW)
    endtask
   
    /*task print_ts1();
        `uvm_info("EP_TS1","========== EP TS1 ORDERED SET ==========",UVM_LOW)
        for (int i = 0; i < 16; i++) begin
            `uvm_info("EP_TS1",$sformatf("TS1[%0d] = 0x%02h",i, ep_ts1_os[i]),UVM_LOW)
        end
        `uvm_info("EP_TS1","========================================",UVM_LOW)
    endtask*/

    task build_ep_ts1();
        ep_ts1_os[0]  = 8'hBC;
        ep_ts1_os[1]  = ep_link_num;
        ep_ts1_os[2]  = ep_lane_num;
        ep_ts1_os[3]  = 8'h10;
        ep_ts1_os[4]  = 8'h00;
        ep_ts1_os[5]  = 8'h00;
        ep_ts1_os[6]  = 8'h00;
        ep_ts1_os[7]  = 8'h4A;
        ep_ts1_os[8]  = 8'h4A;
        ep_ts1_os[9]  = 8'h4A;
        ep_ts1_os[10] = 8'h4A;
        ep_ts1_os[11] = 8'h4A;
        ep_ts1_os[12] = 8'h4A;
        ep_ts1_os[13] = 8'h4A;
        ep_ts1_os[14] = 8'h4A;
        ep_ts1_os[15] = 8'h4A;
        
        for (int i = 0; i < 16; i++) begin
            `uvm_info("EP_TS1",$sformatf("TS1[%0d] = 0x%02h",i, ep_ts1_os[i]),UVM_LOW)
        end
    endtask

    task build_ep_ts2();
         ep_ts2_os[0]  = 8'h39;
         ep_ts2_os[1]  = ep_link_num;
         ep_ts2_os[2]  = ep_lane_num;
         ep_ts2_os[3]  = 8'h00;
         ep_ts2_os[4]  = 8'h00;
         ep_ts2_os[5]  = 8'h00;
         ep_ts2_os[6]  = 8'h00;
         ep_ts2_os[7]  = 8'h00;
         ep_ts2_os[8]  = 8'h39;
         ep_ts2_os[9]  = ep_link_num;
         ep_ts2_os[10] = ep_lane_num;
         ep_ts2_os[11] = 8'h00;
         ep_ts2_os[12] = 8'h00;
         ep_ts2_os[13] = 8'h00;
         ep_ts2_os[14] = 8'h00;
         ep_ts2_os[15] = 8'h00;
        
         for (int i = 0; i < 16; i++) begin
            `uvm_info("EP_LTSSM",$sformatf("TS2[%0d] = %02h",i,ep_ts2_os[i]),UVM_LOW)
         end
    endtask

    /*task print_ts2();
        `uvm_info("EP_LTSSM","========== EP TS2 ORDERED SET ==========",UVM_LOW)
        for (int i = 0; i < 16; i++) begin
            `uvm_info("EP_LTSSM",$sformatf("TS2[%0d] = %02h",i,ep_ts2_os[i]),UVM_LOW)
        end
        `uvm_info("EP_LTSSM","========================================",UVM_LOW)
    endtask*/

    task build_ep_idle();
        for (int i = 0; i < 16; i++) begin
            ep_idle_os[i] = 8'h00;
        end
    endtask

    task print_idle();
        `uvm_info("EP_LTSSM","========== EP IDLE FLIT ==========",UVM_LOW)
        for (int i = 0; i < 16; i++) begin
            `uvm_info("EP_LTSSM",$sformatf("IDLE[%0d] = 0x%02h",i,ep_idle_os[i]),UVM_LOW)
        end
        `uvm_info("EP_LTSSM","========================================",UVM_LOW)
    endtask

    task reset_scrambler();
       lfsr = `PCIe_PL_SCRAMBLER_SEED;
    endtask

    task scramble(input  bit [7:0] data_in,output bit [7:0] data_out);
      bit scramble_bit;
      data_out = data_in;
      `uvm_info("PCIe_PL_MODEL","ENTERED_INTO_SCRAMBLER_TASK",  UVM_LOW)
      for(int i = 0; i < 8; i++)
      begin
         scramble_bit = lfsr[22];
         data_out[i] = data_in[i] ^ scramble_bit;
         if(scramble_bit)
         begin
            lfsr = (lfsr << 1) ^ polynomial;
         end
         else
         begin
            lfsr = (lfsr << 1);
         end
      end
      `uvm_info("PCIe_PL_MODEL","EXIT_FROM_SCRAMBLER_TASK", UVM_LOW)
    endtask

   // One PIPE word = 32 bits
    task scramble_32(input  bit [31:0] data_in, output bit [31:0] data_out );
      bit [7:0] temp;
      `uvm_info("PCIe_PL_MODEL",$sformatf( "SCRAMBLE_32_INPUT = %08h",  data_in),UVM_LOW)
      scramble( data_in[7:0],temp);
      data_out[7:0] = temp;
      scramble(data_in[15:8],temp);
      data_out[15:8] = temp;
      scramble(data_in[23:16],temp);
      data_out[23:16] = temp;
      scramble(data_in[31:24],temp);
      data_out[31:24] = temp;
      `uvm_info("PCIe_PL_MODEL",$sformatf("SCRAMBLE_32_OUTPUT = %08h",data_out),UVM_LOW)
    endtask

    task tx_gray_encode(input  bit [31:0] data_in,output bit [31:0] gray_out);
      bit [1:0] symbol;
      gray_out = 32'b0;
      `uvm_info("PCIe_PL_MODEL",$sformatf("ENTERED_INTO_GRAY_ENCODE_TASK"),UVM_LOW)
      `uvm_info("PCIe_PL_MODEL",$sformatf("GRAY_ENCODE_INPUT = %0b",data_in),UVM_LOW)
      for(int i = 0; i < 32; i = i + 2)
      begin
         symbol = data_in[i +: 2];
         case(symbol)
            2'b00:
               gray_out[i +: 2] = 2'b00;
            2'b01:
               gray_out[i +: 2] = 2'b01;
            2'b10:
               gray_out[i +: 2] = 2'b11;
            2'b11:
               gray_out[i +: 2] = 2'b10;
            default:
               gray_out[i +: 2] = 2'b00;
         endcase
      end
      `uvm_info("PCIe_PL_MODEL",$sformatf("GRAY_ENCODE_OUTPUT = %0b",gray_out),UVM_LOW)
      `uvm_info("PCIe_PL_MODEL",$sformatf("EXIT_FROM_GRAY_ENCODE_TASK"),UVM_LOW)
    endtask

    task tx_parity_generate(input  bit [31:0] data_in, output bit parity_bit);
     `uvm_info("PCIe_PL_MODEL",$sformatf("ENTERED_INTO_PARITY_GENERATE_TASK"),UVM_LOW)
      parity_bit = ^data_in;
     `uvm_info("PCIe_PL_MODEL",$sformatf("PARITY_INPUT = %08h PARITY = %0b", data_in, parity_bit),UVM_LOW)
     `uvm_info("PCIe_PL_MODEL",$sformatf("PARITY_GENERATE_OUTPUT =%b",parity_bit),UVM_LOW)
    endtask
  
    task tx_precoder(input bit [31:0] gray_data, output bit [31:0] precoded_data);
      bit [1:0]  current_symbol;
      precoded_data = 32'b0;
      `uvm_info("PCIe_PL_MODEL",$sformatf("ENTERED_INTO_PRE_ENCODE_TASK"),UVM_LOW)
      `uvm_info("PCIe_PL_MODEL",$sformatf("PRECODE_INPUT = %0b",gray_data),UVM_LOW)
      for(int i=0;i<32;i=i+2) begin
        current_symbol = gray_data[i+:2];
        precoded_data[i+:2] = current_symbol ^ previous_symbol;
        previous_symbol = precoded_data[i+:2];
      end
      `uvm_info("PCIe_PL_MODEL",$sformatf("PRECODE_OUTPUT = %0b",precoded_data),UVM_LOW)
      `uvm_info("PCIe_PL_MODEL",$sformatf("EXIT_FROM_PRE_ENCODE_TASK"),UVM_LOW)
    endtask

    task tx_process(input  bit [31:0] data_in,output bit [31:0] data_out,PCIe_sequence_item item);
      bit [31:0] scramble_data;
      bit [31:0] gray_data;
      bit [31:0] pre_data;
      bit        parity;
      `uvm_info("PCIe_PL_MODEL","ENTERED_INTO_TX_PROCESS_TASK", UVM_LOW)
      `uvm_info("PCIe_PL_MODEL",$sformatf("The data_in_from PL inside tx_prpcess is %d",data_in), UVM_LOW)
       tx_process_executed = 1'b1;
      case(item.pkt_mode)
         // NON-FLIT MODE
         NON_FLIT:
         begin
            `uvm_info("PCIe_PL_MODEL","TX_PROCESS:NON_FLIT_MODE", UVM_LOW)
            scramble_32(data_in, scramble_data);
            tx_gray_encode(scramble_data,gray_data);
            tx_parity_generate(gray_data,parity);
            tx_parity_q.push_back(parity);//storing the parity bits in queue in order to check the tx and rx parity is matching
            `uvm_info("PCIe_PL_MODEL",$sformatf("TX_PARITY = %0b  PARITY_QUEUE_SIZE = %0d",parity,tx_parity_q.size()),UVM_LOW);
            tx_precoder(gray_data,pre_data);
            data_out = pre_data;
         end
         // FLIT MODE
         FLIT:
         begin
            `uvm_info("PCIe_PL_MODEL","TX_PROCESS:FLIT_MODE", UVM_LOW)
            scramble_32(data_in,scramble_data);
            tx_gray_encode(scramble_data,gray_data);
            tx_parity_generate(gray_data,parity);
            tx_parity_q.push_back(parity);//storing the parity bits in queue in order to check the tx and rx parity is matching
            `uvm_info("PCIe_PL_MODEL",$sformatf("TX_PARITY = %0b  PARITY_QUEUE_SIZE = %0d",parity,tx_parity_q.size()),UVM_LOW);
            tx_precoder(gray_data,pre_data);
            data_out = pre_data;
         end
         default:
         begin
            `uvm_error("PCIe_PL_MODEL", "INVALID_PCIe_MODE")
            data_out = data_in;
         end
      endcase
      `uvm_info("PCIe_PL_MODEL", $sformatf("TX_PROCESS_INPUT=%08h OUTPUT=%08h", data_in, data_out),UVM_LOW)
      `uvm_info("PCIe_PL_MODEL","EXIT_FROM_TX_PROCESS_TASK",  UVM_LOW)
    endtask

   // PL model receives the 242-byte DL result.
    function void write(PCIe_sequence_item item);
     bit [31:0] temp;
     `uvm_info("EP_PL_MODEL",$sformatf("PL -> INTERFACE received 242-byte packet, payload=%p",item.dlp_flit_out),UVM_MEDIUM)
      dl_flit_out=item.dlp_flit_out;
      pl_qu.delete();
      for (int i = 0; i < 242; i += 4) begin
        temp = '0;
        for (int j = 0; j < 4; j++) begin
          if ((i+j) < 242)
             temp[j*8 +: 8] = dl_flit_out[i+j];
          end
          pl_qu.push_back(temp);
      end
      `uvm_info("EP_PL_MODEL",$sformatf("PL -> INTERFACE received 242-byte packet, payload=%p",pl_qu),UVM_MEDIUM)
       pl_sent=1;
    endfunction

   
endclass




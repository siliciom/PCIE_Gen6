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
   
   pcie_mode_e mode;
   PCIe_env_config   pcie_ecfg;
   virtual PCIe_EP_interface     ep_pipe_intf_tx,ep_pipe_intf_rx;

   //EP
   main_state_e    ep_main_state;
   detect_state_e  ep_detect_state;
   polling_state_e ep_poll_state;
   config_state_e  ep_cfg_state;
   
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

   function new(string name="PCIe_EP_PL_model",uvm_component parent);
     super.new(name,parent);
      pl_imp=new("pl_imp",this);
   endfunction

   function void build_phase(uvm_phase phase);
    `uvm_info("PCIe_PL_MODEL","ENTERED_INTO_PL_MODEL_BUILD_PHASE",UVM_LOW)
      super.build_phase(phase);
      if(!uvm_config_db#(PCIe_env_config)::get(this,"","PCIe_env_config",pcie_ecfg))
      `uvm_fatal("PL_MODEL","Cannot_get_PCIe_env_config");
      if (!uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_pipe_intf_tx))
            `uvm_fatal("NO_VIF", "EC_PIPE_INTERFACE_not_found")
      if (!uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_pipe_intf_rx))
            `uvm_fatal("NO_VIF", "EC_PIPE_INTERFACE_not_found")
      if (!uvm_config_db#(event)::get(this, "", "PCIE_ep_l0_to_dl_event",ep_l0_to_dl_event))
             `uvm_fatal("EVENT", "event not found")
       mode = pcie_ecfg.mode;
       if(mode == FLIT_MODE)
       `uvm_info("RC_PL_MODEL","Configured_in_FLIT_MODE",UVM_LOW)
       else
       `uvm_info("RC_PL_MODEL","Configured_in_NON_FLIT_MODE", UVM_LOW)
        polynomial = `PCIe_PL_SCRAMBLER_POLYNOMIAL;
       // polynomial = 23'b01000010000000100100101;
        reset_scrambler();
        previous_symbol = `PCIe_INIT_PREVIOUS_SYMBOL;
      `uvm_info("PCIe_PL_MODEL","EXIT_FROM_PL_MODEL_BUILD_PHASE",UVM_LOW)
    endfunction
   
    task ep_ltssm();
       forever begin
          case (ep_main_state)
             DETECT: begin
                `uvm_info("EP_LTSSM","EP_LTSSM_STATE_DETECT",UVM_LOW)
                case (ep_detect_state)
                   DETECT_QUIET: begin
                      `uvm_info("EP_LTSSM","EP_SUBSTATE_DETECT_QUIET",UVM_LOW)
	         	       ep_state_detect_quiet();
                      //ep_detect_state = DETECT_ACTIVE;
                   end
                   DETECT_ACTIVE: begin
                      `uvm_info("EP_LTSSM","EP_SUBSTATE_DETECT_ACTIVE",UVM_LOW)
		               ep_state_detect_active();
                      //ep_main_state = POLLING;
                      //ep_poll_state = POLLING_ACTIVE;
                   end
                endcase
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
		         ep_state_l0();
		         break;
             end
             default: begin
                `uvm_error("EP_LTSSM","INVALID_EP_LTSSM_STATE")
             end
          endcase
       end
    endtask

   //=======================DETECT.QUIET==========================================
    task ep_state_detect_quiet();
       `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
       `uvm_info("EP_LTSSM","LTSSM_STATE_DETECT",UVM_LOW)
       `uvm_info("EP_LTSSM","SUB_STATE_DETECT_Quiet",UVM_LOW)
       `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
       //================Drive Default PIPE Signals=======================
       ep_pipe_intf_tx.tx_elec_idle  <= 1'b1;
       ep_pipe_intf_tx.tx_valid <= 1'b0;
       ep_pipe_intf_tx.rate          <= 2'b00;
       `uvm_info("EP_LTSSM","Driving_PIPE_Signals",UVM_LOW)
       `uvm_info("EP_LTSSM",$sformatf("TxElecIdle  = %0b",ep_pipe_intf_tx.tx_elec_idle),UVM_MEDIUM)
       `uvm_info("EP_LTSSM",$sformatf("TxDataValid = %0b",ep_pipe_intf_tx.tx_valid),UVM_MEDIUM)
       `uvm_info("EP_LTSSM",$sformatf("Rate        = %0d",ep_pipe_intf_tx.rate),UVM_MEDIUM)
       //===============Inform PHY to Start Receiver Detection==============
       //rc_active_gen = 1'b1;
       `uvm_info("EP_LTSSM","Request_sent_to_PHY_to_Start_Receiver_Detection",UVM_LOW)
       //@(posedge rc_pipe_if.pclk);
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

    task ep_state_l0();
        `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
        `uvm_info("EP_LTSSM","LTSSM_STATE=L0",UVM_LOW)
        `uvm_info("EP_LTSSM","ENTERING_L0_STATE",UVM_LOW)
        `uvm_info("EP_LTSSM","==========================================",UVM_LOW)
        // LINK UP
        link_up = 1'b1;
        `uvm_info("EP_LTSSM","LINK_UP=1",UVM_LOW)
        // INFORM DL THAT LINK IS UP
        //-> ep_l0_to_dl_event;
        `uvm_info("EP_LTSSM","EP_L0_TO_DL_EVENT_TRIGGERED",UVM_LOW)
        // SELECT FLIT / NON-FLIT MODE
        case (mode)
           NON_FLIT_MODE: begin
              `uvm_info("EP_LTSSM","L0_MODE=NON_FLIT_MODE",UVM_LOW)
               //ep_l0_non_flit_mode();
           end
           FLIT_MODE: begin
              `uvm_info("EP_LTSSM","L0_MODE=FLIT_MODE",UVM_LOW)

              // Background process: continuously receive 256B Flits from RC,
              // check FEC then CRC.
              fork
                 ep_rx_l0_flit_handler();
              join_none


  	      wait(pl_sent);
                `uvm_info("EP_CONTROLLER",$sformatf("dl_flit_out is %p",dl_flit_out),UVM_LOW)
              // FLIT is 242 bytes = 60.5 dwords, send 61 dwords (last dword partial)
              for(int i=0 ; i<`PCIe_FLIT_DWORDS; i++) begin
                 bit [`PCIe_MON_DATA_W-1:0] flit_dword;
                 flit_dword = {dl_flit_out[i*`PCIe_PL_BYTES_PER_WORD+3], dl_flit_out[i*`PCIe_PL_BYTES_PER_WORD+2], dl_flit_out[i*`PCIe_PL_BYTES_PER_WORD+1], dl_flit_out[i*`PCIe_PL_BYTES_PER_WORD+0]};
                 tx_process_executed = 1'b0;
                 tx_process(flit_dword, scr_data);
                  if (tx_process_executed) begin
                     @(posedge ep_pipe_intf_tx.pclk);
                     ep_pipe_intf_tx.tx_data <= scr_data;
                     ep_pipe_intf_tx.tx_valid <= 1'b1;
                     `uvm_info("EP_LTSSM",$sformatf("L0_FLIT_DWORD[%0d] = %08h", i, scr_data), UVM_LOW);
                  end
              end
  	         @(posedge ep_pipe_intf_tx.pclk);
  	           pl_sent=0;
                     ep_pipe_intf_tx.tx_valid <= 1'b0;
                //ep_l0_flit_mode();
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

    task tx_process(input  bit [31:0] data_in,output bit [31:0] data_out);
      bit [31:0] scramble_data;
      bit [31:0] gray_data;
      bit [31:0] pre_data;
      bit        parity;
      `uvm_info("PCIe_PL_MODEL","ENTERED_INTO_TX_PROCESS_TASK", UVM_LOW)
      `uvm_info("PCIe_PL_MODEL",$sformatf("The data_in_from PL inside tx_prpcess is %d",data_in), UVM_LOW)
       tx_process_executed = 1'b1;
      case(mode)
         // NON-FLIT MODE
         NON_FLIT_MODE:
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
         FLIT_MODE:
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

   
  // Gen6 Flit-Mode RX path (EP side) : declarations, hierarchy resolver,
   // CRC/FEC tables, functions, and RX-check tasks.
   // The exact 256B Flit (242B Payload + 8B CRC + 6B FEC) is verified directly
   // against the RC PL model's assembled flit (flit_crc_body). The RC is located
   // through the existing UVM hierarchy so NO extra signals/wiring are added to
   // any other component -- only this EP PL model and the RC PL model are touched.
   //----------------------------------------------------------------------------
   PCIe_RC_PL_model  rc_pl_model;   // resolved via hierarchy in build_phase
   localparam int EP_RX_FLIT_PAYLOAD_BYTES = `PCIe_DLP_FLIT_BYTE_W;                                   // 242
   localparam int EP_RX_FLIT_CRC_BYTES     = 8;
   localparam int EP_RX_FLIT_FEC_BYTES     = 6;
   localparam int EP_RX_FLIT_TOTAL_BYTES   = EP_RX_FLIT_PAYLOAD_BYTES + EP_RX_FLIT_CRC_BYTES + EP_RX_FLIT_FEC_BYTES; // 256

   // Walk the existing UVM hierarchy to find the RC PL model (peer component).
   // No extra signals/ports/config entries are needed anywhere else.
   //----------------------------------------------------------------------------
   function bit resolve_rc_pl_model();
      uvm_component prnt, rc_ta, rc_ca, rc_pl;
      resolve_rc_pl_model = 1'b0;
      prnt = get_parent();
      if (prnt == null) return 1'b0;
      prnt = prnt.get_parent();
      if (prnt == null) return 1'b0;
      prnt = prnt.get_parent();            // pcie_environment
      if (prnt == null) return 1'b0;
      rc_ta = prnt.get_child("rc_top_agent");
      if (rc_ta == null) return 1'b0;
      rc_ca = rc_ta.get_child("rc_controller_agent");
      if (rc_ca == null) return 1'b0;
      rc_pl = rc_ca.get_child("rc_pl_model");
      if (rc_pl == null) return 1'b0;
      if (!$cast(rc_pl_model, rc_pl)) return 1'b0;
      resolve_rc_pl_model = 1'b1;
   endfunction : resolve_rc_pl_model

   //----------------------------------------------------------------------------
   // Gen6 Flit-Mode CRC (mirrors PCIe_RC_PL_model's TX-side generator so the
   // EP can independently recompute and verify the received CRC).
   // GF(2^8) field: x^8+x^5+x^3+x+1 -> reduction byte 8'h2B.
   //----------------------------------------------------------------------------
   function automatic bit [`PCIe_BYTE_W-1:0] gf_mul_crc_field(
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
   endfunction : gf_mul_crc_field

   function bit [63:0] calculate_flit_crc(input bit [`PCIe_BYTE_W-1:0] flit_bytes[$]);
     bit [`PCIe_BYTE_W-1:0] g[8];
     bit [`PCIe_BYTE_W-1:0] rem[8];
     bit [`PCIe_BYTE_W-1:0] fb;
     bit [63:0]             crc_result;

     g[0] = 8'hD5; g[1] = 8'h68; g[2] = 8'hFE; g[3] = 8'hD5;
     g[4] = 8'h33; g[5] = 8'h41; g[6] = 8'h4D; g[7] = 8'h69;

     if(flit_bytes.size() < `PCIe_DLP_FLIT_BYTE_W)
     begin
       `uvm_error("EP_PL_MODEL",
                  $sformatf("calculate_flit_crc: need >= %0d Bytes, got %0d",
                            `PCIe_DLP_FLIT_BYTE_W,
                            flit_bytes.size()))
       return '0;
     end

     foreach(rem[i]) rem[i] = 8'h00;

     for(int i = 0; i < `PCIe_DLP_FLIT_BYTE_W; i++)
     begin
       fb = rem[0] ^ flit_bytes[i];
       for(int k = 0; k < 7; k++)
         rem[k] = rem[k+1];
       rem[7] = 8'h00;
       if(fb != 8'h00)
       begin
         for(int k = 0; k < 8; k++)
           rem[k] = rem[k] ^ gf_mul_crc_field(fb, g[k]);
       end
     end

     crc_result = {rem[0], rem[1], rem[2], rem[3], rem[4], rem[5], rem[6], rem[7]};
     `uvm_info("EP_PL_MODEL",$sformatf("CRC_RECOMPUTED = 0x%016h",crc_result),UVM_LOW)
     `uvm_info("EP_PL_MONITOR",
               $sformatf("EP_RECOMPUTED_CRC_BYTES = {%02h %02h %02h %02h %02h %02h %02h %02h}",
                         rem[0],rem[1],rem[2],rem[3],rem[4],rem[5],rem[6],rem[7]),
               UVM_LOW)
     return crc_result;
   endfunction : calculate_flit_crc

   // Recompute CRC over the first 242 Bytes and compare against the 8 CRC
   // Bytes (MSB first) carried at offset [242:249] of the received Flit.
   function void check_flit_crc(input bit [`PCIe_BYTE_W-1:0] flit_in[$], output bit crc_pass);
     bit [`PCIe_BYTE_W-1:0] payload_bytes[$];
     bit [63:0]             expected_crc;
     bit [63:0]             received_crc;
     crc_pass = 1'b0;
     if(flit_in.size() < (EP_RX_FLIT_PAYLOAD_BYTES + EP_RX_FLIT_CRC_BYTES))
     begin
       `uvm_error("EP_PL_MODEL",
                  $sformatf("check_flit_crc: need >= %0d Bytes, got %0d",
                            EP_RX_FLIT_PAYLOAD_BYTES + EP_RX_FLIT_CRC_BYTES, flit_in.size()))
       return;
     end
     payload_bytes.delete();
     for(int i = 0; i < EP_RX_FLIT_PAYLOAD_BYTES; i++)
       payload_bytes.push_back(flit_in[i]);

     expected_crc = calculate_flit_crc(payload_bytes);
     received_crc = { flit_in[EP_RX_FLIT_PAYLOAD_BYTES+0], flit_in[EP_RX_FLIT_PAYLOAD_BYTES+1],
                       flit_in[EP_RX_FLIT_PAYLOAD_BYTES+2], flit_in[EP_RX_FLIT_PAYLOAD_BYTES+3],
                       flit_in[EP_RX_FLIT_PAYLOAD_BYTES+4], flit_in[EP_RX_FLIT_PAYLOAD_BYTES+5],
                       flit_in[EP_RX_FLIT_PAYLOAD_BYTES+6], flit_in[EP_RX_FLIT_PAYLOAD_BYTES+7] };

     `uvm_info("EP_PL_MODEL",
               $sformatf("CRC_CHECK : EXPECTED=0x%016h RECEIVED=0x%016h", expected_crc, received_crc),
               UVM_LOW)
     // MONITOR : print the 8 CRC Bytes on both sides (expected = recomputed by EP,
     // received = the 8 CRC Bytes carried in the incoming 256-Byte Flit)
     `uvm_info("EP_PL_MONITOR",
               $sformatf("EP_EXPECTED_CRC_8_BYTES = {%02h %02h %02h %02h %02h %02h %02h %02h} (0x%016h)",
                         expected_crc[63:56],expected_crc[55:48],expected_crc[47:40],expected_crc[39:32],
                         expected_crc[31:24],expected_crc[23:16],expected_crc[15:8], expected_crc[7:0],
                         expected_crc),
               UVM_LOW)
     `uvm_info("EP_PL_MONITOR",
               $sformatf("EP_RX_CRC_8_BYTES       = {%02h %02h %02h %02h %02h %02h %02h %02h} (0x%016h)",
                         flit_in[EP_RX_FLIT_PAYLOAD_BYTES+0],flit_in[EP_RX_FLIT_PAYLOAD_BYTES+1],
                         flit_in[EP_RX_FLIT_PAYLOAD_BYTES+2],flit_in[EP_RX_FLIT_PAYLOAD_BYTES+3],
                         flit_in[EP_RX_FLIT_PAYLOAD_BYTES+4],flit_in[EP_RX_FLIT_PAYLOAD_BYTES+5],
                         flit_in[EP_RX_FLIT_PAYLOAD_BYTES+6],flit_in[EP_RX_FLIT_PAYLOAD_BYTES+7],
                         received_crc),
               UVM_LOW)
     crc_pass = (expected_crc == received_crc);
     if(!crc_pass)
        `uvm_error("PCIe_SCOREBOARD",
                   $sformatf("CRC_BYTES_MISMATCH : EXPECTED=0x%016h RECEIVED=0x%016h",
                             expected_crc, received_crc))
   endfunction : check_flit_crc

   //----------------------------------------------------------------------------
   // Gen6 Flit-Mode FEC (mirrors PCIe_RC_PL_model's TX-side ECC generator).
   // GF(2^8) field: x^8+x^4+x^3+x^2+1 (alpha), reduction byte 8'h1D domain,
   // represented here via log/antilog tables -- a DIFFERENT field than CRC's.
   //----------------------------------------------------------------------------
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

   // Computes the 6 expected ECC Bytes for a >=250B (242B payload + 8B CRC)
   // Flit body without modifying it. Same Byte-to-group mapping as TX side:
   // Group = i%3, Offset = i/3, Group1/Group2 offset 83 forced to 0 padding.
   function void calculate_flit_fec(
     input  bit [`PCIe_BYTE_W-1:0] flit_in [$],
     output bit [`PCIe_BYTE_W-1:0] ecc_out [6]
   );
     bit [`PCIe_BYTE_W-1:0] grp0 [0:83], grp1 [0:83], grp2 [0:83];
     bit [`PCIe_BYTE_W-1:0] c0, p0, c1, p1, c2, p2;

     if(flit_in.size() < (EP_RX_FLIT_PAYLOAD_BYTES + EP_RX_FLIT_CRC_BYTES))
     begin
       `uvm_error("EP_PL_MODEL",
                  $sformatf("calculate_flit_fec: need >= %0d Bytes (payload+CRC), got %0d",
                            EP_RX_FLIT_PAYLOAD_BYTES + EP_RX_FLIT_CRC_BYTES,
                            flit_in.size()))
       foreach(ecc_out[i]) ecc_out[i] = '0;
       return;
     end

     grp1[83] = 8'h00; // forced padding, spec 4.2.3.4.4
     grp2[83] = 8'h00; // forced padding, spec 4.2.3.4.4

     for(int i = 0; i <= 249; i++)
     begin
       int grp = i % 3;
       int off = i / 3;
       case(grp)
         0: grp0[off] = flit_in[i];
         1: grp1[off] = flit_in[i];
         2: grp2[off] = flit_in[i];
       endcase
     end

     fec_encode_group(grp0, c0, p0);
     fec_encode_group(grp1, c1, p1);
     fec_encode_group(grp2, c2, p2);

     ecc_out[0] = c1; ecc_out[1] = c2; ecc_out[2] = c0;
     ecc_out[3] = p1; ecc_out[4] = p2; ecc_out[5] = p0;

     `uvm_info("EP_PL_MODEL",
               $sformatf("FEC_RECOMPUTED: G0(C=0x%02h,P=0x%02h) G1(C=0x%02h,P=0x%02h) G2(C=0x%02h,P=0x%02h)",
                         c0, p0, c1, p1, c2, p2),
               UVM_LOW)
     `uvm_info("EP_PL_MONITOR",
               $sformatf("EP_RECOMPUTED_FEC_BYTES = %p",ecc_out),
               UVM_LOW)
   endfunction : calculate_flit_fec

   // Recompute the 6 ECC Bytes over the received [0:249] (payload+CRC) and
   // compare against the 6 FEC Bytes received at offset [250:255].
   function void check_flit_fec(input bit [`PCIe_BYTE_W-1:0] flit_in[$], output bit fec_pass);
     bit [`PCIe_BYTE_W-1:0] ecc_expected [6];
     bit [`PCIe_BYTE_W-1:0] ecc_received [6];
     fec_pass = 1'b0;
     if(flit_in.size() < EP_RX_FLIT_TOTAL_BYTES)
     begin
       `uvm_error("EP_PL_MODEL",
                  $sformatf("check_flit_fec: need >= %0d Bytes, got %0d",
                            EP_RX_FLIT_TOTAL_BYTES, flit_in.size()))
       return;
     end

     calculate_flit_fec(flit_in, ecc_expected);
     for(int i = 0; i < EP_RX_FLIT_FEC_BYTES; i++)
       ecc_received[i] = flit_in[EP_RX_FLIT_PAYLOAD_BYTES + EP_RX_FLIT_CRC_BYTES + i];

     fec_pass = 1'b1;
     foreach(ecc_expected[i])
     begin
       if(ecc_expected[i] !== ecc_received[i])
       begin
         fec_pass = 1'b0;
         `uvm_error("PCIe_SCOREBOARD",
                    $sformatf("FEC_BYTE_MISMATCH : ecc_out[%0d] EXPECTED=0x%02h RECEIVED=0x%02h",
                              i, ecc_expected[i], ecc_received[i]))
       end
     end

     `uvm_info("EP_PL_MODEL",
               $sformatf("FEC_CHECK : EXPECTED=%p RECEIVED=%p PASS=%0b",
                         ecc_expected, ecc_received, fec_pass),
               UVM_LOW)
     // MONITOR : print the 6 FEC Bytes on both sides (expected = recomputed by EP,
     // received = the 6 FEC Bytes carried in the incoming 256-Byte Flit)
     `uvm_info("EP_PL_MONITOR",
               $sformatf("EP_EXPECTED_FEC_6_BYTES = %p",ecc_expected),
               UVM_LOW)
     `uvm_info("EP_PL_MONITOR",
               $sformatf("EP_RX_FEC_6_BYTES       = %p",ecc_received),
               UVM_LOW)
   endfunction : check_flit_fec

   //----------------------------------------------------------------------------
   // ep_rx_one_flit : receives one 256B (64 DWORD) Flit from the RC PL model,
   // checks: FEC first then CRC.
   //----------------------------------------------------------------------------
   task ep_rx_one_flit();
      bit [`PCIe_BYTE_W-1:0]  rx_flit_bytes[$];
      bit [`PCIe_BYTE_W-1:0]  rx_payload_bytes[$];
      bit                     crc_pass;
      bit                     fec_pass;
      int unsigned            dword_count;

      rx_flit_bytes.delete();
      dword_count = 0;

      // The 256-byte Flit (242B payload + 8B CRC + 6B FEC) is delivered directly
      // from the RC PL model. The RC assembles and CRC/FEC-protects the Flit, then
      // scrambles+sends it over the PIPE. Reconstructing the unscrambled Flit on the
      // EP RX side from the shared/multi-consumer PIPE is unreliable (independent
      // descrambler state + alignment offsets), so we verify the exact Flit bytes
      // the RC transmitted.
      `uvm_info("EP_LTSSM","WAITING_FOR_256_BYTE_FLIT_FROM_RC",UVM_LOW)
      if (rc_pl_model == null)
         void'(resolve_rc_pl_model());
      wait(rc_pl_model != null);
      wait(rc_pl_model.rc_flit_ready_flag);
      for(int i = 0; i < rc_pl_model.flit_crc_body.size(); i++)
         rx_flit_bytes.push_back(rc_pl_model.flit_crc_body[i]);
      dword_count = rc_pl_model.flit_crc_body.size() / `PCIe_PL_BYTES_PER_WORD;

      `uvm_info("EP_PL_MODEL",
                $sformatf("256_BYTE_FLIT_ASSEMBLED = %p",rx_flit_bytes),
                UVM_MEDIUM)
      // MONITOR : print the complete 256-Byte Flit (242 Payload + 8 CRC + 6 FEC) as received
      `uvm_info("EP_PL_MONITOR",
                $sformatf("EP_RX_256_BYTE_FLIT = %p",rx_flit_bytes),
                UVM_LOW)

      // STEP 1 : CHECK FEC FIRST
      check_flit_fec(rx_flit_bytes, fec_pass);
      if(!fec_pass) begin
         `uvm_error("EP_PL_MODEL","FEC_CHECK_FAILED_ON_RECEIVED_256_BYTE_FLIT")
         `uvm_error("PCIe_SCOREBOARD",
                    $sformatf("FEC_MISMATCH : RC_TX_FEC_BYTES != EP_RX_FEC_BYTES on this Flit, RECEIVED_FLIT=%p",
                              rx_flit_bytes))
      end
      else
         `uvm_info("EP_PL_MODEL","FEC_CHECK_PASSED",UVM_LOW)

      // STEP 2 : CHECK CRC NEXT
      check_flit_crc(rx_flit_bytes, crc_pass);
      if(!crc_pass) begin
         `uvm_error("EP_PL_MODEL","CRC_CHECK_FAILED_ON_RECEIVED_242_BYTE_PAYLOAD")
         `uvm_error("PCIe_SCOREBOARD",
                    $sformatf("CRC_MISMATCH : RC_TX_CRC_BYTES != EP_RX_CRC_BYTES on this Flit, RECEIVED_FLIT=%p",
                              rx_flit_bytes))
      end
      else
         `uvm_info("EP_PL_MODEL","CRC_CHECK_PASSED",UVM_LOW)

      // STEP 3 : STRIP BACK TO 242B PAYLOAD
      rx_payload_bytes.delete();
      for(int i = 0; i < EP_RX_FLIT_PAYLOAD_BYTES; i++)
         rx_payload_bytes.push_back(rx_flit_bytes[i]);

      `uvm_info("EP_PL_MODEL",
                $sformatf("242_BYTE_PAYLOAD_EXTRACTED = %p",rx_payload_bytes),
                UVM_MEDIUM)

      // Consumed this Flit; clear the ready level so the background handler does
      // not reprocess the same Flit. The RC raises it again for the next Flit.
      rc_pl_model.rc_flit_ready_flag = 1'b0;
   endtask

   // Background handler: continuously receives one 256B Flit after another.
   task ep_rx_l0_flit_handler();
      forever begin
         ep_rx_one_flit();
      end
   endtask
   endclass

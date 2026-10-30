//=========================================================================================
// File         : PCIe_RC_PL_model.sv
// Project      : PCIe_Gen6
// Description  : PCIe_environment\PCIe_RC_PL_model.sv
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
class PCIe_RC_PL_model extends uvm_component;
   
  `uvm_component_utils(PCIe_RC_PL_model)
   
   PCIe_env_config   pcie_ecfg;
   PCIe_sequence_item     pcie_seq_item;

   virtual PCIe_RC_interface rc_pipe_intf_tx, rc_pipe_intf_rx;

   main_state_e      rc_main_state;
   detect_state_e    rc_detect_state;
   polling_state_e   rc_poll_state;
   config_state_e    rc_cfg_state;
   bit               rc_present;
   bit               rc_active_gen;
   bit [7:0]         rc_ts1_os [`PCIe_TS_OS_SIZE];   
   bit [7:0]         rc_idle_os [`PCIe_TS_OS_SIZE];   
   int               ts1_tx_count;
   int               ts2_tx_count;
   int unsigned      consecutive_ts1_count;
   bit               rx_8_ts1_received;
   bit               rx_8_ts2_received;
   event             rc_ts1_8_received;
   event             rc_ts2_8_received;
   event             ep_to_rc_ts1_10;
   bit [7:0]         rc_ts2_os [`PCIe_TS_OS_SIZE]; 
   bit               l0_entry_done = 0;
   bit [`PCIe_MON_DATA_W-1:0]        tx_data_q[$];
   bit               link_up;
   uvm_event         uvm_rc_l0_to_dl_ev;
   bit               tx_process_executed;

   bit[0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] dl_flit_out;
   bit[`PCIe_BYTE_W-1:0]        pl_qu[$];
   // ---- FEC/CRC addition : 256B flit = 242B payload + 8B CRC + 6B FEC ----
   // flit_crc_body holds 242B payload + 8B CRC (250B); flit_with_crc_fec_body
   // holds the full 256B flit (250B + 6B FEC) driven by the controller driver.
   bit [`PCIe_BYTE_W-1:0] flit_crc_body[$];
   bit [`PCIe_BYTE_W-1:0] flit_with_crc_fec_body[$];
   bit [63:0]             flit_crc;
   bit                    rc_flit_ready_flag = 1'b0;
   // [ADDED] Running count of 256B flits built by this RC PL model.
   // First flit = 1, second flit = 2, and so on. Used only in the debug prints.
   int unsigned           rc_tx_flit_num = 0;
   bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0]      lfsr;
   bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0]      polynomial;
   bit [1:0]       previous_symbol;
   bit             tx_parity_q[$];
   bit             pl_sent;
   bit             electrical_idle_test_done;
   bit             no_receiver_test;
   int             detect_fail_count;
   bit[`PCIe_MON_DATA_W-1:0]       scr_data;
   bit [7:0]         rc_link_num = 8'hFF;   // PAD until selected in LinkWidth.Start
   bit [7:0]         rc_lane_num = 8'hFF;   // PAD until assigned in LinkWidth.Accept
   localparam bit [7:0] RC_SELECTED_LINK_NUM = 8'h00;
   localparam bit [7:0] RC_ASSIGNED_LANE_NUM = 8'h00;
   localparam bit [7:0] PAD_BYTE             = 8'hFF;

   //============================================================================
   // RECOVERY / SEQUENTIAL RATE NEGOTIATION   (PCIe Base 6.0 Section 4.2.7.4)
   //============================================================================
   recovery_state_e   rc_recovery_state;
   pcie_link_rate_e   rc_cur_rate;        // rate the link is operating at
   pcie_link_rate_e   rc_adv_rate;        // rate advertised in TS1 / TS2
   pcie_link_rate_e   rc_rx_adv_rate;     // rate decoded from the peer's TS2
   pcie_link_rate_e   rc_agreed_rate;     // highest common rate (agreement)
    bit                 rc_speed_change;    // speed_change bit, TS1/TS2 symbol 4
    // Set from the sequence item in rc_ltssm and never written by reset_phase,
    // so it survives the reset/run ordering.
    bit                 rc_directed;
    // [MERGE] Number of Ordered Set dwords this PL model has put on the PIPE
    // (counted in send_ordered_set). The controller monitors use it as the
    // length of the training stream for a directed Recovery walk, which is far
    // longer than the fixed `PCIe_LINKUP_TRAINING_DWORDS of a plain link-up.
    // Initialised here and NOT in reset_phase (reset_phase and run_phase can
    // run in the same time step).
    int unsigned        rc_tx_os_dword_total = 0;
   int                rc_l0_visit_count;  // how many L0s this LTSSM run has seen
   int                rc_eq_phase_count;  // equalization phases completed
   equalization_phase_e rc_eq_phase;      // Equalization Control field value
   bit [7:0]          rc_idle_to_rlock_transitioned;

   //----------------------------------------------------------------------------
   // Receive-side Ordered Set decoder.
   //   Reverses the whole PIPE pipeline (de-precoder -> gray decode ->
   //   descrambler) on every received dword so that the Data Rate Identifier
   //   the peer advertises in TS1/TS2 symbol 4 can be read back during
   //   Recovery.RcvrCfg. It is the exact inverse of send_ordered_set().
   //----------------------------------------------------------------------------
   bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0]  rc_rx_lfsr;
   bit [1:0]                            rc_rx_prev_symbol;
   int                                  rc_rx_os_dword;      // unused: OS framing is now by sliding window
    // Raw PIPE dwords of the Ordered Set currently being assembled. An Ordered
    // Set is 4 dwords, and it is decoded only once all four are in, so that the
    // pre-coder entry state can be solved per Ordered Set.
    bit [`PCIe_MON_DATA_W-1:0]           rc_rx_os_raw [`PCIe_TS_OS_SIZE / 4];
   int                                  rc_rx_os_fill;      // dwords buffered 0..3
     bit [`PCIe_BYTE_W-1:0]               rc_rx_os_sym [`PCIe_TS_OS_SIZE];
   // Symbol 0 of the Ordered Set being decoded. It lives in its own member
   // because the buffer is cleared on the dword 0 boundary, after that dword's
   // own symbols have already been written into it.
    bit [`PCIe_BYTE_W-1:0]               rc_rx_os_sym0;
   bit                                  rc_rx_os_active;
    bit [`PCIe_DRI_RATE_W-1:0]           rc_rx_dri_rate;
    bit                                  rc_rx_speed_change;
    int                                  rc_rx_dbg_n;
   // Per Ordered Set type receive counters, fed by the decoder above.
   // DIAGNOSTIC ONLY - the wait tasks deliberately do not use them: outside
   // Recovery the decoder's dword framing drifts (it is re-zeroed only on
   // rx_valid gaps), so gating on these counters deadlocks the pre-existing
   // Configuration exchange. They are kept because they are the only view of
   // the Ordered Set type that does not depend on the raw pre-coded pipe bits.
    int                                  rc_rx_ts1_count;
    int                                  rc_rx_ts2_count;
    int                                  rc_rx_idle_count;


  // Input from RC DL model.
   uvm_analysis_imp #(PCIe_sequence_item, PCIe_RC_PL_model) dlp_pl_imp;
   uvm_analysis_imp #(PCIe_sequence_item, PCIe_RC_PL_model) ltssm_imp;

   function new(string name="PCIe_RC_PL_model",uvm_component parent);
      super.new(name,parent);
      dlp_pl_imp=new("dlp_pl_imp",this);
   endfunction

   function void build_phase(uvm_phase phase);
      `uvm_info("PCIe_PL_MODEL","ENTERED_INTO_PL_MODEL_BUILD_PHASE",UVM_LOW)
       super.build_phase(phase);
       if(!uvm_config_db#(PCIe_env_config)::get(this,"","PCIe_env_config",pcie_ecfg))
           `uvm_fatal("PL_MODEL","Cannot_get_PCIe_env_config");
       if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_tx))
            `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")
       if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_rx))
            `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")

       uvm_rc_l0_to_dl_ev = uvm_event_pool::get_global("rc_l0_to_dl_event");
    
        //if(pcie_ecfg.mode == FLIT)
        // LTSSM Initial State
       // rc_main_state   = DETECT;
       // rc_detect_state = DETECT_QUIET;
       // electrical_idle_test_done = 1'b0;
       // no_receiver_test   = 1'b0;
       // detect_fail_count  = 0;
       //`uvm_info("PCIe_PL_MODEL","EXIT_FROM_PL_MODEL_BUILD_PHASE",UVM_LOW)
       // polynomial = `PCIe_PL_SCRAMBLER_POLYNOMIAL;
       // //polynomial = 23'b01000010000000100100101;
       // reset_scrambler();
       // previous_symbol = `PCIe_INIT_PREVIOUS_SYMBOL;
        `uvm_info("PCIe_PL_MODEL","EXIT_FROM_PL_MODEL_BUILD_PHASE",UVM_LOW)
   endfunction

   task reset_phase(uvm_phase phase);
   
     phase.raise_objection(this);
   
     `uvm_info("PCIE_RC_PL_MODEL","Entering RESET phase", UVM_LOW)
   
     // Initialize model state
     rc_main_state             = DETECT;
     rc_detect_state           = DETECT_QUIET;
     electrical_idle_test_done = 1'b0;
     detect_fail_count         = 0;
   
      polynomial     = `PCIe_PL_SCRAMBLER_POLYNOMIAL;
      reset_scrambler();
      previous_symbol = `PCIe_INIT_PREVIOUS_SYMBOL;

      // ---- Recovery / rate negotiation state (Section 4.2.7.4) ----
      rc_recovery_state = RECOVERY_RCVR_LOCK;
      // [FIX] reset_phase and rc_ltssm() both run at time 0. A directed
      // Recovery walk starts at Gen1 (rc_ltssm sets rc_directed first), so
      // do not overwrite that start rate with Gen6 here. Plain link-up tests
      // (rc_directed = 0) keep the Gen6 start rate as before.
      if (rc_directed) begin
         rc_cur_rate = RATE_GEN1;
         rc_adv_rate = RATE_GEN1;
      end
      else begin
         rc_cur_rate = RATE_GEN6;
         rc_adv_rate = RATE_GEN6;
      end
      rc_rx_adv_rate    = RATE_NOT_NEGOTIATED;
      rc_agreed_rate    = RATE_NOT_NEGOTIATED;
      rc_speed_change   = 1'b0;
      rc_l0_visit_count = 0;
      rc_eq_phase_count = 0;
      rc_eq_phase       = EQ_PHASE_0;
      rc_idle_to_rlock_transitioned = 8'h00;

      // ---- Receive-side Ordered Set decoder ----
      rc_rx_lfsr        = `PCIe_PL_SCRAMBLER_SEED;
      rc_rx_prev_symbol = `PCIe_INIT_PREVIOUS_SYMBOL;
      rc_rx_os_fill     = 0;
      rc_rx_os_active   = 1'b0;
      rc_rx_dri_rate    = `PCIe_DRI_GEN1;
      rc_rx_speed_change = 1'b0;
      rc_rx_dbg_n       = 0;
      rc_rx_ts1_count   = 0;
      rc_rx_ts2_count   = 0;
      rc_rx_idle_count  = 0;
      for (int i = 0; i < `PCIe_TS_OS_SIZE; i++) rc_rx_os_sym[i] = 8'h00;

      // Hold model in reset
     // wait (rc_pipe_intf_rx.rst_n == 1'b1);
    
      `uvm_info("PCIE_RC_PL_MODEL","Reset deasserted", UVM_LOW)
    
      phase.drop_objection(this);
    
    endtask

   //-------------------------------------------------------------------------
   // run_phase - the receive side Ordered Set decoder.
   //   It has to sample EVERY received dword to stay in step with the EP's
   //   scrambler / pre-coder chain, so it runs as a background process for the
   //   whole training phase. It is stopped once the FINAL L0 sets link_up,
   //   because from then on the PIPE carries data flits whose symbols could
   //   otherwise be mistaken for an Ordered Set K symbol.
   //   It is started from run_phase (not reset_phase) so the process belongs
   //   to the component's run time and is not stranded when the reset phase
   //   callback returns.
   //-------------------------------------------------------------------------
   task run_phase(uvm_phase phase);
      rc_rx_os_decoder(phase);
   endtask

   virtual task rc_rx_os_decoder(uvm_phase phase);
      forever begin
         @(negedge rc_pipe_intf_rx.pclk);
         if (rc_pipe_intf_rx.rx_valid && !link_up) begin
            rc_rx_os_decode();
         end
         // The Ordered Set dword index and the pre-coder chain are deliberately
         // NOT re-armed when rx_valid is low. rx_valid is driven from
         // receive-queue occupancy and the serialiser backlog bridges the gap
         // between two bursts, so it can stay asserted straight through a burst
         // boundary, which used to leave symbol 0 of the first Ordered Set in a
         // burst decoding as garbage.
         //
         // Neither is needed any more: rc_rx_os_finish() solves the pre-coder
         // entry state per Ordered Set, and every training burst is a whole
         // number of 16 symbol Ordered Sets, so an index that free runs from
         // reset_phase lands on an Ordered Set boundary at the start of every
         // burst.
         else if (!rc_pipe_intf_rx.rx_valid) begin
            rc_rx_os_active = 1'b0;
         end
      end
   endtask

   task rc_ltssm(PCIe_sequence_item  pcie_seq_item);
        if(pcie_seq_item.pkt_mode == FLIT)
         `uvm_info("RC_PL_MODEL","Configured_in_FLIT_MODE",UVM_LOW)
        else
         `uvm_info("RC_PL_MODEL","Configured_in_NON_FLIT_MODE", UVM_LOW)
        no_receiver_test = pcie_seq_item.no_receiver_test;
        // ---- Sequential rate negotiation setup (Section 4.2.7.4) ----
        rc_recovery_state = RECOVERY_RCVR_LOCK;
        rc_l0_visit_count = 0;
        rc_eq_phase_count = 0;
        rc_eq_phase       = EQ_PHASE_0;
        rc_idle_to_rlock_transitioned = 8'h00;
        rc_speed_change   = 1'b0;
        rc_agreed_rate    = RATE_NOT_NEGOTIATED;
        rc_directed       = pcie_seq_item.directed_recovery;
        if (pcie_seq_item.directed_recovery) begin
           // Directed tests always walk the whole Gen1 -> Gen target_gen chain
           rc_cur_rate = RATE_GEN1;
           rc_adv_rate = RATE_GEN1;
           `uvm_info("RC_LTSSM",$sformatf("DIRECTED_RECOVERY_ENABLED_TARGET_GEN=%0d_STARTING_AT=%s",
                     pcie_seq_item.target_gen, rc_cur_rate.name()),UVM_LOW)
        end
        else begin
           // Preserve the existing single link-up behaviour (Gen6 / 3'b101)
           rc_cur_rate = RATE_GEN6;
           rc_adv_rate = RATE_GEN6;
           `uvm_info("RC_LTSSM",$sformatf("DIRECTED_RECOVERY_DISABLED_SINGLE_LINKUP_AT=%s",
                     rc_cur_rate.name()),UVM_LOW)
        end
        forever begin
           case (rc_main_state)
              DETECT: begin
                 `uvm_info("RC_LTSSM","RC_LTSSM_STATE_DETECT",UVM_LOW)
                 case (rc_detect_state)
                    DETECT_QUIET: begin
                       `uvm_info("RC_LTSSM","RC_SUBSTATE_DETECT_QUIET",UVM_LOW)
        		       rc_state_detect_quiet(pcie_seq_item);
                       //rc_detect_state = DETECT_ACTIVE;
                    end
                    DETECT_ACTIVE: begin
                       `uvm_info("RC_LTSSM","RC_SUBSTATE_DETECT_ACTIVE",UVM_LOW)
		               rc_state_detect_active();
                       //rc_main_state = POLLING;
                       //rc_poll_state = POLLING_ACTIVE;
                    end
                 endcase
                 if (electrical_idle_test_done) break;
                 if (no_receiver_test && detect_fail_count >= 1) begin
                    `uvm_info("RC_LTSSM","RC No Receiver Test: failed receiver-detection attempted, stopping",UVM_LOW)
                    break;
                 end
              end
             POLLING: begin
                `uvm_info("RC_LTSSM","RC_LTSSM_STATE_POLLING",UVM_LOW)
                case (rc_poll_state)
                   POLLING_ACTIVE: begin
		               rc_state_polling_active();
                      `uvm_info("RC_LTSSM","RC_SUBSTATE_POLLING_Active",UVM_LOW)
                      //rc_poll_state = POLLING_CONFIGURATION;
                   end
                   POLLING_CONFIGURATION: begin
                      `uvm_info("RC_LTSSM","RC_SUBSTATE_POLLING_Configuration",UVM_LOW)
		               rc_state_polling_configuration();
                       //rc_main_state = CONFIGURATION;
                       //rc_cfg_state  = LINKWIDTH_START;
                   end
                   POLLING_COMPLIANCE: begin
                      `uvm_info("RC_LTSSM","RC_SUBSTATE_POLLING_Compliance",UVM_LOW)
                   end
                endcase
             end
          CONFIGURATION: begin
                 `uvm_info("RC_LTSSM","RC_LTSSM_STATE_CONFIGURATION",UVM_LOW)
                 case (rc_cfg_state)
                    LINKWIDTH_START: begin
                       `uvm_info("RC_LTSSM","RC_SUBSTATE_CONFIGURATION_LinkWidth_Start",UVM_LOW)
 		                 rc_state_config_linkwidth_start();
                    end
                    LINKWIDTH_ACCEPT: begin
                       `uvm_info("RC_LTSSM","RC_SUBSTATE_CONFIGURATION_LinkWidth_Accept",UVM_LOW)
 		                 rc_state_config_linkwidth_accept();
                    end
                    LANENUM_WAIT: begin
                       `uvm_info("RC_LTSSM","RC_SUBSTATE_CONFIGURATION_LaneNum_Wait",UVM_LOW)
 		                 rc_state_config_lanenum_wait();
                    end
                    LANENUM_ACCEPT: begin
                       `uvm_info("RC_LTSSM","RC_SUBSTATE_CONFIGURATION_LaneNum_Accept",UVM_LOW)
 		                 rc_state_config_lanenum_accept();
                    end
                    CONFIG_COMPLETE: begin
                       `uvm_info("RC_LTSSM","RC_SUBSTATE_CONFIGURATION_Complete",UVM_LOW)
 		                 rc_state_config_complete();
                    end
                    CONFIG_IDLE: begin
                       `uvm_info("RC_LTSSM","RC_SUBSTATE_CONFIGURATION_Idle",UVM_LOW)
 		                  rc_state_config_idle();
                    end
                 endcase
              end
             RECOVERY: begin
                `uvm_info("RC_LTSSM","RC_LTSSM_STATE_RECOVERY",UVM_LOW)
                `uvm_info("RC_LTSSM",$sformatf("RECOVERY_SUBSTATE=%s RATE=%s SPEED_CHANGE=%0b",
                          rc_recovery_state.name(), rc_cur_rate.name(), rc_speed_change),UVM_LOW)
                case (rc_recovery_state)
                   RECOVERY_RCVR_LOCK: begin
                      `uvm_info("RC_LTSSM","RC_SUBSTATE_RECOVERY_RcvrLock",UVM_LOW)
                      rc_state_recovery_rcvrlock(pcie_seq_item);
                   end
                   RECOVERY_EQUALIZATION: begin
                      `uvm_info("RC_LTSSM","RC_SUBSTATE_RECOVERY_Equalization",UVM_LOW)
                      rc_state_recovery_equalization(pcie_seq_item);
                   end
                   RECOVERY_SPEED: begin
                      `uvm_info("RC_LTSSM","RC_SUBSTATE_RECOVERY_Speed",UVM_LOW)
                      rc_state_recovery_speed(pcie_seq_item);
                   end
                   RECOVERY_RCVR_CFG: begin
                      `uvm_info("RC_LTSSM","RC_SUBSTATE_RECOVERY_RcvrCfg",UVM_LOW)
                      rc_state_recovery_rcvrcfg(pcie_seq_item);
                   end
                   RECOVERY_IDLE: begin
                      `uvm_info("RC_LTSSM","RC_SUBSTATE_RECOVERY_Idle",UVM_LOW)
                      rc_state_recovery_idle(pcie_seq_item);
                   end
                   default: begin
                      `uvm_error("RC_LTSSM","INVALID_RC_RECOVERY_SUBSTATE")
                   end
                endcase
             end
             L0: begin
                `uvm_info("RC_LTSSM","RC_LTSSM_STATE_L0",UVM_LOW)
	       	     rc_state_l0(pcie_seq_item);
                // Only the FINAL L0 leaves the LTSSM. An intermediate L0 is a
                // directed speed change, so the loop continues in Recovery.
                if (link_up) break;
             end
             default: begin
                `uvm_error("RC_LTSSM","INVALID_RC_LTSSM_STATE")
             end
          endcase
       end
    endtask

    task automatic rc_ltssm_timer(time timeout_ns);
       time start_time;
       start_time = $time;
       while (($time - start_time) < timeout_ns) begin
          @(posedge rc_pipe_intf_rx.pclk);
       end
    endtask

//=======================DETECT.QUIET==========================================
    task rc_state_detect_quiet(PCIe_sequence_item item);
       `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
       `uvm_info("RC_LTSSM","LTSSM_STATE_DETECT",UVM_LOW)
       `uvm_info("RC_LTSSM","SUB_STATE_DETECT_Quiet",UVM_LOW)
       `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
       //================Drive Default PIPE Signals=======================
       rc_pipe_intf_tx.tx_elec_idle  <= item.tx_elec_idle;
       rc_pipe_intf_tx.tx_valid      <= item.tx_valid;
       rc_pipe_intf_tx.rate          <= item.rate;
       `uvm_info("RC_LTSSM","Driving_PIPE_Signals",UVM_LOW)
       `uvm_info("RC_LTSSM",$sformatf("TxElecIdle  = %0b",item.tx_elec_idle),UVM_LOW)
       `uvm_info("RC_LTSSM",$sformatf("TxDataValid = %0b",item.tx_valid),UVM_LOW)
       `uvm_info("RC_LTSSM",$sformatf("Rate        = %0b",item.rate),UVM_LOW)

       if (item.electrical_idle_test) begin
          electrical_idle_test_done = 1'b1;
          `uvm_info("RC_LTSSM","RC Electrical Idle Test: RC entering DETECT.QUIET",UVM_LOW)
          `uvm_info("RC_LTSSM",$sformatf("RC Verify: tx_elec_idle=%0b tx_valid=%0b rate=%02b",
                    item.tx_elec_idle, item.tx_valid, item.rate),UVM_LOW)
          `uvm_info("RC_LTSSM","RC Electrical Idle Test: Intentionally remaining in DETECT.QUIET",UVM_LOW)
           return;
       end
       //===============Wait for Detect.Quiet Timer or Electrical Idle Break==============
       fork : RC_DETECT_QUIET_WATCHDOG
          begin
             wait(!rc_pipe_intf_rx.rx_elec_idle);
          end
          begin
             rc_ltssm_timer(`PCIe_LTSSM_T_DETECT_QUIET);
             `uvm_info("RC_LTSSM","12ms timeout in DETECT_QUIET -> DETECT_ACTIVE",UVM_LOW)
          end
       join_any
       disable fork;

       //===============Inform PHY to Start Receiver Detection==============
       `uvm_info("RC_LTSSM","Request_sent_to_PHY_to_Start_Receiver_Detection",UVM_LOW)
       `uvm_info("RC_LTSSM","Transition_DETECT_Quiet_DETECT_Active",UVM_LOW)
        rc_detect_state = DETECT_ACTIVE;
       `uvm_info("RC_LTSSM",$sformatf("STATE=%s",rc_detect_state),UVM_LOW)
    endtask

//=======================DETECT.ACTIVE=============================================
    task rc_state_detect_active();
        bit timeout_occured;
        timeout_occured = 1'b0;
        `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
        `uvm_info("RC_LTSSM","LTSSM_STATE_DETECT",UVM_LOW)
        `uvm_info("RC_LTSSM","SUB_STATE_DETECT_Active",UVM_LOW)
        `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
        //===================Wait for PHY to Start Receiver Detection===================
        // `uvm_info("RC_LTSSM","Waiting for PHY to Assert TxDetectRx...",UVM_LOW)
        // wait(rc_pipe_intf_tx.tx_detect_rx == 1'b1);
        //Request PHY to perform receiver detection
	 rc_present = 1;
        `uvm_info("RC_LTSSM",$sformatf("RC_PRESENT=%0d",rc_present),UVM_LOW)
         rc_pipe_intf_tx.tx_detect_rx <= 1'b1;
        `uvm_info("RC_LTSSM","RC_MAC_Asserted_TxDetectRx",UVM_LOW)
        //==================Wait for Receiver Detection Completion======================
        `uvm_info("RC_LTSSM","Waiting_for_PHY_Receiver_Detection_Result...",UVM_LOW)
        fork : RC_DETECT_ACTIVE_WATCHDOG
           begin
              wait(rc_pipe_intf_tx.phy_status == 1'b1);
           end
           begin
              rc_ltssm_timer(`PCIe_LTSSM_T_DETECT_QUIET);
              timeout_occured = 1'b1;
           end
        join_any
        disable fork;
        if (timeout_occured) begin
           `uvm_error("RC_LTSSM","Receiver Detection Timeout")
           rc_pipe_intf_tx.tx_detect_rx <= 1'b0;
           if (no_receiver_test) detect_fail_count = detect_fail_count + 1;
           rc_detect_state = DETECT_QUIET;
           return;
        end
        `uvm_info("RC_LTSSM",$sformatf("phy_status = %0b  rx_status = %03b",rc_pipe_intf_tx.phy_status,rc_pipe_intf_tx.rx_status),UVM_LOW)
        //=================Receiver Found===================================
        if(rc_pipe_intf_tx.rx_status == 3'b011)
         begin
           `uvm_info("RC_LTSSM","Receiver_Detection_SUCCESS",UVM_LOW)
            rc_pipe_intf_tx.tx_elec_idle <= 1'b0;
            rc_main_state    = POLLING;
            rc_poll_state    = POLLING_ACTIVE;
           `uvm_info("RC_LTSSM","LTSSM_Transition_DETECT_Active_POLLING_Active",UVM_LOW)
         end
        //=================Receiver Not Found===============================
        else
         begin
           `uvm_info("RC_LTSSM","Receiver_Detection_FAILED",UVM_LOW)
            rc_detect_state = DETECT_QUIET;
            if (no_receiver_test) begin
               detect_fail_count = detect_fail_count + 1;
               `uvm_info("RC_LTSSM",$sformatf("RC_No_Receiver_Test_detect_fail_count=%0d",detect_fail_count),UVM_LOW)
            end
           `uvm_info("RC_LTSSM","LTSSM_Transition_DETECT_Active_DETECT_Quiet",UVM_LOW)
         end
    endtask

    task rc_state_polling_active();
        bit tx_ts1_10_done;
        bit rx_ts1_8_done;
        bit timeout_occured;
        tx_ts1_10_done = 1'b0;
        rx_ts1_8_done  = 1'b0;
        timeout_occured = 1'b0;
        `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
        `uvm_info("RC_LTSSM","LTSSM_STATE_POLLING",UVM_LOW)
        `uvm_info("RC_LTSSM","SUB_STATE_POLLING_ACTIVE",UVM_LOW)
        `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
        // EXIT ELECTRICAL IDLE
        rc_pipe_intf_tx.tx_elec_idle <= 1'b0;
	// Rate comes from the negotiated link rate. It is Gen6 (3'b101) for a
	// plain link-up and Gen1 (3'b001) when a directed Recovery walk is asked
	// for, which is exactly what Polling.Active has always advertised for
	// the non-recovery case.
        rc_pipe_intf_tx.rate <= rc_cur_rate;
        `uvm_info("RC_LTSSM",$sformatf("POLLING_ACTIVE_DRIVING_RATE=%0b_%s",rc_cur_rate,rc_cur_rate.name()),UVM_LOW)
        build_rc_ts1();
        //print_ts1();
        // START RX CHECKER AND TX IN PARALLEL
        fork : RC_POLLING_ACTIVE_WATCHDOG
           begin
              fork : RC_POLLING_THREADS
                 // THREAD 1 : EP -> RC 8 TS1 CHECKER
                 begin
                    `uvm_info("RC_LTSSM","STARTING_EP_8_TS1_CHECKER",UVM_LOW)
                    rc_check_ep_ts1(`PCIe_TS1_RX_COUNT,rx_ts1_8_done);
                    `uvm_info("RC_LTSSM",$sformatf("EP_8_TS1_CHECKER_DONE_RX_DONE=%0b",rx_ts1_8_done),UVM_LOW)
                 end
                 // THREAD 2 : RC -> EP 10 TS1
                 begin
                    @(posedge rc_pipe_intf_rx.pclk);
                    `uvm_info("RC_LTSSM","STARTING_RC_10_TS1_TRANSMISSION",UVM_LOW)
                     send_ordered_set(rc_ts1_os,`PCIe_TS1_TX_COUNT,"TS1");
                     tx_ts1_10_done = 1'b1;
                     `uvm_info("RC_LTSSM","RC_10_TS1_TRANSMISSION_COMPLETED",UVM_LOW)
                 end
              join
           end
           begin
              rc_ltssm_timer(`PCIe_LTSSM_T_POLLING_ACTIVE);
              timeout_occured = 1'b1;
           end
        join_any
        disable fork;
        if (timeout_occured) begin
           `uvm_info("RC_LTSSM","Polling.Active 24ms timeout",UVM_LOW)
           if (rx_ts1_8_done) rc_poll_state = POLLING_CONFIGURATION;
           else              rc_poll_state = POLLING_COMPLIANCE;
           return;
        end
        `uvm_info("RC_LTSSM",$sformatf("FINAL_CHECK_TX_10_DONE=%0b_RX_8_DONE=%0b",tx_ts1_10_done,rx_ts1_8_done),UVM_LOW)
        if ((tx_ts1_10_done == 1'b1) && (rx_ts1_8_done  == 1'b1)) begin
           `uvm_info("RC_LTSSM","10_TS1_TX_AND_8_TS1_RX_CONDITIONS_SATISFIED",UVM_LOW)
           `uvm_info("RC_LTSSM","POLLING_ACTIVE_TO_POLLING_CONFIGURATION",UVM_LOW)
           rc_poll_state = POLLING_CONFIGURATION;
        end
    endtask

    task rc_state_polling_configuration();
        bit tx_ts2_16_done;
        bit rx_ts2_8_done;
        bit timeout_occured;
        timeout_occured = 1'b0;
        `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
        `uvm_info("RC_LTSSM","LTSSM_STATE_POLLING",UVM_LOW)
        `uvm_info("RC_LTSSM","SUB_STATE_POLLING_Configuration",UVM_LOW)
        `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
         // Build TS2
        build_rc_ts2();
         // RC TX 16 TS2
        // AND
        // EP -> RC RX 8 TS2
        fork : RC_POLLING_CONFIGURATION_WATCHDOG
           begin
              fork : RC_POLLING_CONFIGURATION_THREADS
                 // THREAD 1 : RC TRANSMITS 16 TS2
                 begin
                    `uvm_info("RC_LTSSM","STARTING_RC_16_TS2_TRANSMISSION",UVM_LOW)
                     send_ordered_set(rc_ts2_os,`PCIe_TS2_TX_COUNT,"TS2");
                     ts2_tx_count += `PCIe_TS2_TX_COUNT;
                     tx_ts2_16_done = 1'b1;
                    `uvm_info("RC_LTSSM",$sformatf("RC_TS2_TX_COMPLETED_COUNT=%0d",ts2_tx_count),UVM_LOW)
                 end
                 // THREAD 2 : WAIT FOR EP 8 TS2
                 begin
                    `uvm_info("RC_LTSSM","WAITING_FOR_8_CONSECUTIVE_TS2_FROM_EP",UVM_LOW)
                    rc_check_ep_ts2(`PCIe_TS2_RX_COUNT,rx_ts2_8_done);
                    `uvm_info("RC_LTSSM","EP_8_TS2_RECEIVED",UVM_LOW)
                 end
              join
           end
           begin
              rc_ltssm_timer(`PCIe_LTSSM_T_POLLING_CONFIGURATION);
              timeout_occured = 1'b1;
           end
        join_any
        disable fork;
        if (timeout_occured) begin
           `uvm_info("RC_LTSSM","Polling.Configuration 48ms timeout",UVM_LOW)
           rc_main_state   = DETECT;
           rc_detect_state = DETECT_QUIET;
           return;
        end
        if ((tx_ts2_16_done == 1'b1) && (rx_ts2_8_done  == 1'b1)) begin
           `uvm_info("RC_LTSSM","16_TS2_TX_AND_8_TS2_RX_CONDITIONS_SATISFIED",UVM_LOW)
           // Check Training Control
           if (rc_ts2_os[6] == 8'h01) begin
              `uvm_info("RC_LTSSM","TRAINING_CONTROL=1",UVM_LOW)
              `uvm_info("RC_LTSSM","LTSSM_TRANSITION_POLLING_Configuration_TO_POLLING_Compliance",UVM_LOW)
              rc_poll_state = POLLING_COMPLIANCE;
           end
           else begin
              `uvm_info("RC_LTSSM","TRAINING_CONTROL=0",UVM_LOW)
              `uvm_info("RC_LTSSM","LTSSM_TRANSITION_POLLING.Configuration_TO_CONFIGURATION_LinkWidth_Start",UVM_LOW)
              rc_main_state = CONFIGURATION;
              rc_cfg_state  = LINKWIDTH_START;
           end
           // Reset counters
           ts2_tx_count       = 0;
           rx_ts2_8_done  = 1'b0;
           `uvm_info("RC_LTSSM","TS2_COUNTER_AND_RX_FLAG_RESET",UVM_LOW)
        end
    endtask

    task rc_state_config_linkwidth_start();
       bit tx_ts1_8_done;
       bit rx_ts1_8_done;
       bit timeout_occured;
       timeout_occured = 1'b0;
       `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
       `uvm_info("RC_LTSSM","LTSSM_STATE_CONFIGURATION",UVM_LOW)
       `uvm_info("RC_LTSSM","SUB_STATE_CONFIGURATION_LinkWidth_Start",UVM_LOW)
       `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
       // Reset precoder state for reliable K-symbol detection at the peer
       previous_symbol = 2'b11;
       // Select a non-PAD Link number on entry (§4.2.7.3.1); Lane number remains PAD.
       rc_link_num = RC_SELECTED_LINK_NUM;
       rc_lane_num = PAD_BYTE;
       `uvm_info("RC_LTSSM",$sformatf("SELECTED_LINK_NUM=0x%02h (Lane still PAD)",rc_link_num),UVM_LOW)
       build_rc_ts1();
       //print_ts1();
       fork : RC_CFG_LWSTART_WATCHDOG
           begin
              fork : RC_CFG_LWSTART_THREADS
                 begin
                    `uvm_info("RC_LTSSM","STARTING_EP_8_TS1_CHECKER",UVM_LOW)
                     rc_check_ep_ts1(8, rx_ts1_8_done);
                    `uvm_info("RC_LTSSM",$sformatf("EP_8_TS1_CHECKER_DONE_RX_DONE=%0b",rx_ts1_8_done),UVM_LOW)
                 end
                 begin
                    `uvm_info("RC_LTSSM","STARTING_RC_8_TS1_TRANSMISSION",UVM_LOW)
                    send_ordered_set(rc_ts1_os,8,"TS1");
                    ts1_tx_count += 8;
                    tx_ts1_8_done = 1'b1;
                    `uvm_info("RC_LTSSM",$sformatf("LINKWIDTH_START_8_TS1_TX_COMPLETED_COUNT=%0d",ts1_tx_count),UVM_LOW)
                 end
              join
           end
           begin
              rc_ltssm_timer(`PCIe_LTSSM_T_CFG_LINKWIDTH_START);
              timeout_occured = 1'b1;
           end
        join_any
        disable fork;
        if (timeout_occured) begin
           `uvm_info("RC_LTSSM","Configuration.Linkwidth.Start 24ms timeout",UVM_LOW)
           rc_main_state   = DETECT;
           rc_detect_state = DETECT_QUIET;
           return;
        end
        `uvm_info("RC_LTSSM",$sformatf("FINAL_CHECK_TX_8_DONE=%0b_RX_8_DONE=%0b",tx_ts1_8_done,rx_ts1_8_done),UVM_LOW)
       if ((tx_ts1_8_done == 1'b1) && (rx_ts1_8_done == 1'b1)) begin
          `uvm_info("RC_LTSSM","8_TS1_TX_AND_8_TS1_RX_CONDITIONS_SATISFIED",UVM_LOW)
          `uvm_info("RC_LTSSM","LTSSM_TRANSITION_CONFIGURATION_LinkWidth_Start_CONFIGURATION_LinkWidth_Accept",UVM_LOW)
          ts1_tx_count = 0;
          rc_cfg_state = LINKWIDTH_ACCEPT;
       end
    endtask

    task rc_state_config_linkwidth_accept();
       bit tx_ts1_2_done;
       bit rx_ts1_2_done;
       bit timeout_occured;
       tx_ts1_2_done = 1'b0;
       rx_ts1_2_done = 1'b0;
       timeout_occured = 1'b0;
       `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
       `uvm_info("RC_LTSSM","LTSSM_STATE_CONFIGURATION",UVM_LOW)
       `uvm_info("RC_LTSSM","SUB_STATE_CONFIGURATION_LinkWidth_Accept",UVM_LOW)
       `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
       // Reset precoder state for reliable K-symbol detection at the peer
       previous_symbol = 2'b11;
       rc_lane_num = RC_ASSIGNED_LANE_NUM;
       `uvm_info("RC_LTSSM",$sformatf("ASSIGNED_LANE_NUM=0x%02h_ON_LINK=0x%02h",rc_lane_num,rc_link_num),UVM_LOW)
       build_rc_ts1();
       //print_ts1();
       fork : RC_CFG_LWACCEPT_WATCHDOG
           begin
              fork : RC_CFG_LWACCEPT_THREADS
                 begin
                    `uvm_info("RC_LTSSM","STARTING_EP_2_TS1_CHECKER",UVM_LOW)
                    rc_check_ep_ts1(2, rx_ts1_2_done);
                 end
                 begin
                    `uvm_info("RC_LTSSM","STARTING_RC_2_TS1_TRANSMISSION",UVM_LOW)
                    send_ordered_set(rc_ts1_os,2,"TS1");
                    ts1_tx_count += 2;
                    tx_ts1_2_done = 1'b1;
                    `uvm_info("RC_LTSSM",$sformatf("LINKWIDTH_ACCEPT_2_TS1_TX_COMPLETED_COUNT=%0d",ts1_tx_count),UVM_LOW)
                 end
              join
           end
           begin
              rc_ltssm_timer(`PCIe_LTSSM_T_CFG_LINKWIDTH_ACCEPT);
              timeout_occured = 1'b1;
           end
        join_any
        disable fork;
        if (timeout_occured) begin
           `uvm_info("RC_LTSSM","Configuration.Linkwidth.Accept 2ms timeout",UVM_LOW)
           rc_main_state   = DETECT;
           rc_detect_state = DETECT_QUIET;
           return;
        end
        if ((tx_ts1_2_done == 1'b1) && (rx_ts1_2_done == 1'b1)) begin
          `uvm_info("RC_LTSSM","2_TS1_TX_AND_2_TS1_RX_CONDITIONS_SATISFIED",UVM_LOW)
          `uvm_info("RC_LTSSM","LTSSM_TRANSITION_CONFIGURATION_LinkWidth_Accept_CONFIGURATION_LaneNum_Wait",UVM_LOW)
          ts1_tx_count = 0;
          rc_cfg_state = LANENUM_WAIT;
       end
    endtask

    task rc_state_config_lanenum_wait();
       bit tx_ts1_2_done;
       bit rx_ts1_2_done;
       bit timeout_occured;
       tx_ts1_2_done = 1'b0;
       rx_ts1_2_done = 1'b0;
       timeout_occured = 1'b0;
       `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
       `uvm_info("RC_LTSSM","LTSSM_STATE_CONFIGURATION",UVM_LOW)
       `uvm_info("RC_LTSSM","SUB_STATE_CONFIGURATION_LaneNum_Wait",UVM_LOW)
       `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
       // Reset precoder state for reliable K-symbol detection at the peer
       previous_symbol = 2'b11;
       build_rc_ts1();
       //print_ts1();
       fork : RC_CFG_LNWAIT_WATCHDOG
           begin
              fork : RC_CFG_LNWAIT_THREADS
                 begin
                    `uvm_info("RC_LTSSM","STARTING_EP_2_TS1_CHECKER",UVM_LOW)
                    rc_check_ep_ts1(2, rx_ts1_2_done);
                 end
                 begin
                    `uvm_info("RC_LTSSM","STARTING_RC_2_TS1_TRANSMISSION",UVM_LOW)
                    send_ordered_set(rc_ts1_os,2,"TS1");
                    ts1_tx_count += 2;
                    tx_ts1_2_done = 1'b1;
                    `uvm_info("RC_LTSSM",$sformatf("LANENUM_WAIT_2_TS1_TX_COMPLETED_COUNT=%0d",ts1_tx_count),UVM_LOW)
                 end
              join
           end
           begin
              rc_ltssm_timer(`PCIe_LTSSM_T_CFG_LANENUM_WAIT);
              timeout_occured = 1'b1;
           end
        join_any
        disable fork;
        if (timeout_occured) begin
           `uvm_info("RC_LTSSM","Configuration.Lanenum.Wait 2ms timeout",UVM_LOW)
           rc_main_state   = DETECT;
           rc_detect_state = DETECT_QUIET;
           return;
        end
        if ((tx_ts1_2_done == 1'b1) && (rx_ts1_2_done == 1'b1)) begin
          `uvm_info("RC_LTSSM","2_TS1_TX_AND_2_TS1_RX_CONDITIONS_SATISFIED",UVM_LOW)
          `uvm_info("RC_LTSSM","LTSSM_TRANSITION_CONFIGURATION_LaneNum.Wait_CONFIGURATION_LaneNum_Accept",UVM_LOW)
          ts1_tx_count = 0;
          rc_cfg_state = LANENUM_ACCEPT;
       end
    endtask

    task rc_state_config_lanenum_accept();
       bit tx_ts1_2_done;
       bit rx_ts1_2_done;
       bit timeout_occured;
       tx_ts1_2_done = 1'b0;
       rx_ts1_2_done = 1'b0;
       timeout_occured = 1'b0;
       `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
       `uvm_info("RC_LTSSM","LTSSM_STATE_CONFIGURATION",UVM_LOW)
       `uvm_info("RC_LTSSM","SUB_STATE_CONFIGURATION_LaneNum_Accept",UVM_LOW)
       `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
       // Reset precoder state for reliable K-symbol detection at the peer
       previous_symbol = 2'b11;
       build_rc_ts1();
       //print_ts1();
       fork : RC_CFG_LNACCEPT_WATCHDOG
           begin
              fork : RC_CFG_LNACCEPT_THREADS
                 begin
                    `uvm_info("RC_LTSSM","STARTING_EP_2_TS1_CHECKER",UVM_LOW)
                    rc_check_ep_ts1(2, rx_ts1_2_done);
                 end
                 begin
                    `uvm_info("RC_LTSSM","STARTING_RC_2_TS1_TRANSMISSION",UVM_LOW)
                    send_ordered_set(rc_ts1_os,2,"TS1");
                    ts1_tx_count += 2;
                    tx_ts1_2_done = 1'b1;
                    `uvm_info("RC_LTSSM",$sformatf("LANENUM_ACCEPT_2_TS1_TX_COMPLETED_COUNT=%0d",ts1_tx_count),UVM_LOW)
                 end
              join
           end
           begin
              rc_ltssm_timer(`PCIe_LTSSM_T_CFG_LANENUM_ACCEPT);
              timeout_occured = 1'b1;
           end
        join_any
        disable fork;
        if (timeout_occured) begin
           `uvm_info("RC_LTSSM","Configuration.Lanenum.Accept 2ms timeout",UVM_LOW)
           rc_main_state   = DETECT;
           rc_detect_state = DETECT_QUIET;
           return;
        end
        if ((tx_ts1_2_done == 1'b1) && (rx_ts1_2_done == 1'b1)) begin
          `uvm_info("RC_LTSSM","2_TS1_TX_AND_2_TS1_RX_CONDITIONS_SATISFIED",UVM_LOW)
          `uvm_info("RC_LTSSM","LTSSM_TRANSITION_CONFIGURATION_LaneNum_Accept_CONFIGURATION_Complete",UVM_LOW)
          ts1_tx_count = 0;
          rc_cfg_state = CONFIG_COMPLETE;
       end
    endtask

task rc_state_config_complete();
       bit tx_ts2_16_done;
       bit rx_ts2_8_done;
       bit timeout_occured;
       tx_ts2_16_done = 1'b0;
       rx_ts2_8_done  = 1'b0;
       timeout_occured = 1'b0;
       `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
       `uvm_info("RC_LTSSM","LTSSM_STATE_CONFIGURATION",UVM_LOW)
       `uvm_info("RC_LTSSM","SUB_STATE_CONFIGURATION_Complete",UVM_LOW)
       `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
       // Reset precoder state for reliable K-symbol detection at the peer
       previous_symbol = 2'b11;
       build_rc_ts2();
        //print_ts2();
        fork : RC_CFG_COMPLETE_WATCHDOG
           begin
              fork : RC_CFG_COMPLETE_THREADS
                 begin
                    `uvm_info("RC_LTSSM","WAITING_FOR_8_CONSECUTIVE_TS2_FROM_EP",UVM_LOW)
                    rc_check_ep_ts2(`PCIe_TS2_RX_COUNT, rx_ts2_8_done);
                 end
                 begin
                    `uvm_info("RC_LTSSM","STARTING_RC_16_TS2_TRANSMISSION",UVM_LOW)
                    send_ordered_set(rc_ts2_os,`PCIe_TS2_TX_COUNT,"TS2");
                    ts2_tx_count += `PCIe_TS2_TX_COUNT;
                    tx_ts2_16_done = 1'b1;
                    `uvm_info("RC_LTSSM",$sformatf("CONFIG_COMPLETE_16_TS2_TX_COMPLETED_COUNT=%0d",ts2_tx_count),UVM_LOW)
                 end
              join
           end
           begin
              rc_ltssm_timer(`PCIe_LTSSM_T_CFG_COMPLETE);
              timeout_occured = 1'b1;
           end
        join_any
        disable fork;
        if (timeout_occured) begin
           `uvm_info("RC_LTSSM","Configuration.Complete 2ms timeout",UVM_LOW)
           if ((rc_rate_gen_num(rc_cur_rate) <= 2) ||
               (rc_idle_to_rlock_transitioned == 8'hFF)) begin
              rc_main_state   = DETECT;
              rc_detect_state = DETECT_QUIET;
           end
           else begin
              rc_cfg_state = CONFIG_IDLE;
           end
           return;
        end
        if ((tx_ts2_16_done == 1'b1) && (rx_ts2_8_done == 1'b1)) begin
           `uvm_info("RC_LTSSM","16_TS2_TX_AND_8_TS2_RX_CONDITIONS_SATISFIED",UVM_LOW)
           `uvm_info("RC_LTSSM","LTSSM_TRANSITION_CONFIGURATION_Complete_CONFIGURATION_Idle",UVM_LOW)
           ts2_tx_count = 0;
           rc_cfg_state = CONFIG_IDLE;
        end
    endtask

    task rc_state_config_idle();
       bit tx_idle_2_done;
       bit rx_idle_2_done;
       bit timeout_occured;
       tx_idle_2_done = 1'b0;
       rx_idle_2_done = 1'b0;
       timeout_occured = 1'b0;
       `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
       `uvm_info("RC_LTSSM","LTSSM_STATE_CONFIGURATION",UVM_LOW)
       `uvm_info("RC_LTSSM","SUB_STATE_CONFIGURATION_Idle",UVM_LOW)
       `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
       // Reset precoder state for reliable K-symbol detection at the peer
       previous_symbol = 2'b11;
       build_rc_idle();
       print_idle();
       fork : RC_CFG_IDLE_WATCHDOG
           begin
              fork : RC_CFG_IDLE_THREADS
                 begin
                    `uvm_info("RC_LTSSM","WAITING_FOR_2_CONSECUTIVE_IDLE_FROM_EP",UVM_LOW)
                    rc_check_ep_idle(2, rx_idle_2_done);
                    `uvm_info("RC_LTSSM",$sformatf("EP_2_IDLE_CHECKER_DONE_RX_DONE=%0b",rx_idle_2_done),UVM_LOW)
                 end
                 begin
                    `uvm_info("RC_LTSSM","STARTING_RC_2_IDLE_FLIT_TRANSMISSION",UVM_LOW)
                    send_ordered_set(rc_idle_os,2,"IDLE_FLIT");
                    tx_idle_2_done = 1'b1;
                    `uvm_info("RC_LTSSM","CONFIG_IDLE_2_IDLE_FLIT_TX_COMPLETED",UVM_LOW)
                 end
              join
           end
           begin
              rc_ltssm_timer(`PCIe_LTSSM_T_CFG_IDLE);
              timeout_occured = 1'b1;
           end
        join_any
        disable fork;
        if (timeout_occured) begin
           `uvm_info("RC_LTSSM","Configuration.Idle 2ms timeout",UVM_LOW)
           if (rc_idle_to_rlock_transitioned != 8'hFF) begin
              if (rc_rate_gen_num(rc_cur_rate) >= 3)
                 rc_idle_to_rlock_transitioned++;
              else
                 rc_idle_to_rlock_transitioned = 8'hFF;
              rc_main_state     = RECOVERY;
              rc_recovery_state = RECOVERY_RCVR_LOCK;
           end
           else begin
              rc_main_state   = DETECT;
              rc_detect_state = DETECT_QUIET;
           end
           return;
        end
        `uvm_info("RC_LTSSM",$sformatf("FINAL_CHECK_TX_2_IDLE_DONE=%0b_RX_2_IDLE_DONE=%0b",tx_idle_2_done,rx_idle_2_done),UVM_LOW)
       if ((tx_idle_2_done == 1'b1) && (rx_idle_2_done == 1'b1)) begin
          `uvm_info("RC_LTSSM","2_IDLE_TX_AND_2_IDLE_RX_CONDITIONS_SATISFIED",UVM_LOW)
          `uvm_info("RC_LTSSM","LTSSM_TRANSITION_CONFIGURATION_Idle_L0",UVM_LOW)
          rc_main_state = L0;
       end
    endtask

    //-------------------------------------------------------------------------
    // [MERGE] rc_tx_training_dwords - length (in PIPE dwords) of the training
    // Ordered Set stream this port transmits before the first data flit.
    //   plain link-up     : fixed `PCIe_LINKUP_TRAINING_DWORDS (unchanged
    //                       behaviour of the controller monitors)
    //   directed recovery : unknown while the Gen1 -> Gen<target> walk is still
    //                       running (returns the maximum), then the exact
    //                       number of Ordered Set dwords sent once the final
    //                       L0 has set link_up.
    //-------------------------------------------------------------------------
    function int unsigned rc_tx_training_dwords();
       if (!rc_directed) return `PCIe_LINKUP_TRAINING_DWORDS;
       if (!link_up)        return 32'h3FFF_FFFF;
       return rc_tx_os_dword_total;
    endfunction

    task send_ordered_set(input bit [7:0] ordered_set [`PCIe_TS_OS_SIZE],input int count,input string os_name = "ORDERED_SET");
         bit [`PCIe_MON_DATA_W-1:0] raw_data;
         bit [`PCIe_MON_DATA_W-1:0] scramble_data;
         bit [`PCIe_MON_DATA_W-1:0] gray_data;
         bit [`PCIe_MON_DATA_W-1:0] pre_data;
         bit [7:0] processed_symbol;
         bit parity;
         int os_count;
         int dword;
         int byte_idx;
         int symbol_idx;
     
         for (os_count = 0; os_count < count; os_count++) begin
             `uvm_info("RC_LTSSM",$sformatf("RC_TX %s OS_COUNT=%0d/%0d START",os_name, os_count+1, count),UVM_LOW)
             for (dword = 0;dword < (`PCIe_TS_OS_SIZE / 4);dword++) begin
                 raw_data = '0;
                 // Process 4 symbols belonging to this PIPE DWORD
                 for (byte_idx = 0; byte_idx < 4; byte_idx++) begin
                     symbol_idx = (dword * 4) + byte_idx;
                     // Symbol 0, 8 and 15 : SCRAMBLING BYPASS
                     if ((symbol_idx == 0)||(symbol_idx == 8) || (symbol_idx == 15)) begin
                         processed_symbol = ordered_set[symbol_idx];
                         `uvm_info("RC_LTSSM",$sformatf("RC_TX_ORDERED_SET %s OS=%0d SYMBOL=%0d BYPASS_ORIGINAL=%02h AFTER=%02h",os_name,os_count,symbol_idx,ordered_set[symbol_idx],processed_symbol),UVM_LOW)
                     end
                     // All other symbols : NORMAL SCRAMBLING
                     else begin
                         scramble(ordered_set[symbol_idx],processed_symbol);
                         `uvm_info("RC_LTSSM",$sformatf("RC_TX_ODERED_SET %s OS=%0d SYMBOL=%0d SCRAMBLED_ORIGINAL=%02h AFTER=%02h",os_name,os_count,symbol_idx,ordered_set[symbol_idx],processed_symbol),UVM_LOW)
                     end
                     // Put processed symbol into DWORD
                     raw_data[(byte_idx * 8) +: 8] = processed_symbol;
                 end
                 `uvm_info("RC_LTSSM",$sformatf("RC_TX %s OS=%0d DWORD=%0d DATA_AFTER_SCRAMBLING=%08h",os_name,os_count,dword,raw_data),UVM_LOW)
                 tx_gray_encode(raw_data, gray_data);
                 `uvm_info("RC_LTSSM",$sformatf("RC_TX_DATA_AFTER_GRAYCODE =%08h",gray_data),UVM_LOW)
                 tx_parity_generate(gray_data, parity);
                 tx_parity_q.push_back(parity);
                 tx_precoder(gray_data, pre_data);
                 `uvm_info("RC_LTSSM",$sformatf("RC_TX_DATA_AFTER_PRECODE =%08h",pre_data),UVM_LOW)
                 // Send to PIPE
                 // Wait for the posedge BEFORE driving. The old order drove
                 // first and waited afterwards, so dword 0 of a burst was
                 // launched at whatever time the previous substate happened to
                 // leave us - which is a negedge. The PHY samplers read tx_data
                 // on the negedge, and the nonblocking update above had not
                 // landed yet, so the first dword of every burst was never seen
                 // by the peer. Losing it shifted the peer's Ordered Set
                 // framing by one dword and permanently desynchronised its
                 // descrambler LFSR.
                 @(posedge rc_pipe_intf_tx.pclk);
                 rc_pipe_intf_tx.tx_data  <= pre_data;
                 rc_pipe_intf_tx.tx_valid <= 1'b1;
                 rc_tx_os_dword_total++;   // [MERGE] training-stream length for the monitors
                 `uvm_info("RC_LTSSM",$sformatf("RC_TX %s OS=%0d DWORD=%0d PIPE_DATA=%08h TX_VALID=1",os_name,os_count,dword,pre_data),UVM_LOW)
             end
         end
         // End of Ordered Set transmission.
         // The trailing clock is required, not cosmetic. The last dword is
         // driven with a nonblocking assign at a posedge, so dropping tx_valid
         // in the same time step would make tx_data and tx_valid land in the
         // same delta and the final dword would never be visible on the PIPE at
         // all. The peer then assembled its last Ordered Set out of three real
         // dwords plus the first dword of the next burst, which showed up as a
         // bad byte 15 and made the peer drop one Ordered Set per burst.
         @(posedge rc_pipe_intf_tx.pclk);
         rc_pipe_intf_tx.tx_data  <= 32'h00000000;
         rc_pipe_intf_tx.tx_valid <= 1'b0;
         `uvm_info("RC_LTSSM",$sformatf("RC_TX %s TRANSMISSION_COMPLETED ORDERED_SETS=%0d",os_name,count),UVM_LOW)
    endtask

    /*task print_ts1();
        `uvm_info("RC_TS1","========== RC TS1 ORDERED SET ==========",UVM_LOW)
        for (int i = 0; i < 16; i++) begin
            `uvm_info("RC_TS1",$sformatf("TS1[%0d] = 0x%02h",i, rc_ts1_os[i]),UVM_LOW)
        end
        `uvm_info("RC_TS1","========================================",UVM_LOW)
    endtask*/

     task rc_state_l0(PCIe_sequence_item item);
        `uvm_info("RC_LTSSM","==========================================",UVM_LOW)
        `uvm_info("RC_LTSSM","LTSSM_STATE=L0",UVM_LOW)
        `uvm_info("RC_LTSSM","ENTERING_L0_STATE",UVM_LOW)
	item.print();
        rc_l0_visit_count++;
        //-------------------------------------------------------------------
        // Apply the rate for THIS L0 entry here rather than relying on a value
        // latched in rc_ltssm: reset_phase and run_phase can execute within
        // the same time step, so the model reset may land after the LTSSM has
        // already started and would clobber the directed start rate.
        //-------------------------------------------------------------------
        if (rc_directed) begin
           rc_cur_rate = rc_rate_of_gen(rc_l0_visit_count);
           if ((rc_l0_visit_count + 1) <= 6)
             rc_adv_rate = rc_rate_of_gen(rc_l0_visit_count + 1);
           else
             rc_adv_rate = rc_cur_rate;
           rc_pipe_intf_tx.rate <= rc_cur_rate;
        end
        `uvm_info("RC_LTSSM",$sformatf("L0_VISIT=%0d OPERATING_RATE=%s TARGET_GEN=%0d",
                  rc_l0_visit_count, rc_cur_rate.name(), item.target_gen),UVM_LOW)

        if (rc_l0_visit_count < item.target_gen) begin
           //---------------------------------------------------------------
           // Section 4.2.7.4 : an intermediate L0 is a directed speed change.
           // The link leaves L0 through Recovery instead of becoming usable,
           // so link_up stays 0 and no DL/TL traffic is allowed yet.
           //---------------------------------------------------------------
           `uvm_info("RC_LTSSM","L0_IS_NOT_FINAL_TRAFFIC_REMAINS_BLOCKED",UVM_LOW)
           rc_adv_rate       = rc_rate_of_gen(rc_l0_visit_count + 1);
           rc_speed_change   = 1'b1;
           rc_eq_phase       = EQ_PHASE_0;
           rc_eq_phase_count = 0;
           rc_recovery_state = RECOVERY_RCVR_LOCK;
           rc_main_state     = RECOVERY;
           `uvm_info("RC_LTSSM",$sformatf("LTSSM_TRANSITION_L0_RECOVERY_ADVERTISING_NEXT_RATE=%s",
                     rc_adv_rate.name()),UVM_LOW)
        end
        else begin
        // LINK UP
        link_up = 1'b1;
        `uvm_info("RC_LTSSM","LINK_UP=1",UVM_LOW)
        `uvm_info("RC_LTSSM",$sformatf("FINAL_L0_REACHED_AT_RATE=%s",rc_cur_rate.name()),UVM_LOW)
        // INFORM DL THAT LINK IS UP
        uvm_rc_l0_to_dl_ev.trigger();
        `uvm_info("RC_LTSSM","RC_L0_TO_DL_EVENT_TRIGGERED",UVM_LOW)
        `uvm_info("RC_LTSSM","STARTING_RANDOM_DATA_GENERATION",UVM_LOW)
         //generate_random_data();
         `uvm_info("RC_LTSSM",$sformatf("RANDOM_DATA_READY_QUEUE_SIZE=%0d",tx_data_q.size()),UVM_LOW)
        // SELECT FLIT / NON-FLIT MODE
        //case (pcie_ecfg.mode);
        case (item.pkt_mode)
           NON_FLIT: begin
              `uvm_info("RC_LTSSM","L0_MODE=NON_FLIT_MODE",UVM_LOW)
               //rc_l0_non_flit_mode();
           end
           FLIT: begin
              `uvm_info("RC_LTSSM","L0_MODE=FLIT_MODE",UVM_LOW)
           end
           default: begin
                  `uvm_error("RC_LTSSM","INVALID_PCIE_MODE")
           end
        endcase
        end
    endtask

    task rc_l0_flit_mode();
        bit [`PCIe_MON_DATA_W-1:0] flit_data[`PCIe_FLIT_DWORDS+3];
        `uvm_info("RC_PL","STARTING_ONE_FLIT",UVM_LOW)
        if (tx_data_q.size() < `PCIe_FLIT_DWORDS+3) begin
           `uvm_info("RC_PL",$sformatf("NOT_ENOUGH_DATA_QUEUE_SIZE=%0d",tx_data_q.size()),UVM_LOW)
           return;
        end
        // Collect 64 DWORD
        for (int i = 0; i < `PCIe_FLIT_DWORDS+3; i++) begin
           flit_data[i] = tx_data_q.pop_front();
           `uvm_info("RC_PL",$sformatf("FLIT_DWORD_%0d=%08h",i,flit_data[i]),UVM_LOW)
        end
        `uvm_info("RC_PL","64_DWORDS_COLLECTED_FLIT_READY",UVM_LOW)
        // Send FLIT
        for (int i = 0; i < `PCIe_FLIT_DWORDS+3; i++) begin
           rc_pipe_intf_tx.tx_data  <= flit_data[i];
           rc_pipe_intf_tx.tx_valid <= 1'b1;
           `uvm_info("RC_PL",$sformatf("FLIT_TX_DWORD_%0d=%08h",i,flit_data[i]),UVM_LOW)
           @(negedge rc_pipe_intf_tx.pclk);
        end
        rc_pipe_intf_tx.tx_valid <= 1'b0;
        `uvm_info("RC_PL","ONE_FLIT_TRANSMISSION_COMPLETED",UVM_LOW)
    endtask

    task rc_l0_non_flit_mode();
       bit [31:0] tx_data;
       int data_count;
       data_count = 0;
       `uvm_info("RC_PL","STARTING_NON_FLIT_MODE",UVM_LOW)
       `uvm_info("RC_PL",$sformatf("NON_FLIT_QUEUE_SIZE=%0d",tx_data_q.size()),UVM_LOW)
       if (tx_data_q.size() == 0) begin
          `uvm_info("RC_PL","NON_FLIT_NO_DATA_AVAILABLE",UVM_LOW)
          return;
       end
       // SEND DATA DIRECTLY
       while (tx_data_q.size() > 0) begin
          // Get one DWORD
          tx_data = tx_data_q.pop_front();
          // Drive PIPE interface
          rc_pipe_intf_tx.tx_data  <= tx_data;
          rc_pipe_intf_tx.tx_valid <= 1'b1;
          data_count++;
          `uvm_info("RC_PL",$sformatf("NON_FLIT_TX_DWORD_%0d=%08h",data_count,tx_data),UVM_LOW)
          @(negedge rc_pipe_intf_tx.pclk);
       end
       rc_pipe_intf_tx.tx_valid <= 1'b0;
       rc_pipe_intf_tx.tx_data  <= '0;
       `uvm_info("RC_PL",$sformatf("NON_FLIT_TRANSMISSION_COMPLETED_TOTAL_DWORDS=%0d",data_count),UVM_LOW)
    endtask

    task build_rc_ts1();
        rc_ts1_os[0]  = 8'hBC;
        rc_ts1_os[1]  = rc_link_num;
        rc_ts1_os[2]  = rc_lane_num;
        rc_ts1_os[3]  = 8'h10;
        rc_ts1_os[4]  = 8'h00;
        rc_ts1_os[5]  = 8'h00;
        rc_ts1_os[6]  = 8'h00;
        rc_ts1_os[7]  = 8'h4A;
        rc_ts1_os[8]  = 8'h4A;
        rc_ts1_os[9]  = 8'h4A;
        rc_ts1_os[10] = 8'h4A;
        rc_ts1_os[11] = 8'h4A;
        rc_ts1_os[12] = 8'h4A;
        rc_ts1_os[13] = 8'h4A;
        rc_ts1_os[14] = 8'h4A;
        rc_ts1_os[15] = 8'h4A;
        
        for (int i = 0; i < 16; i++) begin
            `uvm_info("RC_TS1",$sformatf("TS1[%0d] = 0x%02h",i, rc_ts1_os[i]),UVM_LOW)
        end
    endtask

    task build_rc_ts2();
         rc_ts2_os[0]  = 8'h39;
         rc_ts2_os[1]  = rc_link_num;
         rc_ts2_os[2]  = rc_lane_num;
         rc_ts2_os[3]  = 8'h00;
         rc_ts2_os[4]  = 8'h00;
         rc_ts2_os[5]  = 8'h00;
         rc_ts2_os[6]  = 8'h00;
         rc_ts2_os[7]  = 8'h00;
         rc_ts2_os[8]  = 8'h39;
         rc_ts2_os[9]  = rc_link_num;
         rc_ts2_os[10] = rc_lane_num;
         rc_ts2_os[11] = 8'h00;
         rc_ts2_os[12] = 8'h00;
         rc_ts2_os[13] = 8'h00;
         rc_ts2_os[14] = 8'h00;
         rc_ts2_os[15] = 8'h00;
        
         for (int i = 0; i < 16; i++) begin
            `uvm_info("RC_LTSSM",$sformatf("TS2[%0d] = %02h",i,rc_ts2_os[i]),UVM_LOW)
         end
    endtask

    /*task print_ts2();
        `uvm_info("RC_LTSSM","========== RC TS2 ORDERED SET ==========",UVM_LOW)
        for (int i = 0; i < 16; i++) begin
            `uvm_info("RC_LTSSM",$sformatf("TS2[%0d] = %02h",i,rc_ts2_os[i]),UVM_LOW)
        end
        `uvm_info("RC_LTSSM","========================================",UVM_LOW)
    endtask*/

    task build_rc_idle();
        for (int i = 0; i < 16; i++) begin
            rc_idle_os[i] = 8'h00;
        end
    endtask

    task print_idle();
        `uvm_info("RC_LTSSM","========== RC IDLE FLIT ==========",UVM_LOW)
        for (int i = 0; i < 16; i++) begin
            `uvm_info("RC_LTSSM",$sformatf("IDLE[%0d] = 0x%02h",i,rc_idle_os[i]),UVM_LOW)
        end
        `uvm_info("RC_LTSSM","========================================",UVM_LOW)
    endtask

    task rc_check_ep_ts1(input int count,output bit rx_done);
      bit [1:0] rx_symbol;
      int ts1_count;
      rx_done   = 1'b0;
      ts1_count = 0;
      `uvm_info("RC_LTSSM",$sformatf("WAITING_FOR_%0d_TS1_FROM_EP",count),UVM_LOW)
      forever begin
         @(negedge rc_pipe_intf_rx.pclk);
         if (rc_pipe_intf_rx.rx_valid) begin
            rx_symbol = rc_pipe_intf_rx.rx_data[1:0];
            if (rx_symbol == 2'b11) begin
               ts1_count++;
               `uvm_info("RC_LTSSM",$sformatf("TS1_FIRST_SYMBOL_DETECTED = %02b COUNT = %0d",rx_symbol, ts1_count),UVM_LOW)
            end
            if (ts1_count >= count) begin
               `uvm_info("RC_LTSSM",$sformatf("%0d_TS1_RECEIVED_FROM_EP",count),UVM_LOW)
               rx_done = 1'b1;
               break;
            end
         end
      end
    endtask

    task rc_check_ep_ts2(input int count,output bit rx_done);
       bit [1:0] rx_symbol;
       int ts2_count;
       rx_done   = 1'b0;
       ts2_count = 0;
       `uvm_info("RC_LTSSM",$sformatf("WAITING_FOR_%0d_TS2_FROM_EP",count),UVM_LOW)
       forever begin
          @(negedge rc_pipe_intf_rx.pclk);
          if (rc_pipe_intf_rx.rx_valid) begin
             rx_symbol = rc_pipe_intf_rx.rx_data[1:0];
             if (rx_symbol == 2'b10) begin
                ts2_count++;
                `uvm_info("RC_LTSSM",$sformatf("TS2_FIRST_SYMBOL_DETECTED = %02b COUNT = %0d",rx_symbol, ts2_count),UVM_LOW)
             end
             if (ts2_count >= count) begin
                `uvm_info("RC_LTSSM",$sformatf("%0d_TS2_RECEIVED_FROM_EP",count),UVM_LOW)
                rx_done = 1'b1;
                break;
             end
          end
       end
    endtask

    task rc_check_ep_idle(input int count, output bit rx_done);
       bit [1:0] rx_symbol;
       int idle_count;
       rx_done   = 1'b0;
       idle_count = 0;
       `uvm_info("RC_LTSSM",$sformatf("WAITING_FOR_%0d_IDLE_FROM_EP", count),UVM_LOW)
       forever begin
          @(negedge rc_pipe_intf_rx.pclk);
          if (rc_pipe_intf_rx.rx_valid) begin
             rx_symbol = rc_pipe_intf_rx.rx_data[1:0];
             if (rx_symbol == 2'b00) begin
               idle_count++;
               `uvm_info("RC_LTSSM",$sformatf("IDLE_FIRST_SYMBOL_DETECTED = %02b COUNT = %0d",rx_symbol, idle_count),UVM_LOW)
            end
            if (idle_count >= count) begin
               `uvm_info("RC_LTSSM",$sformatf("%0d_IDLE_RECEIVED_FROM_EP", count),UVM_LOW)
               rx_done = 1'b1;
               break;
            end
         end
       end
    endtask

    //=======================================================================
    //        RECOVERY SUBSTATES  -  PCIe Base 6.0 Section 4.2.7.4
    //=======================================================================

    //-------------------------------------------------------------------------
    // rc_rate_to_dri / rc_dri_to_rate - PIPE rate label <-> TS Data Rate
    // Identifier (symbol 4 bits [5:1], Table 4-26)
    //-------------------------------------------------------------------------
    function bit [`PCIe_DRI_RATE_W-1:0] rc_rate_to_dri(pcie_link_rate_e r);
       case (r)
          RATE_GEN2   : return `PCIe_DRI_GEN2;
          RATE_GEN3   : return `PCIe_DRI_GEN3;
          RATE_GEN4   : return `PCIe_DRI_GEN4;
          RATE_GEN5   : return `PCIe_DRI_GEN5;
          RATE_GEN6   : return `PCIe_DRI_GEN6;
          default     : return `PCIe_DRI_GEN1;
       endcase
    endfunction

    function pcie_link_rate_e rc_dri_to_rate(bit [`PCIe_DRI_RATE_W-1:0] dri);
       case (dri)
          `PCIe_DRI_GEN2 : return RATE_GEN2;
          `PCIe_DRI_GEN3 : return RATE_GEN3;
          `PCIe_DRI_GEN4 : return RATE_GEN4;
          `PCIe_DRI_GEN5 : return RATE_GEN5;
          `PCIe_DRI_GEN6 : return RATE_GEN6;
          default        : return RATE_GEN1;
       endcase
    endfunction

    //-------------------------------------------------------------------------
    // rc_rate_gen_num / rc_rate_of_gen - generation number 1..6 <-> rate
    //-------------------------------------------------------------------------
    function int rc_rate_gen_num(pcie_link_rate_e r);
       case (r)
          RATE_GEN1 : return 1;
          RATE_GEN2 : return 2;
          RATE_GEN3 : return 3;
          RATE_GEN4 : return 4;
          RATE_GEN5 : return 5;
          RATE_GEN6 : return 6;
          default   : return 1;
       endcase
    endfunction

    function pcie_link_rate_e rc_rate_of_gen(int gen);
       case (gen)
          1       : return RATE_GEN1;
          2       : return RATE_GEN2;
          3       : return RATE_GEN3;
          4       : return RATE_GEN4;
          5       : return RATE_GEN5;
          default : return RATE_GEN6;
       endcase
    endfunction

    //-------------------------------------------------------------------------
    // rc_tx_ts1 - TS1 carrying the advertised rate and the Equalization
    //   Control / Coefficient symbols. build_rc_ts1() fills in the common
    //   layout, this only stamps the two Recovery-specific symbols.
    //-------------------------------------------------------------------------
    task rc_build_recovery_ts1();
       // NOTE: previous_symbol is deliberately NOT reset here. The pre-coder
       // chain in send_ordered_set() is continuous across Ordered Sets, so
       // restarting it here would de-precoder/desynchronise the peer.
       build_rc_ts1();
       // Symbol 4 : {2'b00, Data Rate Identifier [5:1], speed_change}
       rc_ts1_os[`PCIe_OS_SYM_RATE_ID] = {2'b00, rc_rate_to_dri(rc_adv_rate), rc_speed_change};
       // Symbol 5 : Equalization Control field in bits [1:0]
       rc_ts1_os[`PCIe_OS_SYM_EQ_CTRL] = {6'b000000, rc_eq_phase};
       // Symbol 6 : Preset / coefficient
       rc_ts1_os[`PCIe_OS_SYM_EQ_COEF] = 8'h00;
       `uvm_info("RC_RECOVERY",$sformatf("TS1_RATE_ID_SYMBOL=0x%02h SPEED_CHANGE=%0b EQ_PHASE=%0d",
                 rc_ts1_os[`PCIe_OS_SYM_RATE_ID], rc_speed_change, rc_eq_phase),UVM_LOW)
    endtask

    //-------------------------------------------------------------------------
    // rc_build_recovery_ts2 - TS2 carrying the advertised rate. Symbols other
    //   than 4 are left exactly as build_rc_ts2() produces them, so the
    //   Training Control check already present in Polling.Configuration
    //   keeps working unchanged.
    //-------------------------------------------------------------------------
    task rc_build_recovery_ts2();
       // previous_symbol stays continuous - see rc_build_recovery_ts1().
       build_rc_ts2();
       // Symbol 4 : {2'b00, Data Rate Identifier [5:1], speed_change}
       rc_ts2_os[`PCIe_OS_SYM_RATE_ID] = {2'b00, rc_rate_to_dri(rc_adv_rate), rc_speed_change};
       `uvm_info("RC_RECOVERY",$sformatf("TS2_RATE_ID_SYMBOL=0x%02h SPEED_CHANGE=%0b",
                 rc_ts2_os[`PCIe_OS_SYM_RATE_ID], rc_speed_change),UVM_LOW)
    endtask

    //-------------------------------------------------------------------------
    // rc_rx_descramble_byte - inverse of scramble(), advances rc_rx_lfsr
    //-------------------------------------------------------------------------
    task rc_rx_descramble_byte(input bit [7:0] data_in, output bit [7:0] data_out);
       bit descramble_bit;
       data_out = data_in;
       for (int i = 0; i < `PCIe_BYTE_W; i++) begin
          descramble_bit = rc_rx_lfsr[`PCIe_PL_SCRAMBLER_LFSR_W-1];
          data_out[i] = data_in[i] ^ descramble_bit;
          if (descramble_bit)
             rc_rx_lfsr = (rc_rx_lfsr << 1) ^ polynomial;
          else
             rc_rx_lfsr = (rc_rx_lfsr << 1);
       end
    endtask

    //-------------------------------------------------------------------------
    // There used to be a rc_rx_lfsr_skip() here that advanced the receive
    // descrambler by `PCIe_OS_LFSR_STEPS (104) on every rejected window, on the
    // reasoning that a receive window is 4 PIPE dwords = 16 consecutive symbol
    // slots, that any 16 consecutive slots contain exactly one slot of each
    // residue mod 16, and that the transmitter therefore always takes exactly 3
    // bypasses and 104 scrambler steps per window.
    //
    // The residue argument is sound but the premise is not. The transmitter
    // chooses its bypass slots from the absolute symbol index *within its own
    // Ordered Set*, so the "exactly 3 bypasses" result only holds while all 16
    // slots really are one Ordered Set. A rejected window can straddle two
    // Ordered Sets, or contain peer data, where there are no bypass slots at all
    // (32 steps per dword instead of 104 per 4 dwords). Since the window slides
    // one dword at a time, a single 8-dword RECOVERY_IDLE burst was charged 8
    // x 104 = 832 steps against the transmitter's 2 x 104 = 208, and the
    // descrambler was 78 bytes out of phase before the first Rate Identifier
    // that mattered. The receive side now leaves the phase alone on a reject and
    // lets rc_rx_os_phase_solve() re-acquire it from the next accepted Ordered
    // Set, which is self-correcting and needs no assumption about what the peer
    // sent.
    //-------------------------------------------------------------------------

    //-------------------------------------------------------------------------
    // rc_rx_lfsr_advance - step a COPY of the scrambler state forward. Used by
    // the phase search, which must not disturb the live receive phase.
    //-------------------------------------------------------------------------
    function automatic bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] rc_rx_lfsr_advance(
             input bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] s, input int nbits);
       bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] x;
       x = s;
       for (int i = 0; i < nbits; i++)
          x = x[`PCIe_PL_SCRAMBLER_LFSR_W-1] ? ((x << 1) ^ polynomial) : (x << 1);
       return x;
    endfunction

    //-------------------------------------------------------------------------
    // rc_rx_lfsr_retreat - step a COPY of the scrambler state BACKWARD.
    //
    // The forward step is  msb = s[W-1]; s = (s << 1) ^ (msb ? POLY : 0).
    // Undoing it needs msb, and the two taps that recover it are POLY[1] = 0 and
    // POLY[0] = 1:
    //     new[0] = s[0] ^ msb      and      s[0] = new[1] ^ (msb & POLY[1])
    //  =>        msb   = new[0] ^ new[1]
    // and then, for m = 0 .. W-2,  s[m] = new[m+1] ^ (msb & POLY[m+1]),  with
    // s[W-1] = msb.
    //
    // This is only used by the phase search, which has to be able to look
    // backwards as well as forwards. See PCIe_RX_LFSR_PHASE_SEARCH.
    //-------------------------------------------------------------------------
    function automatic bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] rc_rx_lfsr_retreat(
             input bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] s, input int nbits);
       bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] x;
       bit msb;
       for (int n = 0; n < nbits; n++) begin
          msb = s[0] ^ s[1];
          for (int m = 0; m < (`PCIe_PL_SCRAMBLER_LFSR_W - 1); m++)
             x[m] = s[m + 1] ^ (msb & polynomial[m + 1]);
          x[`PCIe_PL_SCRAMBLER_LFSR_W-1] = msb;
          s = x;
       end
       return s;
    endfunction

    //-------------------------------------------------------------------------
    // rc_rx_descramble_byte_s - rc_rx_descramble_byte() on a scratch copy of
    // the scrambler state, returning the state after the byte.
    //-------------------------------------------------------------------------
    function automatic bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] rc_rx_descramble_byte_s(
             input  bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] s,
             input  bit [`PCIe_BYTE_W-1:0]               d,
             output bit [`PCIe_BYTE_W-1:0]               dout);
       bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] x;
       bit db;
       x    = s;
       dout = d;
       for (int i = 0; i < `PCIe_BYTE_W; i++) begin
          db     = x[`PCIe_PL_SCRAMBLER_LFSR_W-1];
          dout[i] = d[i] ^ db;
          x      = db ? ((x << 1) ^ polynomial) : (x << 1);
       end
       return x;
    endfunction

    //-------------------------------------------------------------------------
    // rc_rx_os_content_ok - is this descrambled Ordered Set self consistent?
    //
    // The pre-coder entry state is solved from byte 0, which is a bypass slot and
    // so says nothing about the scrambler. Once a window has been accepted as an
    // Ordered Set, though, the descrambled CONTROL symbols are almost entirely
    // determined by the type, which gives a very strong check on whether the
    // descrambler phase is right:
    //
    //   TS1  0xBC : s3=0x10  s5..s6=0x00  s7=0x4A  s11..s14=0x4A
    //   TS2  0x39 : s3=0x00  s5..s6=0x00  s7=0x00  s11..s14=0x00
    //   IDLE 0x4A : s1..s7=0x00                            s11..s14=0x00
    //
    // Symbol 4 is the Data Rate Identifier {2'b00, dri, speed_change}, so its
    // top bit is always 0. A wrong phase produces random bytes, so requiring
    // six to eight exact matches plus that reserved bit is decisive: the chance
    // of a false match is on the order of 2**-48.
    //
    // Symbols 1, 2, 9 and 10 (link number and lane number) are deliberately not
    // checked, because a receiver is not entitled to assume what they are.
    //-------------------------------------------------------------------------
    function automatic bit rc_rx_os_content_ok(bit [7:0] k, bit [7:0] s [`PCIe_TS_OS_SIZE]);
       bit ok;
       ok = 1'b1;
       if (s[`PCIe_OS_SYM_RATE_ID][7] != 1'b0) ok = 1'b0;
       case (k)
         `PCIe_OS_SYM0_TS1: begin
            if (s[3]  != 8'h10) ok = 1'b0;
            if (s[5]  != 8'h00) ok = 1'b0;
            if (s[6]  != 8'h00) ok = 1'b0;
            if (s[7]  != 8'h4A) ok = 1'b0;
            if (s[11] != 8'h4A) ok = 1'b0;
            if (s[12] != 8'h4A) ok = 1'b0;
            if (s[13] != 8'h4A) ok = 1'b0;
            if (s[14] != 8'h4A) ok = 1'b0;
         end
         `PCIe_OS_SYM0_TS2: begin
            if (s[3]  != 8'h00) ok = 1'b0;
            if (s[5]  != 8'h00) ok = 1'b0;
            if (s[6]  != 8'h00) ok = 1'b0;
            if (s[7]  != 8'h00) ok = 1'b0;
            if (s[11] != 8'h00) ok = 1'b0;
            if (s[12] != 8'h00) ok = 1'b0;
            if (s[13] != 8'h00) ok = 1'b0;
            if (s[14] != 8'h00) ok = 1'b0;
         end
         default: begin
            if (s[1]  != 8'h00) ok = 1'b0;
            if (s[2]  != 8'h00) ok = 1'b0;
            if (s[3]  != 8'h00) ok = 1'b0;
            if (s[5]  != 8'h00) ok = 1'b0;
            if (s[6]  != 8'h00) ok = 1'b0;
            if (s[7]  != 8'h00) ok = 1'b0;
            if (s[11] != 8'h00) ok = 1'b0;
            if (s[12] != 8'h00) ok = 1'b0;
            if (s[13] != 8'h00) ok = 1'b0;
            if (s[14] != 8'h00) ok = 1'b0;
         end
       endcase
       return ok;
    endfunction

    //-------------------------------------------------------------------------
    // rc_rx_os_phase_solve - re-acquire the descrambler phase, then leave
    // rc_rx_lfsr positioned so the caller can descramble the 13 non K bytes with
    // the normal rc_rx_descramble_byte() path and keep the bookkeeping exact.
    //
    // Why this is needed: the transmit scrambler is ONE continuous LFSR shared by
    // the Ordered Set path and by scramble_32() on the data path. An Ordered Set
    // window costs it 104 steps, a data window costs it 128. The receiver cannot
    // tell them apart before it has decoded something, so a nominal phase that
    // always assumes 104 permanently under-counts, and the first stretch of data
    // dwords on the wire desynchronises the descrambler for good. That is what
    // made the decoded Data Rate Identifier come out near-uniform over all 32
    // values while build_rc_ts1/ts2() were putting the correct rate on the wire.
    //
    // A window can never cost FEWER than 104 steps, so the true phase is never
    // behind the nominal one and only needs searching forward, in byte units.
    //-------------------------------------------------------------------------
    task rc_rx_os_phase_solve(input bit [7:0] k, input bit [7:0] cs [`PCIe_TS_OS_SIZE]);
       bit [`PCIe_PL_SCRAMBLER_LFSR_W-1:0] st;
       bit [7:0] tmp [`PCIe_TS_OS_SIZE];
       bit [7:0] diag [`PCIe_TS_OS_SIZE];
       bit [7:0] cand_sym_d0;
       bit [7:0] cand_sym_d8;
       int  kk;
       int  best;
       int  hits;
       bit  got;

       cand_sym_d0 = cs[0];
       cand_sym_d8 = cs[8];
       got  = 1'b0;
       best = 0;
       hits = 0;
       for (kk = -`PCIe_RX_LFSR_PHASE_SEARCH; kk <= `PCIe_RX_LFSR_PHASE_SEARCH; kk++) begin
          st = (kk >= 0) ? rc_rx_lfsr_advance(rc_rx_lfsr, kk * 8)
                         : rc_rx_lfsr_retreat(rc_rx_lfsr, -kk * 8);
          for (int z = 0; z < `PCIe_TS_OS_SIZE; z++) tmp[z] = 8'h00;
          for (int z = 0; z < `PCIe_TS_OS_SIZE; z++) begin
             if ((z == `PCIe_OS_BYPASS_IDX_0) ||
                 (z == `PCIe_OS_BYPASS_IDX_1) ||
                 (z == `PCIe_OS_BYPASS_IDX_2))
                tmp[z] = cs[z];
             else
                st = rc_rx_descramble_byte_s(st, cs[z], tmp[z]);
          end
          if (rc_rx_os_content_ok(k, tmp)) begin
             if (!got) begin
                got  = 1'b1;
                best = kk;
             end
             hits++;
          end
       end

       if (got) begin
          rc_rx_lfsr = (best >= 0) ? rc_rx_lfsr_advance(rc_rx_lfsr, best * 8)
                                   : rc_rx_lfsr_retreat(rc_rx_lfsr, -best * 8);
          if (best != 0)
             `uvm_info("RC_RECOVERY_RX_OS",$sformatf(
                       "DESCRAMBLER_RELOCKED SYM0=0x%02h OFFSET_BYTES=%0d OTHER_MATCHES=%0d",
                       k, best, hits - 1),UVM_LOW)
       end
       else begin
          // Diagnostic: descramble at the nominal phase and show what came out.
          // A wrong phase gives noise here. Correct values at 3/5/6/7 but a
          // mismatch against the case above would instead mean the window is not
          // a real Ordered Set at all.
          st = rc_rx_lfsr;
          for (int z = 0; z < `PCIe_TS_OS_SIZE; z++) diag[z] = 8'h00;
          for (int z = 0; z < `PCIe_TS_OS_SIZE; z++) begin
             if ((z == `PCIe_OS_BYPASS_IDX_0) ||
                 (z == `PCIe_OS_BYPASS_IDX_1) ||
                 (z == `PCIe_OS_BYPASS_IDX_2))
                diag[z] = cs[z];
             else
                st = rc_rx_descramble_byte_s(st, cs[z], diag[z]);
          end
          `uvm_info("RC_RECOVERY_RX_OS",$sformatf(
                    "DESCRAMBLER_PHASE_NOT_FOUND SYM0=0x%02h BYTE0=%02h BYTE8=%02h " ,
                    k, cand_sym_d0, cand_sym_d8),UVM_LOW)
          `uvm_info("RC_RECOVERY_RX_OS",$sformatf(
                    "DESCRAMBLER_PHASE_NOT_FOUND s3=%02h s4=%02h s5=%02h s6=%02h s7=%02h s11=%02h s14=%02h",
                    diag[3], diag[4], diag[5], diag[6], diag[7], diag[11], diag[14]),UVM_LOW)
       end
    endtask

    //-------------------------------------------------------------------------
    // rc_rx_gray_decode_byte - inverse of the transmit gray encoder
    //-------------------------------------------------------------------------
    function automatic bit [7:0] rc_rx_gray_decode_byte(bit [7:0] g);
       bit [7:0] p;
       p = '0;
       for (int i = 0; i < 8; i += 2) begin
          case (g[i +: 2])
            2'b11   : p[i +: 2] = 2'b10;
            2'b10   : p[i +: 2] = 2'b11;
            default : p[i +: 2] = g[i +: 2];
          endcase
       end
       return p;
    endfunction

    //-------------------------------------------------------------------------
    // rc_rx_os_k_valid - is this decoded first symbol a legal Ordered Set
    // K symbol? TS1 = 0xBC, TS2 = 0x39, IDLE = 0x4A.
    //-------------------------------------------------------------------------
    function automatic bit rc_rx_os_k_valid(bit [7:0] s);
       return (s == `PCIe_OS_SYM0_TS1) ||
              (s == `PCIe_OS_SYM0_TS2) ||
              (s == `PCIe_OS_SYM0_IDLE);
    endfunction

    //-------------------------------------------------------------------------
    // rc_rx_os_bs_valid - is byte 8 a legal second symbol?
    //
    // Byte 8 repeats the structure of byte 0 but is NOT always a K symbol:
    //   build_*_ts1()  byte 0 = 0xBC, byte 8 = 0x4A
    //   build_*_ts2()  byte 0 = 0x39, byte 8 = 0x39
    //   build_*_idle() byte 0 = 0x4A, byte 8 = 0x00
    // so all three K symbols plus 0x00 have to be accepted here. A previous
    // version pinned byte 8 to 0x4A and that silently rejected every TS2, which
    // stalled Recovery.RcvrCfg waiting for a Data Rate Identifier.
    //
    // The pre-coder chain is only entered once, at group 0 - sym_prev is then
    // overwritten with the raw group - so byte 8 does not depend on the entry
    // state at all. That makes it a clean "is this really an Ordered Set" filter
    // that cannot be faked by picking a different entry state.
    //-------------------------------------------------------------------------
    function automatic bit rc_rx_os_bs_valid(bit [7:0] s);
       return (s == `PCIe_OS_SYM0_TS1) ||
              (s == `PCIe_OS_SYM0_TS2) ||
              (s == `PCIe_OS_SYM0_IDLE) ||
              (s == 8'h00);
    endfunction

    //-------------------------------------------------------------------------
    // rc_rx_os_decode - shift one received PIPE dword into the Ordered Set
    // window and try to decode a complete Ordered Set out of it.
    //
    // Decoding is deferred until four dwords are available, because the receive
    // side has no reliable way to know where an Ordered Set starts:
    //
    //   * rx_valid is driven from receive-queue occupancy in the PHY driver, and
    //     the serialiser backlog bridges the gap between two bursts, so rx_valid
    //     can stay asserted straight through a burst boundary.
    //   * Not every burst is a whole number of 16 symbol Ordered Sets, so a
    //     dword index that just free runs drifts out of step and never recovers.
    //
    // So the window slides instead. Every time four dwords are buffered the
    // Ordered Set is decoded, and if the group turns out not to be one the
    // oldest dword is dropped and the window slides on by one. This realigns
    // after any disturbance without depending on rx_valid edges at all.
    //-------------------------------------------------------------------------
    task rc_rx_os_decode();
       if (rc_rx_os_fill < (`PCIe_TS_OS_SIZE / 4)) begin
          rc_rx_os_raw[rc_rx_os_fill] = rc_pipe_intf_rx.rx_data;
          rc_rx_os_fill++;
       end
       else begin
          // window already holds four rejected dwords: slide it on by one
          for (int t = 0; t < ((`PCIe_TS_OS_SIZE / 4) - 1); t++)
             rc_rx_os_raw[t] = rc_rx_os_raw[t + 1];
          rc_rx_os_raw[`PCIe_TS_OS_SIZE / 4 - 1] = rc_pipe_intf_rx.rx_data;
       end
       if (rc_rx_os_fill == (`PCIe_TS_OS_SIZE / 4)) rc_rx_os_finish();
    endtask

    //-------------------------------------------------------------------------
    // rc_rx_os_finish - reverse process the four dword window as one Ordered
    // Set: de-precoder, gray decode, then descramble every byte whose symbol
    // index is not 0, 8 or 15.
    //
    // The pre-coder entry state is solved here rather than carried across
    // Ordered Sets. The pre-coder is a 2 bit state, so all four entry states are
    // tried and the one whose decoded byte 0 is a legal K symbol (0xbc / 0x39 /
    // 0x4a) and whose scrambler-bypassed filler K symbols at byte 8 and byte 15
    // both decode to 0x4a is kept. build_rc_ts1() / build_rc_ts2() /
    // build_rc_idle() fill bytes 8 and 15 with 8'h4a in every Ordered Set, so
    // that signature pins the entry state exactly.
    //-------------------------------------------------------------------------
    task rc_rx_os_finish();
       bit [7:0] cand_sym [`PCIe_TS_OS_SIZE];
       bit [7:0] win_sym  [`PCIe_TS_OS_SIZE];
       bit [7:0] b_acc;
       bit [7:0] pair;
       bit [1:0] sym_prev;
       bit [1:0] raw_g;
       bit [1:0] gray_g;
       bit [7:0] k_first;
       bit [7:0] unused;
       bit       cand_ok;
       int       cand_cnt;
       int       win;
       int       s;

       // ---- try all four pre-coder entry states ----
       cand_cnt = 0;
       win      = -1;
       k_first  = 8'h00;
       for (int p = 0; p < 4; p++) begin
          sym_prev = p[1:0];
          for (int z = 0; z < `PCIe_TS_OS_SIZE; z++) cand_sym[z] = 8'h00;
          for (int t = 0; t < (`PCIe_TS_OS_SIZE / 4); t++) begin
             for (int i = 0; i < `PCIe_MON_DATA_W; i += 2) begin
                raw_g       = rc_rx_os_raw[t][i +: 2];
                gray_g      = raw_g ^ sym_prev;
                sym_prev    = raw_g;
                // gray decode one 2 bit group. The group has to sit in the low
                // bits of the byte because that is where the group index i is.
                b_acc       = rc_rx_gray_decode_byte({6'b000000, gray_g});
                // a Verilog shift keeps the width of its left operand, so widen
                // the group to a full byte before shifting it into place
                pair        = b_acc[1:0];
                cand_sym[(t * 4) + (i / 8)] =
                    cand_sym[(t * 4) + (i / 8)] | (pair << (i % 8));
             end
          end
          cand_ok = rc_rx_os_k_valid(cand_sym[0]) &&
                    rc_rx_os_bs_valid(cand_sym[`PCIe_OS_BYPASS_IDX_1]);
          if (cand_ok) begin
             cand_cnt++;
             win     = p;
             k_first = cand_sym[0];
             // Keep the WINNING candidate. cand_sym is reused by the next
             // iteration of this loop, so after the loop it holds the LAST
             // candidate tried, not the accepted one. Descrambling cand_sym used
             // to be a real bug: it only looked right while the winning entry
             // state happened to be 2'b11 (p = 3), which is the value
             // `PCIe_INIT_PREVIOUS_SYMBOL re-arms the pre-coder to, so it was
             // correct for the first ~57 Ordered Sets and then every descrambled
             // symbol was noise. That is what made the Data Rate Identifier come
             // out near-uniform over all 32 values, and no scrambler phase can
             // repair de-precoded bytes that are already wrong.
             for (int z = 0; z < `PCIe_TS_OS_SIZE; z++) win_sym[z] = cand_sym[z];
          end
       end

       // ---- no legal entry state : not an Ordered Set, slide the window on ----
       if (cand_cnt == 0) begin
          // The receive descrambler is deliberately NOT advanced here. The old
          // code stepped `PCIe_OS_LFSR_STEPS (104) on every rejected window on
          // the assumption that "the transmitter still scrambled 13 bytes for
          // this window". That assumption is only true when the window really
          // is one 4-dword Ordered Set. A rejected window can equally be peer
          // data (32 steps per dword, no bypass symbols) or part of a multi
          // Ordered Set burst - and because the window slides one dword at a
          // time, one 8-dword RECOVERY_IDLE burst produced 8 rejected windows
          // = 832 steps against the transmitter's 2 x 104 = 208. That 624 step
          // (78 byte) overshoot per IDLE burst is what drove the phase away: it
          // was already hopeless after the first few IDLE bursts, which is why
          // DRI decoded cleanly for the first ~57 Ordered Sets and was then
          // noise for the rest, and why a +/-200 byte phase search found nothing.
          //
          // Nothing is lost by leaving the phase alone here. The phase is
          // re-acquired from scratch by rc_rx_os_phase_solve() on the next
          // Ordered Set that does pass framing, and PCIe_RX_LFSR_PHASE_SEARCH
          // only has to cover one gap between two accepted Ordered Sets.
          for (int t = 0; t < ((`PCIe_TS_OS_SIZE / 4) - 1); t++)
             rc_rx_os_raw[t] = rc_rx_os_raw[t + 1];
          rc_rx_os_fill--;
          `uvm_info("RC_RECOVERY_RX_OS","UNSOLVABLE_OS_SLIDING_WINDOW",UVM_LOW)
          return;
       end
       if (cand_cnt > 1)
          `uvm_info("RC_RECOVERY_RX_OS",$sformatf("AMBIGUOUS_OS_SYM0=0x%02h CANDIDATES=%0d USING_ENTRY=%0d", k_first, cand_cnt, win),UVM_LOW)

       // ---- re-acquire the descrambler phase, then descramble the 13 non K bytes ----
       rc_rx_os_phase_solve(k_first, win_sym);
       for (s = 0; s < `PCIe_TS_OS_SIZE; s++) begin
          if ((s == `PCIe_OS_BYPASS_IDX_0) ||
              (s == `PCIe_OS_BYPASS_IDX_1) ||
              (s == `PCIe_OS_BYPASS_IDX_2))
             rc_rx_os_sym[s] = win_sym[s];
          else
             rc_rx_descramble_byte(win_sym[s], rc_rx_os_sym[s]);
       end

       // ---- capture the peer's Data Rate Identifier ----
       rc_rx_os_active    = 1'b0;
       rc_rx_os_fill      = 0;
       rc_rx_os_sym0      = k_first;
       rc_rx_dri_rate     = rc_rx_os_sym[`PCIe_OS_SYM_RATE_ID] >> `PCIe_DRI_RATE_SHIFT;
       rc_rx_speed_change = rc_rx_os_sym[`PCIe_OS_SYM_RATE_ID][`PCIe_DRI_SPEED_CHANGE_BIT];
       case (k_first)
         `PCIe_OS_SYM0_TS1  : rc_rx_ts1_count++;
         `PCIe_OS_SYM0_TS2  : rc_rx_ts2_count++;
         `PCIe_OS_SYM0_IDLE : rc_rx_idle_count++;
         default            : ;
       endcase
       `uvm_info("RC_RECOVERY_RX_OS",$sformatf("DECODED_PEER_OS_SYM0=0x%02h TS1_CNT=%0d TS2_CNT=%0d IDLE_CNT=%0d",
                 k_first, rc_rx_ts1_count, rc_rx_ts2_count, rc_rx_idle_count),UVM_LOW)
       `uvm_info("RC_RECOVERY_RX_OS",$sformatf("DECODED_PEER_OS_RATE_ID_SYMBOL=0x%02h DRI=%05b SPEED_CHANGE=%0b",
                 rc_rx_os_sym[`PCIe_OS_SYM_RATE_ID], rc_rx_dri_rate, rc_rx_speed_change),UVM_LOW)
    endtask

    //-------------------------------------------------------------------------
    // rc_check_ep_ts2_rate - count `count` consecutive TS2 from the EP and
    //   leave the peer's advertised rate in rc_rx_dri_rate. Identical K-symbol
    //   rule to rc_check_ep_ts2(); the rate itself is taken from the shared
    //   Ordered Set decoder.
    //-------------------------------------------------------------------------
    task rc_check_ep_ts2_rate(input int count, output bit rx_done);
       bit [1:0] rx_symbol;
       int ts2_count;
       rx_done   = 1'b0;
       ts2_count = 0;
       `uvm_info("RC_RECOVERY",$sformatf("WAITING_FOR_%0d_TS2_FROM_EP",count),UVM_LOW)
       forever begin
          @(negedge rc_pipe_intf_rx.pclk);
          if (rc_pipe_intf_rx.rx_valid) begin
             rx_symbol = rc_pipe_intf_rx.rx_data[1:0];
             if (rx_symbol == `PCIe_TS_K_SYMBOL_TS2)
               ts2_count++;
             if (ts2_count >= count) begin
                // Let the last received ordered set finish decoding so the
                // captured Data Rate Identifier belongs to it.
                repeat (8) @(negedge rc_pipe_intf_rx.pclk);
                rx_done = 1'b1;
                `uvm_info("RC_RECOVERY",$sformatf("%0d_TS2_RECEIVED_FROM_EP_PEER_DRI=%05b",
                          count, rc_rx_dri_rate),UVM_LOW)
                break;
             end
          end
       end
    endtask

    //=======================================================================
    //  RECOVERY WAIT CONDITIONS ON THE DECODED ORDERED SET STREAM
    //=======================================================================
    // The tasks above (rc_check_ep_ts1 / _ts2 / _idle) test the RAW PIPE
    // symbol against a K symbol. That only works while the transmit
    // pre-coder chain happens to be restarted with previous_symbol = 2'b11
    // at the start of every burst, which is what the Detect / Polling /
    // Configuration substates do.
    //
    // Recovery must NOT do that. The pre-coder is a running differential
    // XOR chain that stays continuous across an entire speed change, so a
    // TS1 does not show up as a raw 2'b11. The raw test then matches a few
    // times by accident and stalls, which is what hung the link in
    // Equalization phase 2.
    //
    // The waiters below instead use the counters maintained by
    // rc_rx_os_decode(), which reverses the full transmit chain (de-precoder
    // -> gray decode -> descrambler) and classifies each Ordered Set on its
    // decoded symbol 0. Symbol 0 bypasses the scrambler, so that
    // classification needs no descrambler alignment and cannot false-fire
    // the way a comma aligner on an arbitrary training dword would.
    //
    // The counters are cumulative from reset, not per substate, so every
    // waiter takes a baseline sampled by the caller BEFORE the peer starts
    // its burst and waits for `count` increments relative to it.

    task rc_wait_ep_ts1_os(input int count, input int base_cnt, output bit rx_done);
       int now_cnt;
       rx_done = 1'b0;
       now_cnt = rc_rx_ts1_count;
       `uvm_info("RC_RECOVERY",$sformatf("WAITING_FOR_%0d_TS1_FROM_EP_DECODED_BASE_TS1_CNT=%0d",
                 count, base_cnt),UVM_LOW)
       forever begin
          @(negedge rc_pipe_intf_rx.pclk);
          if ((rc_rx_ts1_count - base_cnt) >= count) begin
             `uvm_info("RC_RECOVERY",$sformatf("%0d_DECODED_TS1_RECEIVED_FROM_EP NEW_TS1_CNT=%0d",
                       count, rc_rx_ts1_count-base_cnt),UVM_LOW)
             rx_done = 1'b1;
             break;
          end
       end
    endtask

    task rc_wait_ep_ts2_os_rate(input int count, input int base_cnt, output bit rx_done);
       rx_done = 1'b0;
       `uvm_info("RC_RECOVERY",$sformatf("WAITING_FOR_%0d_TS2_FROM_EP_DECODED_BASE_TS2_CNT=%0d",
                 count, base_cnt),UVM_LOW)
       forever begin
          @(negedge rc_pipe_intf_rx.pclk);
          if ((rc_rx_ts2_count - base_cnt) >= count) begin
             `uvm_info("RC_RECOVERY",$sformatf("%0d_DECODED_TS2_RECEIVED_FROM_EP_PEER_DRI=%05b NEW_TS2_CNT=%0d",
                       count, rc_rx_dri_rate, rc_rx_ts2_count-base_cnt),UVM_LOW)
             rx_done = 1'b1;
             break;
          end
       end
    endtask

    task rc_wait_ep_idle_os(input int count, input int base_cnt, output bit rx_done);
       rx_done = 1'b0;
       `uvm_info("RC_RECOVERY",$sformatf("WAITING_FOR_%0d_IDLE_FROM_EP_DECODED_BASE_IDLE_CNT=%0d",
                 count, base_cnt),UVM_LOW)
       forever begin
          @(negedge rc_pipe_intf_rx.pclk);
          if ((rc_rx_idle_count - base_cnt) >= count) begin
             `uvm_info("RC_RECOVERY",$sformatf("%0d_DECODED_IDLE_RECEIVED_FROM_EP NEW_IDLE_CNT=%0d",
                       count, rc_rx_idle_count-base_cnt),UVM_LOW)
             rx_done = 1'b1;
             break;
          end
       end
    endtask

    //-------------------------------------------------------------------------
    // rc_build_recovery_idle - IDLE Ordered Set for Recovery.Idle.
    //   build_rc_idle() emits an all-zero Ordered Set, which decodes on
    //   symbol 0 to 0x00 and would never match `PCIe_OS_SYM0_IDLE. The symbol
    //   0 of an IDLE Ordered Set is 0x4A, so Recovery.Idle stamps it here.
    //   The remaining symbols are left as build_rc_idle() produced them, so
    //   the Polling / Configuration path that shares build_rc_idle() is
    //   untouched.
    //-------------------------------------------------------------------------
    task rc_build_recovery_idle();
       build_rc_idle();
       rc_idle_os[0] = `PCIe_OS_SYM0_IDLE;
    endtask

    //-------------------------------------------------------------------------
    // rc_state_recovery_rcvrlock - Section 4.2.7.4.1
    //   Transmit 8 TS1 and wait for 8 consecutive TS1. Equalization is
    //   required when the link operates at 8 GT/s or above.
    //-------------------------------------------------------------------------
    task rc_state_recovery_rcvrlock(PCIe_sequence_item item);
       bit tx_ts1_done;
       bit rx_ts1_done;
       int  base_ts1;
       tx_ts1_done = 1'b0;
       rx_ts1_done = 1'b0;
       base_ts1    = rc_rx_ts1_count;
       `uvm_info("RC_RECOVERY","LTSSM_STATE_RECOVERY",UVM_LOW)
       `uvm_info("RC_RECOVERY","SUB_STATE_RECOVERY_RcvrLock",UVM_LOW)
       `uvm_info("RC_RECOVERY","==========================================",UVM_LOW)
       rc_build_recovery_ts1();
       fork : RC_RECOVERY_RCVR_LOCK_THREADS
          begin
             `uvm_info("RC_RECOVERY","STARTING_RC_8_TS1_TRANSMISSION",UVM_LOW)
             send_ordered_set(rc_ts1_os,`PCIe_RECOVERY_TS1_TX_COUNT,"RECOVERY_TS1");
             tx_ts1_done = 1'b1;
          end
          begin
             `uvm_info("RC_RECOVERY","WAITING_FOR_8_TS1_FROM_EP",UVM_LOW)
             rc_wait_ep_ts1_os(`PCIe_RECOVERY_TS1_RX_COUNT, base_ts1, rx_ts1_done);
          end
       join
       if (tx_ts1_done && rx_ts1_done) begin
          `uvm_info("RC_RECOVERY","8_TS1_TX_AND_8_TS1_RX_CONDITIONS_SATISFIED",UVM_LOW)
          // Equalization applies to the rate being moved to (8 GT/s and above)
          if (rc_rate_gen_num(rc_adv_rate) >= `PCIe_EQ_MIN_GEN) begin
             rc_recovery_state = RECOVERY_EQUALIZATION;
             rc_eq_phase       = EQ_PHASE_1;
             rc_eq_phase_count = 0;
             `uvm_info("RC_RECOVERY",$sformatf("EQUALIZATION_REQUIRED_AT_RATE=%s LTSSM_TRANSITION_RECOVERY_RcvrLock_Recovery_Equalization",
                       rc_adv_rate.name()),UVM_LOW)
          end
          else begin
             rc_recovery_state = RECOVERY_RCVR_CFG;
             `uvm_info("RC_RECOVERY",$sformatf("EQUALIZATION_NOT_REQUIRED_AT_RATE=%s LTSSM_TRANSITION_RECOVERY_RcvrLock_Recovery_RcvrCfg",
                       rc_adv_rate.name()),UVM_LOW)
          end
       end
       else begin
          `uvm_error("RC_RECOVERY","RECOVERY_RcvrLock_TX_RX_CONDITIONS_NOT_MET")
       end
    endtask

    //-------------------------------------------------------------------------
    // rc_state_recovery_equalization - Section 4.2.7.4.2
    //   Each Port runs Phases 1 to 3, exchanging 8 TS1 with the Equalization
    //   Control field set to the current phase.
    //-------------------------------------------------------------------------
    task rc_state_recovery_equalization(PCIe_sequence_item item);
       int phase;
       `uvm_info("RC_RECOVERY","LTSSM_STATE_RECOVERY",UVM_LOW)
       `uvm_info("RC_RECOVERY","SUB_STATE_RECOVERY_Equalization",UVM_LOW)
       `uvm_info("RC_RECOVERY",$sformatf("EQUALIZING_AT_RATE=%s",rc_cur_rate.name()),UVM_LOW)
       for (phase = 1; phase <= `PCIe_RECOVERY_EQ_PHASE_COUNT; phase++) begin
          bit tx_eq_done;
          bit rx_eq_done;
          int  base_ts1;
          tx_eq_done = 1'b0;
          rx_eq_done = 1'b0;
          base_ts1  = rc_rx_ts1_count;
          rc_eq_phase = equalization_phase_e'(phase);
          rc_build_recovery_ts1();
          fork : RC_RECOVERY_EQ_THREADS
             begin
                send_ordered_set(rc_ts1_os,`PCIe_RECOVERY_TS1_TX_COUNT,"RECOVERY_EQ_TS1");
                tx_eq_done = 1'b1;
             end
             begin
                rc_wait_ep_ts1_os(`PCIe_RECOVERY_TS1_RX_COUNT, base_ts1, rx_eq_done);
             end
          join
          if (tx_eq_done && rx_eq_done) begin
             rc_eq_phase_count++;
             `uvm_info("RC_RECOVERY",$sformatf("EQUALIZATION_PHASE_%0d_COMPLETED",phase),UVM_LOW)
          end
          else begin
             `uvm_error("RC_RECOVERY",$sformatf("EQUALIZATION_PHASE_%0d_TX_RX_CONDITIONS_NOT_MET",phase))
             break;
          end
       end
       if (rc_eq_phase_count >= `PCIe_RECOVERY_EQ_PHASE_COUNT) begin
          // Equalization Control returns to 00b outside of the EQ exchange
          rc_eq_phase       = EQ_PHASE_0;
          rc_recovery_state = RECOVERY_RCVR_CFG;
          `uvm_info("RC_RECOVERY","EQUALIZATION_COMPLETE LTSSM_TRANSITION_RECOVERY_Equalization_Recovery_RcvrCfg",UVM_LOW)
       end
    endtask

    //-------------------------------------------------------------------------
    // rc_state_recovery_speed - Section 4.2.7.4.3
    //   Reached only when the peer cannot reach the rate we advertised. The
    //   new rate is the highest common rate, and TS1s are exchanged at it
    //   before returning to Recovery.RcvrLock.
    //-------------------------------------------------------------------------
    task rc_state_recovery_speed(PCIe_sequence_item item);
       `uvm_info("RC_RECOVERY","LTSSM_STATE_RECOVERY",UVM_LOW)
       `uvm_info("RC_RECOVERY","SUB_STATE_RECOVERY_Speed",UVM_LOW)
       `uvm_info("RC_RECOVERY",$sformatf("PEER_ADVERTISED=%s WE_ADVERTISED=%s COMMON_RATE=%s",
                 rc_rx_adv_rate.name(), rc_adv_rate.name(), rc_agreed_rate.name()),UVM_LOW)
       rc_adv_rate       = rc_agreed_rate;
       rc_cur_rate       = rc_agreed_rate;
       rc_speed_change   = 1'b0;
       rc_pipe_intf_tx.rate <= rc_cur_rate;
       rc_recovery_state = RECOVERY_RCVR_LOCK;
       `uvm_info("RC_RECOVERY",$sformatf("SPEED_CHANGED_TO=%s LTSSM_TRANSITION_RECOVERY_Speed_Recovery_RcvrLock",
                 rc_cur_rate.name()),UVM_LOW)
    endtask

    //-------------------------------------------------------------------------
    // rc_state_recovery_rcvrcfg - Section 4.2.7.4.4
    //   Transmit 16 TS2 advertising the rate we want, receive 8 consecutive
    //   TS2, and settle on the highest common rate. A directed speed change
    //   re-locks at the new rate with speed_change cleared and comes back
    //   here to confirm before moving on to Recovery.Idle.
    //-------------------------------------------------------------------------
    task rc_state_recovery_rcvrcfg(PCIe_sequence_item item);
       bit tx_ts2_done;
       bit rx_ts2_done;
       int  base_ts2;
       tx_ts2_done = 1'b0;
       rx_ts2_done = 1'b0;
       base_ts2    = rc_rx_ts2_count;
       `uvm_info("RC_RECOVERY","LTSSM_STATE_RECOVERY",UVM_LOW)
       `uvm_info("RC_RECOVERY","SUB_STATE_RECOVERY_RcvrCfg",UVM_LOW)
       rc_build_recovery_ts2();
       fork : RC_RECOVERY_RCVR_CFG_THREADS
          begin
             `uvm_info("RC_RECOVERY","STARTING_RC_16_TS2_TRANSMISSION",UVM_LOW)
             send_ordered_set(rc_ts2_os,`PCIe_RECOVERY_TS2_TX_COUNT,"RECOVERY_TS2");
             tx_ts2_done = 1'b1;
          end
          begin
             `uvm_info("RC_RECOVERY","WAITING_FOR_8_TS2_FROM_EP",UVM_LOW)
             rc_wait_ep_ts2_os_rate(`PCIe_RECOVERY_TS2_RX_COUNT, base_ts2, rx_ts2_done);
          end
       join
       if (tx_ts2_done && rx_ts2_done) begin
          rc_rx_adv_rate = rc_dri_to_rate(rc_rx_dri_rate);
          // Highest common rate advertised by both ports
          if (rc_rate_gen_num(rc_rx_adv_rate) < rc_rate_gen_num(rc_adv_rate))
             rc_agreed_rate = rc_rx_adv_rate;
          else
             rc_agreed_rate = rc_adv_rate;
          `uvm_info("RC_RECOVERY",$sformatf("RATE_NEGOTIATION WE_ADVERTISE=%s PEER_ADVERTISES=%s AGREED=%s",
                    rc_adv_rate.name(), rc_rx_adv_rate.name(), rc_agreed_rate.name()),UVM_LOW)
          if (rc_rx_adv_rate != rc_adv_rate) begin
             rc_cur_rate = rc_agreed_rate;
             rc_pipe_intf_tx.rate <= rc_cur_rate;
             rc_recovery_state = RECOVERY_SPEED;
          end
          else if (rc_speed_change) begin
             // Speed change accepted : re-lock at the new rate with
             // speed_change cleared, then confirm in a second RcvrCfg
             rc_cur_rate       = rc_agreed_rate;
             rc_speed_change   = 1'b0;
             rc_eq_phase       = EQ_PHASE_0;
             rc_eq_phase_count = 0;
             rc_pipe_intf_tx.rate <= rc_cur_rate;
             rc_recovery_state = RECOVERY_RCVR_LOCK;
             `uvm_info("RC_RECOVERY",$sformatf("SPEED_CHANGE_ACCEPTED_NOW_AT=%s LTSSM_TRANSITION_RECOVERY_RcvrCfg_Recovery_RcvrLock",
                       rc_cur_rate.name()),UVM_LOW)
          end
          else begin
             rc_recovery_state = RECOVERY_IDLE;
             `uvm_info("RC_RECOVERY",$sformatf("RATE_CONFIRMED=%s LTSSM_TRANSITION_RECOVERY_RcvrCfg_Recovery_Idle",
                       rc_cur_rate.name()),UVM_LOW)
          end
       end
    endtask

    //-------------------------------------------------------------------------
    // rc_state_recovery_idle - Section 4.2.7.4.5
    //   2 IDLE in both directions, then L0.
    //-------------------------------------------------------------------------
    task rc_state_recovery_idle(PCIe_sequence_item item);
       bit tx_idle_done;
       bit rx_idle_done;
       int  base_idle;
       tx_idle_done = 1'b0;
       rx_idle_done = 1'b0;
       base_idle    = rc_rx_idle_count;
       `uvm_info("RC_RECOVERY","LTSSM_STATE_RECOVERY",UVM_LOW)
       `uvm_info("RC_RECOVERY","SUB_STATE_RECOVERY_Idle",UVM_LOW)
       previous_symbol = `PCIe_INIT_PREVIOUS_SYMBOL;
       rc_build_recovery_idle();
       fork : RC_RECOVERY_IDLE_THREADS
          begin
             `uvm_info("RC_RECOVERY","STARTING_RC_2_IDLE_TRANSMISSION",UVM_LOW)
             send_ordered_set(rc_idle_os,`PCIe_RECOVERY_IDLE_COUNT,"RECOVERY_IDLE");
             tx_idle_done = 1'b1;
          end
          begin
             `uvm_info("RC_RECOVERY","WAITING_FOR_2_IDLE_FROM_EP",UVM_LOW)
             rc_wait_ep_idle_os(`PCIe_RECOVERY_IDLE_COUNT, base_idle, rx_idle_done);
          end
       join
       if (tx_idle_done && rx_idle_done) begin
          rc_main_state = L0;
          `uvm_info("RC_RECOVERY",$sformatf("2_IDLE_TX_AND_2_IDLE_RX_CONDITIONS_SATISFIED LTSSM_TRANSITION_RECOVERY_Idle_L0_AT=%s",
                    rc_cur_rate.name()),UVM_LOW)
       end
       else begin
          `uvm_error("RC_RECOVERY","RECOVERY_Idle_TX_RX_CONDITIONS_NOT_MET")
       end
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

    task tx_process(input  bit [31:0] data_in,output bit [31:0] data_out,input PCIe_sequence_item item);
      bit [31:0] scramble_data;
      bit [31:0] gray_data;
      bit [31:0] pre_data;
      bit        parity;
      `uvm_info("PCIe_PL_MODEL","ENTERED_INTO_TX_PROCESS_TASK", UVM_LOW)
      if (item != null) item.print();
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
     `uvm_info("RC_PL_MODEL",$sformatf("PL -> INTERFACE received 242-byte packet, payload=%p",item.dlp_flit_out),UVM_MEDIUM)
      dl_flit_out=item.dlp_flit_out;
      // [ADDED] One more flit received from DL -> give it the next flit number.
      rc_tx_flit_num++;
      pl_qu.delete();
      for (int i = 0; i < 242; i += 4) begin
        temp = '0;
        for (int j = 0; j < 4; j++) begin
          if ((i+j) < 242)
             temp[j*8 +: 8] = dl_flit_out[i+j];
          end
          pl_qu.push_back(temp);
      end
     // `uvm_info("RC_PL_MODEL",$sformatf("PL -> INTERFACE received 242-byte packet, payload=%p",pl_qu),UVM_MEDIUM)

       // ===== Gen6 Flit-Mode CRC/FEC Computation =====
       // Build the 256-byte Flit: 242B payload + 8B CRC + 6B FEC
       begin
          bit [`PCIe_BYTE_W-1:0] dl_bytes_q[$];
          bit [`PCIe_BYTE_W-1:0] crc_bytes [0:7];
          bit [`PCIe_BYTE_W-1:0] fec_bytes [0:5];

          dl_bytes_q.delete();
          for(int ci = 0; ci < `PCIe_DLP_FLIT_BYTE_W; ci++)
             dl_bytes_q.push_back(dl_flit_out[ci]);

          flit_crc = calculate_final_crc_250b(dl_bytes_q);
          `uvm_info("RC_PL_MODEL",$sformatf("RC_TX_FLIT_CRC64 = 0x%016h",flit_crc),UVM_LOW)

          crc_bytes = '{flit_crc[63:56], flit_crc[55:48], flit_crc[47:40], flit_crc[39:32],
                        flit_crc[31:24], flit_crc[23:16], flit_crc[15:8],  flit_crc[7:0]};
          `uvm_info("RC_PL_MONITOR",
                    $sformatf("RC_TX_CRC_8_BYTES = %p (CRC64 = 0x%016h)",crc_bytes,flit_crc),
                    UVM_LOW)

          // Display the full CRC packet format (byte and field views).
          `uvm_info("RC_TX_CRC_PACKET",
                    $sformatf({"\n",
                    "        ============================================================\n",
                    "                          CRC PACKET FORMAT\n",
                    "        ============================================================\n",
                    "        CRC SIZE : 8 bytes\n",
                    "        ------------------------------------------------------------\n",
                    "        COMPLETE CRC BYTES:\n",
                    "        ------------------------------------------------------------\n",
                    "          CRC[0] = %02h\n",
                    "          CRC[1] = %02h\n",
                    "          CRC[2] = %02h\n",
                    "          CRC[3] = %02h\n",
                    "          CRC[4] = %02h\n",
                    "          CRC[5] = %02h\n",
                    "          CRC[6] = %02h\n",
                    "          CRC[7] = %02h\n",
                    "        ------------------------------------------------------------\n",
                    "        CRC FIELDS:\n",
                    "        ------------------------------------------------------------\n",
                    "          CRC[63:56] = %02h\n",
                    "          CRC[55:48] = %02h\n",
                    "          CRC[47:40] = %02h\n",
                    "          CRC[39:32] = %02h\n",
                    "          CRC[31:24] = %02h\n",
                    "          CRC[23:16] = %02h\n",
                    "          CRC[15:8]  = %02h\n",
                    "          CRC[7:0]   = %02h\n",
                    "          FLIT_CRC64 = 0x%016h\n",
                    "        ============================================================"},
                    crc_bytes[0],crc_bytes[1],crc_bytes[2],crc_bytes[3],
                    crc_bytes[4],crc_bytes[5],crc_bytes[6],crc_bytes[7],
                    flit_crc[63:56],flit_crc[55:48],flit_crc[47:40],flit_crc[39:32],
                    flit_crc[31:24],flit_crc[23:16],flit_crc[15:8],flit_crc[7:0],
                    flit_crc), UVM_LOW)

          flit_crc_body = {dl_bytes_q, crc_bytes};

          `uvm_info("RC_PL_MODEL",
                    $sformatf("RC_TX_FINAL_CRC_250B_FLIT = %0d Bytes (242 bytes + 8 bytes CRC)",
                              flit_crc_body.size()),
                    UVM_LOW)
          `uvm_info("RC_PL_MONITOR",
                    $sformatf("RC_TX_250B_FLIT(242 bytes DL + 8 bytes CRC) = %p",flit_crc_body),
                    UVM_LOW)

          calculate_final_fec_256b(flit_crc_body, fec_bytes);
          `uvm_info("RC_PL_MONITOR",
                    $sformatf("RC_TX_FEC_6_BYTES = %p",fec_bytes),
                    UVM_LOW)

          flit_with_crc_fec_body = {flit_crc_body, fec_bytes};

          // [ADDED] FLIT_NUM in both prints below.
          `uvm_info("RC_PL_MODEL",
                    $sformatf("RC_TX_FINAL_CRC_FEC_256B_FLIT : FLIT_NUM = %0d : %0d Bytes (242 DL + 8 CRC + 6 FEC)",
                              rc_tx_flit_num,
                              flit_with_crc_fec_body.size()),
                    UVM_LOW)
          `uvm_info("RC_PL_MONITOR",
                    $sformatf("RC_TX_256_BYTE_FLIT : FLIT_NUM = %0d : %p",
                              rc_tx_flit_num,
                              flit_with_crc_fec_body),
                    UVM_LOW)

          // ADDED: formatted dump of ALL 256 bytes of the final flit
          // (236B TLP + 6B DLP + 8B CRC + 6B FEC), region by region.
          begin
            string dump;
            string line;
            dump = {dump, "\n"};
            dump = {dump, "        ============================================================\n"};
            dump = {dump, "                 COMPLETE 256-BYTE FLIT DUMP (TLP+DLP+CRC+FEC)\n"};
            dump = {dump, "        ============================================================\n"};
            dump = {dump, "        TLP PAYLOAD [0-235] = 236 bytes:\n"};
            dump = {dump, "        ------------------------------------------------------------\n"};
            for(int r = 0; r < 236; r += 16) begin
              line = $sformatf("        [%03d-%03d] :", r, r+15);
              for(int c = 0; c < 16; c++) begin
                if(r+c < 236) line = {line, $sformatf(" %02h", flit_with_crc_fec_body[r+c])};
                else          line = {line, " --"};
                if(c == 7) line = {line, "  |"};
              end
              dump = {dump, line, "\n"};
            end
            dump = {dump, "        DLP [236-241] = 6 bytes:\n"};
            dump = {dump, "        ------------------------------------------------------------\n"};
            line = "        [236-241] :";
            for(int c = 0; c < 6; c++) line = {line, $sformatf(" %02h", flit_with_crc_fec_body[236+c])};
            dump = {dump, line, "\n"};
            dump = {dump, "        CRC [242-249] = 8 bytes:\n"};
            line = "        [242-249] :";
            for(int c = 0; c < 8; c++) line = {line, $sformatf(" %02h", flit_with_crc_fec_body[242+c])};
            dump = {dump, line, "\n"};
            dump = {dump, "        FEC [250-255] = 6 bytes:\n"};
            line = "        [250-255] :";
            for(int c = 0; c < 6; c++) line = {line, $sformatf(" %02h", flit_with_crc_fec_body[250+c])};
            dump = {dump, line, "\n"};
            dump = {dump, "        ============================================================"};
            `uvm_info("RC_TX_256B_DUMP", dump, UVM_LOW)
          end

          rc_flit_ready_flag = 1'b1;
       end
       // ===== END CRC/FEC Computation =====

       pl_sent=1;
     endfunction

//----------------------------------------------------------------------------
  // Gen6 Flit-Mode CRC/FEC : declarations, tables, and functions
  //----------------------------------------------------------------------------

  // GF(2^8) antilog table for FEC field
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

  // GF(2^8) multiply for CRC field (reduction 8'h2B)
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

  // Compute 8-byte CRC over 242-byte Flit payload
  function bit [63:0] calculate_final_crc_250b(input bit [`PCIe_BYTE_W-1:0] flit_bytes[$]);
    bit [`PCIe_BYTE_W-1:0] g[8];
    bit [`PCIe_BYTE_W-1:0] rem[8];
    bit [`PCIe_BYTE_W-1:0] fb;
    bit [63:0]             crc_result;

    g[0] = 8'hD5; g[1] = 8'h68; g[2] = 8'hFE; g[3] = 8'hD5;
    g[4] = 8'h33; g[5] = 8'h41; g[6] = 8'h4D; g[7] = 8'h69;

    if(flit_bytes.size() < `PCIe_DLP_FLIT_BYTE_W)
    begin
      `uvm_error("PCIe_PL_MODEL",
                 $sformatf("calculate_final_crc_250b: need >= %0d Bytes, got %0d",
                           `PCIe_DLP_FLIT_BYTE_W, flit_bytes.size()))
      `uvm_info("RC_PL_MODEL","CRC error is there",UVM_LOW)
      return '0;
    end
    `uvm_info("RC_PL_MODEL","CRC error is not there",UVM_LOW)

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
    `uvm_info("RC_PL_MODEL",
              $sformatf("CRC is calculated = 0x%016h",crc_result), UVM_LOW)
    `uvm_info("RC_PL_MONITOR",
              $sformatf("RC_TX_CRC_BYTES = {%02h %02h %02h %02h %02h %02h %02h %02h}",
                        rem[0],rem[1],rem[2],rem[3],rem[4],rem[5],rem[6],rem[7]),
              UVM_LOW)
    return crc_result;
  endfunction : calculate_final_crc_250b

  // GF(2^8) multiply via log/antilog tables for FEC field
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

  // Compute 6 ECC bytes for a 250-byte (242B payload + 8B CRC) Flit body
  function void calculate_final_fec_256b(
    input  bit [`PCIe_BYTE_W-1:0] flit_in [$],
    output bit [`PCIe_BYTE_W-1:0] fec_bytes [0:5]
  );
    bit [`PCIe_BYTE_W-1:0] grp0 [0:83], grp1 [0:83], grp2 [0:83];
    bit [`PCIe_BYTE_W-1:0] c0, p0, c1, p1, c2, p2;

    if(flit_in.size() < (`PCIe_DLP_FLIT_BYTE_W + 8))
    begin
      `uvm_error("PCIe_PL_MODEL",
                 $sformatf("calculate_final_fec_256b: need >= %0d Bytes, got %0d",
                           `PCIe_DLP_FLIT_BYTE_W + 8, flit_in.size()))
      `uvm_info("RC_PL_MODEL","FEC error is there",UVM_LOW)
      foreach(fec_bytes[i]) fec_bytes[i] = '0;
      return;
    end
    `uvm_info("RC_PL_MODEL","FEC error is not there",UVM_LOW)

    grp1[83] = 8'h00;
    grp2[83] = 8'h00;

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

    fec_bytes[0] = c1; fec_bytes[1] = c2; fec_bytes[2] = c0;
    fec_bytes[3] = p1; fec_bytes[4] = p2; fec_bytes[5] = p0;

    `uvm_info("RC_PL_MODEL",
              $sformatf("FEC ECC computed: G0(C=0x%02h,P=0x%02h) G1(C=0x%02h,P=0x%02h) G2(C=0x%02h,P=0x%02h)",
                        c0, p0, c1, p1, c2, p2), UVM_LOW)
    `uvm_info("RC_PL_MODEL","FEC is calculated",UVM_LOW)
    `uvm_info("RC_PL_MONITOR",
              $sformatf("RC_TX_FEC_BYTES = %p",fec_bytes), UVM_LOW)

    // Display the full FEC packet format (byte and per-Group field views).
    `uvm_info("RC_TX_FEC_PACKET",
              $sformatf({"\n",
              "        ============================================================\n",
              "                          FEC PACKET FORMAT\n",
              "        ============================================================\n",
              "        FEC SIZE : 6 bytes\n",
              "        ------------------------------------------------------------\n",
              "        COMPLETE FEC BYTES:\n",
              "        ------------------------------------------------------------\n",
              "          FEC[0] = %02h\n",
              "          FEC[1] = %02h\n",
              "          FEC[2] = %02h\n",
              "          FEC[3] = %02h\n",
              "          FEC[4] = %02h\n",
              "          FEC[5] = %02h\n",
              "        ------------------------------------------------------------\n",
              "        FEC0-FEC1 GROUP0 FIELDS:\n",
              "        ------------------------------------------------------------\n",
              "          GROUP0_CHECK  [7:0] = %02h\n",
              "          GROUP0_PARITY [7:0] = %02h\n",
              "        ------------------------------------------------------------\n",
              "        FEC2-FEC3 GROUP1 FIELDS:\n",
              "        ------------------------------------------------------------\n",
              "          GROUP1_CHECK  [7:0] = %02h\n",
              "          GROUP1_PARITY [7:0] = %02h\n",
              "        ------------------------------------------------------------\n",
              "        FEC4-FEC5 GROUP2 FIELDS:\n",
              "        ------------------------------------------------------------\n",
              "          GROUP2_CHECK  [7:0] = %02h\n",
              "          GROUP2_PARITY [7:0] = %02h\n",
              "        ============================================================"},
              fec_bytes[0],fec_bytes[1],fec_bytes[2],fec_bytes[3],fec_bytes[4],fec_bytes[5],
              c0,p0,c1,p1,c2,p2), UVM_LOW)
  endfunction : calculate_final_fec_256b

  // Convenience: append 6B ECC onto an assembled 250B Flit body queue
  function void append_final_fec_256b(ref bit [`PCIe_BYTE_W-1:0] flit_bytes[$]);
    bit [`PCIe_BYTE_W-1:0] fec_bytes [0:5];
    calculate_final_fec_256b(flit_bytes, fec_bytes);
    for(int e = 0; e < 6; e++)
      flit_bytes.push_back(fec_bytes[e]);
    `uvm_info("RC_PL_MODEL",
              $sformatf("FEC appended, Flit size = %0d Bytes", flit_bytes.size()), UVM_LOW)
  endfunction : append_final_fec_256b

endclass









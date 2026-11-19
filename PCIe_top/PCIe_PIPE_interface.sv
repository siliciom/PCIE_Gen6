//=========================================================================================
// File         : PCIe_PIPE_interface.sv
// Project      : PCIE_Gen6
// Description  : PCIe_top\PCIe_PIPE_interface.sv
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

`timescale 1ns/1ps
// [DL_ASSERT] needed by the DL assertions inside both interfaces
`include "uvm_macros.svh"
`include "../PCIe_config/PCIe_defines.sv"

`ifndef PCIE_NUM_LANES
  `define PCIE_NUM_LANES 4
`endif

interface PCIe_RC_interface(input logic pclk);

   //----------------------------------------
   // Clock & Reset
   //----------------------------------------
   logic               rst_n;
   //----------------------------------------
   // MAC -> PHY (Transmit)
   //----------------------------------------
   logic [31:0] tx_data;
   logic [`PCIE_NUM_LANES-1:0][31:0] tx_data_lane;
   logic [`PCIE_NUM_LANES-1:0][31:0] tx_data_striped = '0;
   logic        tx_striped = 1'b0;
   logic        tx_valid;
   logic        tx_elec_idle;
   logic        tx_detect_rx;
   logic [1:0]  powerdown;
   logic [2:0]  rate;
   //----------------------------------------
   // PHY -> MAC (Receive)
   //----------------------------------------
   logic [31:0] rx_data;
   logic [`PCIE_NUM_LANES-1:0][31:0] rx_data_lane;
   logic        rx_valid;
   logic        phy_status;
   logic        rx_elec_idle;
   logic [2:0]  rx_status;

   // Ordered Sets / LTSSM traffic : scalar tx_data is broadcast on every lane.
   // FLIT data : the PL/controller drives tx_data_striped and raises tx_striped.
   always_comb begin
      for (int l = 0; l < `PCIE_NUM_LANES; l++)
         tx_data_lane[l] = tx_striped ? tx_data_striped[l] : tx_data;
   end

   // The scalar receive bus is lane 0. Ordered Sets are broadcast, so this is
   // also the logical word while the link is in training.
   assign rx_data = rx_data_lane[0];
   //----------------------------------------
   // Driver Clocking Block
   //----------------------------------------
   clocking cb_rc_drv @(posedge pclk);
      default input #1step output #1step;
      output tx_data;
      output tx_valid;
      output tx_elec_idle;
      output tx_detect_rx;
      output powerdown;
      output rate;

      input  rx_data;
      input  rx_valid;
      input  phy_status;
      input  rx_elec_idle;
      input  rx_status;
   endclocking
   //----------------------------------------
   // Monitor Clocking Block
   //----------------------------------------
   clocking cb_rc_mon @(negedge pclk);
      default input #1step;
      input tx_data;
      input tx_valid;
      input tx_elec_idle;
      input tx_detect_rx;
      input powerdown;
      input rate;
      input rx_data;
      input rx_valid;
      input phy_status;
      input rx_elec_idle;
      input rx_status;
   endclocking

   //----------------------------------------
   // Driver Modport
   //----------------------------------------
   modport mp_rc_driver (clocking cb_rc_drv);
   //----------------------------------------
   // Monitor Modport
   //----------------------------------------
   modport mp_rc_monitor (clocking cb_rc_mon);


   //==========================================================================
   //==========================================================================
   // [DL_ASSERT] RC DL state machine assertions (DL_INACTIVE -> DL_FEATURE -> DL_INIT -> DL_ACTIVE)
   //   Assertions cannot be written inside a class, so PCIe_RC_DL_model.sv copies its
   //   DL state/counters/flags into the signals below on every pclk negedge (run_dl_assert_mirror).
   //   The checks read them on every pclk posedge and give UVM_ERROR if a rule is broken.
   //
   //   Check name                            What it checks
   //   DL_START_STATE_CHECK                  DL starts in DL_INACTIVE
   //   DL_LINKUP_START_CHECK                 New link-up starts from DL_INACTIVE
   //   DL_<state>_NEXT_STATE_CHECK (5)       Only legal state moves
   //   DL_LINKDOWN_CHECK                     Link down -> DL_INACTIVE
   //   DL_TLP_ONLY_IN_ACTIVE_CHECK           TLP sent only in DL_ACTIVE
   //   DL_NO_DLLP_IN_INACTIVE_CHECK          No DLLP in DL_INACTIVE
   //   DL_RESET_COUNTERS/FLAGS/BUFFERS_CHECK On DL_INACTIVE : all values reset
   //   DL_START_DEFAULTS_CHECK               Default values at start
   //   DL_LINK_ACTIVE_ONLY_IN_ACTIVE_CHECK   dl_link_active = 1 only in DL_ACTIVE
   //   DL_ACTIVE_NEEDS_LINK_ACTIVE_CHECK     DL_ACTIVE always has dl_link_active = 1
   //   On failure the log shows : UVM_ERROR ... [<check name>] FAILED : <reason>
   //==========================================================================
   //==========================================================================
   import uvm_pkg::*;
   import typedef_enums::*;
   localparam string SIDE = "RC";

   //--------------------------------------------------------------------------
   // On / off
   //--------------------------------------------------------------------------
   bit assert_en    = 1'b1;   // 1 = checks ON. A test can set 0 to switch all DL checks OFF
   bit sample_valid = 1'b0;   // DL model sets 1 after its first copy. Checks wait for this

   //--------------------------------------------------------------------------
   // DL state : copied from the DL model on every falling edge of pclk
   //--------------------------------------------------------------------------
   dl_state_e          dl_state       = DL_INACTIVE;
   dl_init_substate_e  dl_init_sub    = INIT_FC1;
   bit                 dl_link_active;
   bit                 phy_linkup;

   // Sequence number counters (value in comment = value they must have in DL_INACTIVE)
   bit [`PCIe_SEQ_NUM_W-1:0]        next_tx_seq;        // NEXT_TX_FLIT_SEQ_NUM          default 001h
   bit [`PCIe_SEQ_NUM_W-1:0]        tx_acknak_seq;      // TX_ACKNAK_FLIT_SEQ_NUM        default 3FFh (1023)
   bit [`PCIe_SEQ_NUM_W-1:0]        ackd_seq;           // ACKD_FLIT_SEQ_NUM             default 3FFh
   bit [`PCIe_SEQ_NUM_W-1:0]        next_exp_rx_seq;    // NEXT_EXPECTED_RX_FLIT_SEQ_NUM default 001h
   bit [`PCIe_SEQ_NUM_W-1:0]        implicit_rx_seq;    // IMPLICIT_RX_FLIT_SEQ_NUM      default 000h
   bit [`PCIe_SEQ_NUM_W-1:0]        tx_replay_seq;      // TX_REPLAY_FLIT_SEQ_NUM        default 000h
   bit [`PCIe_SEQ_NUM_W-1:0]        nak_ignore_seq;     // NAK_IGNORE_FLIT_SEQ_NUM       default 000h
   bit [`PCIe_FLIT_REPLAY_NUM_W-1:0] flit_replay_num;   // FLIT_REPLAY_NUM               default 000b

   // ACK / NAK / replay flags (all must be 0 in DL_INACTIVE)
   bit nak_scheduled;
   bit ack_scheduled;
   bit replay_scheduled;
   bit replay_in_progress;
   bit nak_withdrawal_allowed;

   // Number of entries in the TX / RX retry buffers (must be 0 in DL_INACTIVE)
   int unsigned tx_retry_size;
   int unsigned rx_retry_size;

   //--------------------------------------------------------------------------
   // Flit sent events : the DL model updates these at the moment it sends a flit.
   // The count goes +1 for every flit, and *_dl_state saves the DL state at
   // that moment. A check sees "count changed" and looks at the saved state.
   //--------------------------------------------------------------------------
   int unsigned tx_payload_cnt;            // + 1 for every payload (TLP) flit sent to PL
   dl_state_e   tx_payload_dl_state = DL_INACTIVE;
   int unsigned tx_dllp_cnt;               // + 1 for every DLLP flit sent to PL
   dl_state_e   tx_dllp_dl_state    = DL_INACTIVE;
   bit [31:0]   tx_dllp_content;

   //--------------------------------------------------------------------------
   // dl_check_state : same as dl_state, but DL_INIT is split into
   //                  FC_INIT1 / FC_INIT2 so every state move can be checked
   //                  (STATE_ names : DL_ names already exist in enum_defs.sv)
   //--------------------------------------------------------------------------
   typedef enum {STATE_INACTIVE, STATE_FEATURE, STATE_FC_INIT1, STATE_FC_INIT2, STATE_ACTIVE} dl_check_state_e;
   dl_check_state_e dl_check_state;

   always_comb begin
      case (dl_state)
         DL_INACTIVE : dl_check_state = STATE_INACTIVE;
         DL_FEATURE  : dl_check_state = STATE_FEATURE;
         DL_INIT     : dl_check_state = (dl_init_sub == INIT_FC2) ? STATE_FC_INIT2 : STATE_FC_INIT1;
         default     : dl_check_state = STATE_ACTIVE;
      endcase
   end

   // Helper signals : 1 when all values are at their DL_INACTIVE default (used by DL_RESET_... checks)
   wire seq_default = (next_tx_seq     == 10'h001) && (tx_acknak_seq  == 10'h3FF) &&
                      (ackd_seq        == 10'h3FF) && (next_exp_rx_seq == 10'h001) &&
                      (implicit_rx_seq == 10'h000) && (tx_replay_seq   == 10'h000) &&
                      (nak_ignore_seq  == 10'h000) && (flit_replay_num == '0);
   wire flags_clear = !nak_scheduled && !ack_scheduled && !replay_scheduled &&
                      !replay_in_progress && !nak_withdrawal_allowed;
   wire buffers_empty = (tx_retry_size == 0) && (rx_retry_size == 0);

   //--------------------------------------------------------------------------
   // Every check below runs on the rising edge of pclk, and is OFF while
   // sample_valid = 0 (copy not started yet) or assert_en = 0 (switched off)
   //--------------------------------------------------------------------------
   default clocking dl_cb @(posedge pclk); endclocking
   default disable iff (!sample_valid || !assert_en);

   //==========================================================================
   // CHECK 1 : DL must start in DL_INACTIVE
   //==========================================================================
   // At start of simulation the DL state must be DL_INACTIVE.
   // (own disable : it checks the very first cycle where sample_valid becomes 1)
   DL_START_STATE_CHECK : assert property (
      @(posedge pclk) disable iff (!assert_en)
      $rose(sample_valid) |-> (dl_state == DL_INACTIVE))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_START_STATE_CHECK] FAILED : at start DL state must be DL_INACTIVE, but it is %s", dl_state.name()))

   // When the link comes up (phy_linkup 0 -> 1), DL must still be in DL_INACTIVE
   // (DL_FEATURE is also OK : the model leaves DL_INACTIVE in zero time).
   DL_LINKUP_START_CHECK : assert property (
      $rose(phy_linkup) |-> (dl_check_state inside {STATE_INACTIVE, STATE_FEATURE}))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_LINKUP_START_CHECK] FAILED : link came up but DL state is %s (expected DL_INACTIVE)", dl_check_state.name()))

   //==========================================================================
   // CHECK 2 : Only legal state moves
   //   INACTIVE -> FEATURE -> FC_INIT1 -> FC_INIT2 -> ACTIVE , any -> INACTIVE
   //==========================================================================
   // From DL_INACTIVE, next state must be DL_INACTIVE or DL_FEATURE
   DL_INACTIVE_NEXT_STATE_CHECK : assert property (
      (dl_check_state == STATE_INACTIVE) |=> (dl_check_state inside {STATE_INACTIVE, STATE_FEATURE}))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_INACTIVE_NEXT_STATE_CHECK] FAILED : from DL_INACTIVE only DL_FEATURE is allowed, but moved to %s", dl_check_state.name()))

   // From DL_FEATURE, next state must be DL_FEATURE, FC_INIT1 or DL_INACTIVE
   DL_FEATURE_NEXT_STATE_CHECK : assert property (
      (dl_check_state == STATE_FEATURE) |=> (dl_check_state inside {STATE_FEATURE, STATE_FC_INIT1, STATE_INACTIVE}))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_FEATURE_NEXT_STATE_CHECK] FAILED : from DL_FEATURE only FC_INIT1 or DL_INACTIVE is allowed, but moved to %s", dl_check_state.name()))

   // From FC_INIT1, next state must be FC_INIT1, FC_INIT2 or DL_INACTIVE
   DL_FC_INIT1_NEXT_STATE_CHECK : assert property (
      (dl_check_state == STATE_FC_INIT1) |=> (dl_check_state inside {STATE_FC_INIT1, STATE_FC_INIT2, STATE_INACTIVE}))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_FC_INIT1_NEXT_STATE_CHECK] FAILED : from FC_INIT1 only FC_INIT2 or DL_INACTIVE is allowed, but moved to %s", dl_check_state.name()))

   // From FC_INIT2, next state must be FC_INIT2, DL_ACTIVE or DL_INACTIVE
   DL_FC_INIT2_NEXT_STATE_CHECK : assert property (
      (dl_check_state == STATE_FC_INIT2) |=> (dl_check_state inside {STATE_FC_INIT2, STATE_ACTIVE, STATE_INACTIVE}))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_FC_INIT2_NEXT_STATE_CHECK] FAILED : from FC_INIT2 only DL_ACTIVE or DL_INACTIVE is allowed, but moved to %s", dl_check_state.name()))

   // From DL_ACTIVE, next state must be DL_ACTIVE or DL_INACTIVE
   DL_ACTIVE_NEXT_STATE_CHECK : assert property (
      (dl_check_state == STATE_ACTIVE) |=> (dl_check_state inside {STATE_ACTIVE, STATE_INACTIVE}))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_ACTIVE_NEXT_STATE_CHECK] FAILED : from DL_ACTIVE only DL_INACTIVE is allowed, but moved to %s", dl_check_state.name()))

   //==========================================================================
   // CHECK 3 : Link down -> DL_INACTIVE
   //==========================================================================
   // On an actual link-down event (phy_linkup 1 -> 0), in the next clock DL
   // state must be DL_INACTIVE. $fell() is used instead of the !phy_linkup
   // level: on link-up the DL FSM legitimately moves DL_INACTIVE -> DL_FEATURE
   // in the same cycle phy_linkup rises, and a level-based antecedent would
   // falsely flag that legal transition as a link-down failure.
   DL_LINKDOWN_CHECK : assert property (
      $fell(phy_linkup) |=> (dl_state == DL_INACTIVE))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_LINKDOWN_CHECK] FAILED : link went down (phy_linkup 1->0) but DL state is %s (expected DL_INACTIVE)", dl_check_state.name()))

   //==========================================================================
   // CHECK 4 : TLP (payload flit) only in DL_ACTIVE
   //==========================================================================
   // Every time a TLP flit is sent, DL state at that moment must be DL_ACTIVE
   DL_TLP_ONLY_IN_ACTIVE_CHECK : assert property (
      $changed(tx_payload_cnt) |-> (tx_payload_dl_state == DL_ACTIVE))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_TLP_ONLY_IN_ACTIVE_CHECK] FAILED : TLP flit sent in %s (TLPs allowed only in DL_ACTIVE)",
      tx_payload_dl_state.name()))

   //==========================================================================
   // CHECK 5 : No DLLP in DL_INACTIVE
   //==========================================================================
   // Every time a DLLP is sent, DL state at that moment must not be DL_INACTIVE
   DL_NO_DLLP_IN_INACTIVE_CHECK : assert property (
      $changed(tx_dllp_cnt) |-> (tx_dllp_dl_state != DL_INACTIVE))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_NO_DLLP_IN_INACTIVE_CHECK] FAILED : DLLP %08h sent while DL is in DL_INACTIVE", tx_dllp_content))

   //==========================================================================
   // CHECK 6 : On entering DL_INACTIVE, reset everything to default
   //   counters / flags / retry buffers. One pclk of grace (##[0:1]).
   //==========================================================================
   // s_enter_inactive : DL state is DL_INACTIVE now, and was NOT DL_INACTIVE in the last clock
   sequence s_enter_inactive;
      (dl_state == DL_INACTIVE) && ($past(dl_state) != DL_INACTIVE);
   endsequence

   // On entering DL_INACTIVE, all sequence counters must go back to default
   DL_RESET_COUNTERS_CHECK : assert property (
      s_enter_inactive |-> ##[0:1] seq_default)
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_RESET_COUNTERS_CHECK] FAILED : DL went to DL_INACTIVE but counters are not reset : NEXT_TX=%0d(exp 1) TX_ACKNAK=%0d(exp 1023) ACKD=%0d(exp 1023) NEXT_EXP_RX=%0d(exp 1) IMPLICIT_RX=%0d(exp 0) TX_REPLAY=%0d(exp 0) NAK_IGNORE=%0d(exp 0) FLIT_REPLAY_NUM=%0d(exp 0)",
      next_tx_seq, tx_acknak_seq, ackd_seq, next_exp_rx_seq, implicit_rx_seq, tx_replay_seq, nak_ignore_seq, flit_replay_num))

   // On entering DL_INACTIVE, all ACK / NAK / replay flags must be 0
   DL_RESET_FLAGS_CHECK : assert property (
      s_enter_inactive |-> ##[0:1] flags_clear)
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_RESET_FLAGS_CHECK] FAILED : DL went to DL_INACTIVE but flags are not cleared : NAK_SCHEDULED=%0b ACK_SCHEDULED=%0b REPLAY_SCHEDULED=%0b REPLAY_IN_PROGRESS=%0b NAK_WITHDRAWAL_ALLOWED=%0b",
      nak_scheduled, ack_scheduled, replay_scheduled, replay_in_progress, nak_withdrawal_allowed))

   // On entering DL_INACTIVE, TX and RX retry buffers must be empty
   DL_RESET_BUFFERS_CHECK : assert property (
      s_enter_inactive |-> ##[0:1] buffers_empty)
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_RESET_BUFFERS_CHECK] FAILED : DL went to DL_INACTIVE but retry buffers are not empty : TX_RETRY_BUFFER=%0d RX_RETRY_BUFFER=%0d entries",
      tx_retry_size, rx_retry_size))

   // At start of simulation, counters / flags / retry buffers must all be at default
   DL_START_DEFAULTS_CHECK : assert property (
      @(posedge pclk) disable iff (!assert_en)
      $rose(sample_valid) |-> (seq_default && flags_clear && buffers_empty))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_START_DEFAULTS_CHECK] FAILED : at start DL values are not default : NEXT_TX=%0d ACKD=%0d NEXT_EXP_RX=%0d IMPLICIT_RX=%0d TX_BUF=%0d RX_BUF=%0d",
      next_tx_seq, ackd_seq, next_exp_rx_seq, implicit_rx_seq, tx_retry_size, rx_retry_size))

   //==========================================================================
   // CHECK 7 : dl_link_active = 1 only in DL_ACTIVE
   //==========================================================================
   // If dl_link_active = 1, DL state must be DL_ACTIVE
   DL_LINK_ACTIVE_ONLY_IN_ACTIVE_CHECK : assert property (
      dl_link_active |-> (dl_state == DL_ACTIVE))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_LINK_ACTIVE_ONLY_IN_ACTIVE_CHECK] FAILED : dl_link_active=1 but DL state is %s", dl_check_state.name()))

   // If DL state is DL_ACTIVE, dl_link_active must be 1
   DL_ACTIVE_NEEDS_LINK_ACTIVE_CHECK : assert property (
      (dl_state == DL_ACTIVE) |-> dl_link_active)
   else `uvm_error({SIDE,"_DL_ASSERT"},
      "[DL_ACTIVE_NEEDS_LINK_ACTIVE_CHECK] FAILED : DL state is DL_ACTIVE but dl_link_active=0")

   //==========================================================================
   // Covers : count how many times each state move happened (0 = that move was never tested)
   //==========================================================================
   DL_COVER_INACTIVE_TO_FEATURE : cover property ((dl_check_state == STATE_INACTIVE) ##1 (dl_check_state == STATE_FEATURE));
   DL_COVER_FEATURE_TO_FC_INIT1 : cover property ((dl_check_state == STATE_FEATURE)  ##1 (dl_check_state == STATE_FC_INIT1));
   DL_COVER_FC_INIT1_TO_FC_INIT2: cover property ((dl_check_state == STATE_FC_INIT1) ##1 (dl_check_state == STATE_FC_INIT2));
   DL_COVER_FC_INIT2_TO_ACTIVE  : cover property ((dl_check_state == STATE_FC_INIT2) ##1 (dl_check_state == STATE_ACTIVE));
   DL_COVER_ACTIVE_TO_INACTIVE  : cover property ((dl_check_state == STATE_ACTIVE)   ##1 (dl_check_state == STATE_INACTIVE));
   DL_COVER_TLP_IN_ACTIVE       : cover property ($changed(tx_payload_cnt) && (tx_payload_dl_state == DL_ACTIVE));

   //==========================================================================
   // [DL_ASSERT] STATUS MESSAGES : show in the log that the DL checks are running
   //   Search "DL_STATUS" in the log. A summary is printed at the end of the test.
   //==========================================================================
   int unsigned     dl_moves_checked     = 0;  // DL state changes checked
   int unsigned     dl_tlps_checked      = 0;  // TLP flits checked
   int unsigned     dl_dllps_checked     = 0;  // DLLP flits checked
   int unsigned     dl_linkdowns_checked = 0;  // link-down events checked
   bit              dl_checks_started    = 0;  // 1 after the first check cycle
   dl_check_state_e prev_dl_check_state  = STATE_INACTIVE;
   int unsigned     prev_tx_payload_cnt  = 0;
   int unsigned     prev_tx_dllp_cnt     = 0;
   bit              prev_phy_linkup      = 0;

   // Every pclk rising edge : count what the checks looked at, print each DL state move
   always @(posedge pclk) begin
      if (sample_valid && assert_en) begin
         if (!dl_checks_started) begin
            dl_checks_started = 1;
            `uvm_info({SIDE,"_DL_STATUS"}, "DL assertions STARTED checking", UVM_LOW)
         end
         else begin
            if (dl_check_state != prev_dl_check_state) begin
               dl_moves_checked++;
               `uvm_info({SIDE,"_DL_STATUS"}, $sformatf("DL state move checked : %s -> %s",
                         prev_dl_check_state.name(), dl_check_state.name()), UVM_LOW)
            end
            dl_tlps_checked  += (tx_payload_cnt - prev_tx_payload_cnt);
            dl_dllps_checked += (tx_dllp_cnt    - prev_tx_dllp_cnt);
            if (prev_phy_linkup && !phy_linkup) dl_linkdowns_checked++;
         end
         prev_dl_check_state = dl_check_state;
         prev_tx_payload_cnt = tx_payload_cnt;
         prev_tx_dllp_cnt    = tx_dllp_cnt;
         prev_phy_linkup     = phy_linkup;
      end
   end

   // End of test : print a summary with the number of checks, failures and final result
   final begin
      uvm_report_server svr;
      int               fail_cnt;
      string            result;
      svr      = uvm_report_server::get_server();
      fail_cnt = svr.get_id_count({SIDE,"_DL_ASSERT"});   // number of DL assertion UVM_ERRORs
      if (!dl_checks_started) result = "NOT CHECKED";
      else if (fail_cnt == 0) result = "PASSED";
      else                    result = "FAILED";
      `uvm_info({SIDE,"_DL_STATUS"}, $sformatf({"\n",
         "  DL assertion failures    : %0d\n",
         "  DL assertions            : %s\n"},
         fail_cnt, result), UVM_LOW)
   end

   // [DL_ASSERT] end of DL assertions

   //==========================================================================
   // [TL_ASSERT] RC TRANSACTION LAYER ASSERTIONS
   //   The RC TL model writes these variables through its handle tl_aif.
   //   TX : 236 B TLP formed -> tl_tx_ready = 1 -> sent TL -> DL -> tl_tx_ready = 0
   //   RX : 236 B received from DL -> decoded -> completion matched to its request
   //   Search "RC_TL_ASSERT" in the log for failures.
   //==========================================================================
   bit          tl_assert_en    = 1'b1;   // 1 = TL checks ON (a test can set 0)
   bit          tl_sample_valid = 1'b0;   // RC TL model sets 1 at start of simulation

   // TX : TL -> DL
   bit          tl_tx_ready;              // 1 = 236 B TLP formed, not yet sent to DL
   int unsigned tl_tx_formed_cnt;         // +1 when a 236 B TLP is formed
   int unsigned tl_tx_sent_cnt;           // +1 when a TLP is sent TL -> DL

   // RX : DL -> TL
   int unsigned tl_rx_cnt;                // +1 when a 236 B TLP comes from the DL
   int unsigned tl_rx_done_cnt;           // +1 when its decode is finished
   int unsigned tl_rx_cpl_cnt;            // +1 when a completion is received
   int unsigned tl_rx_cpl_matched_cnt;    // +1 when that completion's tag was outstanding

   //--------------------------------------------------------------------------
   // CHECK 1 : a formed 236 B TLP (ready = 1) must be sent to the DL
   //--------------------------------------------------------------------------
   TL_TX_READY_THEN_SENT_CHECK : assert property (
      @(posedge pclk) disable iff (!tl_sample_valid || !tl_assert_en)
      tl_tx_ready |-> ##[0:`PCIe_TL_HANDOFF_CLKS] !tl_tx_ready)
   else `uvm_error({SIDE,"_TL_ASSERT"},
      "[TL_TX_READY_THEN_SENT_CHECK] FAILED : 236B TLP formed (tl_tx_ready=1) but not sent to DL")

   //--------------------------------------------------------------------------
   // CHECK 2 : every formed TLP was sent (count formed = count sent)
   //--------------------------------------------------------------------------
   TL_TX_FORMED_EQ_SENT_CHECK : assert property (
      @(posedge pclk) disable iff (!tl_sample_valid || !tl_assert_en)
      (tl_tx_formed_cnt == tl_tx_sent_cnt))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_TX_FORMED_EQ_SENT_CHECK] FAILED : TLPs formed=%0d but sent to DL=%0d", tl_tx_formed_cnt, tl_tx_sent_cnt))

   //--------------------------------------------------------------------------
   // CHECK 3 : every 236 B TLP received from the DL is decoded
   //--------------------------------------------------------------------------
   TL_RX_DONE_CHECK : assert property (
      @(posedge pclk) disable iff (!tl_sample_valid || !tl_assert_en)
      (tl_rx_cnt == tl_rx_done_cnt))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_RX_DONE_CHECK] FAILED : TLPs received from DL=%0d but decoded=%0d", tl_rx_cnt, tl_rx_done_cnt))

   //--------------------------------------------------------------------------
   // CHECK 4 : every completion belongs to a request we sent (tag matched)
   //--------------------------------------------------------------------------
   TL_RX_CPL_MATCHED_CHECK : assert property (
      @(posedge pclk) disable iff (!tl_sample_valid || !tl_assert_en)
      (tl_rx_cpl_matched_cnt == tl_rx_cpl_cnt))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_RX_CPL_MATCHED_CHECK] FAILED : completions received=%0d but only %0d matched a request",
      tl_rx_cpl_cnt, tl_rx_cpl_matched_cnt))

   //--------------------------------------------------------------------------
   // CHECKS 5-7 : the 236 B sent to the DL holds the right TLP
   //   Called by the RC TL model once for every TLP it sends.
   //   pfx    : 1 = a 1 DW Flit Mode prefix is in front of the header
   //   hdr_dw : header DWs (Header Base + OHC), the payload starts after them
   //--------------------------------------------------------------------------
   function automatic void tl_tx_tlp_check(
      input bit [0:`PCIe_TLP_DATA_BYTE_W-1][7:0] tlp,
      input bit          pfx,
      input bit [7:0]    exp_type,
      input bit [9:0]    exp_len,
      input int unsigned hdr_dw,
      input bit [31:0]   exp_data[]);

      int unsigned b0;           // byte where the TLP header starts
      int unsigned p;            // byte where payload DW i starts
      bit [31:0]   got;
      int unsigned bad;

      if (!tl_sample_valid || !tl_assert_en) return;
      b0 = pfx ? 4 : 0;

      // CHECK 5 : Type byte = type of the request (e.g. 4Ch = FetchAdd 32-bit)
      TL_TX_TYPE_CHECK : assert (tlp[b0] == exp_type)
      else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
         "[TL_TX_TYPE_CHECK] FAILED : type byte = 0x%02h, expected 0x%02h", tlp[b0], exp_type))

      // CHECK 6 : Length field (DW0 bits [9:0]) = Length of the request
      TL_TX_LENGTH_CHECK : assert ({tlp[b0+2][1:0], tlp[b0+3]} == exp_len)
      else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
         "[TL_TX_LENGTH_CHECK] FAILED : Length field = %0d, expected %0d", {tlp[b0+2][1:0], tlp[b0+3]}, exp_len))

      // CHECK 7 : every payload DW in the 236 B = the data of the request
      bad = 0;
      foreach (exp_data[i]) begin
         p = b0 + (hdr_dw + i) * 4;
         if ((p + 3) < `PCIe_TLP_DATA_BYTE_W) begin
            got = {tlp[p], tlp[p+1], tlp[p+2], tlp[p+3]};
            if (got != exp_data[i]) bad++;
         end
      end
      TL_TX_PAYLOAD_CHECK : assert (bad == 0)
      else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
         "[TL_TX_PAYLOAD_CHECK] FAILED : %0d payload DW in the 236B differ from the request data", bad))
   endfunction

   // end of test : one summary line
   final
      `uvm_info({SIDE,"_TL_STATUS"}, $sformatf(
         "TL summary : TLPs formed=%0d sent=%0d | received=%0d decoded=%0d | completions=%0d matched=%0d",
         tl_tx_formed_cnt, tl_tx_sent_cnt, tl_rx_cnt, tl_rx_done_cnt, tl_rx_cpl_cnt, tl_rx_cpl_matched_cnt), UVM_LOW)

   // [TL_ASSERT] end of TL assertions

endinterface

interface PCIe_EP_interface(input logic pclk);

   //----------------------------------------
   // Clock & Reset
   //----------------------------------------
   logic               rst_n;

   //----------------------------------------
   // MAC -> PHY (Transmit)
   //----------------------------------------
   logic [31:0] tx_data;
   logic [`PCIE_NUM_LANES-1:0][31:0] tx_data_lane;
   logic [`PCIE_NUM_LANES-1:0][31:0] tx_data_striped = '0;
   logic        tx_striped = 1'b0;
   logic        tx_valid;
   logic        tx_elec_idle;
   logic        tx_detect_rx;
   logic [1:0]  powerdown;
   logic [2:0]  rate;

   //----------------------------------------
   // PHY -> MAC (Receive)
   //----------------------------------------
   logic [31:0] rx_data;
   logic [`PCIE_NUM_LANES-1:0][31:0] rx_data_lane;
   logic        rx_valid;
   logic        phy_status;
   logic        rx_elec_idle;
   logic [2:0]  rx_status;

   // Ordered Sets / LTSSM traffic : scalar tx_data is broadcast on every lane.
   // FLIT data : the PL/controller drives tx_data_striped and raises tx_striped.
   always_comb begin
      for (int l = 0; l < `PCIE_NUM_LANES; l++)
         tx_data_lane[l] = tx_striped ? tx_data_striped[l] : tx_data;
   end

   // The scalar receive bus is lane 0. Ordered Sets are broadcast, so this is
   // also the logical word while the link is in training.
   assign rx_data = rx_data_lane[0];

   //----------------------------------------
   // Driver Clocking Block
   //----------------------------------------
   clocking cb_ep_drv @(posedge pclk);
      default input #1step output #1step;
      output tx_data;
      output tx_valid;
      output tx_elec_idle;
      output tx_detect_rx;
      output powerdown;
      output rate;

      input  rx_data;
      input  rx_valid;
      input  phy_status;
      input  rx_elec_idle;
      input  rx_status;
   endclocking
   //----------------------------------------
   // Monitor Clocking Block
   //----------------------------------------
   clocking cb_ep_mon @(negedge pclk);
      default input #1step;
      input tx_data;
      input tx_valid;
      input tx_elec_idle;
      input tx_detect_rx;
      input powerdown;
      input rate;
      input rx_data;
      input rx_valid;
      input phy_status;
      input rx_elec_idle;
      input rx_status;
   endclocking
   //----------------------------------------
   // Driver Modport
   //----------------------------------------
   modport mp_ep_driver (clocking cb_ep_drv);
   //----------------------------------------
   // Monitor Modport
   //----------------------------------------
   modport mp_ep_monitor (clocking cb_ep_mon);


   //==========================================================================
   //==========================================================================
   // [DL_ASSERT] EP DL state machine assertions (DL_INACTIVE -> DL_FEATURE -> DL_INIT -> DL_ACTIVE)
   //   Assertions cannot be written inside a class, so PCIe_EP_DL_model.sv copies its
   //   DL state/counters/flags into the signals below on every pclk negedge (run_dl_assert_mirror).
   //   The checks read them on every pclk posedge and give UVM_ERROR if a rule is broken.
   //
   //   Check name                            What it checks
   //   DL_START_STATE_CHECK                  DL starts in DL_INACTIVE
   //   DL_LINKUP_START_CHECK                 New link-up starts from DL_INACTIVE
   //   DL_<state>_NEXT_STATE_CHECK (5)       Only legal state moves
   //   DL_LINKDOWN_CHECK                     Link down -> DL_INACTIVE
   //   DL_TLP_ONLY_IN_ACTIVE_CHECK           TLP sent only in DL_ACTIVE
   //   DL_NO_DLLP_IN_INACTIVE_CHECK          No DLLP in DL_INACTIVE
   //   DL_RESET_COUNTERS/FLAGS/BUFFERS_CHECK On DL_INACTIVE : all values reset
   //   DL_START_DEFAULTS_CHECK               Default values at start
   //   DL_LINK_ACTIVE_ONLY_IN_ACTIVE_CHECK   dl_link_active = 1 only in DL_ACTIVE
   //   DL_ACTIVE_NEEDS_LINK_ACTIVE_CHECK     DL_ACTIVE always has dl_link_active = 1
   //   On failure the log shows : UVM_ERROR ... [<check name>] FAILED : <reason>
   //==========================================================================
   //==========================================================================
   import uvm_pkg::*;
   import typedef_enums::*;
   localparam string SIDE = "EP";

   //--------------------------------------------------------------------------
   // On / off
   //--------------------------------------------------------------------------
   bit assert_en    = 1'b1;   // 1 = checks ON. A test can set 0 to switch all DL checks OFF
   bit sample_valid = 1'b0;   // DL model sets 1 after its first copy. Checks wait for this

   //--------------------------------------------------------------------------
   // DL state : copied from the DL model on every falling edge of pclk
   //--------------------------------------------------------------------------
   dl_state_e          dl_state       = DL_INACTIVE;
   dl_init_substate_e  dl_init_sub    = INIT_FC1;
   bit                 dl_link_active;
   bit                 phy_linkup;

   // Sequence number counters (value in comment = value they must have in DL_INACTIVE)
   bit [`PCIe_SEQ_NUM_W-1:0]        next_tx_seq;        // NEXT_TX_FLIT_SEQ_NUM          default 001h
   bit [`PCIe_SEQ_NUM_W-1:0]        tx_acknak_seq;      // TX_ACKNAK_FLIT_SEQ_NUM        default 3FFh (1023)
   bit [`PCIe_SEQ_NUM_W-1:0]        ackd_seq;           // ACKD_FLIT_SEQ_NUM             default 3FFh
   bit [`PCIe_SEQ_NUM_W-1:0]        next_exp_rx_seq;    // NEXT_EXPECTED_RX_FLIT_SEQ_NUM default 001h
   bit [`PCIe_SEQ_NUM_W-1:0]        implicit_rx_seq;    // IMPLICIT_RX_FLIT_SEQ_NUM      default 000h
   bit [`PCIe_SEQ_NUM_W-1:0]        tx_replay_seq;      // TX_REPLAY_FLIT_SEQ_NUM        default 000h
   bit [`PCIe_SEQ_NUM_W-1:0]        nak_ignore_seq;     // NAK_IGNORE_FLIT_SEQ_NUM       default 000h
   bit [`PCIe_FLIT_REPLAY_NUM_W-1:0] flit_replay_num;   // FLIT_REPLAY_NUM               default 000b

   // ACK / NAK / replay flags (all must be 0 in DL_INACTIVE)
   bit nak_scheduled;
   bit ack_scheduled;
   bit replay_scheduled;
   bit replay_in_progress;
   bit nak_withdrawal_allowed;

   // Number of entries in the TX / RX retry buffers (must be 0 in DL_INACTIVE)
   int unsigned tx_retry_size;
   int unsigned rx_retry_size;

   //--------------------------------------------------------------------------
   // Flit sent events : the DL model updates these at the moment it sends a flit.
   // The count goes +1 for every flit, and *_dl_state saves the DL state at
   // that moment. A check sees "count changed" and looks at the saved state.
   //--------------------------------------------------------------------------
   int unsigned tx_payload_cnt;            // + 1 for every payload (TLP) flit sent to PL
   dl_state_e   tx_payload_dl_state = DL_INACTIVE;
   int unsigned tx_dllp_cnt;               // + 1 for every DLLP flit sent to PL
   dl_state_e   tx_dllp_dl_state    = DL_INACTIVE;
   bit [31:0]   tx_dllp_content;

   //--------------------------------------------------------------------------
   // dl_check_state : same as dl_state, but DL_INIT is split into
   //                  FC_INIT1 / FC_INIT2 so every state move can be checked
   //                  (STATE_ names : DL_ names already exist in enum_defs.sv)
   //--------------------------------------------------------------------------
   typedef enum {STATE_INACTIVE, STATE_FEATURE, STATE_FC_INIT1, STATE_FC_INIT2, STATE_ACTIVE} dl_check_state_e;
   dl_check_state_e dl_check_state;

   always_comb begin
      case (dl_state)
         DL_INACTIVE : dl_check_state = STATE_INACTIVE;
         DL_FEATURE  : dl_check_state = STATE_FEATURE;
         DL_INIT     : dl_check_state = (dl_init_sub == INIT_FC2) ? STATE_FC_INIT2 : STATE_FC_INIT1;
         default     : dl_check_state = STATE_ACTIVE;
      endcase
   end

   // Helper signals : 1 when all values are at their DL_INACTIVE default (used by DL_RESET_... checks)
   wire seq_default = (next_tx_seq     == 10'h001) && (tx_acknak_seq  == 10'h3FF) &&
                      (ackd_seq        == 10'h3FF) && (next_exp_rx_seq == 10'h001) &&
                      (implicit_rx_seq == 10'h000) && (tx_replay_seq   == 10'h000) &&
                      (nak_ignore_seq  == 10'h000) && (flit_replay_num == '0);
   wire flags_clear = !nak_scheduled && !ack_scheduled && !replay_scheduled &&
                      !replay_in_progress && !nak_withdrawal_allowed;
   wire buffers_empty = (tx_retry_size == 0) && (rx_retry_size == 0);

   //--------------------------------------------------------------------------
   // Every check below runs on the rising edge of pclk, and is OFF while
   // sample_valid = 0 (copy not started yet) or assert_en = 0 (switched off)
   //--------------------------------------------------------------------------
   default clocking dl_cb @(posedge pclk); endclocking
   default disable iff (!sample_valid || !assert_en);

   //==========================================================================
   // CHECK 1 : DL must start in DL_INACTIVE
   //==========================================================================
   // At start of simulation the DL state must be DL_INACTIVE.
   // (own disable : it checks the very first cycle where sample_valid becomes 1)
   DL_START_STATE_CHECK : assert property (
      @(posedge pclk) disable iff (!assert_en)
      $rose(sample_valid) |-> (dl_state == DL_INACTIVE))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_START_STATE_CHECK] FAILED : at start DL state must be DL_INACTIVE, but it is %s", dl_state.name()))

   // When the link comes up (phy_linkup 0 -> 1), DL must still be in DL_INACTIVE
   // (DL_FEATURE is also OK : the model leaves DL_INACTIVE in zero time).
   DL_LINKUP_START_CHECK : assert property (
      $rose(phy_linkup) |-> (dl_check_state inside {STATE_INACTIVE, STATE_FEATURE}))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_LINKUP_START_CHECK] FAILED : link came up but DL state is %s (expected DL_INACTIVE)", dl_check_state.name()))

   //==========================================================================
   // CHECK 2 : Only legal state moves
   //   INACTIVE -> FEATURE -> FC_INIT1 -> FC_INIT2 -> ACTIVE , any -> INACTIVE
   //==========================================================================
   // From DL_INACTIVE, next state must be DL_INACTIVE or DL_FEATURE
   DL_INACTIVE_NEXT_STATE_CHECK : assert property (
      (dl_check_state == STATE_INACTIVE) |=> (dl_check_state inside {STATE_INACTIVE, STATE_FEATURE}))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_INACTIVE_NEXT_STATE_CHECK] FAILED : from DL_INACTIVE only DL_FEATURE is allowed, but moved to %s", dl_check_state.name()))

   // From DL_FEATURE, next state must be DL_FEATURE, FC_INIT1 or DL_INACTIVE
   DL_FEATURE_NEXT_STATE_CHECK : assert property (
      (dl_check_state == STATE_FEATURE) |=> (dl_check_state inside {STATE_FEATURE, STATE_FC_INIT1, STATE_INACTIVE}))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_FEATURE_NEXT_STATE_CHECK] FAILED : from DL_FEATURE only FC_INIT1 or DL_INACTIVE is allowed, but moved to %s", dl_check_state.name()))

   // From FC_INIT1, next state must be FC_INIT1, FC_INIT2 or DL_INACTIVE
   DL_FC_INIT1_NEXT_STATE_CHECK : assert property (
      (dl_check_state == STATE_FC_INIT1) |=> (dl_check_state inside {STATE_FC_INIT1, STATE_FC_INIT2, STATE_INACTIVE}))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_FC_INIT1_NEXT_STATE_CHECK] FAILED : from FC_INIT1 only FC_INIT2 or DL_INACTIVE is allowed, but moved to %s", dl_check_state.name()))

   // From FC_INIT2, next state must be FC_INIT2, DL_ACTIVE or DL_INACTIVE
   DL_FC_INIT2_NEXT_STATE_CHECK : assert property (
      (dl_check_state == STATE_FC_INIT2) |=> (dl_check_state inside {STATE_FC_INIT2, STATE_ACTIVE, STATE_INACTIVE}))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_FC_INIT2_NEXT_STATE_CHECK] FAILED : from FC_INIT2 only DL_ACTIVE or DL_INACTIVE is allowed, but moved to %s", dl_check_state.name()))

   // From DL_ACTIVE, next state must be DL_ACTIVE or DL_INACTIVE
   DL_ACTIVE_NEXT_STATE_CHECK : assert property (
      (dl_check_state == STATE_ACTIVE) |=> (dl_check_state inside {STATE_ACTIVE, STATE_INACTIVE}))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_ACTIVE_NEXT_STATE_CHECK] FAILED : from DL_ACTIVE only DL_INACTIVE is allowed, but moved to %s", dl_check_state.name()))

   //==========================================================================
   // CHECK 3 : Link down -> DL_INACTIVE
   //==========================================================================
   // On an actual link-down event (phy_linkup 1 -> 0), in the next clock DL
   // state must be DL_INACTIVE. $fell() is used instead of the !phy_linkup
   // level: on link-up the DL FSM legitimately moves DL_INACTIVE -> DL_FEATURE
   // in the same cycle phy_linkup rises, and a level-based antecedent would
   // falsely flag that legal transition as a link-down failure.
   DL_LINKDOWN_CHECK : assert property (
      $fell(phy_linkup) |=> (dl_state == DL_INACTIVE))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_LINKDOWN_CHECK] FAILED : link went down (phy_linkup 1->0) but DL state is %s (expected DL_INACTIVE)", dl_check_state.name()))

   //==========================================================================
   // CHECK 4 : TLP (payload flit) only in DL_ACTIVE
   //==========================================================================
   // Every time a TLP flit is sent, DL state at that moment must be DL_ACTIVE
   DL_TLP_ONLY_IN_ACTIVE_CHECK : assert property (
      $changed(tx_payload_cnt) |-> (tx_payload_dl_state == DL_ACTIVE))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_TLP_ONLY_IN_ACTIVE_CHECK] FAILED : TLP flit sent in %s (TLPs allowed only in DL_ACTIVE)",
      tx_payload_dl_state.name()))

   //==========================================================================
   // CHECK 5 : No DLLP in DL_INACTIVE
   //==========================================================================
   // Every time a DLLP is sent, DL state at that moment must not be DL_INACTIVE
   DL_NO_DLLP_IN_INACTIVE_CHECK : assert property (
      $changed(tx_dllp_cnt) |-> (tx_dllp_dl_state != DL_INACTIVE))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_NO_DLLP_IN_INACTIVE_CHECK] FAILED : DLLP %08h sent while DL is in DL_INACTIVE", tx_dllp_content))

   //==========================================================================
   // CHECK 6 : On entering DL_INACTIVE, reset everything to default
   //   counters / flags / retry buffers. One pclk of grace (##[0:1]).
   //==========================================================================
   // s_enter_inactive : DL state is DL_INACTIVE now, and was NOT DL_INACTIVE in the last clock
   sequence s_enter_inactive;
      (dl_state == DL_INACTIVE) && ($past(dl_state) != DL_INACTIVE);
   endsequence

   // On entering DL_INACTIVE, all sequence counters must go back to default
   DL_RESET_COUNTERS_CHECK : assert property (
      s_enter_inactive |-> ##[0:1] seq_default)
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_RESET_COUNTERS_CHECK] FAILED : DL went to DL_INACTIVE but counters are not reset : NEXT_TX=%0d(exp 1) TX_ACKNAK=%0d(exp 1023) ACKD=%0d(exp 1023) NEXT_EXP_RX=%0d(exp 1) IMPLICIT_RX=%0d(exp 0) TX_REPLAY=%0d(exp 0) NAK_IGNORE=%0d(exp 0) FLIT_REPLAY_NUM=%0d(exp 0)",
      next_tx_seq, tx_acknak_seq, ackd_seq, next_exp_rx_seq, implicit_rx_seq, tx_replay_seq, nak_ignore_seq, flit_replay_num))

   // On entering DL_INACTIVE, all ACK / NAK / replay flags must be 0
   DL_RESET_FLAGS_CHECK : assert property (
      s_enter_inactive |-> ##[0:1] flags_clear)
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_RESET_FLAGS_CHECK] FAILED : DL went to DL_INACTIVE but flags are not cleared : NAK_SCHEDULED=%0b ACK_SCHEDULED=%0b REPLAY_SCHEDULED=%0b REPLAY_IN_PROGRESS=%0b NAK_WITHDRAWAL_ALLOWED=%0b",
      nak_scheduled, ack_scheduled, replay_scheduled, replay_in_progress, nak_withdrawal_allowed))

   // On entering DL_INACTIVE, TX and RX retry buffers must be empty
   DL_RESET_BUFFERS_CHECK : assert property (
      s_enter_inactive |-> ##[0:1] buffers_empty)
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_RESET_BUFFERS_CHECK] FAILED : DL went to DL_INACTIVE but retry buffers are not empty : TX_RETRY_BUFFER=%0d RX_RETRY_BUFFER=%0d entries",
      tx_retry_size, rx_retry_size))

   // At start of simulation, counters / flags / retry buffers must all be at default
   DL_START_DEFAULTS_CHECK : assert property (
      @(posedge pclk) disable iff (!assert_en)
      $rose(sample_valid) |-> (seq_default && flags_clear && buffers_empty))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_START_DEFAULTS_CHECK] FAILED : at start DL values are not default : NEXT_TX=%0d ACKD=%0d NEXT_EXP_RX=%0d IMPLICIT_RX=%0d TX_BUF=%0d RX_BUF=%0d",
      next_tx_seq, ackd_seq, next_exp_rx_seq, implicit_rx_seq, tx_retry_size, rx_retry_size))

   //==========================================================================
   // CHECK 7 : dl_link_active = 1 only in DL_ACTIVE
   //==========================================================================
   // If dl_link_active = 1, DL state must be DL_ACTIVE
   DL_LINK_ACTIVE_ONLY_IN_ACTIVE_CHECK : assert property (
      dl_link_active |-> (dl_state == DL_ACTIVE))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_LINK_ACTIVE_ONLY_IN_ACTIVE_CHECK] FAILED : dl_link_active=1 but DL state is %s", dl_check_state.name()))

   // If DL state is DL_ACTIVE, dl_link_active must be 1
   DL_ACTIVE_NEEDS_LINK_ACTIVE_CHECK : assert property (
      (dl_state == DL_ACTIVE) |-> dl_link_active)
   else `uvm_error({SIDE,"_DL_ASSERT"},
      "[DL_ACTIVE_NEEDS_LINK_ACTIVE_CHECK] FAILED : DL state is DL_ACTIVE but dl_link_active=0")

   //==========================================================================
   // Covers : count how many times each state move happened (0 = that move was never tested)
   //==========================================================================
   DL_COVER_INACTIVE_TO_FEATURE : cover property ((dl_check_state == STATE_INACTIVE) ##1 (dl_check_state == STATE_FEATURE));
   DL_COVER_FEATURE_TO_FC_INIT1 : cover property ((dl_check_state == STATE_FEATURE)  ##1 (dl_check_state == STATE_FC_INIT1));
   DL_COVER_FC_INIT1_TO_FC_INIT2: cover property ((dl_check_state == STATE_FC_INIT1) ##1 (dl_check_state == STATE_FC_INIT2));
   DL_COVER_FC_INIT2_TO_ACTIVE  : cover property ((dl_check_state == STATE_FC_INIT2) ##1 (dl_check_state == STATE_ACTIVE));
   DL_COVER_ACTIVE_TO_INACTIVE  : cover property ((dl_check_state == STATE_ACTIVE)   ##1 (dl_check_state == STATE_INACTIVE));
   DL_COVER_TLP_IN_ACTIVE       : cover property ($changed(tx_payload_cnt) && (tx_payload_dl_state == DL_ACTIVE));

   //==========================================================================
   // [DL_ASSERT] STATUS MESSAGES : show in the log that the DL checks are running
   //   Search "DL_STATUS" in the log. A summary is printed at the end of the test.
   //==========================================================================
   int unsigned     dl_moves_checked     = 0;  // DL state changes checked
   int unsigned     dl_tlps_checked      = 0;  // TLP flits checked
   int unsigned     dl_dllps_checked     = 0;  // DLLP flits checked
   int unsigned     dl_linkdowns_checked = 0;  // link-down events checked
   bit              dl_checks_started    = 0;  // 1 after the first check cycle
   dl_check_state_e prev_dl_check_state  = STATE_INACTIVE;
   int unsigned     prev_tx_payload_cnt  = 0;
   int unsigned     prev_tx_dllp_cnt     = 0;
   bit              prev_phy_linkup      = 0;

   // Every pclk rising edge : count what the checks looked at, print each DL state move
   always @(posedge pclk) begin
      if (sample_valid && assert_en) begin
         if (!dl_checks_started) begin
            dl_checks_started = 1;
            `uvm_info({SIDE,"_DL_STATUS"}, "DL assertions STARTED checking", UVM_LOW)
         end
         else begin
            if (dl_check_state != prev_dl_check_state) begin
               dl_moves_checked++;
               `uvm_info({SIDE,"_DL_STATUS"}, $sformatf("DL state move checked : %s -> %s",
                         prev_dl_check_state.name(), dl_check_state.name()), UVM_LOW)
            end
            dl_tlps_checked  += (tx_payload_cnt - prev_tx_payload_cnt);
            dl_dllps_checked += (tx_dllp_cnt    - prev_tx_dllp_cnt);
            if (prev_phy_linkup && !phy_linkup) dl_linkdowns_checked++;
         end
         prev_dl_check_state = dl_check_state;
         prev_tx_payload_cnt = tx_payload_cnt;
         prev_tx_dllp_cnt    = tx_dllp_cnt;
         prev_phy_linkup     = phy_linkup;
      end
   end

   // End of test : print a summary with the number of checks, failures and final result
   final begin
      uvm_report_server svr;
      int               fail_cnt;
      string            result;
      svr      = uvm_report_server::get_server();
      fail_cnt = svr.get_id_count({SIDE,"_DL_ASSERT"});   // number of DL assertion UVM_ERRORs
      if (!dl_checks_started) result = "NOT CHECKED";
      else if (fail_cnt == 0) result = "PASSED";
      else                    result = "FAILED";
      `uvm_info({SIDE,"_DL_STATUS"}, $sformatf({"\n",
         "  DL assertion failures    : %0d\n",
         "  DL assertions            : %s\n"},
         fail_cnt, result), UVM_LOW)
   end

   // [DL_ASSERT] end of DL assertions

   //==========================================================================
   // [TL_ASSERT] EP TRANSACTION LAYER ASSERTIONS
   //   The EP TL model writes these variables through its handle tl_aif.
   //   RX  : 236 B request received from DL -> decoded
   //   CPL : Non-Posted request -> 236 B completion formed (tl_cpl_ready = 1)
   //         -> sent TL -> DL (tl_cpl_ready = 0)
   //   Search "EP_TL_ASSERT" in the log for failures.
   //==========================================================================
   bit          tl_assert_en    = 1'b1;   // 1 = TL checks ON (a test can set 0)
   bit          tl_sample_valid = 1'b0;   // EP TL model sets 1 at start of simulation

   // RX : DL -> TL
   int unsigned tl_rx_cnt;                // +1 when a 236 B request comes from the DL
   int unsigned tl_rx_done_cnt;           // +1 when its processing is finished

   // Non-Posted requests
   int unsigned tl_np_rx_cnt;             // +1 Non-Posted request received (needs a completion)
   int unsigned tl_np_done_cnt;           // +1 its completion was sent

   // CPL : TL -> DL
   bit          tl_cpl_ready;             // 1 = 236 B completion formed, not yet sent to DL
   int unsigned tl_cpl_formed_cnt;        // +1 when a 236 B completion is formed
   int unsigned tl_cpl_sent_cnt;          // +1 when a completion is sent TL -> DL

   //--------------------------------------------------------------------------
   // CHECK 1 : every 236 B request received from the DL is processed
   //--------------------------------------------------------------------------
   TL_RX_DONE_CHECK : assert property (
      @(posedge pclk) disable iff (!tl_sample_valid || !tl_assert_en)
      (tl_rx_cnt == tl_rx_done_cnt))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_RX_DONE_CHECK] FAILED : requests received=%0d but processed=%0d", tl_rx_cnt, tl_rx_done_cnt))

   //--------------------------------------------------------------------------
   // CHECK 2 : every Non-Posted request gets its completion
   //--------------------------------------------------------------------------
   TL_NP_GETS_CPL_CHECK : assert property (
      @(posedge pclk) disable iff (!tl_sample_valid || !tl_assert_en)
      (tl_np_rx_cnt == tl_np_done_cnt))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_NP_GETS_CPL_CHECK] FAILED : Non-Posted requests=%0d but completed=%0d", tl_np_rx_cnt, tl_np_done_cnt))

   //--------------------------------------------------------------------------
   // CHECK 3 : a formed 236 B completion (ready = 1) must be sent to the DL
   //--------------------------------------------------------------------------
   TL_CPL_READY_THEN_SENT_CHECK : assert property (
      @(posedge pclk) disable iff (!tl_sample_valid || !tl_assert_en)
      tl_cpl_ready |-> ##[0:`PCIe_TL_HANDOFF_CLKS] !tl_cpl_ready)
   else `uvm_error({SIDE,"_TL_ASSERT"},
      "[TL_CPL_READY_THEN_SENT_CHECK] FAILED : 236B completion formed (tl_cpl_ready=1) but not sent to DL")

   //--------------------------------------------------------------------------
   // CHECK 4 : every formed completion was sent (count formed = count sent)
   //--------------------------------------------------------------------------
   TL_CPL_FORMED_EQ_SENT_CHECK : assert property (
      @(posedge pclk) disable iff (!tl_sample_valid || !tl_assert_en)
      (tl_cpl_formed_cnt == tl_cpl_sent_cnt))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_CPL_FORMED_EQ_SENT_CHECK] FAILED : completions formed=%0d but sent to DL=%0d",
      tl_cpl_formed_cnt, tl_cpl_sent_cnt))

   //--------------------------------------------------------------------------
   // CHECKS 5-6 : the 236 B completion holds the right type and tag
   //   Called by the EP TL model once for every completion it forms.
   //--------------------------------------------------------------------------
   function automatic void tl_cpl_tx_check(
      input bit [0:`PCIe_TLP_DATA_BYTE_W-1][7:0] tlp,
      input bit          flit,
      input bit          has_data,
      input bit [13:0]   exp_tag);

      bit [13:0] got_tag;

      if (!tl_sample_valid || !tl_assert_en) return;

      // CHECK 5 : CplD (4Ah) if it carries data, Cpl (0Ah) if not
      TL_CPL_TYPE_CHECK : assert (tlp[0] == (has_data ? `PCIe_FLITTYPE_CPLD : `PCIe_FLITTYPE_CPL))
      else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
         "[TL_CPL_TYPE_CHECK] FAILED : type byte = 0x%02h for a %s", tlp[0], has_data ? "CplD" : "Cpl"))

      // CHECK 6 : completion tag = tag of the request
      //   Flit : DW1[13:0] (bytes 6-7)   Non-Flit : {DW0[23], DW0[19], DW2[15:8]}
      if (flit) got_tag = {tlp[6][5:0], tlp[7]};
      else      got_tag = {4'h0, tlp[1][7], tlp[1][3], tlp[10]};
      TL_CPL_TAG_CHECK : assert (flit ? (got_tag == exp_tag) : (got_tag[9:0] == exp_tag[9:0]))
      else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
         "[TL_CPL_TAG_CHECK] FAILED : completion tag = 0x%0h, request tag = 0x%0h", got_tag, exp_tag))
   endfunction

   // end of test : one summary line
   final
      `uvm_info({SIDE,"_TL_STATUS"}, $sformatf(
         "TL summary : requests received=%0d processed=%0d | Non-Posted=%0d completed=%0d | completions formed=%0d sent=%0d",
         tl_rx_cnt, tl_rx_done_cnt, tl_np_rx_cnt, tl_np_done_cnt, tl_cpl_formed_cnt, tl_cpl_sent_cnt), UVM_LOW)

   // [TL_ASSERT] end of TL assertions

endinterface

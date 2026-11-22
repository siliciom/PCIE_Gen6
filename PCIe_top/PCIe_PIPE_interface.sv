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
   // [DL_ASSERT] RC DL state machine assertions (PCIe 6.1 Sec 3.2)
   //   PCIe_RC_DL_model.sv copies its state/counters/flags here every pclk negedge.
   //   Checks run every pclk posedge : state moves, DL_Up/DL_Down, link up/down, reset values.
   //   On failure : UVM_ERROR [RC_DL_ASSERT] [<check name>] FAILED : <reason>
   //==========================================================================
   import uvm_pkg::*;
   import typedef_enums::*;
   localparam string SIDE = "RC";

   //--------------------------------------------------------------------------
   // On / off
   //--------------------------------------------------------------------------
   logic assert_en    = 1'b1;   // 1 = checks ON. A test can set 0 to switch all DL checks OFF
   logic sample_valid = 1'b0;   // DL model sets 1 after its first copy. Checks wait for this

   //--------------------------------------------------------------------------
   // DL state : copied from the DL model on every falling edge of pclk
   //--------------------------------------------------------------------------
   dl_state_e          dl_state       = DL_INACTIVE;
   dl_init_substate_e  dl_init_sub    = INIT_FC1;
   logic               dl_link_active;
   logic               phy_linkup;

   // Sequence number counters (value in comment = value they must have in DL_INACTIVE)
   logic [`PCIe_SEQ_NUM_W-1:0]      next_tx_seq;        // NEXT_TX_FLIT_SEQ_NUM          default 001h
   logic [`PCIe_SEQ_NUM_W-1:0]      tx_acknak_seq;      // TX_ACKNAK_FLIT_SEQ_NUM        default 3FFh (1023)
   logic [`PCIe_SEQ_NUM_W-1:0]      ackd_seq;           // ACKD_FLIT_SEQ_NUM             default 3FFh
   logic [`PCIe_SEQ_NUM_W-1:0]      next_exp_rx_seq;    // NEXT_EXPECTED_RX_FLIT_SEQ_NUM default 001h
   logic [`PCIe_SEQ_NUM_W-1:0]      implicit_rx_seq;    // IMPLICIT_RX_FLIT_SEQ_NUM      default 000h
   logic [`PCIe_SEQ_NUM_W-1:0]      tx_replay_seq;      // TX_REPLAY_FLIT_SEQ_NUM        default 000h
   logic [`PCIe_SEQ_NUM_W-1:0]      nak_ignore_seq;     // NAK_IGNORE_FLIT_SEQ_NUM       default 000h
   logic [`PCIe_FLIT_REPLAY_NUM_W-1:0] flit_replay_num;   // FLIT_REPLAY_NUM               default 000b

   // ACK / NAK / replay flags (all must be 0 in DL_INACTIVE)
   logic nak_scheduled;
   logic ack_scheduled;
   logic replay_scheduled;
   logic replay_in_progress;
   logic nak_withdrawal_allowed;

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
   logic [`PCIe_DLLP_CONTENT_W-1:0] tx_dllp_content;

   //--------------------------------------------------------------------------
   // dl_curr_state : DL state NOW (same as dl_state, but DL_INIT is split into
   //                 FC_INIT1 / FC_INIT2 so every state move can be checked)
   //                  (STATE_ names : DL_ names already exist in enum_defs.sv)
   //--------------------------------------------------------------------------
   dl_curr_state_e dl_curr_state;

   always_comb begin
      case (dl_state)
         DL_INACTIVE : dl_curr_state = STATE_INACTIVE;
         DL_FEATURE  : dl_curr_state = STATE_FEATURE;
         DL_INIT     : dl_curr_state = (dl_init_sub == INIT_FC2) ? STATE_FC_INIT2 : STATE_FC_INIT1;
         default     : dl_curr_state = STATE_ACTIVE;
      endcase
   end

   // DL status reported to the TL (spec Sec 3.2.1)
   //   DL_Down : DL_INACTIVE, DL_FEATURE, FC_INIT1
   //   DL_Up   : FC_INIT2, DL_ACTIVE
   logic dl_up;
   logic dl_down;

   always_comb begin
      case (dl_curr_state)
         STATE_INACTIVE : begin dl_down = 1'b1; dl_up = 1'b0; end
         STATE_FEATURE  : begin dl_down = 1'b1; dl_up = 1'b0; end
         STATE_FC_INIT1 : begin dl_down = 1'b1; dl_up = 1'b0; end
         STATE_FC_INIT2 : begin dl_down = 1'b0; dl_up = 1'b1; end
         STATE_ACTIVE   : begin dl_down = 1'b0; dl_up = 1'b1; end
         default        : begin dl_down = 1'b1; dl_up = 1'b0; end
      endcase
   end

   // values in the last pclk (to see "what was it before")
   dl_curr_state_e dl_prev_state = STATE_INACTIVE;
   logic            dl_prev_up    = 1'b0;
   logic            dl_prev_down  = 1'b1;

   always @(posedge pclk) begin
      dl_prev_state <= dl_curr_state;
      dl_prev_up    <= dl_up;
      dl_prev_down  <= dl_down;
   end

   // Helper signals : 1 when all values are at their DL_INACTIVE default (used by DL_RESET_... checks)
   logic seq_default;      // 1 = all 8 sequence counters are at reset value
   logic flags_clear;      // 1 = all 5 Ack / Nak / replay flags are 0
   logic buffers_empty;    // 1 = TX and RX retry buffers are empty

   always_comb begin
      seq_default   = (next_tx_seq     == `PCIe_INIT_NEXT_TX_FLIT_SEQ_NUM)          &&
                      (tx_acknak_seq   == `PCIe_INIT_TX_ACKNAK_SEQ_NUM)             &&
                      (ackd_seq        == `PCIe_INIT_ACKD_FLIT_SEQ_NUM)             &&
                      (next_exp_rx_seq == `PCIe_INIT_NEXT_EXPECTED_RX_FLIT_SEQ_NUM) &&
                      (implicit_rx_seq == `PCIe_INIT_IMPLICIT_RX_FLIT_SEQ_NUM)      &&
                      (tx_replay_seq   == `PCIe_INIT_TX_REPLAY_FLIT_SEQ_NUM)        &&
                      (nak_ignore_seq  == `PCIe_INIT_NAK_IGNORE_FLIT_SEQ_NUM)       &&
                      (flit_replay_num == `PCIe_INIT_FLIT_REPLAY_NUM);

      flags_clear   = (nak_scheduled          == 1'b0) &&
                      (ack_scheduled          == 1'b0) &&
                      (replay_scheduled       == 1'b0) &&
                      (replay_in_progress     == 1'b0) &&
                      (nak_withdrawal_allowed == 1'b0);

      buffers_empty = (tx_retry_size == 0) && (rx_retry_size == 0);
   end

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

   // Before the link comes up, DL must be in DL_INACTIVE with DL_Down = 1, DL_Up = 0.
   // So when phy_linkup goes 0 -> 1, the values in the last pclk are checked.
   DL_LINKUP_START_CHECK : assert property (
      $rose(phy_linkup) |-> (dl_prev_state == STATE_INACTIVE) && (dl_prev_down == 1'b1) && (dl_prev_up == 1'b0))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_LINKUP_START_CHECK] FAILED : link came up but before it DL was %s, DL_Down=%0b, DL_Up=%0b (expected DL_INACTIVE, 1, 0)",
      dl_prev_state.name(), dl_prev_down, dl_prev_up))

   //==========================================================================
   // CHECK 2 : One check for each state move (spec Figure 3-2, Sec 3.2.1)
   //
   //   DL_INACTIVE -> DL_FEATURE -> FC_INIT1 -> FC_INIT2 -> DL_ACTIVE
   //   (link down from any state -> DL_INACTIVE : see CHECK 3)
   //
   //   dl_prev_state = state in the last pclk
   //   dl_curr_state = state now
   //   "left X"       = dl_prev_state is X and dl_curr_state is not X
   //==========================================================================

   // DL_INACTIVE -> DL_FEATURE  (DL_Down = 1, DL_Up = 0)
   DL_INACTIVE_TO_FEATURE_CHECK : assert property (
      (dl_prev_state == STATE_INACTIVE) && (dl_curr_state != STATE_INACTIVE)
      |-> (dl_curr_state == STATE_FEATURE) && (dl_down == 1'b1) && (dl_up == 1'b0))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_INACTIVE_TO_FEATURE_CHECK] FAILED : left DL_INACTIVE, expected DL_FEATURE / DL_Down=1 / DL_Up=0, got %s / DL_Down=%0b / DL_Up=%0b",
      dl_curr_state.name(), dl_down, dl_up))

   // DL_FEATURE -> FC_INIT1  (link still up)  (DL_Down = 1, DL_Up = 0)
   DL_FEATURE_TO_FC_INIT1_CHECK : assert property (
      (dl_prev_state == STATE_FEATURE) && (dl_curr_state != STATE_FEATURE) && (phy_linkup == 1'b1)
      |-> (dl_curr_state == STATE_FC_INIT1) && (dl_down == 1'b1) && (dl_up == 1'b0))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_FEATURE_TO_FC_INIT1_CHECK] FAILED : left DL_FEATURE, expected FC_INIT1 / DL_Down=1 / DL_Up=0, got %s / DL_Down=%0b / DL_Up=%0b",
      dl_curr_state.name(), dl_down, dl_up))

   // FC_INIT1 -> FC_INIT2  (link still up)  (DL_Down = 0, DL_Up = 1)
   DL_FC_INIT1_TO_FC_INIT2_CHECK : assert property (
      (dl_prev_state == STATE_FC_INIT1) && (dl_curr_state != STATE_FC_INIT1) && (phy_linkup == 1'b1)
      |-> (dl_curr_state == STATE_FC_INIT2) && (dl_down == 1'b0) && (dl_up == 1'b1))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_FC_INIT1_TO_FC_INIT2_CHECK] FAILED : left FC_INIT1, expected FC_INIT2 / DL_Down=0 / DL_Up=1, got %s / DL_Down=%0b / DL_Up=%0b",
      dl_curr_state.name(), dl_down, dl_up))

   // FC_INIT2 -> DL_ACTIVE  (link still up)  (DL_Down = 0, DL_Up = 1)
   DL_FC_INIT2_TO_ACTIVE_CHECK : assert property (
      (dl_prev_state == STATE_FC_INIT2) && (dl_curr_state != STATE_FC_INIT2) && (phy_linkup == 1'b1)
      |-> (dl_curr_state == STATE_ACTIVE) && (dl_down == 1'b0) && (dl_up == 1'b1))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_FC_INIT2_TO_ACTIVE_CHECK] FAILED : left FC_INIT2, expected DL_ACTIVE / DL_Down=0 / DL_Up=1, got %s / DL_Down=%0b / DL_Up=%0b",
      dl_curr_state.name(), dl_down, dl_up))

   // DL_ACTIVE -> DL_INACTIVE  (DL_Down = 1, DL_Up = 0)
   DL_ACTIVE_TO_INACTIVE_CHECK : assert property (
      (dl_prev_state == STATE_ACTIVE) && (dl_curr_state != STATE_ACTIVE)
      |-> (dl_curr_state == STATE_INACTIVE) && (dl_down == 1'b1) && (dl_up == 1'b0))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_ACTIVE_TO_INACTIVE_CHECK] FAILED : left DL_ACTIVE, expected DL_INACTIVE / DL_Down=1 / DL_Up=0, got %s / DL_Down=%0b / DL_Up=%0b",
      dl_curr_state.name(), dl_down, dl_up))

   //==========================================================================
   // CHECK 3 : Link down -> DL_INACTIVE
   //==========================================================================
   // On an actual link-down event (phy_linkup 1 -> 0), in the next clock DL
   // state must be DL_INACTIVE. $fell() is used instead of the !phy_linkup
   // level: on link-up the DL FSM legitimately moves DL_INACTIVE -> DL_FEATURE
   // in the same cycle phy_linkup rises, and a level-based antecedent would
   // falsely flag that legal transition as a link-down failure.
   DL_LINKDOWN_CHECK : assert property (
      $fell(phy_linkup) |=> (dl_state == DL_INACTIVE) && (dl_down == 1'b1) && (dl_up == 1'b0))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_LINKDOWN_CHECK] FAILED : link went down but DL is %s, DL_Down=%0b, DL_Up=%0b (expected DL_INACTIVE, 1, 0)",
      dl_curr_state.name(), dl_down, dl_up))

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
   //   counters / flags / retry buffers. Grace time : `PCIe_DL_RESET_GRACE_CLKS pclk.
   //==========================================================================
   // s_enter_inactive : DL state is DL_INACTIVE now, and was NOT DL_INACTIVE in the last clock
   sequence s_enter_inactive;
      (dl_state == DL_INACTIVE) && ($past(dl_state) != DL_INACTIVE);
   endsequence

   // On entering DL_INACTIVE, all sequence counters must go back to default
   DL_RESET_COUNTERS_CHECK : assert property (
      s_enter_inactive |-> ##[0:`PCIe_DL_RESET_GRACE_CLKS] seq_default)
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_RESET_COUNTERS_CHECK] FAILED : DL went to DL_INACTIVE but counters are not reset : NEXT_TX=%0d(exp %0d) TX_ACKNAK=%0d(exp %0d) ACKD=%0d(exp %0d) NEXT_EXP_RX=%0d(exp %0d) IMPLICIT_RX=%0d(exp %0d) TX_REPLAY=%0d(exp %0d) NAK_IGNORE=%0d(exp %0d) FLIT_REPLAY_NUM=%0d(exp %0d)",
      next_tx_seq,     `PCIe_INIT_NEXT_TX_FLIT_SEQ_NUM,
      tx_acknak_seq,   `PCIe_INIT_TX_ACKNAK_SEQ_NUM,
      ackd_seq,        `PCIe_INIT_ACKD_FLIT_SEQ_NUM,
      next_exp_rx_seq, `PCIe_INIT_NEXT_EXPECTED_RX_FLIT_SEQ_NUM,
      implicit_rx_seq, `PCIe_INIT_IMPLICIT_RX_FLIT_SEQ_NUM,
      tx_replay_seq,   `PCIe_INIT_TX_REPLAY_FLIT_SEQ_NUM,
      nak_ignore_seq,  `PCIe_INIT_NAK_IGNORE_FLIT_SEQ_NUM,
      flit_replay_num, `PCIe_INIT_FLIT_REPLAY_NUM))

   // On entering DL_INACTIVE, all ACK / NAK / replay flags must be 0
   DL_RESET_FLAGS_CHECK : assert property (
      s_enter_inactive |-> ##[0:`PCIe_DL_RESET_GRACE_CLKS] flags_clear)
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_RESET_FLAGS_CHECK] FAILED : DL went to DL_INACTIVE but flags are not cleared : NAK_SCHEDULED=%0b ACK_SCHEDULED=%0b REPLAY_SCHEDULED=%0b REPLAY_IN_PROGRESS=%0b NAK_WITHDRAWAL_ALLOWED=%0b",
      nak_scheduled, ack_scheduled, replay_scheduled, replay_in_progress, nak_withdrawal_allowed))

   // On entering DL_INACTIVE, TX and RX retry buffers must be empty
   DL_RESET_BUFFERS_CHECK : assert property (
      s_enter_inactive |-> ##[0:`PCIe_DL_RESET_GRACE_CLKS] buffers_empty)
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
      "[DL_LINK_ACTIVE_ONLY_IN_ACTIVE_CHECK] FAILED : dl_link_active=1 but DL state is %s", dl_curr_state.name()))

   // If DL state is DL_ACTIVE, dl_link_active must be 1
   DL_ACTIVE_NEEDS_LINK_ACTIVE_CHECK : assert property (
      (dl_state == DL_ACTIVE) |-> dl_link_active)
   else `uvm_error({SIDE,"_DL_ASSERT"},
      "[DL_ACTIVE_NEEDS_LINK_ACTIVE_CHECK] FAILED : DL state is DL_ACTIVE but dl_link_active=0")

   //==========================================================================
   // Covers : count how many times each state move happened (0 = that move was never tested)
   //==========================================================================
   DL_COVER_INACTIVE_TO_FEATURE : cover property ((dl_curr_state == STATE_INACTIVE) ##1 (dl_curr_state == STATE_FEATURE));
   DL_COVER_FEATURE_TO_FC_INIT1 : cover property ((dl_curr_state == STATE_FEATURE)  ##1 (dl_curr_state == STATE_FC_INIT1));
   DL_COVER_FC_INIT1_TO_FC_INIT2: cover property ((dl_curr_state == STATE_FC_INIT1) ##1 (dl_curr_state == STATE_FC_INIT2));
   DL_COVER_FC_INIT2_TO_ACTIVE  : cover property ((dl_curr_state == STATE_FC_INIT2) ##1 (dl_curr_state == STATE_ACTIVE));
   DL_COVER_ACTIVE_TO_INACTIVE  : cover property ((dl_curr_state == STATE_ACTIVE)   ##1 (dl_curr_state == STATE_INACTIVE));
   DL_COVER_TLP_IN_ACTIVE       : cover property ($changed(tx_payload_cnt) && (tx_payload_dl_state == DL_ACTIVE));

   //==========================================================================
   // STATUS MESSAGES : search "DL_STATUS" in the log
   //==========================================================================
   logic dl_checks_started = 1'b0;   // 1 after the first check clock

   // Print when the checks start, and print every DL state move
   always @(posedge pclk) begin
      if (sample_valid && assert_en) begin
         if (dl_checks_started == 1'b0) begin
            dl_checks_started = 1'b1;
            `uvm_info({SIDE,"_DL_STATUS"}, "DL assertions STARTED checking", UVM_LOW)
         end
         else if (dl_curr_state != dl_prev_state) begin
            `uvm_info({SIDE,"_DL_STATUS"}, $sformatf("DL state move checked : %s -> %s",
                      dl_prev_state.name(), dl_curr_state.name()), UVM_LOW)
         end
      end
   end

   // End of test : count the DL assertion errors and print PASSED / FAILED
   final begin
      uvm_report_server svr;
      int unsigned      fail_cnt;
      string            result;
      svr      = uvm_report_server::get_server();
      fail_cnt = svr.get_id_count({SIDE,"_DL_ASSERT"});
      if      (dl_checks_started == 1'b0) result = "NOT CHECKED";
      else if (fail_cnt == 0)             result = "PASSED";
      else                                result = "FAILED";
      `uvm_info({SIDE,"_DL_STATUS"}, $sformatf("\n  DL assertion failures    : %0d\n  DL assertions            : %s\n",
                fail_cnt, result), UVM_LOW)
   end

   // [DL_ASSERT] end of DL assertions

   //==========================================================================
   //==========================================================================
   // [TL_ASSERT] RC Transaction Layer assertions (PCIe 6.0 Sec 2)
   //   PCIe_RC_TL_model.sv writes the values below through its handle tl_aif :
   //     tl_tx_sample()  : once for every TLP sent TL -> DL
   //     tl_cpl_sample() : once for every completion received from the DL
   //     tl_rx_cnt / tl_rx_done_cnt : +1 before / after every TLP decode
   //   Checks run every pclk posedge. A check looks at "count changed" and
   //   then at the values saved with it (same way as the DL checks above).
   //   On failure : UVM_ERROR [RC_TL_ASSERT] [<check name>] FAILED : <reason>
   //==========================================================================
   //==========================================================================

   //--------------------------------------------------------------------------
   // On / off
   //--------------------------------------------------------------------------
   logic tl_assert_en    = 1'b1;   // 1 = checks ON. A test can set 0 to switch all TL checks OFF
   logic tl_sample_valid = 1'b0;   // TL model sets 1 at start of simulation. Checks wait for this
   wire  tl_off          = !tl_sample_valid || !tl_assert_en;

   //--------------------------------------------------------------------------
   // TX : TLP sent TL -> DL (saved at the moment it is sent)
   //   *_exp = value in the request (sequence item)
   //   *_got = value read back from the 236 B handed to the DL
   //--------------------------------------------------------------------------
   int unsigned tl_tx_cnt;                 // + 1 for every TLP sent to the DL
   logic [7:0]  tl_tx_type_exp, tl_tx_type_got;   // Type byte (Flit) / Fmt+Type byte (Non-Flit)
   logic [9:0]  tl_tx_len_exp,  tl_tx_len_got;    // Length field
   logic        tl_tx_has_tag;                    // 0 for Flit Mode Messages (no Tag field)
   logic [13:0] tl_tx_tag_exp,  tl_tx_tag_got;    // Tag
   logic        tl_tx_ep_exp,   tl_tx_ep_got;     // EP (Poisoned) bit
   int unsigned tl_tx_data_bad;                   // payload DWs that differ from the request data
   logic        tl_tx_np;                         // 1 = Non-Posted request

   //--------------------------------------------------------------------------
   // RX : TLP received DL -> TL
   //--------------------------------------------------------------------------
   int unsigned tl_rx_cnt;                 // + 1 when a TLP comes from the DL
   int unsigned tl_rx_done_cnt;            // + 1 when its decode is finished

   // Completion received (saved at the moment it is decoded)
   int unsigned tl_cpl_cnt;                // + 1 for every completion received
   logic        tl_cpl_matched;            // 1 = its tag belongs to a request we sent
   logic [2:0]  tl_cpl_status;             // Completion Status
   logic        tl_cpl_has_data;           // 1 = CplD, 0 = Cpl
   logic [2:0]  tl_cpl_tc;                 // TC of the completion
   logic [2:0]  tl_cpl_req_tc;             // TC of its request

   //--------------------------------------------------------------------------
   // tl_tx_sample : called by the RC TL model for every TLP it sends.
   //   Reads Type / Length / Tag / EP / payload back from the 236 B.
   //   pfx    : 1 = a 1 DW Flit Mode prefix is in front of the header
   //   hdr_dw : header DWs (Header Base + OHC), the payload starts after them
   //--------------------------------------------------------------------------
   function automatic void tl_tx_sample(
      input bit [0:`PCIe_TLP_DATA_BYTE_W-1][7:0] tlp,
      input bit          flit,
      input bit          pfx,
      input bit [7:0]    exp_type,
      input bit [9:0]    exp_len,
      input bit          has_tag,
      input bit [13:0]   exp_tag,
      input bit          exp_ep,
      input int unsigned hdr_dw,
      input bit [31:0]   exp_data[],
      input bit          np);

      int unsigned b0;           // byte where the TLP header starts
      int unsigned p;            // byte where payload DW i starts
      int unsigned bad;

      b0 = pfx ? 4 : 0;

      tl_tx_type_exp = exp_type;
      tl_tx_type_got = tlp[b0];
      tl_tx_len_exp  = exp_len;
      tl_tx_len_got  = {tlp[b0+2][1:0], tlp[b0+3]};
      tl_tx_has_tag  = has_tag;
      tl_tx_ep_exp   = exp_ep;
      if (flit) begin
         // DW1 : [31:16] Requester ID  [15] EP  [14] R  [13:0] Tag
         tl_tx_ep_got  = tlp[b0+6][7];
         tl_tx_tag_got = {tlp[b0+6][5:0], tlp[b0+7]};
         tl_tx_tag_exp = exp_tag;
      end
      else begin
         // DW0 [23] T9 [19] T8 [14] EP , DW1 [15:8] Tag[7:0]
         tl_tx_ep_got  = tlp[b0+2][6];
         tl_tx_tag_got = {4'h0, tlp[b0+1][7], tlp[b0+1][3], tlp[b0+6]};
         tl_tx_tag_exp = {4'h0, exp_tag[9:0]};
      end

      bad = 0;
      foreach (exp_data[i]) begin
         p = b0 + (hdr_dw + i) * 4;
         if ((p + 3) < `PCIe_TLP_DATA_BYTE_W)
            if ({tlp[p], tlp[p+1], tlp[p+2], tlp[p+3]} != exp_data[i]) bad++;
      end
      tl_tx_data_bad = bad;
      tl_tx_np       = np;
      tl_tx_cnt++;                      // event : the checks see "count changed"
   endfunction

   //--------------------------------------------------------------------------
   // tl_cpl_sample : called by the RC TL model for every completion received
   //--------------------------------------------------------------------------
   function automatic void tl_cpl_sample(
      input bit       matched,
      input bit [2:0] status,
      input bit       has_data,
      input bit [2:0] tc,
      input bit [2:0] req_tc);
      tl_cpl_matched  = matched;
      tl_cpl_status   = status;
      tl_cpl_has_data = has_data;
      tl_cpl_tc       = tc;
      tl_cpl_req_tc   = req_tc;
      tl_cpl_cnt++;                     // event : the checks see "count changed"
   endfunction

   //--------------------------------------------------------------------------
   // Every check below runs on the rising edge of pclk (default clocking above),
   // and is OFF while tl_sample_valid = 0 or tl_assert_en = 0 (tl_off = 1)
   //--------------------------------------------------------------------------

   //==========================================================================
   // CHECK 1 : at start nothing has been sent or received
   //==========================================================================
   TL_START_CHECK : assert property (
      @(posedge pclk) disable iff (!tl_assert_en)
      $rose(tl_sample_valid) |-> (tl_tx_cnt == 0) && (tl_cpl_cnt == 0))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_START_CHECK] FAILED : at start TLPs sent=%0d completions=%0d (expected 0, 0)", tl_tx_cnt, tl_cpl_cnt))

   //==========================================================================
   // CHECK 2 : the TLP sent to the DL holds the request (Sec 2.2)
   //==========================================================================
   // Type byte = type of the request (e.g. 40h = MWr 32-bit, 5Bh = DMWr 32-bit)
   TL_TX_TYPE_CHECK : assert property (disable iff (tl_off)
      $changed(tl_tx_cnt) |-> (tl_tx_type_got == tl_tx_type_exp))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_TX_TYPE_CHECK] FAILED : type byte = 0x%02h, expected 0x%02h", tl_tx_type_got, tl_tx_type_exp))

   // Length field = Length of the request
   TL_TX_LENGTH_CHECK : assert property (disable iff (tl_off)
      $changed(tl_tx_cnt) |-> (tl_tx_len_got == tl_tx_len_exp))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_TX_LENGTH_CHECK] FAILED : Length field = %0d, expected %0d", tl_tx_len_got, tl_tx_len_exp))

   // Tag field = Tag of the request (Flit Mode Messages have no Tag)
   TL_TX_TAG_CHECK : assert property (disable iff (tl_off)
      $changed(tl_tx_cnt) && tl_tx_has_tag |-> (tl_tx_tag_got == tl_tx_tag_exp))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_TX_TAG_CHECK] FAILED : Tag field = 0x%0h, expected 0x%0h", tl_tx_tag_got, tl_tx_tag_exp))

   // EP bit = EP of the request (1 only for a Poisoned TLP)
   TL_TX_EP_CHECK : assert property (disable iff (tl_off)
      $changed(tl_tx_cnt) |-> (tl_tx_ep_got == tl_tx_ep_exp))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_TX_EP_CHECK] FAILED : EP bit = %0b, expected %0b", tl_tx_ep_got, tl_tx_ep_exp))

   // Every payload DW = the data of the request
   TL_TX_PAYLOAD_CHECK : assert property (disable iff (tl_off)
      $changed(tl_tx_cnt) |-> (tl_tx_data_bad == 0))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_TX_PAYLOAD_CHECK] FAILED : %0d payload DW differ from the request data", tl_tx_data_bad))

   //==========================================================================
   // CHECK 3 : every TLP received from the DL is decoded
   //==========================================================================
   TL_RX_DECODE_CHECK : assert property (disable iff (tl_off)
      (tl_rx_cnt == tl_rx_done_cnt))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_RX_DECODE_CHECK] FAILED : TLPs received from DL=%0d but decoded=%0d", tl_rx_cnt, tl_rx_done_cnt))

   //==========================================================================
   // CHECK 4 : completion rules (Sec 2.2.9, 2.3.2)
   //==========================================================================
   // A completion must belong to a request we sent (tag outstanding)
   TL_CPL_MATCH_CHECK : assert property (disable iff (tl_off)
      $changed(tl_cpl_cnt) |-> tl_cpl_matched)
   else `uvm_error({SIDE,"_TL_ASSERT"},
      "[TL_CPL_MATCH_CHECK] FAILED : completion received for a tag that is not outstanding (Unexpected Completion)")

   // Completion Status must be SC, UR, CRS or CA (other values are Reserved)
   TL_CPL_STATUS_CHECK : assert property (disable iff (tl_off)
      $changed(tl_cpl_cnt) |-> (tl_cpl_status inside {`PCIe_CPL_STATUS_SC, `PCIe_CPL_STATUS_UR,
                                                       `PCIe_CPL_STATUS_CRS, `PCIe_CPL_STATUS_CA}))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_CPL_STATUS_CHECK] FAILED : Completion Status = %03b is Reserved", tl_cpl_status))

   // A completion that is not SC (UR / CRS / CA) must not carry data
   TL_CPL_NO_DATA_IF_NOT_SC_CHECK : assert property (disable iff (tl_off)
      $changed(tl_cpl_cnt) && (tl_cpl_status != `PCIe_CPL_STATUS_SC) |-> !tl_cpl_has_data)
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_CPL_NO_DATA_IF_NOT_SC_CHECK] FAILED : CplD received with Completion Status %03b (only SC may carry data)", tl_cpl_status))

   // The completion keeps the TC of its request (Sec 2.5)
   TL_CPL_TC_CHECK : assert property (disable iff (tl_off)
      $changed(tl_cpl_cnt) && tl_cpl_matched |-> (tl_cpl_tc == tl_cpl_req_tc))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_CPL_TC_CHECK] FAILED : completion TC%0d, request TC%0d", tl_cpl_tc, tl_cpl_req_tc))

   //==========================================================================
   // Covers : count how many times each case happened (0 = never tested)
   //==========================================================================
   TL_COVER_POSTED_SENT     : cover property ($changed(tl_tx_cnt) && !tl_tx_np);
   TL_COVER_NON_POSTED_SENT : cover property ($changed(tl_tx_cnt) &&  tl_tx_np);
   TL_COVER_POISONED_SENT   : cover property ($changed(tl_tx_cnt) &&  tl_tx_ep_got);
   TL_COVER_CPL_SC          : cover property ($changed(tl_cpl_cnt) && (tl_cpl_status == `PCIe_CPL_STATUS_SC));
   TL_COVER_CPL_UR          : cover property ($changed(tl_cpl_cnt) && (tl_cpl_status == `PCIe_CPL_STATUS_UR));
   TL_COVER_CPLD            : cover property ($changed(tl_cpl_cnt) &&  tl_cpl_has_data);

   //==========================================================================
   // STATUS MESSAGES : search "TL_STATUS" in the log
   //==========================================================================
   logic tl_checks_started = 1'b0;   // 1 after the first check clock

   always @(posedge pclk) begin
      if (!tl_off && (tl_checks_started == 1'b0)) begin
         tl_checks_started = 1'b1;
         `uvm_info({SIDE,"_TL_STATUS"}, "TL assertions STARTED checking", UVM_HIGH)
      end
   end

   // End of test : count the TL assertion errors and print PASSED / FAILED
   final begin
      uvm_report_server svr;
      int unsigned      fail_cnt;
      string            result;
      svr      = uvm_report_server::get_server();
      fail_cnt = svr.get_id_count({SIDE,"_TL_ASSERT"});
      if      (tl_checks_started == 1'b0) result = "NOT CHECKED";
      else if (fail_cnt == 0)             result = "PASSED";
      else                                result = "FAILED";
      `uvm_info({SIDE,"_TL_STATUS"}, $sformatf({"\n",
                "  TLPs sent / received     : %0d / %0d\n",
                "  Completions received     : %0d\n",
                "  TL assertion failures    : %0d\n",
                "  TL assertions            : %s\n"},
                tl_tx_cnt, tl_rx_cnt, tl_cpl_cnt, fail_cnt, result), UVM_HIGH)
   end

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
   // [DL_ASSERT] EP DL state machine assertions (PCIe 6.1 Sec 3.2)
   //   PCIe_EP_DL_model.sv copies its state/counters/flags here every pclk negedge.
   //   Checks run every pclk posedge : state moves, DL_Up/DL_Down, link up/down, reset values.
   //   On failure : UVM_ERROR [EP_DL_ASSERT] [<check name>] FAILED : <reason>
   //==========================================================================
   import uvm_pkg::*;
   import typedef_enums::*;
   localparam string SIDE = "EP";

   //--------------------------------------------------------------------------
   // On / off
   //--------------------------------------------------------------------------
   logic assert_en    = 1'b1;   // 1 = checks ON. A test can set 0 to switch all DL checks OFF
   logic sample_valid = 1'b0;   // DL model sets 1 after its first copy. Checks wait for this

   //--------------------------------------------------------------------------
   // DL state : copied from the DL model on every falling edge of pclk
   //--------------------------------------------------------------------------
   dl_state_e          dl_state       = DL_INACTIVE;
   dl_init_substate_e  dl_init_sub    = INIT_FC1;
   logic               dl_link_active;
   logic               phy_linkup;

   // Sequence number counters (value in comment = value they must have in DL_INACTIVE)
   logic [`PCIe_SEQ_NUM_W-1:0]      next_tx_seq;        // NEXT_TX_FLIT_SEQ_NUM          default 001h
   logic [`PCIe_SEQ_NUM_W-1:0]      tx_acknak_seq;      // TX_ACKNAK_FLIT_SEQ_NUM        default 3FFh (1023)
   logic [`PCIe_SEQ_NUM_W-1:0]      ackd_seq;           // ACKD_FLIT_SEQ_NUM             default 3FFh
   logic [`PCIe_SEQ_NUM_W-1:0]      next_exp_rx_seq;    // NEXT_EXPECTED_RX_FLIT_SEQ_NUM default 001h
   logic [`PCIe_SEQ_NUM_W-1:0]      implicit_rx_seq;    // IMPLICIT_RX_FLIT_SEQ_NUM      default 000h
   logic [`PCIe_SEQ_NUM_W-1:0]      tx_replay_seq;      // TX_REPLAY_FLIT_SEQ_NUM        default 000h
   logic [`PCIe_SEQ_NUM_W-1:0]      nak_ignore_seq;     // NAK_IGNORE_FLIT_SEQ_NUM       default 000h
   logic [`PCIe_FLIT_REPLAY_NUM_W-1:0] flit_replay_num;   // FLIT_REPLAY_NUM               default 000b

   // ACK / NAK / replay flags (all must be 0 in DL_INACTIVE)
   logic nak_scheduled;
   logic ack_scheduled;
   logic replay_scheduled;
   logic replay_in_progress;
   logic nak_withdrawal_allowed;

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
   logic [`PCIe_DLLP_CONTENT_W-1:0] tx_dllp_content;

   //--------------------------------------------------------------------------
   // dl_curr_state : DL state NOW (same as dl_state, but DL_INIT is split into
   //                 FC_INIT1 / FC_INIT2 so every state move can be checked)
   //                  (STATE_ names : DL_ names already exist in enum_defs.sv)
   //--------------------------------------------------------------------------
   dl_curr_state_e dl_curr_state;

   always_comb begin
      case (dl_state)
         DL_INACTIVE : dl_curr_state = STATE_INACTIVE;
         DL_FEATURE  : dl_curr_state = STATE_FEATURE;
         DL_INIT     : dl_curr_state = (dl_init_sub == INIT_FC2) ? STATE_FC_INIT2 : STATE_FC_INIT1;
         default     : dl_curr_state = STATE_ACTIVE;
      endcase
   end

   // DL status reported to the TL (spec Sec 3.2.1)
   //   DL_Down : DL_INACTIVE, DL_FEATURE, FC_INIT1
   //   DL_Up   : FC_INIT2, DL_ACTIVE
   logic dl_up;
   logic dl_down;

   always_comb begin
      case (dl_curr_state)
         STATE_INACTIVE : begin dl_down = 1'b1; dl_up = 1'b0; end
         STATE_FEATURE  : begin dl_down = 1'b1; dl_up = 1'b0; end
         STATE_FC_INIT1 : begin dl_down = 1'b1; dl_up = 1'b0; end
         STATE_FC_INIT2 : begin dl_down = 1'b0; dl_up = 1'b1; end
         STATE_ACTIVE   : begin dl_down = 1'b0; dl_up = 1'b1; end
         default        : begin dl_down = 1'b1; dl_up = 1'b0; end
      endcase
   end

   // values in the last pclk (to see "what was it before")
   dl_curr_state_e dl_prev_state = STATE_INACTIVE;
   logic            dl_prev_up    = 1'b0;
   logic            dl_prev_down  = 1'b1;

   always @(posedge pclk) begin
      dl_prev_state <= dl_curr_state;
      dl_prev_up    <= dl_up;
      dl_prev_down  <= dl_down;
   end

   // Helper signals : 1 when all values are at their DL_INACTIVE default (used by DL_RESET_... checks)
   logic seq_default;      // 1 = all 8 sequence counters are at reset value
   logic flags_clear;      // 1 = all 5 Ack / Nak / replay flags are 0
   logic buffers_empty;    // 1 = TX and RX retry buffers are empty

   always_comb begin
      seq_default   = (next_tx_seq     == `PCIe_INIT_NEXT_TX_FLIT_SEQ_NUM)          &&
                      (tx_acknak_seq   == `PCIe_INIT_TX_ACKNAK_SEQ_NUM)             &&
                      (ackd_seq        == `PCIe_INIT_ACKD_FLIT_SEQ_NUM)             &&
                      (next_exp_rx_seq == `PCIe_INIT_NEXT_EXPECTED_RX_FLIT_SEQ_NUM) &&
                      (implicit_rx_seq == `PCIe_INIT_IMPLICIT_RX_FLIT_SEQ_NUM)      &&
                      (tx_replay_seq   == `PCIe_INIT_TX_REPLAY_FLIT_SEQ_NUM)        &&
                      (nak_ignore_seq  == `PCIe_INIT_NAK_IGNORE_FLIT_SEQ_NUM)       &&
                      (flit_replay_num == `PCIe_INIT_FLIT_REPLAY_NUM);

      flags_clear   = (nak_scheduled          == 1'b0) &&
                      (ack_scheduled          == 1'b0) &&
                      (replay_scheduled       == 1'b0) &&
                      (replay_in_progress     == 1'b0) &&
                      (nak_withdrawal_allowed == 1'b0);

      buffers_empty = (tx_retry_size == 0) && (rx_retry_size == 0);
   end

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

   // Before the link comes up, DL must be in DL_INACTIVE with DL_Down = 1, DL_Up = 0.
   // So when phy_linkup goes 0 -> 1, the values in the last pclk are checked.
   DL_LINKUP_START_CHECK : assert property (
      $rose(phy_linkup) |-> (dl_prev_state == STATE_INACTIVE) && (dl_prev_down == 1'b1) && (dl_prev_up == 1'b0))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_LINKUP_START_CHECK] FAILED : link came up but before it DL was %s, DL_Down=%0b, DL_Up=%0b (expected DL_INACTIVE, 1, 0)",
      dl_prev_state.name(), dl_prev_down, dl_prev_up))

   //==========================================================================
   // CHECK 2 : One check for each state move (spec Figure 3-2, Sec 3.2.1)
   //
   //   DL_INACTIVE -> DL_FEATURE -> FC_INIT1 -> FC_INIT2 -> DL_ACTIVE
   //   (link down from any state -> DL_INACTIVE : see CHECK 3)
   //
   //   dl_prev_state = state in the last pclk
   //   dl_curr_state = state now
   //   "left X"       = dl_prev_state is X and dl_curr_state is not X
   //==========================================================================

   // DL_INACTIVE -> DL_FEATURE  (DL_Down = 1, DL_Up = 0)
   DL_INACTIVE_TO_FEATURE_CHECK : assert property (
      (dl_prev_state == STATE_INACTIVE) && (dl_curr_state != STATE_INACTIVE)
      |-> (dl_curr_state == STATE_FEATURE) && (dl_down == 1'b1) && (dl_up == 1'b0))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_INACTIVE_TO_FEATURE_CHECK] FAILED : left DL_INACTIVE, expected DL_FEATURE / DL_Down=1 / DL_Up=0, got %s / DL_Down=%0b / DL_Up=%0b",
      dl_curr_state.name(), dl_down, dl_up))

   // DL_FEATURE -> FC_INIT1  (link still up)  (DL_Down = 1, DL_Up = 0)
   DL_FEATURE_TO_FC_INIT1_CHECK : assert property (
      (dl_prev_state == STATE_FEATURE) && (dl_curr_state != STATE_FEATURE) && (phy_linkup == 1'b1)
      |-> (dl_curr_state == STATE_FC_INIT1) && (dl_down == 1'b1) && (dl_up == 1'b0))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_FEATURE_TO_FC_INIT1_CHECK] FAILED : left DL_FEATURE, expected FC_INIT1 / DL_Down=1 / DL_Up=0, got %s / DL_Down=%0b / DL_Up=%0b",
      dl_curr_state.name(), dl_down, dl_up))

   // FC_INIT1 -> FC_INIT2  (link still up)  (DL_Down = 0, DL_Up = 1)
   DL_FC_INIT1_TO_FC_INIT2_CHECK : assert property (
      (dl_prev_state == STATE_FC_INIT1) && (dl_curr_state != STATE_FC_INIT1) && (phy_linkup == 1'b1)
      |-> (dl_curr_state == STATE_FC_INIT2) && (dl_down == 1'b0) && (dl_up == 1'b1))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_FC_INIT1_TO_FC_INIT2_CHECK] FAILED : left FC_INIT1, expected FC_INIT2 / DL_Down=0 / DL_Up=1, got %s / DL_Down=%0b / DL_Up=%0b",
      dl_curr_state.name(), dl_down, dl_up))

   // FC_INIT2 -> DL_ACTIVE  (link still up)  (DL_Down = 0, DL_Up = 1)
   DL_FC_INIT2_TO_ACTIVE_CHECK : assert property (
      (dl_prev_state == STATE_FC_INIT2) && (dl_curr_state != STATE_FC_INIT2) && (phy_linkup == 1'b1)
      |-> (dl_curr_state == STATE_ACTIVE) && (dl_down == 1'b0) && (dl_up == 1'b1))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_FC_INIT2_TO_ACTIVE_CHECK] FAILED : left FC_INIT2, expected DL_ACTIVE / DL_Down=0 / DL_Up=1, got %s / DL_Down=%0b / DL_Up=%0b",
      dl_curr_state.name(), dl_down, dl_up))

   // DL_ACTIVE -> DL_INACTIVE  (DL_Down = 1, DL_Up = 0)
   DL_ACTIVE_TO_INACTIVE_CHECK : assert property (
      (dl_prev_state == STATE_ACTIVE) && (dl_curr_state != STATE_ACTIVE)
      |-> (dl_curr_state == STATE_INACTIVE) && (dl_down == 1'b1) && (dl_up == 1'b0))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_ACTIVE_TO_INACTIVE_CHECK] FAILED : left DL_ACTIVE, expected DL_INACTIVE / DL_Down=1 / DL_Up=0, got %s / DL_Down=%0b / DL_Up=%0b",
      dl_curr_state.name(), dl_down, dl_up))

   //==========================================================================
   // CHECK 3 : Link down -> DL_INACTIVE
   //==========================================================================
   // On an actual link-down event (phy_linkup 1 -> 0), in the next clock DL
   // state must be DL_INACTIVE. $fell() is used instead of the !phy_linkup
   // level: on link-up the DL FSM legitimately moves DL_INACTIVE -> DL_FEATURE
   // in the same cycle phy_linkup rises, and a level-based antecedent would
   // falsely flag that legal transition as a link-down failure.
   DL_LINKDOWN_CHECK : assert property (
      $fell(phy_linkup) |=> (dl_state == DL_INACTIVE) && (dl_down == 1'b1) && (dl_up == 1'b0))
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_LINKDOWN_CHECK] FAILED : link went down but DL is %s, DL_Down=%0b, DL_Up=%0b (expected DL_INACTIVE, 1, 0)",
      dl_curr_state.name(), dl_down, dl_up))

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
   //   counters / flags / retry buffers. Grace time : `PCIe_DL_RESET_GRACE_CLKS pclk.
   //==========================================================================
   // s_enter_inactive : DL state is DL_INACTIVE now, and was NOT DL_INACTIVE in the last clock
   sequence s_enter_inactive;
      (dl_state == DL_INACTIVE) && ($past(dl_state) != DL_INACTIVE);
   endsequence

   // On entering DL_INACTIVE, all sequence counters must go back to default
   DL_RESET_COUNTERS_CHECK : assert property (
      s_enter_inactive |-> ##[0:`PCIe_DL_RESET_GRACE_CLKS] seq_default)
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_RESET_COUNTERS_CHECK] FAILED : DL went to DL_INACTIVE but counters are not reset : NEXT_TX=%0d(exp %0d) TX_ACKNAK=%0d(exp %0d) ACKD=%0d(exp %0d) NEXT_EXP_RX=%0d(exp %0d) IMPLICIT_RX=%0d(exp %0d) TX_REPLAY=%0d(exp %0d) NAK_IGNORE=%0d(exp %0d) FLIT_REPLAY_NUM=%0d(exp %0d)",
      next_tx_seq,     `PCIe_INIT_NEXT_TX_FLIT_SEQ_NUM,
      tx_acknak_seq,   `PCIe_INIT_TX_ACKNAK_SEQ_NUM,
      ackd_seq,        `PCIe_INIT_ACKD_FLIT_SEQ_NUM,
      next_exp_rx_seq, `PCIe_INIT_NEXT_EXPECTED_RX_FLIT_SEQ_NUM,
      implicit_rx_seq, `PCIe_INIT_IMPLICIT_RX_FLIT_SEQ_NUM,
      tx_replay_seq,   `PCIe_INIT_TX_REPLAY_FLIT_SEQ_NUM,
      nak_ignore_seq,  `PCIe_INIT_NAK_IGNORE_FLIT_SEQ_NUM,
      flit_replay_num, `PCIe_INIT_FLIT_REPLAY_NUM))

   // On entering DL_INACTIVE, all ACK / NAK / replay flags must be 0
   DL_RESET_FLAGS_CHECK : assert property (
      s_enter_inactive |-> ##[0:`PCIe_DL_RESET_GRACE_CLKS] flags_clear)
   else `uvm_error({SIDE,"_DL_ASSERT"}, $sformatf(
      "[DL_RESET_FLAGS_CHECK] FAILED : DL went to DL_INACTIVE but flags are not cleared : NAK_SCHEDULED=%0b ACK_SCHEDULED=%0b REPLAY_SCHEDULED=%0b REPLAY_IN_PROGRESS=%0b NAK_WITHDRAWAL_ALLOWED=%0b",
      nak_scheduled, ack_scheduled, replay_scheduled, replay_in_progress, nak_withdrawal_allowed))

   // On entering DL_INACTIVE, TX and RX retry buffers must be empty
   DL_RESET_BUFFERS_CHECK : assert property (
      s_enter_inactive |-> ##[0:`PCIe_DL_RESET_GRACE_CLKS] buffers_empty)
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
      "[DL_LINK_ACTIVE_ONLY_IN_ACTIVE_CHECK] FAILED : dl_link_active=1 but DL state is %s", dl_curr_state.name()))

   // If DL state is DL_ACTIVE, dl_link_active must be 1
   DL_ACTIVE_NEEDS_LINK_ACTIVE_CHECK : assert property (
      (dl_state == DL_ACTIVE) |-> dl_link_active)
   else `uvm_error({SIDE,"_DL_ASSERT"},
      "[DL_ACTIVE_NEEDS_LINK_ACTIVE_CHECK] FAILED : DL state is DL_ACTIVE but dl_link_active=0")

   //==========================================================================
   // Covers : count how many times each state move happened (0 = that move was never tested)
   //==========================================================================
   DL_COVER_INACTIVE_TO_FEATURE : cover property ((dl_curr_state == STATE_INACTIVE) ##1 (dl_curr_state == STATE_FEATURE));
   DL_COVER_FEATURE_TO_FC_INIT1 : cover property ((dl_curr_state == STATE_FEATURE)  ##1 (dl_curr_state == STATE_FC_INIT1));
   DL_COVER_FC_INIT1_TO_FC_INIT2: cover property ((dl_curr_state == STATE_FC_INIT1) ##1 (dl_curr_state == STATE_FC_INIT2));
   DL_COVER_FC_INIT2_TO_ACTIVE  : cover property ((dl_curr_state == STATE_FC_INIT2) ##1 (dl_curr_state == STATE_ACTIVE));
   DL_COVER_ACTIVE_TO_INACTIVE  : cover property ((dl_curr_state == STATE_ACTIVE)   ##1 (dl_curr_state == STATE_INACTIVE));
   DL_COVER_TLP_IN_ACTIVE       : cover property ($changed(tx_payload_cnt) && (tx_payload_dl_state == DL_ACTIVE));

   //==========================================================================
   // STATUS MESSAGES : search "DL_STATUS" in the log
   //==========================================================================
   logic dl_checks_started = 1'b0;   // 1 after the first check clock

   // Print when the checks start, and print every DL state move
   always @(posedge pclk) begin
      if (sample_valid && assert_en) begin
         if (dl_checks_started == 1'b0) begin
            dl_checks_started = 1'b1;
            `uvm_info({SIDE,"_DL_STATUS"}, "DL assertions STARTED checking", UVM_LOW)
         end
         else if (dl_curr_state != dl_prev_state) begin
            `uvm_info({SIDE,"_DL_STATUS"}, $sformatf("DL state move checked : %s -> %s",
                      dl_prev_state.name(), dl_curr_state.name()), UVM_LOW)
         end
      end
   end

   // End of test : count the DL assertion errors and print PASSED / FAILED
   final begin
      uvm_report_server svr;
      int unsigned      fail_cnt;
      string            result;
      svr      = uvm_report_server::get_server();
      fail_cnt = svr.get_id_count({SIDE,"_DL_ASSERT"});
      if      (dl_checks_started == 1'b0) result = "NOT CHECKED";
      else if (fail_cnt == 0)             result = "PASSED";
      else                                result = "FAILED";
      `uvm_info({SIDE,"_DL_STATUS"}, $sformatf("\n  DL assertion failures    : %0d\n  DL assertions            : %s\n",
                fail_cnt, result), UVM_LOW)
   end

   // [DL_ASSERT] end of DL assertions

   //==========================================================================
   //==========================================================================
   // [TL_ASSERT] EP Transaction Layer assertions (PCIe 6.0 Sec 2)
   //   PCIe_EP_TL_model.sv writes the values below through its handle tl_aif :
   //     tl_req_sample() : once for every request decoded (+ its error flags)
   //     tl_cpl_sample() : once for every completion formed
   //     tl_rx_cnt / tl_rx_done_cnt : +1 before / after every TLP decode
   //     tl_np_rx_cnt / tl_np_done_cnt : Non-Posted request in / completed
   //   Checks run every pclk posedge. A check looks at "count changed" and
   //   then at the values saved with it (same way as the DL checks above).
   //   On failure : UVM_ERROR [EP_TL_ASSERT] [<check name>] FAILED : <reason>
   //==========================================================================
   //==========================================================================

   //--------------------------------------------------------------------------
   // On / off
   //--------------------------------------------------------------------------
   logic tl_assert_en    = 1'b1;   // 1 = checks ON. A test can set 0 to switch all TL checks OFF
   logic tl_sample_valid = 1'b0;   // TL model sets 1 at start of simulation. Checks wait for this
   wire  tl_off          = !tl_sample_valid || !tl_assert_en;

   //--------------------------------------------------------------------------
   // RX : TLP received DL -> TL
   //--------------------------------------------------------------------------
   int unsigned tl_rx_cnt;                 // + 1 when a TLP comes from the DL
   int unsigned tl_rx_done_cnt;            // + 1 when its processing is finished

   // Request decoded (saved at the moment it is decoded)
   int unsigned tl_req_cnt;                // + 1 for every request decoded
   logic        tl_req_np;                 // 1 = Non-Posted (needs a completion)
   logic        tl_req_malformed;          // 1 = Malformed TLP (Reserved bits set)
   logic        tl_req_poisoned;           // 1 = EP = 1
   logic        tl_req_ecrc_fail;          // 1 = ECRC Check Failed
   logic [13:0] tl_req_tag;                // Tag of the request

   // Non-Posted requests
   int unsigned tl_np_rx_cnt;              // + 1 Non-Posted request accepted (needs a completion)
   int unsigned tl_np_done_cnt;            // + 1 its completion was sent

   //--------------------------------------------------------------------------
   // Completion formed (saved at the moment it is formed)
   //   *_exp = value it must have, *_got = value read back from the 236 B
   //--------------------------------------------------------------------------
   int unsigned tl_cpl_cnt;                // + 1 for every completion formed
   logic [7:0]  tl_cpl_type_exp, tl_cpl_type_got;   // 4Ah CplD / 0Ah Cpl
   logic [13:0] tl_cpl_tag_exp,  tl_cpl_tag_got;    // Tag = Tag of the request
   logic [2:0]  tl_cpl_status;                      // Completion Status
   logic        tl_cpl_has_data;                    // 1 = CplD

   //--------------------------------------------------------------------------
   // tl_req_sample : called by the EP TL model for every request it decodes
   //--------------------------------------------------------------------------
   function automatic void tl_req_sample(
      input bit        np,
      input bit        malformed,
      input bit        poisoned,
      input bit        ecrc_fail,
      input bit [13:0] tag);
      tl_req_np        = np;
      tl_req_malformed = malformed;
      tl_req_poisoned  = poisoned;
      tl_req_ecrc_fail = ecrc_fail;
      tl_req_tag       = tag;
      tl_req_cnt++;                     // event : the checks see "count changed"
   endfunction

   //--------------------------------------------------------------------------
   // tl_cpl_sample : called by the EP TL model for every completion it forms.
   //   Reads Type and Tag back from the 236 B.
   //   Flit Tag : DW1[13:0] (bytes 6-7)   Non-Flit Tag : {DW0[23], DW0[19], DW2[15:8]}
   //--------------------------------------------------------------------------
   function automatic void tl_cpl_sample(
      input bit [0:`PCIe_TLP_DATA_BYTE_W-1][7:0] tlp,
      input bit        flit,
      input bit        has_data,
      input bit [2:0]  status,
      input bit [13:0] exp_tag);
      tl_cpl_type_exp = has_data ? `PCIe_FLITTYPE_CPLD : `PCIe_FLITTYPE_CPL;
      tl_cpl_type_got = tlp[0];
      if (flit) begin
         tl_cpl_tag_got = {tlp[6][5:0], tlp[7]};
         tl_cpl_tag_exp = exp_tag;
      end
      else begin
         tl_cpl_tag_got = {4'h0, tlp[1][7], tlp[1][3], tlp[10]};
         tl_cpl_tag_exp = {4'h0, exp_tag[9:0]};
      end
      tl_cpl_status   = status;
      tl_cpl_has_data = has_data;
      tl_cpl_cnt++;                     // event : the checks see "count changed"
   endfunction

   //--------------------------------------------------------------------------
   // Every check below runs on the rising edge of pclk (default clocking above),
   // and is OFF while tl_sample_valid = 0 or tl_assert_en = 0 (tl_off = 1)
   //--------------------------------------------------------------------------

   //==========================================================================
   // CHECK 1 : at start nothing has been received or sent
   //==========================================================================
   TL_START_CHECK : assert property (
      @(posedge pclk) disable iff (!tl_assert_en)
      $rose(tl_sample_valid) |-> (tl_req_cnt == 0) && (tl_cpl_cnt == 0))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_START_CHECK] FAILED : at start requests=%0d completions=%0d (expected 0, 0)", tl_req_cnt, tl_cpl_cnt))

   //==========================================================================
   // CHECK 2 : every TLP received from the DL is processed, and every
   //           Non-Posted request gets its completion
   //==========================================================================
   TL_RX_DECODE_CHECK : assert property (disable iff (tl_off)
      (tl_rx_cnt == tl_rx_done_cnt))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_RX_DECODE_CHECK] FAILED : TLPs received from DL=%0d but processed=%0d", tl_rx_cnt, tl_rx_done_cnt))

   TL_NP_GETS_CPL_CHECK : assert property (disable iff (tl_off)
      (tl_np_rx_cnt == tl_np_done_cnt))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_NP_GETS_CPL_CHECK] FAILED : Non-Posted requests=%0d but completed=%0d", tl_np_rx_cnt, tl_np_done_cnt))

   //==========================================================================
   // CHECK 3 : no completion for a Posted request or a Malformed TLP
   //==========================================================================
   // Posted request (MWr, Msg) : no completion is sent for it
   TL_POSTED_NO_CPL_CHECK : assert property (disable iff (tl_off)
      $changed(tl_req_cnt) && !tl_req_np |-> !$changed(tl_cpl_cnt))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_POSTED_NO_CPL_CHECK] FAILED : completion sent for a Posted request (tag 0x%0h)", tl_req_tag))

   // Malformed TLP : dropped, no completion (ERR_FATAL)
   TL_MALFORMED_NO_CPL_CHECK : assert property (disable iff (tl_off)
      $changed(tl_req_cnt) && tl_req_malformed |-> !$changed(tl_cpl_cnt))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_MALFORMED_NO_CPL_CHECK] FAILED : completion sent for a Malformed TLP (tag 0x%0h)", tl_req_tag))

   //==========================================================================
   // CHECK 4 : Poisoned / ECRC failed Non-Posted request -> Completion UR
   //==========================================================================
   TL_POISONED_CPL_UR_CHECK : assert property (disable iff (tl_off)
      $changed(tl_cpl_cnt) && tl_req_poisoned |-> (tl_cpl_status == `PCIe_CPL_STATUS_UR))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_POISONED_CPL_UR_CHECK] FAILED : Poisoned request tag 0x%0h completed with status %03b (expected 001b UR)",
      tl_req_tag, tl_cpl_status))

   TL_ECRC_FAIL_CPL_UR_CHECK : assert property (disable iff (tl_off)
      $changed(tl_cpl_cnt) && tl_req_ecrc_fail |-> (tl_cpl_status == `PCIe_CPL_STATUS_UR))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_ECRC_FAIL_CPL_UR_CHECK] FAILED : ECRC failed request tag 0x%0h completed with status %03b (expected 001b UR)",
      tl_req_tag, tl_cpl_status))

   //==========================================================================
   // CHECK 5 : the completion sent to the DL is correct (Sec 2.2.9)
   //==========================================================================
   // Type = CplD (4Ah) when it carries data, Cpl (0Ah) when not
   TL_CPL_TYPE_CHECK : assert property (disable iff (tl_off)
      $changed(tl_cpl_cnt) |-> (tl_cpl_type_got == tl_cpl_type_exp))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_CPL_TYPE_CHECK] FAILED : type byte = 0x%02h, expected 0x%02h", tl_cpl_type_got, tl_cpl_type_exp))

   // Tag = Tag of the request
   TL_CPL_TAG_CHECK : assert property (disable iff (tl_off)
      $changed(tl_cpl_cnt) |-> (tl_cpl_tag_got == tl_cpl_tag_exp))
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_CPL_TAG_CHECK] FAILED : completion tag = 0x%0h, request tag = 0x%0h", tl_cpl_tag_got, tl_cpl_tag_exp))

   // A completion that is not SC (UR / CRS / CA) must not carry data
   TL_CPL_NO_DATA_IF_NOT_SC_CHECK : assert property (disable iff (tl_off)
      $changed(tl_cpl_cnt) && (tl_cpl_status != `PCIe_CPL_STATUS_SC) |-> !tl_cpl_has_data)
   else `uvm_error({SIDE,"_TL_ASSERT"}, $sformatf(
      "[TL_CPL_NO_DATA_IF_NOT_SC_CHECK] FAILED : CplD sent with Completion Status %03b (only SC may carry data)", tl_cpl_status))

   //==========================================================================
   // Covers : count how many times each case happened (0 = never tested)
   //==========================================================================
   TL_COVER_MALFORMED_RCVD : cover property ($changed(tl_req_cnt) && tl_req_malformed);
   TL_COVER_POISONED_RCVD  : cover property ($changed(tl_req_cnt) && tl_req_poisoned);
   TL_COVER_ECRC_FAIL_RCVD : cover property ($changed(tl_req_cnt) && tl_req_ecrc_fail);
   TL_COVER_CPL_SC_SENT    : cover property ($changed(tl_cpl_cnt) && (tl_cpl_status == `PCIe_CPL_STATUS_SC));
   TL_COVER_CPL_UR_SENT    : cover property ($changed(tl_cpl_cnt) && (tl_cpl_status == `PCIe_CPL_STATUS_UR));
   TL_COVER_CPLD_SENT      : cover property ($changed(tl_cpl_cnt) && tl_cpl_has_data);

   //==========================================================================
   // STATUS MESSAGES : search "TL_STATUS" in the log
   //==========================================================================
   logic tl_checks_started = 1'b0;   // 1 after the first check clock

   always @(posedge pclk) begin
      if (!tl_off && (tl_checks_started == 1'b0)) begin
         tl_checks_started = 1'b1;
         `uvm_info({SIDE,"_TL_STATUS"}, "TL assertions STARTED checking", UVM_HIGH)
      end
   end

   // End of test : count the TL assertion errors and print PASSED / FAILED
   final begin
      uvm_report_server svr;
      int unsigned      fail_cnt;
      string            result;
      svr      = uvm_report_server::get_server();
      fail_cnt = svr.get_id_count({SIDE,"_TL_ASSERT"});
      if      (tl_checks_started == 1'b0) result = "NOT CHECKED";
      else if (fail_cnt == 0)             result = "PASSED";
      else                                result = "FAILED";
      `uvm_info({SIDE,"_TL_STATUS"}, $sformatf({"\n",
                "  Requests received        : %0d\n",
                "  Completions sent         : %0d\n",
                "  TL assertion failures    : %0d\n",
                "  TL assertions            : %s\n"},
                tl_req_cnt, tl_cpl_cnt, fail_cnt, result), UVM_HIGH)
   end

   // [TL_ASSERT] end of TL assertions

endinterface


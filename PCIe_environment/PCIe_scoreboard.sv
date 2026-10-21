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

   // ------------------------------------------------------------------------
   // Per-dword data compare gating.
   //   Both controller monitors push EVERY received dword, so the compare
   //   queues also contain the Detect / Polling / Recovery / L0.Idle Ordered
   //   Sets. Those are not data and the two monitors decode them with
   //   independent chains, so a straight queue-to-queue compare reports
   //   thousands of bogus mismatches around every L0 transition. The compare
   //   therefore only runs once BOTH ports are in the data phase, and the
   //   backlog collected up to that point is dropped instead of compared.
   // ------------------------------------------------------------------------
   PCIe_RC_PL_model  sb_rc_pl_model;
   PCIe_EP_PL_model  sb_ep_pl_model;
   bit               sb_data_phase_started = 1'b0;
   int               sb_resync_count     = 0;   // dwords dropped to re-align the EP->RC stream
   int               sb_mismatch_count   = 0;   // genuine dword mismatches after re-alignment
   bit               sb_ep_to_rc_synced  = 1'b0; // set once the EP->RC streams share an anchor
   int               sb_sync_run         = 0;   // consecutive dword matches towards the anchor
   // The RC->EP direction used to be compared by naive index-by-index
   // pop_front(), with no anchor hunt and no drift tolerance, and it reported
   // 5783 mismatches. sb_align_dword() already does the right thing (and its
   // comment already names the 4a000000 / 4a4a4a4a training tail that defeated
   // the naive compare), it just was not wired into this direction. Both
   // directions now share one implementation and keep separate state, because
   // each stream pair is aligned independently.
   bit               sb_rc_to_ep_synced  = 1'b0; // set once the RC->EP streams share an anchor
   int               sb_rc_to_ep_sync_run    = 0; // consecutive dword matches, RC->EP
   int               sb_rc_to_ep_resync_count = 0; // dwords dropped to re-align RC->EP
   int               sb_rc_to_ep_mismatch_count = 0; // genuine RC->EP mismatches after re-align
   int               sb_rc_last_ts       = 0;   // TS1+TS2 seen by the RC monitor, last time
   int               sb_ep_last_ts       = 0;   // TS1+TS2 seen by the EP monitor, last time

   // Consecutive dword matches required before the EP->RC streams are declared
   // synchronised, and how far ahead the receive queue is searched for the
   // dword the transmitter is currently on.
   `define SB_SYNC_RUN_LEN     4
   `define SB_SYNC_SEARCH_WIN  64
   // [FIX] Steady-state drift window, in dwords. The receive monitor sees a
   // dword 2 PIPE cycles after the transmit monitor (serialise / deserialise
   // latency). While the link carries IDLE flits both streams are all zero, so
   // the compare pairs zeros of different positions and the latency is hidden;
   // the first non-zero dword then finds the transmitter 2 dwords ahead. Up to
   // this many dwords of drift are absorbed, and a dword that has not arrived
   // yet is waited for instead of being reported as a mismatch.
   `define SB_DRIFT_WIN        8

   // [FIX] Set by sb_align_dword() when it made no progress because the
   // expected dword is still in flight. The compare loops stop on it.
   bit               sb_waiting = 1'b0;

   function bit sb_data_phase_ready();
      // The PL model handles are published by the environment in connect_phase,
      // i.e. AFTER this component's build_phase, so they are resolved lazily on
      // the first compare instead of in build_phase.
      if (sb_rc_pl_model == null)
         void'(uvm_config_db#(PCIe_RC_PL_model)::get(this, "", "RC_PL_MODEL", sb_rc_pl_model));
      if (sb_ep_pl_model == null)
         void'(uvm_config_db#(PCIe_EP_PL_model)::get(this, "", "EP_PL_MODEL", sb_ep_pl_model));
      if (sb_rc_pl_model == null || sb_ep_pl_model == null) return 1'b0;
      return (sb_rc_pl_model.link_up && sb_ep_pl_model.link_up);
   endfunction

    // A TS1 or TS2 arriving on a receive monitor means a training episode has
   // (re)started on the wire. This is a SECOND episode in the same run: the
   // recovery test renegotiates the rate while already in L0, so link_up never
   // drops and a gate that latches on the first data phase would keep comparing
   // the payload of one side against the Ordered Sets of the other.
   // IDLE/SKP Ordered Sets are deliberately NOT counted here: they occur
   // legitimately in L0 and would re-arm the gate continuously.
    function bit sb_new_training_episode();
       int rc_ts, ep_ts;
       if (sb_rc_pl_model == null || sb_ep_pl_model == null) return 1'b0;
       rc_ts = sb_rc_pl_model.rc_rx_ts1_count + sb_rc_pl_model.rc_rx_ts2_count;
       ep_ts = sb_ep_pl_model.ep_rx_ts1_count + sb_ep_pl_model.ep_rx_ts2_count;
       if ((rc_ts == sb_rc_last_ts) && (ep_ts == sb_ep_last_ts)) return 1'b0;
       sb_rc_last_ts = rc_ts;
       sb_ep_last_ts = ep_ts;
       return 1'b1;
    endfunction

    // Returns 1 when the caller may compare, 0 when the data phase has not
    // started yet, was just started, or a new training episode has just begun
    // (the training backlog is flushed and the streams must re-acquire an
    // anchor in each of those cases).
     function bit sb_allow_data_compare(ref bit [31:0] tx_q[$], ref bit [31:0] rx_q[$]);
        if (!sb_data_phase_ready()) return 1'b0;
        if (!sb_data_phase_started) begin
           sb_data_phase_started = 1'b1;
           // Seed the episode counters so the first call after the initial
           // flush is not mistaken for a brand new training episode.
           void'(sb_new_training_episode());
           sb_flush_for_compare(tx_q, rx_q, "DATA_PHASE_STARTED_TRAINING_BACKLOG_FLUSHED");
           return 1'b0;
        end
        if (sb_new_training_episode()) begin
           sb_flush_for_compare(tx_q, rx_q, "TRAINING_EPISODE_DETECTED_BACKLOG_FLUSHED");
           return 1'b0;
        end
        return 1'b1;
     endfunction

    // Drops everything queued before the current data phase and puts the
   // self-resynchronising compare back into its hunt for an anchor.
    function void sb_flush_for_compare(ref bit [31:0] tx_q[$], ref bit [31:0] rx_q[$], input string why);
       // Ordered Sets that were already on the wire when the backlog was
       // dropped still arrive afterwards, so the compare must go back to
       // hunting for a match rather than pairing index by index.
        sb_ep_to_rc_synced = 1'b0;
        sb_rc_to_ep_synced = 1'b0;
        sb_sync_run        = 0;
        sb_rc_to_ep_sync_run = 0;
       tx_q.delete();
       rx_q.delete();
       `uvm_info("PCIe_SCOREBOARD",$sformatf("%s RESYNCS=%0d MISMATCHES=%0d", why, sb_resync_count, sb_mismatch_count),UVM_LOW)
    endfunction

    // ------------------------------------------------------------------------
    // sb_align_dword - self-resynchronising dword compare for the EP->RC stream.
   //
   //   Two separate problems have to be handled.
   //
   //   1. PIPE latency. The EP controller monitor observes a dword on the cycle
   //      the EP drives it, the RC controller monitor only on the NEXT cycle.
   //      Index by index pairing compares every dword with its predecessor.
   //
   //   2. The training tail. sb_allow_data_compare() drops the backlog once, on
   //      the transition into the data phase, but Ordered Sets already on the
   //      wire still arrive afterwards. The receive side therefore keeps
   //      delivering the training tail while the transmit side has moved on to
   //      payload, and the two streams genuinely hold different dwords.
   //
   //   So the compare has an explicit sync phase. While unsynced it drops queue
   //      heads until the two streams meet, which discards the training tail and
   //      absorbs the latency, and it only starts reporting once a real anchor
   //      has been found. Afterwards it tolerates a one dword drift and reports
   //      anything that matches neither the head nor one dword ahead.
   // ------------------------------------------------------------------------
    function bit sb_is_synced();
       return sb_ep_to_rc_synced;
    endfunction

     function bit sb_align_dword(ref bit [31:0] tx_q[$], ref bit [31:0] rx_q[$],
                                 ref bit synced, ref int run,
                                 ref int resync_count, ref int mismatch_count,
                                 input string dir);
       int look;
       sb_waiting = 1'b0;
       if (tx_q.size() == 0 || rx_q.size() == 0) return 1'b0;

        // ---- sync phase : hunt for a common anchor, dropping what is behind ----
        if (!synced) begin
           if (tx_q[0] == rx_q[0]) begin
              // A single coincidence is NOT an anchor. The training tail is full
              // of repeated dwords (the IDLE Ordered Set is 4a000000 / 4a4a4a4a),
              // so the streams can agree by accident while still holding
              // different data. Require a run of consecutive matches before
              // declaring sync; 4 random 32 bit dwords will not collide.
              run++;
              tx_q.pop_front();
              rx_q.pop_front();
              if (run >= `SB_SYNC_RUN_LEN) begin
                 synced = 1'b1;
                 `uvm_info("PCIe_SCOREBOARD",$sformatf("%s_STREAM_SYNCED after %0d consecutive dwords, RESYNCS=%0d",
                           dir, run, resync_count),UVM_LOW)
              end
              return 1'b1;
           end
           run = 0;
           // The receive side is the one that lags (training tail plus PIPE
           // latency), so search a bounded window of it for the dword the
           // transmitter is on, and drop everything up to it.
           for (look = 1; look < `SB_SYNC_SEARCH_WIN; look++) begin
              if (look >= rx_q.size()) break;
              if (rx_q[look] == tx_q[0]) begin
                 repeat (look) rx_q.pop_front();
                 resync_count++;
                 return 1'b0;
              end
           end
           // Receiver does not have it yet : the transmitter is ahead.
           if (tx_q.size() > 1 && (tx_q[1] == rx_q[0])) begin
              tx_q.pop_front();
              resync_count++;
              return 1'b0;
           end
           rx_q.pop_front();
           resync_count++;
           return 1'b0;
        end

        // ---- steady state : absorb up to `SB_DRIFT_WIN dwords of drift, else report ----
        if (tx_q[0] == rx_q[0]) begin
           tx_q.pop_front();
           rx_q.pop_front();
           return 1'b1;
        end
        // [FIX] Receiver behind : it still holds stale dwords (IDLE-flit zeros
        // the transmitter's stream was already paired with). Drop them up to the
        // dword the transmitter is on.
        for (look = 1; look < `SB_DRIFT_WIN; look++) begin
           if (look >= rx_q.size()) break;
           if (rx_q[look] == tx_q[0]) begin
              repeat (look) rx_q.pop_front();
              resync_count++;
              return 1'b0;
           end
        end
        // Transmitter ahead : drop transmit dwords the receiver never got.
        for (look = 1; look < `SB_DRIFT_WIN; look++) begin
           if (look >= tx_q.size()) break;
           if (tx_q[look] == rx_q[0]) begin
              repeat (look) tx_q.pop_front();
              resync_count++;
              return 1'b0;
           end
        end
        // [FIX] The expected dword is still in flight (PIPE latency) : wait for
        // more receive dwords before calling it a mismatch.
        if (rx_q.size() < `SB_DRIFT_WIN) begin
           sb_waiting = 1'b1;
           return 1'b0;
        end
        `uvm_error("PCIe_SCOREBOARD",$sformatf("***********FAIL*****************:FAIL_%s_EXPECTED_DATA = %08h  ACTUAL_DATA = %08h", dir, tx_q[0], rx_q[0]))
        mismatch_count++;
        tx_q.pop_front();
        rx_q.pop_front();
        return 1'b0;
     endfunction


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

   // The RC controller monitor appends exactly ONE dword to
   // data_q_rc_mon_con_tx immediately before it writes this analysis port, and
   // it never pops that queue, so the item carries the entire transmit history
   // on every single write. This used to foreach the whole queue and push all of
   // it, so dword 1 was appended once, then again with dword 2, then again with
   // dword 3 ... re-appending the whole history O(n^2) times. Compare against
   // the EP side, whose queue is trimmed back to 61 dwords as flits are
   // collected, and the two queues stopped having anything to do with each
   // other: that is what produced the 5783 mismatches full of IDLE Ordered Set
   // bytes (4a000000 / 4a4a4a4a) being compared against payload dwords.
   //
   // Only the newly appended dword - the last element - is new information, and
   // it is the last element at the moment of the write because nothing touches
   // the queue in between. Taking the tail also stays correct regardless of
   // what the monitor does to the front of the queue later.
   function void write_rc_controller_tx(PCIe_sequence_item pkt);
     `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_RC_CONTROLLER_TX_DATA",UVM_HIGH)
     if (pkt.data_q_rc_mon_con_tx.size() > 0)
        rc_controller_tx_q.push_back(pkt.data_q_rc_mon_con_tx[pkt.data_q_rc_mon_con_tx.size()-1]);
     `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_RC_CONTROLLER_TX_DATA",UVM_HIGH)
     compare_controller_rc_to_ep_data();
   endfunction

   function void write_ep_controller_rx(PCIe_sequence_item pkt);
     `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_EP_CONTROLLER_RX_DATA",UVM_HIGH)
     if (pkt.data_q_ep_mon_con_rx.size() > 0)
        ep_controller_rx_q.push_back(pkt.data_q_ep_mon_con_rx[pkt.data_q_ep_mon_con_rx.size()-1]);
     `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_EP_CONTROLLER_RX_DATA",UVM_HIGH)
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_EP_CONTROLLER_RX_DATA",UVM_HIGH)
     compare_controller_rc_to_ep_data();
  endfunction

   function void compare_controller_rc_to_ep_data();
       bit [31:0] rc_controller_tx_data;
       bit [31:0] ep_controller_rx_data;

      `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_COMPARE_CONTROLLER_DATA",UVM_HIGH)
      if (!sb_allow_data_compare(rc_controller_tx_q, ep_controller_rx_q)) begin
         `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_COMPARE_CONTROLLER_DATA",UVM_HIGH)
         return;
      end
      while ((rc_controller_tx_q.size() > 0) && (ep_controller_rx_q.size() > 0)) begin
           // RC->EP dword compare. This used to pair the two queues index by
           // index with a bare pop_front() on each, with none of the anchor hunt
           // or drift tolerance that sb_align_dword() gives the EP->RC direction,
           // and it is the loop that reported all 5783 mismatches. It now shares
           // the same self-resynchronising implementation, with its own sync
           // state so the two directions stay independent.
           void'(sb_align_dword(rc_controller_tx_q, ep_controller_rx_q,
                                sb_rc_to_ep_synced, sb_rc_to_ep_sync_run,
                                sb_rc_to_ep_resync_count, sb_rc_to_ep_mismatch_count,
                                "RC_CONTROLLER_TX_TO_EP_CONTROLLER_RX"));
           if (sb_waiting) break;   // [FIX] expected dword still in flight
        end
        `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_COMPARE_CONTROLLER_DATA",UVM_HIGH)
  endfunction

  function void write_rc_controller_rx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_RC_CONTROLLER_RX_DATA",UVM_HIGH)
    // [FIX] The RC controller monitor appends ONE dword to data_q_rc_mon_con_rx
    // right before every write, but the queue still holds the whole history
    // (the 232 training dwords: TS1 10ffffbc, IDLE 4a000000 / 4a4a4a4a ...) and is
    // only trimmed now and then. Pushing the whole queue on every write
    // re-appended that history again and again, so the EP->RC compare saw
    // training Ordered Sets against EP data dwords (1238 false FAILs in
    // PCIe_3DW_flit_test). Only the newly appended dword - the last element -
    // is new, exactly as write_rc_controller_tx / write_ep_controller_rx do.
    if (pkt.data_q_rc_mon_con_rx.size() > 0)
       rc_controller_rx_q.push_back(pkt.data_q_rc_mon_con_rx[pkt.data_q_rc_mon_con_rx.size()-1]);
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_RC_CONTROLLER_RX_DATA",UVM_HIGH)
     compare_controller_ep_to_rc_data();
  endfunction

  function void write_ep_controller_tx(PCIe_sequence_item pkt);
    `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_EP_CONTROLLER_TX_DATA",UVM_HIGH)
     // [FIX] Same as write_rc_controller_rx : only the newly appended dword
     // (the last element of the monitor queue) is new information.
     if (pkt.data_q_ep_mon_con_tx.size() > 0)
        ep_controller_tx_q.push_back(pkt.data_q_ep_mon_con_tx[pkt.data_q_ep_mon_con_tx.size()-1]);
    `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_EP_CONTROLLER_RX_DATA",UVM_HIGH)
     compare_controller_ep_to_rc_data();
  endfunction

   function void compare_controller_ep_to_rc_data();
      `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_FUNCTION_WRITE_COMPARE_CONTROLLER_DATA",UVM_HIGH)
      if (!sb_allow_data_compare(ep_controller_tx_q, rc_controller_rx_q)) begin
         `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_FUNCTION_WRITE_COMPARE_CONTROLLER_DATA",UVM_HIGH)
         return;
      end
      // The EP transmit monitor runs one dword ahead of the RC receive monitor
      // (PIPE latency), so this direction is aligned with sb_align_dword()
      // instead of a plain index by index pop_front(). sb_align_dword() drops
      // one queue head per call, so this always makes progress.
      while ((rc_controller_rx_q.size() > 0) && (ep_controller_tx_q.size() > 0)) begin
        void'(sb_align_dword(ep_controller_tx_q, rc_controller_rx_q,
                             sb_ep_to_rc_synced, sb_sync_run,
                             sb_resync_count, sb_mismatch_count,
                             "EP_CONTROLLER_TX_TO_RC_CONTROLLER_RX"));
        if (sb_waiting) break;   // [FIX] expected dword still in flight
      end
      `uvm_info("PCIe_SCOREBOARD",$sformatf("EP_TO_RC_STREAM_COMPARE_COMPLETE RESYNCS=%0d MISMATCHES=%0d",
                sb_resync_count, sb_mismatch_count),UVM_MEDIUM)
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


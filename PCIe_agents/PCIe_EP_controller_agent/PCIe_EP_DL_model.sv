//=========================================================================================
// File         : PCIe_EP_DL_model.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_EP_controller_agent\PCIe_EP_DL_model.sv
// Author       : 
// Date         : 2026-09-09
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

import typedef_enums::*;

// [ADDED] separate imp for EP controller monitor -> EP DL : 242B RC->EP flit + is_valid
`uvm_analysis_imp_decl(_ep_mon_242b)

class PCIe_EP_DL_model extends uvm_component;

  `uvm_component_utils(PCIe_EP_DL_model)

  // TL -> DL and DL -> PL TLM connections.
  uvm_analysis_imp #(PCIe_sequence_item,PCIe_EP_DL_model) dl_imp;
  uvm_analysis_port #(PCIe_sequence_item) dl_ap;

  // [ADDED] EP controller monitor -> EP DL : per RC->EP flit, 242B + is_valid
  uvm_analysis_imp_ep_mon_242b #(PCIe_sequence_item,PCIe_EP_DL_model) dl_mon_242b_imp;

  uvm_analysis_port #(PCIe_sequence_item) ep_dl_tl_ap;//dl -> tl

  // [DL_COV] EP DL -> Subscriber : decoded DLP fields of every received flit
  uvm_analysis_port #(PCIe_sequence_item) ep_dl_cov_ap;

    pkt_mode_e dl_rx_pkt_mode = FLIT;
  bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] ep_rx_242b_flit_q[$];   // collected 242B flits (in arrival order)
  bit                                                ep_rx_flit_is_valid_q[$]; // is_valid of each collected flit (same index)
  int                                                ep_rx_242b_flit_cnt = 0;

  bit [31:0] dllp_content;
  bit [`PCIe_DLP_FLIT_BYTE_W-1:0][`PCIe_BYTE_W-1:0] dl_flit_out;
  bit success;
  bit received_explicit_seq;
  bit [`PCIe_REPLAY_CMD_W-1:0] replay_cmd;
  bit [`PCIe_SEQ_NUM_W-1:0] last_sent;
  bit is_payload_flit;

  tx_buffer_t tx_retry_buffer[$];

  replay_scheduled_type_e REPLAY_SCHEDULED_TYPE;

  bit [`PCIe_SEQ_NUM_W-1:0] TX_ACKNAK_FLIT_SEQ_NUM = 10'h3FF;
  bit [`PCIe_SEQ_NUM_W-1:0] NEXT_TX_FLIT_SEQ_NUM = 10'h001;
  bit [`PCIe_SEQ_NUM_W-1:0] NEXT_EXPECTED_RX_FLIT_SEQ_NUM = 10'h001;
  bit [`PCIe_SEQ_NUM_W-1:0] IMPLICIT_RX_FLIT_SEQ_NUM = 10'h000;
  bit [`PCIe_SEQ_NUM_W-1:0] ACKD_FLIT_SEQ_NUM = 10'h3FF;
  bit [`PCIe_SEQ_NUM_W-1:0] TX_REPLAY_FLIT_SEQ_NUM = 10'h000;
  bit [`PCIe_SEQ_NUM_W-1:0] NAK_IGNORE_FLIT_SEQ_NUM = 10'h000;
  bit NON_IDLE_EXPLICIT_SEQ_NUM_FLIT_RCVD;
  bit [`PCIe_FLIT_REPLAY_NUM_W-1:0] FLIT_REPLAY_NUM = 3'b000;
  bit REPLAY_SCHEDULED;
  int unsigned MAX_UNACKNOWLEDGED_FLITS = `PCIe_MAX_UNACK_FLITS;

  bit [`PCIe_SEQ_NUM_W-1:0] RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM;
  bit [`PCIe_SEQ_NUM_W-1:0] NEXT_RX_FLIT_SEQ_NUM_TO_STORE;
  bit RX_RETRY_BUFFER_OVERFLOW;
  bit ALLOW_SELECTIVE_OVERFLOW;
  bit USE_STANDARD_NAK_ONLY = 1'b0;

  bit received_explicit_seq_0;

  bit NAK_SCHEDULED;
  bit ACK_SCHEDULED;
  bit NAK_SCHEDULED_TYPE;
  bit NAK_WITHDRAWAL_ALLOWED;
  bit EP_REPLAY_IN_PROGRESS;

  // ===========================================================================
  // [SEL_NAK] SELECTIVE NAK + RX RETRY BUFFER  (PCIe 6.1 Sec 4.2.3.4.2.1)
  //
  //   Standard NAK  (Replay Command 10b) : "replay ALL flits after N"
  //   Selective NAK (Replay Command 11b) : "replay ONLY flit N+1"
  //
  //   With a Selective NAK the good flits that arrive AFTER the lost flit are
  //   kept in the RX retry buffer. When the lost flit is replayed, it goes to
  //   the TL first and then the stored flits go to the TL in sequence order.
  //   USE_STANDARD_NAK_ONLY = 1 turns this off (Standard NAK only).
  // ===========================================================================
  localparam bit STANDARD_NAK  = 1'b0;     // value of NAK_SCHEDULED_TYPE
  localparam bit SELECTIVE_NAK = 1'b1;     // value of NAK_SCHEDULED_TYPE

  // One RX retry buffer entry = one good flit that came after the lost flit
  typedef struct {
    bit [`PCIe_SEQ_NUM_W-1:0]                         seq_num;
    bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_data;
  } rx_retry_entry_t;
  rx_retry_entry_t rx_retry_buffer[$];
  int unsigned     RX_RETRY_BUFFER_MAX_FLITS = `PCIe_MAX_UNACK_FLITS;

  // Decision of the RX rules for the flit being processed
  //   RX_FLIT_ACCEPT : in order -> TLP goes to the TL now
  //   RX_FLIT_STORE  : after a lost flit -> TLP kept in the RX retry buffer
  //   RX_FLIT_DROP   : bad / duplicate / out of order / NOP -> TLP dropped
  typedef enum {RX_FLIT_DROP, RX_FLIT_ACCEPT, RX_FLIT_STORE} rx_flit_action_e;
  rx_flit_action_e rx_flit_action;
  bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] rx_flit_tlp;   // TLP bytes of the flit being processed
  bit rx_release_stored_flits;   // 1 : replayed flit accepted -> stored flits go to the TL after it

  // NAK_SCHEDULED is the spec RX state : it stays 1 until the lost flit comes back.
  // nak_flit_tx_pending = 1 means a NEW NAK flit must be sent once on the link.
  bit nak_flit_tx_pending;

  // Counters : read by the tests and printed in report_phase
  int unsigned n_std_nak_scheduled;     // new Standard NAKs scheduled
  int unsigned n_sel_nak_scheduled;     // new Selective NAKs scheduled
  int unsigned n_rx_flits_stored;       // flits put in the RX retry buffer
  int unsigned n_rx_flits_released;     // stored flits sent to the TL after the replay
  int unsigned n_rx_replayed_accepted;  // lost flits that came back (replayed) and were accepted

  bit last_flit_was_payload;
  bit credit;
  bit form_dlp_flit;

   // Simplified DLLP content encodings for DLCMSM simulation
    localparam bit [31:0] FEATURE_DLLP = 32'h0200_0000;   // spec Table 3-5 : Feature DLLP type = 02h

    // [FLIT_CNT] flit summary counters (logic + report at the end of the class)
  typedef enum int {FLTC_FEATURE, FLTC_INITFC1, FLTC_INITFC2, FLTC_UPDATEFC,
                    FLTC_ACK, FLTC_NAK, FLTC_NOP, FLTC_OTHER_DLLP,
                    FLTC_OPT_UPDATEFC, FLTC_NOP_DLLP, FLTC_LINK_MGMT_DLLP,   // [FLOW_SUM]
                    FLTC_MWR, FLTC_MRD, FLTC_CFGRD, FLTC_CFGWR, FLTC_MSG, FLTC_MSGD,
                    FLTC_CPL, FLTC_CPLD, FLTC_OTHER_TLP, FLTC_NUM} flit_cnt_e;

  int unsigned flit_tx_cnt [FLTC_NUM];
  int unsigned flit_rx_cnt [FLTC_NUM];
  int unsigned flit_tx_total, flit_rx_total;
  int unsigned flit_rx_bad;                          // RX flits with CRC / FEC error
  int unsigned flit_tx_replay;                       // replayed TLP flits (also counted in their TLP type)
  int unsigned flit_tx_nak_piggy, flit_rx_nak_piggy; // NAK carried on a DLLP / TLP flit
  int unsigned flit_tx_new_cnt [FLTC_NUM];           // [FLOW_SUM] TX flits WITHOUT replays
  int unsigned rx_accept_cnt   [FLTC_NUM];           // [FLOW_SUM] RX TLPs given to the TL, per TLP type

  // [FLOW_SUM] numbers for the end-of-test EP FLIT SUMMARY (flit_summary_report)
  int unsigned              n_tx_new_payload;        // NEW payload flits sent (replays not counted)
  bit [`PCIe_SEQ_NUM_W-1:0] first_tx_seq, last_tx_seq;
  int unsigned              n_rx_tlp_to_tl;          // RX payload flits accepted and given to the EP TL
  bit [`PCIe_SEQ_NUM_W-1:0] first_rx_seq, last_rx_seq;
  int unsigned              max_tx_retry_used;       // biggest TX retry buffer size seen
  int unsigned              n_tx_flits_dropped_on_reset;
  int unsigned              n_ack_rcvd, n_std_nak_rcvd, n_sel_nak_rcvd, n_nak_ignored;
  bit [`PCIe_SEQ_NUM_W-1:0] nak_rcvd_lost_seq_q[$];  // lost flit (N+1) of every NAK(N) received
  int unsigned              n_ack_sent;
  bit [`PCIe_SEQ_NUM_W-1:0] nak_sent_lost_seq_q[$];  // lost flit of every NAK scheduled
  int                       last_rx_acknak_key = -1; // {cmd, seq} of the last ACK/NAK received
  int                       last_tx_acknak_key = -1; // {cmd, seq} of the last ACK sent
  bit                       acknak_rx_is_new;        // 1 : the ACK/NAK just received is a NEW one

  // Declared here (before their first use) : Questa needs a class variable
  // to be declared before the first line that uses it.
  bit                       ack_hold;                // [ACK_HOLD] 1 : the ACK number sent does not move
  bit [`PCIe_SEQ_NUM_W-1:0] ack_hold_seq = 10'h3FF;  // [ACK_HOLD] ACK number sent while ACKs are held

   // localparam bit [31:0] INITFC1_DLLP = 32'h0200_0000;
    //localparam bit [31:0] INITFC2_DLLP = 32'h0300_0000;
        // ---- DLCMSM additions ----
    dl_state_e          DL_STATE = DL_INACTIVE;
    // [DL_ASSERT] DL state machine assertions live inside PCIe_EP_interface (PCIe_top/PCIe_PIPE_interface.sv)
    virtual PCIe_EP_interface dl_aif;
    dl_init_substate_e  dl_init_substate;
    uvm_event           uvm_ep_l0_to_dl_ev;   // fired by PL model when LTSSM reaches L0
    int                 fc1_sent_count, fc1_rcvd_count;
    int                 fc2_sent_count, fc2_rcvd_count;
    bit                 phy_linkup;      
    bit                 link_enabled = 1'b1;

    // ---- DLCMSM FSM additions (dependency-driven, mirrors LTSSM style) ----
    // Named, single-source-of-truth completion targets   no magic numbers
    // scattered in a bare while() loop, referenced by every debug print below.
    localparam int NUM_INITFC1_DLLP = 4;   // FC_INIT1 is "done" once this many INITFC1 DLLPs sent
    localparam int NUM_INITFC2_DLLP = 4;   // FC_INIT2 is "done" once this many INITFC2 DLLPs sent
    bit   dl_link_active;                   // stays 1 while in DL_ACTIVE - TL/driver can gate on this
    // Driver handshake for DLCMSM packets:
    //   DL model sets it to 1 when it hands a DLLP flit to the PL model.
    //   EP controller driver clears it to 0 once that flit is on the PIPE.
    // DLCMSM waits for it to clear, so every DLLP flit is really transmitted
    // (in order) before the next DLCMSM state runs.
    bit   dllp_tx_pending;
    uvm_event ep_dl_active_event;                  // fires once, the instant DL_ACTIVE is entered
    // --------------------------------------------------------------------

    // ---- FLOW CONTROL (dedicated + shared credits, PER VC) ------------------
    //   [TC_VC] OLD : VC0 only, every array was [class].
    //   [TC_VC] NEW : [vc][class]. Like the Gen3 bench, every ENABLED VC is
    //   initialised in DL_Init : each InitFC1 / InitFC2 round carries the six
    //   DLLPs (P/NP/Cpl dedicated + shared) of VC0, then VC1, ... and FI1 / FI2
    //   are Set once all enabled VCs have them. Every FC DLLP carries its VC ID.
    uvm_analysis_imp_fc_from_tl #(PCIe_sequence_item, PCIe_EP_DL_model) fc_tl_imp;  // TL -> DL : local credits
    uvm_analysis_port #(PCIe_sequence_item)                  fc_tl_ap;   // DL -> TL : peer credit limits
    localparam int unsigned FC_NVC = `PCIe_NUM_VC_MAX;
    int unsigned adv_h [FC_NVC][3];  // local CREDITS_ALLOCATED to advertise (from the TL)
    int unsigned adv_d [FC_NVC][3];
    bit          adv_valid [FC_NVC];
    int unsigned peer_h [FC_NVC][3]; // peer values = transmitter CREDIT_LIMIT (from InitFC / UpdateFC)
    int unsigned peer_d [FC_NVC][3];
    bit          peer_hinf [FC_NVC][3];
    bit          peer_dinf [FC_NVC][3];
    bit          fi1_ded [FC_NVC][3];   // FI1 : dedicated values recorded
    bit          fi1_shr [FC_NVC][3];   // FI1 : shared values recorded (Flit Mode needs all six)
    bit          fi2 [FC_NVC];          // FI2
    bit [2:0]    pend_mask [FC_NVC];    // classes that need an UpdateFC DLLP on the wire
    bit          peer_init_fwd [FC_NVC][3];  // initial limit of the class already given to the TL
    // [FC SHARED] Flit Mode shared pool (same meaning as the dedicated fields above)
    int unsigned adv_h_shr [FC_NVC][3];   // local shared CREDITS_ALLOCATED to advertise (from the TL)
    int unsigned adv_d_shr [FC_NVC][3];
    int unsigned peer_h_shr [FC_NVC][3];  // peer shared values = transmitter SHARED_CREDIT_LIMIT
    int unsigned peer_d_shr [FC_NVC][3];
    bit          peer_hinf_shr [FC_NVC][3];
    bit          peer_dinf_shr [FC_NVC][3];
    bit          peer_init_fwd_shr [FC_NVC][3];
    bit [2:0]    pend_mask_shr [FC_NVC];  // classes that need an UpdateFC (shared) DLLP on the wire
    int unsigned n_updfc_tx_shr, n_updfc_rx_shr;
    bit          fc_tx_allowed = 1'b1;   // gate for DL-initiated DLLPs after DL_ACTIVE
    int unsigned n_initfc1_tx, n_initfc1_rx, n_initfc2_tx, n_initfc2_rx, n_updfc_tx, n_updfc_rx;
    int unsigned n_fc_dllp_dis_vc;         // [TC_VC] FC DLLPs received for a VC that is not enabled

  function new(string name = "PCIe_RC_DL_model", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    dl_imp = new("dl_imp", this);
    dl_ap = new("dl_ap", this);
    dl_mon_242b_imp = new("dl_mon_242b_imp", this);   // [ADDED]
    ep_dl_tl_ap=new("ep_dl_tl_ap",this);
    ep_dl_cov_ap = new("ep_dl_cov_ap", this);   // [DL_COV]
    ep_dl_active_event = uvm_event_pool::get_global("ep_dl_active_event");
    uvm_ep_l0_to_dl_ev = uvm_event_pool::get_global("ep_l0_to_dl_event");
    fc_tl_imp = new("fc_tl_imp", this);
    fc_tl_ap  = new("fc_tl_ap",  this);
    fc_dl_init();
///////////////////to enable to non flit mode//////////
     void'(uvm_config_db#(pkt_mode_e)::get(this, "", "link_mode", dl_rx_pkt_mode));
    // [DL_ASSERT] PIPE interface also holds the DL assertions (set in PCIe_top)
    if (!uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", dl_aif))
      `uvm_warning("EP_DL_ASSERT", "PCIe_EP_INTERFACE not found :: DL assertions are OFF for EP")

  endfunction

  // Modulo 1023 helper for sequence number increments (1 to 1023)
  function bit [`PCIe_SEQ_NUM_W-1:0] mod1023_add(bit [`PCIe_SEQ_NUM_W-1:0] a,bit [`PCIe_SEQ_NUM_W-1:0] b_inc);
    int sum = int'(a) + int'(b_inc);
    while(sum > (`PCIe_MAX_UNACK_FLITS + 512)) sum -= (`PCIe_MAX_UNACK_FLITS + 512);
    return sum;
  
  endfunction
  
  // Modulo 1023 helper for sequence number subtraction (1 to 1023)
  function automatic bit [`PCIe_SEQ_NUM_W-1:0] mod1023_sub(bit [`PCIe_SEQ_NUM_W-1:0] a, bit [`PCIe_SEQ_NUM_W-1:0] b);
    int diff;
    bit [`PCIe_SEQ_NUM_W-1:0] temp_a = (a == 10'd0) ? 10'd1023 : a;
    bit [`PCIe_SEQ_NUM_W-1:0] temp_b = (b == 10'd0) ? 10'd1023 : b;
    diff = int'(temp_a) - int'(temp_b);
    if (diff < 0) diff += 1023;
    return diff;
  endfunction

  // =========================================================================
  // DLCMSM FSM   ADDED / ACTIVATED BLOCK
  // Mirrors PCIe_RC_DL_model's DLCMSM implementation exactly (EP side).
  // Dependency chain enforced:
  //   DL_INACTIVE  --(phy_linkup && link_enabled)-->  DL_FEATURE
  //   DL_FEATURE   --(FEATURE_DLLP sent)-->            DL_INIT.FC_INIT1
  //   FC_INIT1     --(fc1_sent_count >= NUM_INITFC1_DLLP)--> FC_INIT2
  //   FC_INIT2     --(fc2_sent_count >= NUM_INITFC2_DLLP)--> DL_ACTIVE
  //   DL_ACTIVE    --> dl_link_active=1, dl_active_event fires -> TL may send TLPs
  // =========================================================================

  // =========================================================================
  // [DL_ASSERT] MIRROR FOR THE DL ASSERTIONS
  // Copies the DLCMSM variables into dl_aif on every pclk negedge, so the assertions
  // in PCIe_EP_interface (sampled on posedge) always sees stable values.
  // =========================================================================
  function void dl_aif_sample();
    if (dl_aif == null) return;
    dl_aif.dl_state               = DL_STATE;
    dl_aif.dl_init_sub            = dl_init_substate;
    dl_aif.dl_link_active         = dl_link_active;
    dl_aif.phy_linkup             = phy_linkup;
    dl_aif.next_tx_seq            = NEXT_TX_FLIT_SEQ_NUM;
    dl_aif.tx_acknak_seq          = TX_ACKNAK_FLIT_SEQ_NUM;
    dl_aif.ackd_seq               = ACKD_FLIT_SEQ_NUM;
    dl_aif.next_exp_rx_seq        = NEXT_EXPECTED_RX_FLIT_SEQ_NUM;
    dl_aif.implicit_rx_seq        = IMPLICIT_RX_FLIT_SEQ_NUM;
    dl_aif.tx_replay_seq          = TX_REPLAY_FLIT_SEQ_NUM;
    dl_aif.nak_ignore_seq         = NAK_IGNORE_FLIT_SEQ_NUM;
    dl_aif.flit_replay_num        = FLIT_REPLAY_NUM;
    dl_aif.nak_scheduled          = NAK_SCHEDULED;
    dl_aif.ack_scheduled          = ACK_SCHEDULED;
    dl_aif.replay_scheduled       = REPLAY_SCHEDULED;
    dl_aif.replay_in_progress     = EP_REPLAY_IN_PROGRESS;
    dl_aif.nak_withdrawal_allowed = NAK_WITHDRAWAL_ALLOWED;
    dl_aif.tx_retry_size          = tx_retry_buffer.size();
    dl_aif.rx_retry_size          = rx_retry_buffer.size();
  endfunction

  task run_dl_assert_mirror();
    if (dl_aif == null) return;
    dl_aif_sample();
    @(negedge dl_aif.pclk);
    dl_aif_sample();
    dl_aif.sample_valid = 1'b1;
    forever begin
      @(negedge dl_aif.pclk);
      dl_aif_sample();
    end
  endtask

  // [DL_ASSERT] run_phase = mirror thread + the original DLCMSM loop (run_dl_main).
  // The mirror is a SIBLING process, so 'disable fork' inside run_dl_main
  // (used on link-down) cannot kill it.
  task run_phase(uvm_phase phase);
    fork
      run_dl_assert_mirror();
      run_dl_main();
    join
  endtask

  task run_dl_main();
     `uvm_info("EP_DLCMSM","[DLCMSM_TRACE] WAITING_FOR_ep_l0_to_dl_event (fired by PL model on LTSSM L0 entry)",UVM_LOW)
     forever begin
         uvm_ep_l0_to_dl_ev.wait_trigger();
         wait(phy_linkup == 1);
        `uvm_info("EP_DLCMSM","[DLCMSM_TRACE] ep_l0_to_dl_event_FIRED :: LTSSM_REACHED_L0 :: STARTING_DLCMSM_FSM",UVM_LOW)
        PCIe_flow_log::print("LTSSM", "EP L0, LINK_UP=1");   // [FLOW]
        DL_STATE       = DL_INACTIVE;
        dl_link_active = 1'b0;
        fc1_sent_count = 0;
        fc2_sent_count = 0;
        dllp_tx_pending        = 1'b0;
        NAK_SCHEDULED          = 1'b0;
        ACK_SCHEDULED          = 1'b0;
        REPLAY_SCHEDULED       = 1'b0;
        EP_REPLAY_IN_PROGRESS  = 1'b0;
        nak_flit_tx_pending    = 1'b0;   // [SEL_NAK]
        rx_release_stored_flits = 1'b0;  // [SEL_NAK]
        rx_retry_buffer.delete();        // [SEL_NAK]
        dl_reset_state("DL_INACTIVE (link up, DLCMSM starts)");   // [DL_RESET]
        // Run the DLCMSM FSM and the concurrent DL data-processing thread
        // (ACK/NAK/REPLAY) together. The fork returns as soon as run_dlcmsm()
        // exits - which only happens in DL_ACTIVE when phy_linkup drops - and
        // then the data-processing loop is killed so the link re-initializes.
        fc_restart_init();
        fork : ep_dl_run
           run_dlcmsm();
           run_dl_data_processing();
           run_fc_update_loop();
        join_any
        disable fork;
        DL_STATE       = DL_INACTIVE;
        dl_link_active = 1'b0;
        dl_reset_state("DL_INACTIVE (Physical LinkUp = 0)");      // [DL_RESET]
        PCIe_flow_log::print("DLCMSM", $sformatf("EP DL_Inactive (link down), %0d unACKed flit(s) dropped", n_tx_flits_dropped_on_reset));   // [FLOW]
        `uvm_info("EP_DLCMSM","[DLCMSM_TRACE] phy_linkup=0 :: DL_RUN_TERMINATED :: WAITING_FOR_NEXT_LINKUP",UVM_LOW)
     end
  endtask

  // ===========================================================================
  // DL DATA PROCESSING THREAD  (runs while DL_ACTIVE)
  //   Priority 1 : a replay is scheduled  -> replay flits to the RC  (do_replay)
  //   Priority 2 : a NEW NAK is pending   -> send ONE NAK flit
  //   Priority 3 : an ACK is scheduled    -> send ONE ACK flit
  //
  //   [SEL_NAK] NAK_SCHEDULED is NOT cleared here. It is the RX state from the
  //   spec and stays 1 until the lost flit is received again (Ack Schedule 1/2).
  //   Only nak_flit_tx_pending is cleared, so each new NAK is sent once.
  // ===========================================================================
  task run_dl_data_processing();
     wait(dl_link_active);
     `uvm_info("EP_DL_PROC","[DL_DATA_PROC] DL_ACTIVE :: STARTING_ACK_NAK_REPLAY_PROCESSING",UVM_LOW)
     forever begin
        if (REPLAY_SCHEDULED && !EP_REPLAY_IN_PROGRESS) begin
           do_replay();
        end
        else if (nak_flit_tx_pending) begin
           `uvm_info("EP_DL_PROC", $sformatf("[DL_DATA_PROC] SENDING %s FLIT :: Flit Sequence Number = %0d (last good flit, replay starts at %0d)",
                     (NAK_SCHEDULED_TYPE == SELECTIVE_NAK) ? "SELECTIVE_NAK" : "STANDARD_NAK",
                     TX_ACKNAK_FLIT_SEQ_NUM, mod1023_add(TX_ACKNAK_FLIT_SEQ_NUM, 10'h1)), UVM_NONE)
           send_dl_control_flit();
           nak_flit_tx_pending = 1'b0;
        end
        else if (ACK_SCHEDULED && !ack_hold) begin   // [ACK_HOLD] no ACK flit while ACKs are held
           if (NAK_SCHEDULED) begin
              // A NAK is outstanding : the NAK replaces the ACK (no ACK flit now)
              ACK_SCHEDULED = 1'b0;
           end
           else begin
              `uvm_info("EP_DL_PROC", $sformatf("[DL_DATA_PROC] SENDING ACK FLIT :: Flit Sequence Number = %0d",
                        TX_ACKNAK_FLIT_SEQ_NUM), UVM_LOW)
              // form_dl_packet() clears ACK_SCHEDULED itself when building an ACK.
              send_dl_control_flit();
           end
        end
        else begin
           // Nothing to send right now - yield so other processes can run.
           #1ns;
        end
     end
  endtask

  // Builds a control flit (ACK or NAK, is_payload=0) using the currently
  // scheduled state, and pushes it to the PL model.
  function void send_dl_control_flit();
     PCIe_sequence_item ctl_item;
     ctl_item = PCIe_sequence_item::type_id::create("ctl_item");
     form_dl_packet(ctl_item.tlp_data, 1'b0, ctl_item.dlp_flit_out);
     flit_cnt_count(1'b1, ctl_item.dlp_flit_out);   // [FLIT_CNT] TX
     dl_ap.write(ctl_item);
  endfunction

  // ===========================================================================
  // [REPLAY] TX REPLAY  (PCIe 6.1 Sec 4.2.3.4.2.1.6 and 4.2.3.4.2.1.7)
  //
  //   Step 1 : peer sends NAK(N) -> schedule_replay_on_nak()
  //              REPLAY_SCHEDULED = 1, TX_REPLAY_FLIT_SEQ_NUM = N+1
  //   Step 2 : do_replay() -> start_replay() makes the list from the TX retry buffer
  //              STANDARD_REPLAY  : flit N+1 and every flit after it
  //              SELECTIVE_REPLAY : only flit N+1
  //            -> send_replay_flit() for each flit
  //              * ORIGINAL sequence number (Explicit Sequence Number flit, Replay Command 00b)
  //              * NEXT_TX_FLIT_SEQ_NUM does not change, flit is NOT stored again
  //   Step 3 : peer sends ACK -> purge_tx_retry_buffer() removes the flits
  //
  //   EP PL model queues its flits (ep_tx_flit_q), so all replay flits can be
  //   written to the PL one after the other here.
  // ===========================================================================
  bit [`PCIe_SEQ_NUM_W-1:0] replayed_seq_q[$];          // seq num of every replayed flit (for tests)
  int unsigned n_std_replay, n_sel_replay;             // replays started
  real         NAK_IGNORE_WINDOW_NS = 300.0;           // spec : lesser of Ack/Nak latency + 2 flits, or 300 ns
  real         nak_ignore_window_start_ns = -1.0;      // -1 : window not started

  task do_replay();
     tx_buffer_t replay_q[$];
     start_replay(replay_q);
     foreach (replay_q[i])
        send_replay_flit(replay_q[i], i + 1, replay_q.size());
     finish_replay(replay_q.size());
  endtask

  // Makes the list of flits to replay. REPLAY_SCHEDULED -> EP_REPLAY_IN_PROGRESS.
  function void start_replay(output tx_buffer_t replay_q[$]);
     int    start_idx = -1;
     string seq_list  = "";

     replay_q.delete();
     REPLAY_SCHEDULED      = 1'b0;
     EP_REPLAY_IN_PROGRESS = 1'b1;

     foreach (tx_retry_buffer[i]) begin
        if (tx_retry_buffer[i].seq_num == TX_REPLAY_FLIT_SEQ_NUM) begin
           start_idx = i;
           break;
        end
     end

     if (start_idx < 0) begin
        `uvm_warning("EP_REPLAY", $sformatf("REPLAY_SKIPPED :: flit SEQ_NUM=%0d is not in the TX retry buffer (already ACKed)",
                     TX_REPLAY_FLIT_SEQ_NUM))
        return;
     end

     if (REPLAY_SCHEDULED_TYPE == SELECTIVE_REPLAY)
        replay_q.push_back(tx_retry_buffer[start_idx]);
     else
        for (int i = start_idx; i < tx_retry_buffer.size(); i++)
           replay_q.push_back(tx_retry_buffer[i]);

     count_replay_num();   // [DL_ERR] FLIT_REPLAY_NUM + rollover rule

     foreach (replay_q[i]) seq_list = {seq_list, $sformatf("%0d ", replay_q[i].seq_num)};
     `uvm_info("EP_REPLAY", $sformatf({"\n",
        "  ==================== EP REPLAY START ====================\n",
        "   Replay type        : %s\n",
        "   Flits to replay    : %0d\n",
        "   Sequence numbers   : %s\n",
        "   FLIT_REPLAY_NUM    : %0d\n",
        "  =========================================================="},
        REPLAY_SCHEDULED_TYPE.name(), replay_q.size(), seq_list, FLIT_REPLAY_NUM), UVM_NONE)
     PCIe_flow_log::print("REPLAY", $sformatf("EP %s seq %s", (REPLAY_SCHEDULED_TYPE == SELECTIVE_REPLAY) ? "SEL" : "STD", seq_list));   // [FLOW]
  endfunction

  // Sends ONE replayed flit to the PL, with its ORIGINAL sequence number.
  function void send_replay_flit(tx_buffer_t entry, int unsigned num, int unsigned total);
     PCIe_sequence_item r_item;
     r_item = PCIe_sequence_item::type_id::create("ep_replay_item");
     r_item.tlp_data   = entry.tlp_data;
     r_item.seq_num    = entry.seq_num;
     r_item.is_payload = 1'b1;
     form_replay_flit(r_item.tlp_data, entry.seq_num, r_item.dlp_flit_out);
     nak_ignore_window_check_start(entry.seq_num);
     flit_cnt_count(1'b1, r_item.dlp_flit_out, 1'b1, 1'b1);   // [FLIT_CNT] TX (replayed flit)
     flit_tx_replay++;                             // [FLIT_CNT] replayed flit
     replayed_seq_q.push_back(entry.seq_num);
     `uvm_info("EP_REPLAY", $sformatf("REPLAY_FLIT %0d/%0d :: SEQ_NUM=%0d :: %s :: sent to EP PL",
               num, total, entry.seq_num, REPLAY_SCHEDULED_TYPE.name()), UVM_NONE)
     dl_ap.write(r_item);
  endfunction

  function void finish_replay(int unsigned n_flits);
     EP_REPLAY_IN_PROGRESS = 1'b0;
     `uvm_info("EP_REPLAY", $sformatf("REPLAY_DONE :: %0d flit(s) replayed :: waiting for ACK from RC", n_flits), UVM_NONE)
  endfunction

  // Builds a replayed payload flit : 236B TLP + 6B DLP with the ORIGINAL seq num.
  //   DLP0[7:6] Flit Usage            = 01b (payload)
  //   DLP0[5]   Prior Flit was Payload
  //   DLP0[3:2] Replay Command        = 00b (Explicit Sequence Number)
  //   DLP0[1:0] + DLP1 = 10-bit Flit Sequence Number
  //   DLP2..5   = 0 (no DLLP in a replayed flit)
  function void form_replay_flit(
    input  bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_data,
    input  bit [`PCIe_SEQ_NUM_W-1:0]                         seq_num,
    output bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] dl_flit_out
  );
     bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp;
     dlp = '0;
     dlp[0][7:6]           = 2'b01;
     dlp[0][5]             = last_flit_was_payload;
     dlp[0][4]             = 1'b0;
     dlp[0][3:2]           = 2'b00;
     {dlp[0][1:0], dlp[1]} = seq_num;
     last_flit_was_payload = 1'b1;
     for (int i = 0; i < `PCIe_TLP_DATA_BYTE_W; i++) dl_flit_out[i] = tlp_data[i];
     for (int i = 0; i < `PCIe_DLP_BYTE_W; i++)      dl_flit_out[`PCIe_TLP_DATA_BYTE_W+i] = dlp[i];
  endfunction

  // Nak Ignore Window : started when payload flit NAK_IGNORE_FLIT_SEQ_NUM+1 is sent
  function void nak_ignore_window_check_start(bit [`PCIe_SEQ_NUM_W-1:0] seq_num);
     if ((NAK_IGNORE_FLIT_SEQ_NUM != 10'h0) && (seq_num == mod1023_add(NAK_IGNORE_FLIT_SEQ_NUM, 10'h1)))
        nak_ignore_window_start_ns = $realtime / 1ns;
  endfunction

  // 1 : a NAK for NAK_IGNORE_FLIT_SEQ_NUM must still be ignored
  function bit nak_ignore_window_open();
     if (nak_ignore_window_start_ns < 0.0) return 1'b0;    // not started
     return (($realtime / 1ns) - nak_ignore_window_start_ns) <= NAK_IGNORE_WINDOW_NS;
  endfunction

  // ===========================================================================
  // [DL_ERR] Data Link Layer error log  (PCIe 6.1 Sec 6.2, Table 6-4)
  //   Each counter is one error the spec says must be LOGGED (reported) :
  //     err_invalid_flit          correctable   receiver    : invalid flit (CRC fails after FEC)
  //                                                           -> NAK + replay (Sec 4.2.3.4.2)
  //     err_replay_timer_timeout  correctable   transmitter : no ACK progress for 1500 flits
  //     err_replay_num_rollover   correctable   transmitter : too many replays, Port must enter Recovery
  //     err_dl_protocol           uncorrectable receiver    : Data Link Protocol Error
  //   Tests read the counters. A NOP / unsupported DLLP or a duplicate flit is
  //   NOT an error : dl_error_total() must not change for them.
  // ===========================================================================
  int unsigned err_invalid_flit;
  int unsigned err_replay_timer_timeout;
  int unsigned err_replay_num_rollover;
  int unsigned err_dl_protocol;

  function void log_dl_error(string error_name, string detail);
    `uvm_info("EP_DL_ERROR", $sformatf("DL ERROR LOGGED :: %s :: %s (total DL errors = %0d)",
              error_name, detail, dl_error_total()), UVM_NONE)
    PCIe_flow_log::print("DL_ERROR", $sformatf("EP %s", error_name));   // [FLOW]
  endfunction

  function int unsigned dl_error_total();
    return err_invalid_flit + err_replay_timer_timeout + err_replay_num_rollover + err_dl_protocol;
  endfunction

  // [REPLAY] FLIT_REPLAY_NUM rules at the start of a replay (spec Flit Replay Transmit Rules 0/1/2, 64.0 GT/s)
  //   FLIT_REPLAY_NUM <  111b : FLIT_REPLAY_NUM + 1, replay
  //   FLIT_REPLAY_NUM == 111b : rollover to 000b, REPLAY_NUM Rollover error logged,
  //                             the Port must enter Recovery (Recovery is NOT modelled :
  //                             the replay is done right away)
  function void count_replay_num();
    if (FLIT_REPLAY_NUM == 3'b111) begin
      FLIT_REPLAY_NUM = 3'b000;
      err_replay_num_rollover++;
      log_dl_error("REPLAY_NUM_ROLLOVER", "8 replays without forward progress -> Port must enter Recovery (not modelled, replay continues)");
    end
    else begin
      FLIT_REPLAY_NUM++;
    end
  endfunction


  // ===========================================================================
  // [DL_RESET] DL_Inactive state reset  (PCIe 6.1 Sec 4.2.3.4.2.1 "Set to ... in DL_Inactive")
  //   Called when the DLCMSM starts and when Physical LinkUp goes to 0.
  //   All sequence numbers go back to their start values, all ACK/NAK/replay
  //   flags are cleared and BOTH retry buffers are emptied.
  // ===========================================================================
  function void dl_reset_state(string why);
    n_tx_flits_dropped_on_reset = tx_retry_buffer.size();   // [FLOW_SUM]
    NEXT_TX_FLIT_SEQ_NUM                = 10'h001;
    TX_ACKNAK_FLIT_SEQ_NUM              = 10'h3FF;
    NEXT_EXPECTED_RX_FLIT_SEQ_NUM       = 10'h001;
    IMPLICIT_RX_FLIT_SEQ_NUM            = 10'h000;
    ACKD_FLIT_SEQ_NUM                   = 10'h3FF;
    TX_REPLAY_FLIT_SEQ_NUM              = 10'h000;
    NAK_IGNORE_FLIT_SEQ_NUM             = 10'h000;
    FLIT_REPLAY_NUM                     = '0;
    NON_IDLE_EXPLICIT_SEQ_NUM_FLIT_RCVD = 1'b0;
    NAK_SCHEDULED                       = 1'b0;
    ACK_SCHEDULED                       = 1'b0;
    REPLAY_SCHEDULED                    = 1'b0;
    EP_REPLAY_IN_PROGRESS               = 1'b0;
    NAK_WITHDRAWAL_ALLOWED              = 1'b0;
    RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM   = 10'h000;
    NEXT_RX_FLIT_SEQ_NUM_TO_STORE       = 10'h000;
    RX_RETRY_BUFFER_OVERFLOW            = 1'b0;
    last_flit_was_payload               = 1'b0;
    nak_flit_tx_pending                 = 1'b0;
    rx_release_stored_flits             = 1'b0;
    nak_ignore_window_start_ns          = -1.0;
    ack_hold_seq                        = 10'h3FF;
    dllp_tx_pending                     = 1'b0;
    tx_retry_buffer.delete();
    rx_retry_buffer.delete();
    `uvm_info("EP_DL_RESET", $sformatf("DL_RESET :: %s :: sequence numbers back to start (NEXT_EXPECTED_RX=1, TX_ACKNAK=1023), flags cleared, retry buffers emptied",
              why), UVM_LOW)
  endfunction

  // ===========================================================================
  // [ACK_HOLD] Test knob : hold the ACKs
  //   set_ack_hold(1) : the EP keeps receiving flits but the ACK number it sends
  //                     does not move (as if the ACKs were delayed / lost).
  //                     The RC TX retry buffer fills up and its replay timer runs.
  //   set_ack_hold(0) : the real ACK (TX_ACKNAK_FLIT_SEQ_NUM) is sent again.
  // ===========================================================================
  // (declaration moved to the top of the class : Questa needs it before its first use)

  function void set_ack_hold(bit on);
    if (on) begin
      ack_hold_seq = TX_ACKNAK_FLIT_SEQ_NUM;
      ack_hold     = 1'b1;
      `uvm_info("EP_ACK_HOLD", $sformatf("ACK_HOLD ON :: the EP keeps sending ACK(%0d) until the hold is released", ack_hold_seq), UVM_NONE)
    end
    else begin
      ack_hold = 1'b0;
      if (dl_link_active) ACK_SCHEDULED = 1'b1;   // send the real ACK now
      `uvm_info("EP_ACK_HOLD", $sformatf("ACK_HOLD OFF :: real ACK(%0d) is sent again", TX_ACKNAK_FLIT_SEQ_NUM), UVM_NONE)
    end
  endfunction

  // ===========================================================================
  // [DUP_FLIT] Duplicate flits : a payload flit whose sequence number was
  //   already received is dropped (Flit Discard 0) and NOT sent to the TL.
  // ===========================================================================
  int unsigned n_rx_dup_discarded;

  // ===========================================================================
  // [SEQ_LOG] Test helper : move the receive sequence numbers near the wrap
  //   point (only when nothing is outstanding). Must match the RC
  //   set_tx_seq_for_test() value.
  // ===========================================================================
  function void set_rx_seq_for_test(bit [`PCIe_SEQ_NUM_W-1:0] next_seq);
    NEXT_EXPECTED_RX_FLIT_SEQ_NUM = next_seq;
    TX_ACKNAK_FLIT_SEQ_NUM        = mod1023_sub(next_seq, 10'h1);
    IMPLICIT_RX_FLIT_SEQ_NUM      = mod1023_sub(next_seq, 10'h1);
    `uvm_info("EP_SEQ_TEST", $sformatf("RX SEQUENCE NUMBER MOVED :: NEXT_EXPECTED_RX_FLIT_SEQ_NUM=%0d TX_ACKNAK_FLIT_SEQ_NUM=%0d",
              NEXT_EXPECTED_RX_FLIT_SEQ_NUM, TX_ACKNAK_FLIT_SEQ_NUM), UVM_NONE)
  endfunction

  // ===========================================================================
  // [OPT_UPDATE_FC] Optimized_Update_FC transmit  (PCIe 6.1 Table 4-17 / Table 4-18)
  //   USE_OPT_UPDATE_FC = 1 : shared Posted credits are returned with ONE
  //   Optimized_Update_FC in DLP2..5 (DLP0[4] = 1) instead of a DLLP :
  //     [31] 0 (indicator)  [30:28] VC  [27:20] Shared NPH
  //     [19:12] Shared PH   [11:0]  Shared PD
  // ===========================================================================
  bit          USE_OPT_UPDATE_FC;
  bit          dlp_is_opt_update_fc;   // 1 only while form_dl_packet() builds that flit
  int unsigned n_opt_updfc_tx;

  task fc_send_opt_update(int unsigned v);
    bit [31:0] opt;
    opt = {1'b0, v[2:0], adv_h_shr[v][1][7:0], adv_h_shr[v][0][7:0], adv_d_shr[v][0][11:0]};
    `uvm_info("EP_DL_FC", $sformatf("[FC_DL_TX] OPTIMIZED_UPDATE_FC VC%0d : SHARED NPH=%0d PH=%0d PD=%0d (raw %08h)",
              v, adv_h_shr[v][1], adv_h_shr[v][0], adv_d_shr[v][0], opt), UVM_LOW)
    dlp_is_opt_update_fc = 1'b1;
    fc_send_active(opt);
    dlp_is_opt_update_fc = 1'b0;
    n_opt_updfc_tx++;
  endtask

  // ===========================================================================
  // [DLLP_RX] Received DLLP rules  (PCIe 6.1 Sec 3.6.2.3, Flit Mode)
  //   * FC DLLPs (InitFC / UpdateFC)   -> Transaction Layer   (fc_rx_flit)
  //   * NOP DLLP (31h)                 -> discarded
  //   * Link Management DLLP (28h)     -> L0p control logic. L0p is not
  //                                       enabled in this model, so it is
  //                                       silently ignored (Sec 4.2.6.7.1)
  //   * PM DLLPs (20h 21h 23h 24h)     -> power management logic (not modelled)
  //   * Data Link Feature (02h)        -> DLCMSM feature exchange
  //   * Vendor-Specific (30h)          -> ignored
  //   * any other (unsupported) type   -> discarded, NOT an error
  //   DLP2..5 = 0 means "no DLLP in this flit" (also the NOP2 encoding).
  // ===========================================================================
  int unsigned n_rx_nop_dllp;
  int unsigned n_rx_link_mgmt_dllp;
  int unsigned n_rx_pm_dllp;
  int unsigned n_rx_feature_dllp;
  int unsigned n_rx_vendor_dllp;
  int unsigned n_rx_unsupported_dllp;
  bit [31:0]   last_link_mgmt_dllp;

  function void dllp_rx_check(bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp, bit is_valid);
    bit [31:0] v;
    if (!is_valid)  return;                                  // bad flit : nothing in it can be used
    if (dlp[0][4])  return;                                  // Optimized_Update_FC / Flit_Marker
    v = {dlp[2], dlp[3], dlp[4], dlp[5]};
    if (v == 32'h0) return;                                  // no DLLP
    if (PCIe_sequence_item::fc_is_dllp(v)) return;           // FC DLLP : fc_rx_flit()
    case (v[31:24])
      8'h31: begin
        n_rx_nop_dllp++;
        `uvm_info("EP_DLLP_RX", $sformatf("NOP DLLP received (%08h) -> discarded", v), UVM_LOW)
      end
      8'h28: begin
        n_rx_link_mgmt_dllp++;
        last_link_mgmt_dllp = v;
        `uvm_info("EP_DLLP_RX", $sformatf("LINK MANAGEMENT DLLP received (%08h) : Link Mgmt Type=%02h L0p.Cmd=%0h width=%0h -> L0p not enabled, silently ignored",
                  v, v[23:16], v[11:8], v[3:0]), UVM_LOW)
      end
      8'h20, 8'h21, 8'h23, 8'h24: begin
        n_rx_pm_dllp++;
        `uvm_info("EP_DLLP_RX", $sformatf("PM DLLP received (%08h) -> power management logic (not modelled)", v), UVM_LOW)
      end
      8'h02: begin
        n_rx_feature_dllp++;
        `uvm_info("EP_DLLP_RX", $sformatf("DATA LINK FEATURE DLLP received (%08h)", v), UVM_LOW)
      end
      8'h30: begin
        n_rx_vendor_dllp++;
        `uvm_info("EP_DLLP_RX", $sformatf("VENDOR-SPECIFIC DLLP received (%08h) -> ignored", v), UVM_LOW)
      end
      default: begin
        n_rx_unsupported_dllp++;
        `uvm_info("EP_DLLP_RX", $sformatf("UNSUPPORTED DLLP TYPE %02h received (%08h) -> discarded, not an error (Sec 3.6.2.3)",
                  v[31:24], v), UVM_NONE)
      end
    endcase
  endfunction

    task run_dlcmsm();
       forever begin
          case (DL_STATE)

             DL_INACTIVE: begin
                `uvm_info("EP_DLCMSM","==========================================",UVM_LOW)
                `uvm_info("EP_DLCMSM","DLCMSM_STATE = DL_INACTIVE",UVM_LOW)
                `uvm_info("EP_DLCMSM","==========================================",UVM_LOW)
                dlcmsm_state_dl_inactive();
             end

             DL_FEATURE: begin
                `uvm_info("EP_DLCMSM","==========================================",UVM_LOW)
                `uvm_info("EP_DLCMSM","DLCMSM_STATE = DL_FEATURE",UVM_LOW)
                `uvm_info("EP_DLCMSM","==========================================",UVM_LOW)
                dlcmsm_state_dl_feature();
             end

             DL_INIT: begin
                case (dl_init_substate)
                   INIT_FC1: begin
                      `uvm_info("EP_DLCMSM","SUB_STATE = DL_INIT.FC_INIT1",UVM_LOW)
                      dlcmsm_state_init_fc1();
                   end
                   INIT_FC2: begin
                      `uvm_info("EP_DLCMSM","SUB_STATE = DL_INIT.FC_INIT2",UVM_LOW)
                      dlcmsm_state_init_fc2();
                   end
                   default: `uvm_error("EP_DLCMSM","INVALID_DL_INIT_SUBSTATE")
                endcase
             end

             DL_ACTIVE: begin
                `uvm_info("EP_DLCMSM","==========================================",UVM_LOW)
                `uvm_info("EP_DLCMSM","DLCMSM_STATE = DL_ACTIVE :: LINK_READY_FOR_TLP_TRAFFIC",UVM_LOW)
                `uvm_info("EP_DLCMSM","==========================================",UVM_LOW)
                dlcmsm_state_dl_active();
                wait (!phy_linkup);
                DL_STATE       = DL_INACTIVE;
                dl_link_active = 1'b0;
                `uvm_info("EP_DLCMSM","[DL_ACTIVE] phy_linkup=0 :: BACK_TO_DL_INACTIVE",UVM_LOW)
                return;
             end

             default: `uvm_error("EP_DLCMSM","INVALID_DLCMSM_STATE")
          endcase
       end
    endtask

    // ---------------- DL_INACTIVE ----------------
    task dlcmsm_state_dl_inactive();
       `uvm_info("EP_DLCMSM",$sformatf(
          "[DL_INACTIVE] CHECKING_DEPENDENCY :: phy_linkup=%0b (mirrored live from LTSSM link_up by the driver) :: link_enabled=%0b",
          phy_linkup, link_enabled),UVM_LOW)
       wait (phy_linkup && link_enabled);
       `uvm_info("EP_DLCMSM",$sformatf(
          "[DL_INACTIVE] DEPENDENCY_SATISFIED :: phy_linkup=%0b link_enabled=%0b :: TRANSITION -> DL_FEATURE",
          phy_linkup, link_enabled),UVM_LOW)
       DL_STATE = DL_FEATURE;
    endtask

    // ---------------- DL_FEATURE ----------------
    task dlcmsm_state_dl_feature();
       send_dllp_flit(FEATURE_DLLP);
       `uvm_info("EP_DLCMSM",$sformatf(
          "[DL_FEATURE] FEATURE_DLLP_SENT=%08h :: TRANSITION -> DL_INIT.FC_INIT1",FEATURE_DLLP),UVM_LOW)
       DL_STATE         = DL_INIT;
       dl_init_substate = INIT_FC1;
       fc1_sent_count    = 0;
       fc2_sent_count    = 0;
    endtask

    // ---------------- DL_INIT : FC_INIT1 ----------------
    task dlcmsm_state_init_fc1();
      fc_send_init_round(`PCIe_FC_TYPE_INITFC1);
      fc1_sent_count++;      // counts complete rounds (6 DLLPs each)
       // [FC_OPT] OLD : for (int w = 0; w < 100 && !fi1_done(); w++) #1ns;
       // [FC_OPT] NEW : wait (up to PCIe_FC_INIT_WAIT_NS) for the peer's six InitFC1 before deciding to resend
       for (int w = 0; w < `PCIe_FC_INIT_WAIT_NS && !fi1_done(); w++) #1ns;

      `uvm_info("EP_DLCMSM",$sformatf(
         "[DL_INIT.FC_INIT1] ROUND_%0d_DONE :: FI1 dedicated P/NP/CPL=%0b%0b%0b shared P/NP/CPL=%0b%0b%0b",
         fc1_sent_count, fi1_ded[0][0], fi1_ded[0][1], fi1_ded[0][2],
         fi1_shr[0][0], fi1_shr[0][1], fi1_shr[0][2]),UVM_LOW)
      if (fi1_done()) begin
         `uvm_info("EP_DLCMSM",$sformatf(
            "[DL_INIT.FC_INIT1] FI1_SET :: peer credits recorded PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d :: TRANSITION -> DL_INIT.FC_INIT2",
            peer_h[0][0], peer_d[0][0], peer_h[0][1], peer_d[0][1], peer_h[0][2], peer_d[0][2]),UVM_LOW)
         dl_init_substate = INIT_FC2;
      end
      else if (fc1_sent_count >= `PCIe_FC_INIT_MAX_ROUNDS) begin
         `uvm_error("EP_DLCMSM",$sformatf("[DL_INIT.FC_INIT1] FI1_NOT_SET_AFTER_%0d_ROUNDS :: peer never sent all six InitFC DLLPs :: FORCING FC_INIT2",fc1_sent_count))
         dl_init_substate = INIT_FC2;
      end
      else begin
         `uvm_info("EP_DLCMSM","[DL_INIT.FC_INIT1] FI1_NOT_SET :: STAYING_IN_FC_INIT1 (resend InitFC1 round)",UVM_LOW)
         #(`PCIe_FC_INIT_ROUND_GAP_NS * 1ns);
      end
   endtask

    // ---------------- DL_INIT : FC_INIT2 ----------------
    task dlcmsm_state_init_fc2();
      fc_send_init_round(`PCIe_FC_TYPE_INITFC2);
      fc2_sent_count++;
      // [FC_OPT] NEW : wait (up to PCIe_FC_INIT_WAIT_NS) for FI2 (peer InitFC2 / UpdateFC / TLP) before deciding to resend
      for (int w = 0; w < `PCIe_FC_INIT_WAIT_NS && !fi2_done(); w++) #1ns;
      `uvm_info("EP_DLCMSM",$sformatf("[DL_INIT.FC_INIT2] ROUND_%0d_DONE :: FI2=%0b",fc2_sent_count,fi2_done()),UVM_LOW)
      if (fi2_done()) begin
         `uvm_info("EP_DLCMSM","[DL_INIT.FC_INIT2] FI2_SET :: TRANSITION -> DL_ACTIVE",UVM_LOW)
         PCIe_flow_log::print("FC_INIT", "EP FC init done");   // [FLOW]
         DL_STATE = DL_ACTIVE;
      end
      else if (fc2_sent_count >= `PCIe_FC_INIT_MAX_ROUNDS) begin
         `uvm_error("EP_DLCMSM",$sformatf("[DL_INIT.FC_INIT2] FI2_NOT_SET_AFTER_%0d_ROUNDS :: FORCING DL_ACTIVE",fc2_sent_count))
         DL_STATE = DL_ACTIVE;
      end
      else begin
         `uvm_info("EP_DLCMSM","[DL_INIT.FC_INIT2] FI2_NOT_SET :: STAYING_IN_FC_INIT2 (resend InitFC2 round)",UVM_LOW)
         #(`PCIe_FC_INIT_ROUND_GAP_NS * 1ns);
      end
   endtask

    // ---------------- DL_ACTIVE ----------------
    task dlcmsm_state_dl_active();
       PCIe_flow_log::print("DLCMSM", "EP DL_Active");   // [FLOW]
       dl_link_active = 1'b1;
         ep_dl_active_event.trigger();
       `uvm_info("EP_DLCMSM",
          "[DL_ACTIVE] dl_link_active=1 :: dl_active_event_TRIGGERED :: TL_MAY_NOW_SEND_TLPs",UVM_LOW)
    endtask

    // Builds a NOP/DLLP-only flit (is_payload=0) with given dllp_content and
    // pushes it through the SAME path normal flits use (dl_ap -> PL model).
    // The task then BLOCKS until the EP controller driver has put that flit on
    // the PIPE (driver clears dllp_tx_pending), so the DLCMSM packets are
    // transmitted one by one, in order, and never overwrite each other in the
    // PL model.
    task send_dllp_flit(bit [31:0] content);
       PCIe_sequence_item dcm_item;
       dcm_item = PCIe_sequence_item::type_id::create("dcm_item");
       dllp_content = content;
       form_dl_packet(dcm_item.tlp_data, 1'b0, dcm_item.dlp_flit_out); // is_payload=0
       // dllp_content belongs to THIS flit only. Clear it so it does not leak
       // into the TLP flit that write() forms after DL_ACTIVE (DLP2-DLP5 of a
       // TLP flit must stay 0, exactly as before the DLCMSM packets were driven).
       dllp_content = '0;
       dllp_tx_pending = 1'b1;
       // [DL_ASSERT] used by DL_NO_DLLP_IN_INACTIVE_CHECK (no DLLP in DL_INACTIVE)
       if (dl_aif != null) begin
         dl_aif.tx_dllp_dl_state = DL_STATE;
         dl_aif.tx_dllp_content  = content;
         dl_aif.tx_dllp_cnt++;
       end
       flit_cnt_count(1'b1, dcm_item.dlp_flit_out);   // [FLIT_CNT] TX
       dl_ap.write(dcm_item);
       `uvm_info("EP_DLCMSM",$sformatf("SENT_DLLP_FLIT content=%08h :: WAITING_FOR_DRIVER_TO_DRIVE_IT_ON_PIPE",content),UVM_LOW)
       wait (dllp_tx_pending == 1'b0);
       `uvm_info("EP_DLCMSM",$sformatf("DLLP_FLIT_DRIVEN_ON_PIPE content=%08h",content),UVM_LOW)
    endtask
  // =========================================================================
  // END DLCMSM FSM BLOCK
  // =========================================================================

  // ===========================================================================
  // [SEL_NAK] RX SIDE : ACK / NAK / DISCARD RULES  (PCIe 6.1 Sec 4.2.3.4.2.1.5)
  //
  //   handle_incoming_flit() runs once for every flit received from the RC.
  //   It updates the DL state and sets rx_flit_action :
  //     RX_FLIT_ACCEPT -> write_ep_mon_242b() sends the TLP to the TL
  //     RX_FLIT_STORE  -> TLP kept in the RX retry buffer (Selective NAK)
  //     RX_FLIT_DROP   -> TLP dropped
  //
  //   Example (Selective NAK) : RC sends flits 10 11 12 13, flit 11 is corrupted
  //     10 good         -> ACCEPT                        (Ack Schedule 0)
  //     11 bad          -> DROP, wait for the next flit  (Nak Schedule 0 : NAK withdrawal)
  //     12 good         -> STORE + SELECTIVE NAK(10)     (Nak Schedule 3)
  //     13 good         -> STORE                         (Nak Schedule 3, NAK already scheduled)
  //     RC replays 11   -> ACCEPT 11, then 12 and 13 go to the TL, ACK(13)  (Ack Schedule 2)
  // ===========================================================================

  function void handle_incoming_flit(bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp, bit is_valid);
    bit [`PCIe_SEQ_NUM_W-1:0]    sequence_number;
    bit [`PCIe_FLIT_USAGE_W-1:0] flit_usage;
    bit                          prior_was_payload;
    bit                          is_payload;
    bit                          is_explicit;
    bit                          is_idle;
    bit                          is_nop;

    rx_flit_action          = RX_FLIT_DROP;   // default : TLP is not used
    rx_release_stored_flits = 1'b0;

    fc_rx_flit(dlp, is_valid);   // FLOW CONTROL : InitFC / UpdateFC DLLP processing
    dllp_rx_check(dlp, is_valid);  // [DLLP_RX] NOP / Link Management / PM / unsupported DLLPs

    // ---- 1. Decode the DLP bytes ----
    sequence_number   = {dlp[0][1:0], dlp[1]};
    flit_usage        = dlp[0][7:6];
    prior_was_payload = dlp[0][5];
    replay_cmd        = dlp[0][3:2];
    is_payload        = (flit_usage == 2'b01);
    is_explicit       = (replay_cmd == 2'b00);                   // Explicit Sequence Number flit
    is_idle           = is_explicit && (flit_usage == 2'b00) && (sequence_number == 10'h0);
    is_nop            = (flit_usage == 2'b00) && !is_idle;       // no TLP inside
    received_explicit_seq   = is_explicit;
    received_explicit_seq_0 = is_explicit && (sequence_number == 10'h0);

    `uvm_info("EP_DL_RX", $sformatf("RX_FLIT :: valid=%0b payload=%0b nop=%0b idle=%0b replay_cmd=%02b seq_field=%0d prior_payload=%0b",
              is_valid, is_payload, is_nop, is_idle, replay_cmd, sequence_number, prior_was_payload), UVM_LOW)

    // ---- 2. IMPLICIT_RX_FLIT_SEQ_NUM is always updated first (spec) ----
    update_implicit_rx_sequence_number(sequence_number, is_valid, is_nop, is_payload, is_explicit, is_idle, prior_was_payload);

    `uvm_info("EP_DL_RX", $sformatf("RX_STATE :: IMPLICIT_RX_SEQ=%0d NEXT_EXPECTED_RX_SEQ=%0d TX_ACKNAK_SEQ=%0d NAK_SCHEDULED=%0b(%s) NAK_WITHDRAWAL_ALLOWED=%0b RX_RETRY_BUFFER=%0d",
              IMPLICIT_RX_FLIT_SEQ_NUM, NEXT_EXPECTED_RX_FLIT_SEQ_NUM, TX_ACKNAK_FLIT_SEQ_NUM, NAK_SCHEDULED,
              (NAK_SCHEDULED_TYPE == SELECTIVE_NAK) ? "SELECTIVE" : "STANDARD",
              NAK_WITHDRAWAL_ALLOWED, rx_retry_buffer.size()), UVM_LOW)

    // ---- 3. Bad flit (CRC / FEC error) ----
    if (!is_valid) begin
      err_invalid_flit++;   // [DL_ERR]
      log_dl_error("INVALID_FLIT", "CRC fails after FEC correction -> flit dropped");
      if (NAK_SCHEDULED) begin
        if (NAK_SCHEDULED_TYPE == STANDARD_NAK) discard_flit(1);
        else                                    execute_nak_schedule(6);
      end
      else begin
        if (NAK_WITHDRAWAL_ALLOWED) execute_nak_schedule(1);
        else                        execute_nak_schedule(0);
      end
      return;
    end

    // ---- 4. Good flit : first use the ACK / NAK it carries for OUR (EP) flits ----
    if (!is_explicit) process_received_ack_nak(sequence_number, replay_cmd);

    // ---- 5. Explicit sequence number 0 ----
    if (received_explicit_seq_0) begin
      if (!is_idle) discard_flit(2);   // Flit Discard 2 : protocol error
      return;                          // IDLE flit : nothing to do
    end

    // ---- 6. NAK withdrawal : the PREVIOUS flit was bad, this flit decides ----
    if (NAK_WITHDRAWAL_ALLOWED) begin
      NAK_WITHDRAWAL_ALLOWED = 1'b0;
      if (prior_was_payload) begin
        // The bad flit was a payload flit : it is really lost -> NAK
        if (is_nop) begin
          schedule_new_nak(USE_STANDARD_NAK_ONLY ? STANDARD_NAK : SELECTIVE_NAK,
                           "bad payload flit followed by a NOP flit");
          if (!USE_STANDARD_NAK_ONLY)
            NEXT_RX_FLIT_SEQ_NUM_TO_STORE = mod1023_add(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1);
        end
        else if (USE_STANDARD_NAK_ONLY) begin
          standard_nak_procedure();
        end
        else begin
          NEXT_RX_FLIT_SEQ_NUM_TO_STORE = mod1023_add(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1);
          selective_nak_procedure();
        end
      end
      else begin
        // The bad flit was a NOP flit : nothing is lost if the sequence is OK
        if (bad_sequence_number() || (is_nop && bad_nop_sequence_number())) begin
          execute_nak_schedule(2);
        end
        else begin
          `uvm_info("EP_DL_RX", "NAK_WITHDRAWN :: the bad flit was a NOP flit, no TLP lost", UVM_LOW)
          if ((is_payload && duplicate_sequence_number()) || is_nop)
            TX_ACKNAK_FLIT_SEQ_NUM = mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1);
          if (is_payload && (NEXT_EXPECTED_RX_FLIT_SEQ_NUM == IMPLICIT_RX_FLIT_SEQ_NUM))
            execute_ack_schedule(0);
        end
      end
      return;
    end

    // ---- 7. A NAK is already outstanding ----
    if (NAK_SCHEDULED) begin
      if (NAK_SCHEDULED_TYPE == STANDARD_NAK) begin
        if (is_nop) begin
          if (is_explicit && (IMPLICIT_RX_FLIT_SEQ_NUM == mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1))) begin
            NAK_SCHEDULED       = 1'b0;
            nak_flit_tx_pending = 1'b0;
            `uvm_info("EP_DL_RX", "STANDARD_NAK_CLEARED :: NOP flit shows no flit was lost", UVM_LOW)
          end
          else discard_flit(0);
        end
        else standard_nak_procedure();
      end
      else begin   // Selective NAK outstanding
        if (is_nop) discard_flit(0);
        else        selective_nak_procedure();
      end
      return;
    end

    // ---- 8. Normal case : no NAK outstanding ----
    if (is_nop) begin
      if (bad_nop_sequence_number()) execute_nak_schedule(2);
      else                           discard_flit(0);
    end
    else begin
      if      (duplicate_sequence_number()) begin n_rx_dup_discarded++; discard_flit(0); end   // [DUP_FLIT]
      else if (bad_sequence_number())       execute_nak_schedule(2);
      else                                  execute_ack_schedule(0);   // forward progress
    end
  endfunction

  // Standard NAK outstanding (or being scheduled) : wait for the lost flit
  function void standard_nak_procedure();
    if (duplicate_sequence_number()) begin
      if (NAK_SCHEDULED) begin n_rx_dup_discarded++; discard_flit(0); end   // [DUP_FLIT]
      else               execute_nak_schedule(2);
    end
    else if (received_explicit_seq && (IMPLICIT_RX_FLIT_SEQ_NUM == NEXT_EXPECTED_RX_FLIT_SEQ_NUM)) begin
      execute_ack_schedule(1);   // the lost flit is back
    end
    else begin
      if (NAK_SCHEDULED) discard_flit(0);
      else               execute_nak_schedule(2);
    end
  endfunction

  // Selective NAK outstanding (or being scheduled) : store later flits, wait for the lost flit
  function void selective_nak_procedure();
    if (duplicate_sequence_number()) begin
      n_rx_dup_discarded++;   // [DUP_FLIT]
      discard_flit(0);
    end
    else if (received_explicit_seq && (IMPLICIT_RX_FLIT_SEQ_NUM == NEXT_EXPECTED_RX_FLIT_SEQ_NUM)) begin
      // the lost flit is back
      if (RX_RETRY_BUFFER_OVERFLOW) execute_nak_schedule(5);
      else                          execute_ack_schedule(2);
    end
    else if (IMPLICIT_RX_FLIT_SEQ_NUM == NEXT_RX_FLIT_SEQ_NUM_TO_STORE) begin
      // next flit after the lost one, in order -> store it
      if (rx_retry_buffer.size() >= RX_RETRY_BUFFER_MAX_FLITS) execute_nak_schedule(4);
      else                                                     execute_nak_schedule(3);
    end
    else begin
      // gap in the stored flits
      if (RX_RETRY_BUFFER_OVERFLOW) discard_flit(0);   // spec : preferred
      else                          execute_nak_schedule(2);
    end
  endfunction

  function bit bad_sequence_number();
    return (mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, IMPLICIT_RX_FLIT_SEQ_NUM) > 511);
  endfunction

  function bit bad_nop_sequence_number();
    return bad_sequence_number() || (IMPLICIT_RX_FLIT_SEQ_NUM == NEXT_EXPECTED_RX_FLIT_SEQ_NUM);
  endfunction

  function bit duplicate_sequence_number();
    return (mod1023_sub(TX_ACKNAK_FLIT_SEQ_NUM, IMPLICIT_RX_FLIT_SEQ_NUM) < 511);
  endfunction

  // ---------------------------------------------------------------------------
  // Puts a NEW NAK in place : RX state + one NAK flit to send
  // ---------------------------------------------------------------------------
  function void schedule_new_nak(bit nak_type, string reason);
    NAK_SCHEDULED          = 1'b1;
    NAK_SCHEDULED_TYPE     = nak_type;
    TX_ACKNAK_FLIT_SEQ_NUM = mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1);
    nak_flit_tx_pending    = 1'b1;
    ACK_SCHEDULED          = 1'b0;
    if (nak_type == SELECTIVE_NAK) n_sel_nak_scheduled++;
    else                           n_std_nak_scheduled++;
    `uvm_info("EP_DL_RX", $sformatf({"\n",
       "  ==================== EP NAK SCHEDULED ====================\n",
       "   NAK type            : %s (Replay Command %s)\n",
       "   Last good flit      : SEQ_NUM=%0d (sent in the NAK)\n",
       "   Lost flit (replay)  : SEQ_NUM=%0d\n",
       "   Reason              : %s\n",
       "  =========================================================="},
       (nak_type == SELECTIVE_NAK) ? "SELECTIVE_NAK" : "STANDARD_NAK",
       (nak_type == SELECTIVE_NAK) ? "11b" : "10b",
       TX_ACKNAK_FLIT_SEQ_NUM, NEXT_EXPECTED_RX_FLIT_SEQ_NUM, reason), UVM_NONE)
    nak_sent_lost_seq_q.push_back(NEXT_EXPECTED_RX_FLIT_SEQ_NUM);   // [FLOW_SUM]
    PCIe_flow_log::print("NAK", $sformatf("EP sent %s NAK(%0d), lost seq %0d", (nak_type == SELECTIVE_NAK) ? "SEL" : "STD", TX_ACKNAK_FLIT_SEQ_NUM, NEXT_EXPECTED_RX_FLIT_SEQ_NUM));   // [FLOW]
  endfunction

  // Keeps the TLP of the current flit in the RX retry buffer
  function void store_flit_in_rx_retry_buffer();
    rx_retry_entry_t entry;
    entry.seq_num  = IMPLICIT_RX_FLIT_SEQ_NUM;
    entry.tlp_data = rx_flit_tlp;
    rx_retry_buffer.push_back(entry);
    RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM;
    NEXT_RX_FLIT_SEQ_NUM_TO_STORE     = mod1023_add(NEXT_RX_FLIT_SEQ_NUM_TO_STORE, 10'h1);
    rx_flit_action = RX_FLIT_STORE;
    n_rx_flits_stored++;
    `uvm_info("EP_DL_RX", $sformatf("RX_RETRY_BUFFER_STORE :: SEQ_NUM=%0d stored (waiting for lost flit SEQ_NUM=%0d) :: buffer size=%0d",
              entry.seq_num, NEXT_EXPECTED_RX_FLIT_SEQ_NUM, rx_retry_buffer.size()), UVM_NONE)
  endfunction

  // Empties the RX retry buffer (a Standard NAK replays all these flits anyway)
  function void purge_rx_retry_buffer(string reason);
    if (rx_retry_buffer.size() > 0)
      `uvm_info("EP_DL_RX", $sformatf("RX_RETRY_BUFFER_PURGE :: %0d stored flit(s) dropped :: %s",
                rx_retry_buffer.size(), reason), UVM_NONE)
    rx_retry_buffer.delete();
    RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = 10'h0;
  endfunction

  // FLIT MODE PACKET CREATION DLP
  //   DLP0[3:2] Replay Command : 00b explicit seq num, 01b ACK, 10b Standard NAK, 11b Selective NAK
  //   A NEW payload flit always gets NEXT_TX_FLIT_SEQ_NUM (even when it carries an
  //   ACK/NAK) and only payload flits are stored in the TX retry buffer.
  function void form_dl_packet(
    input bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_data,
    input bit is_payload,
    output bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] dl_flit_out
  );
    bit [`PCIe_SEQ_NUM_W-1:0] seq_num_to_send;
    bit [`PCIe_REPLAY_CMD_W-1:0] replay_command;
    bit [`PCIe_DLP_BYTE_W-1:0][`PCIe_BYTE_W-1:0] dlp;

    // 1. Determine Replay Command and Sequence Number
    if (NAK_SCHEDULED) begin
      replay_command = (NAK_SCHEDULED_TYPE == STANDARD_NAK) ? 2'b10 : 2'b11;
      seq_num_to_send = TX_ACKNAK_FLIT_SEQ_NUM;
    end
    else if (is_payload) begin
      replay_command = 2'b00;
      seq_num_to_send = NEXT_TX_FLIT_SEQ_NUM;
    end
    else begin
      replay_command = 2'b01;
      // [ACK_HOLD] while ACKs are held the ACK number does not move
      seq_num_to_send = ack_hold ? ack_hold_seq : TX_ACKNAK_FLIT_SEQ_NUM;
    end
    note_acknak_sent(seq_num_to_send, replay_command);   // [FLOW_SUM]

    // 2. Construct DLP0
    dlp[0][7:6] = is_payload ? 2'b01 : 2'b00;
    dlp[0][5] = last_flit_was_payload;
    dlp[0][4] = dlp_is_opt_update_fc;   // [OPT_UPDATE_FC] 1 : DLP2..5 = Optimized_Update_FC
    dlp[0][3:2] = replay_command;
    dlp[0][1:0] = seq_num_to_send[9:8];

    // 3. Construct DLP1
    dlp[1] = seq_num_to_send[7:0];

    // 4. Construct DLP2-DLP5
    dlp[2] = dllp_content[31:24];
    dlp[3] = dllp_content[23:16];
    dlp[4] = dllp_content[15:8];
    dlp[5] = dllp_content[7:0];

    // 5. Update DL Internal State
    if (is_payload) begin
      // [REPLAY] new payload flit : store it with ITS OWN sequence number
      store_tx_retry_buffer(tlp_data, NEXT_TX_FLIT_SEQ_NUM);
      nak_ignore_window_check_start(NEXT_TX_FLIT_SEQ_NUM);
      if (n_tx_new_payload == 0) first_tx_seq = NEXT_TX_FLIT_SEQ_NUM;          // [FLOW_SUM]
      last_tx_seq = NEXT_TX_FLIT_SEQ_NUM;
      n_tx_new_payload++;
      NEXT_TX_FLIT_SEQ_NUM = mod1023_add(NEXT_TX_FLIT_SEQ_NUM, 10'h1);
      `uvm_info("EP_DL_MODEL",$sformatf("NEXT_TX_FLIT_SEQ_NUM INSIDE THE DL INTERNAL STATE IS %d",NEXT_TX_FLIT_SEQ_NUM),UVM_LOW);
    end

   // clear ACK flag here (not while ACKs are held : the real ACK is still to be sent)
   if((replay_command == 2'b01) && !ack_hold) begin
	   ACK_SCHEDULED=1'b0;
   end

    last_flit_was_payload = is_payload;

    // 6. Assemble Output
    for (int i = 0; i < `PCIe_TLP_DATA_BYTE_W; i++) dl_flit_out[i] = tlp_data[i];
    for (int i = 0; i < `PCIe_DLP_BYTE_W; i++) dl_flit_out[`PCIe_TLP_DATA_BYTE_W+i] = dlp[i];

    `uvm_info("EP_DL_MODEL",$sformatf("replay_cmd = %d :: is_payload = %d :: dllp_sequence_number = %0h :: dlp = %p",replay_command,is_payload,{dlp[0][1:0],dlp[1]},dl_flit_out),UVM_LOW);
  endfunction

  // Discard the flit
  function void discard_flit(int discard_type);
    case (discard_type)
      0: `uvm_info("EP_DL_RX","FLIT_DISCARD_0 :: TLP dropped (duplicate / out of order / NOP), sequence kept",UVM_LOW)
      1: `uvm_info("EP_DL_RX","FLIT_DISCARD_1 :: bad flit dropped, a Standard NAK is already outstanding",UVM_LOW)
      2: begin
           NAK_WITHDRAWAL_ALLOWED = 1'b0;
           log_data_link_protocol_error();
           `uvm_info("EP_DL_RX","FLIT_DISCARD_2 :: protocol violation (explicit seq num 0 in a non-IDLE flit)",UVM_LOW)
         end
    endcase
  endfunction

  // Log the receiver error in register
  function void log_data_link_protocol_error();
    err_dl_protocol++;   // [DL_ERR]
    log_dl_error("DATA_LINK_PROTOCOL_ERROR", "bad ACK/NAK sequence number or protocol violation");
  endfunction

  // ---------------------------------------------------------------------------
  // NAK schedules (spec names : Nak Schedule 0 .. 6)
  // ---------------------------------------------------------------------------
  function void execute_nak_schedule(int id);
    case (id)
      // 0 : first bad flit -> drop it, the NEXT flit decides if a NAK is needed
      0: begin
        NAK_WITHDRAWAL_ALLOWED = 1'b1;
        `uvm_info("EP_DL_RX", $sformatf("NAK_SCHEDULE_0 :: bad flit dropped (expected SEQ_NUM=%0d) :: NAK withdrawal window open, next flit decides",
                  NEXT_EXPECTED_RX_FLIT_SEQ_NUM), UVM_NONE)
      end

      // 1 : second bad flit in a row -> Standard NAK
      1: begin
        NAK_WITHDRAWAL_ALLOWED = 1'b0;
        schedule_new_nak(STANDARD_NAK, "two bad flits in a row");
      end

      // 2 : lost / out-of-order flit -> Standard NAK
      2: begin
        NAK_WITHDRAWAL_ALLOWED = 1'b0;
        purge_rx_retry_buffer("Standard NAK scheduled");
        schedule_new_nak(STANDARD_NAK, $sformatf("bad sequence number (got %0d, expected %0d)",
                         IMPLICIT_RX_FLIT_SEQ_NUM, NEXT_EXPECTED_RX_FLIT_SEQ_NUM));
      end

      // 3 : good flit after the lost flit -> store it, Selective NAK (once)
      3: begin
        NAK_WITHDRAWAL_ALLOWED = 1'b0;
        if (!NAK_SCHEDULED)
          schedule_new_nak(SELECTIVE_NAK, $sformatf("flit SEQ_NUM=%0d lost, later flits are stored",
                           NEXT_EXPECTED_RX_FLIT_SEQ_NUM));
        store_flit_in_rx_retry_buffer();
      end

      // 4 : RX retry buffer is full
      4: begin
        NAK_WITHDRAWAL_ALLOWED = 1'b0;
        if (ALLOW_SELECTIVE_OVERFLOW) begin
          RX_RETRY_BUFFER_OVERFLOW = 1'b1;
          `uvm_info("EP_DL_RX", "NAK_SCHEDULE_4 :: RX retry buffer full, flit dropped, Selective NAK kept (overflow)", UVM_NONE)
        end
        else begin
          purge_rx_retry_buffer("RX retry buffer full");
          schedule_new_nak(STANDARD_NAK, "RX retry buffer full -> change Selective NAK to Standard NAK");
        end
      end

      // 5 : lost flit is back, but the buffer overflowed before
      //     -> use the lost flit + stored flits, Standard NAK for the dropped ones
      5: begin
        NAK_WITHDRAWAL_ALLOWED   = 1'b0;
        RX_RETRY_BUFFER_OVERFLOW = 1'b0;
        rx_flit_action           = RX_FLIT_ACCEPT;
        rx_release_stored_flits  = 1'b1;
        n_rx_replayed_accepted++;
        NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM, 10'h1);
        schedule_new_nak(STANDARD_NAK, "lost flit back, RX retry buffer had overflowed");
        RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = 10'h0;
      end

      // 6 : bad flit while a Selective NAK is outstanding -> Standard NAK
      6: begin
        NAK_WITHDRAWAL_ALLOWED   = 1'b0;
        RX_RETRY_BUFFER_OVERFLOW = 1'b0;
        purge_rx_retry_buffer("bad flit during Selective NAK");
        schedule_new_nak(STANDARD_NAK, "bad flit while a Selective NAK is outstanding");
      end
    endcase
  endfunction

  // ---------------------------------------------------------------------------
  // ACK schedules (spec names : Ack Schedule 0 .. 2). The flit is ACCEPTED.
  // ---------------------------------------------------------------------------
  function void execute_ack_schedule(int id);
    case (id)
      // 0 : normal, in-order flit
      0: begin
        TX_ACKNAK_FLIT_SEQ_NUM        = NEXT_EXPECTED_RX_FLIT_SEQ_NUM;
        NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1);
      end

      // 1 : lost flit is back (Standard NAK)
      1: begin
        NAK_SCHEDULED                 = 1'b0;
        TX_ACKNAK_FLIT_SEQ_NUM        = IMPLICIT_RX_FLIT_SEQ_NUM;
        NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(IMPLICIT_RX_FLIT_SEQ_NUM, 10'h1);
        n_rx_replayed_accepted++;
        `uvm_info("EP_DL_RX", $sformatf("REPLAYED_FLIT_RECEIVED :: SEQ_NUM=%0d accepted :: STANDARD_NAK cleared", IMPLICIT_RX_FLIT_SEQ_NUM), UVM_NONE)
      end

      // 2 : lost flit is back (Selective NAK) -> also release the stored flits
      2: begin
        NAK_SCHEDULED = 1'b0;
        n_rx_replayed_accepted++;
        if (rx_retry_buffer.size() == 0) begin
          TX_ACKNAK_FLIT_SEQ_NUM        = IMPLICIT_RX_FLIT_SEQ_NUM;
          NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(IMPLICIT_RX_FLIT_SEQ_NUM, 10'h1);
        end
        else begin
          TX_ACKNAK_FLIT_SEQ_NUM        = RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM;
          NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM, 10'h1);
          rx_release_stored_flits       = 1'b1;
        end
        RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = 10'h0;
        `uvm_info("EP_DL_RX", $sformatf("REPLAYED_FLIT_RECEIVED :: SEQ_NUM=%0d accepted :: SELECTIVE_NAK cleared :: %0d stored flit(s) released :: ACK SEQ_NUM=%0d",
                  IMPLICIT_RX_FLIT_SEQ_NUM, rx_retry_buffer.size(), TX_ACKNAK_FLIT_SEQ_NUM), UVM_NONE)
      end
    endcase
    rx_flit_action      = RX_FLIT_ACCEPT;
    nak_flit_tx_pending = 1'b0;
    ACK_SCHEDULED       = 1'b1;
  endfunction

  // ---------------------------------------------------------------------------
  // TX SIDE : ACK / NAK received from the RC for the flits the EP sent
  // ---------------------------------------------------------------------------
  function void process_received_ack_nak(bit [`PCIe_SEQ_NUM_W-1:0] N, bit [`PCIe_REPLAY_CMD_W-1:0] replay_cmd);
    bit guard_future;
    bit guard_past;
    bit is_ack;
    bit is_nak;

    is_ack = (replay_cmd == 2'b01);
    is_nak = (replay_cmd == 2'b10) || (replay_cmd == 2'b11);

    `uvm_info("EP_DL_MODEL",$sformatf("PROCESS_RECIEVED_ACK_NACK :: N = %d :: is_nak = %d :: is_ack = %d",N,is_nak,is_ack),UVM_LOW);

    if (N == 10'h0) return;   // ACK / NAK with sequence number 0 is ignored
    note_acknak_rcvd(N, replay_cmd);   // [FLOW_SUM] counts + [FLOW] line for a new NAK

    guard_future = (mod1023_sub(NEXT_TX_FLIT_SEQ_NUM - 10'h1,N) <= MAX_UNACKNOWLEDGED_FLITS);
    guard_past = (mod1023_sub(N,ACKD_FLIT_SEQ_NUM) <= MAX_UNACKNOWLEDGED_FLITS);

    if (!(guard_future && guard_past)) begin
      log_data_link_protocol_error();
      return;
    end

    purge_tx_retry_buffer(N);   // flit N and all older flits were received

    if (mod1023_sub(N,ACKD_FLIT_SEQ_NUM) > 0) begin
      FLIT_REPLAY_NUM = 3'h0;
      ACKD_FLIT_SEQ_NUM = N;
    end

    if (is_ack) begin
      NAK_IGNORE_FLIT_SEQ_NUM    = 10'h0;
      nak_ignore_window_start_ns = -1.0;
      if (mod1023_sub(N,TX_REPLAY_FLIT_SEQ_NUM) < MAX_UNACKNOWLEDGED_FLITS) begin
        TX_REPLAY_FLIT_SEQ_NUM = 10'h0;
      end
    end
    else if (is_nak) begin
      // NAK_IGNORE_FLIT_SEQ_NUM rules (spec 4.2.3.4.2.1.4), before the replay rules
      if (N == mod1023_sub(NEXT_TX_FLIT_SEQ_NUM,10'h1))
        NAK_IGNORE_FLIT_SEQ_NUM = N;
      else if (N != NAK_IGNORE_FLIT_SEQ_NUM)
        NAK_IGNORE_FLIT_SEQ_NUM = 10'h0;

      schedule_replay_on_nak(N, (replay_cmd == 2'b11));
    end
  endfunction

  // Modulo 1023 check: Is sequence S "older than or including" N?
  function automatic bit is_older_than_or_including(bit [`PCIe_SEQ_NUM_W-1:0] S, bit [`PCIe_SEQ_NUM_W-1:0] N);
    return (mod1023_sub(N,S) <= MAX_UNACKNOWLEDGED_FLITS);
  endfunction

  function void purge_tx_retry_buffer(bit [`PCIe_SEQ_NUM_W-1:0] N);
    while (tx_retry_buffer.size() > 0) begin
      if (is_older_than_or_including(tx_retry_buffer[0].seq_num, N)) begin
        `uvm_info("EP_DL_MODEL",$sformatf("TX_RETRY_BUFFER_PURGE :: SEQ_NUM=%0d acknowledged, removed",tx_retry_buffer[0].seq_num),UVM_LOW);
        void'(tx_retry_buffer.pop_front());
      end
      else break;
    end
  endfunction

  // ---------------------------------------------------------------------------
  // [REPLAY] Replay scheduling on a received NAK(N)  (spec 4.2.3.4.2.1.6)
  //   Rule 1 : flit N+1 is in the TX retry buffer and no replay is running
  //            -> schedule a Standard or Selective replay of flit N+1
  //   Rule 2 : Standard NAK after a Selective NAK, replay not started yet
  //            -> change the scheduled replay to a Standard replay
  //   A repeated NAK(N) inside the Nak Ignore Window is ignored.
  // ---------------------------------------------------------------------------
  function void schedule_replay_on_nak(bit [`PCIe_SEQ_NUM_W-1:0] N, bit is_selective_nak);
    bit [`PCIe_SEQ_NUM_W-1:0] lost_seq;
    bit lost_flit_in_buffer;

    lost_seq            = mod1023_add(N, 10'h1);
    lost_flit_in_buffer = 1'b0;
    foreach (tx_retry_buffer[i])
      if (tx_retry_buffer[i].seq_num == lost_seq) lost_flit_in_buffer = 1'b1;

    // Rule 2
    if (!is_selective_nak && REPLAY_SCHEDULED && !EP_REPLAY_IN_PROGRESS &&
        (REPLAY_SCHEDULED_TYPE == SELECTIVE_REPLAY) && (TX_REPLAY_FLIT_SEQ_NUM == lost_seq)) begin
      REPLAY_SCHEDULED_TYPE = STANDARD_REPLAY;
      `uvm_info("EP_REPLAY", $sformatf("REPLAY_UPGRADED :: Standard NAK(%0d) after Selective NAK -> STANDARD_REPLAY from SEQ_NUM=%0d", N, lost_seq), UVM_NONE)
      return;
    end

    // Rule 1
    if (!lost_flit_in_buffer) begin
      `uvm_info("EP_REPLAY", $sformatf("NAK(%0d) IGNORED :: flit SEQ_NUM=%0d is not in the TX retry buffer", N, lost_seq), UVM_LOW)
      return;
    end
    if (REPLAY_SCHEDULED || EP_REPLAY_IN_PROGRESS) begin
      `uvm_info("EP_REPLAY", $sformatf("NAK(%0d) IGNORED :: a replay is already scheduled / in progress", N), UVM_LOW)
      return;
    end
    if ((NAK_IGNORE_FLIT_SEQ_NUM == N) && nak_ignore_window_open()) begin
      `uvm_info("EP_REPLAY", $sformatf("NAK(%0d) IGNORED :: repeated NAK inside the Nak Ignore Window", N), UVM_LOW)
      if (acknak_rx_is_new) n_nak_ignored++;   // [FLOW_SUM]
      return;
    end

    REPLAY_SCHEDULED        = 1'b1;
    TX_REPLAY_FLIT_SEQ_NUM  = lost_seq;
    NAK_IGNORE_FLIT_SEQ_NUM = N;
    REPLAY_SCHEDULED_TYPE   = is_selective_nak ? SELECTIVE_REPLAY : STANDARD_REPLAY;
    if (is_selective_nak) n_sel_replay++;
    else                  n_std_replay++;
    `uvm_info("EP_REPLAY", $sformatf("REPLAY_SCHEDULED :: %s NAK(%0d) received -> %s starting at SEQ_NUM=%0d",
              is_selective_nak ? "SELECTIVE" : "STANDARD", N, REPLAY_SCHEDULED_TYPE.name(), lost_seq), UVM_NONE)
  endfunction

  // Storing the tx_retry_buffer
  function void store_tx_retry_buffer(
    input bit [`PCIe_TLP_DATA_BYTE_W-1:0][`PCIe_BYTE_W-1:0] tlp_data,
    input bit [`PCIe_SEQ_NUM_W-1:0] seq_num
  );
    tx_retry_buffer.push_back('{tlp_data:tlp_data,seq_num:seq_num});
    if (tx_retry_buffer.size() > max_tx_retry_used) max_tx_retry_used = tx_retry_buffer.size();   // [FLOW_SUM]
  endfunction

  function void update_implicit_rx_sequence_number(
    input bit [`PCIe_SEQ_NUM_W-1:0] N,
    input bit is_valid,
    input bit is_nop,
    input bit is_payload,
    input bit is_explicit,
    input bit is_idle,
    input bit prior_was_payload
  );

    // 1. Set to N Rule
    if (is_valid && !is_idle && is_explicit && (N != 10'h0)) begin
      IMPLICIT_RX_FLIT_SEQ_NUM = N;
      NON_IDLE_EXPLICIT_SEQ_NUM_FLIT_RCVD = 1'b1;
      `uvm_info("EP_DL_MODEL","IMPLICIT_NUMBER_ASSIGNED_TO_N",UVM_LOW);
    end

    // 2. No Change Rules
    else if (
      is_idle ||
      (is_explicit && (N == 10'h0)) ||
      (!NON_IDLE_EXPLICIT_SEQ_NUM_FLIT_RCVD && (!is_valid || !is_explicit)) ||
      (is_valid && is_nop && !is_explicit && (!NAK_WITHDRAWAL_ALLOWED || prior_was_payload)) ||
      (is_valid && is_payload && !is_explicit && (NAK_WITHDRAWAL_ALLOWED && !prior_was_payload))
    ) begin
      IMPLICIT_RX_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM;
      `uvm_info("EP_DL_MODEL","IMPLICIT_NUMBER_NO_CHANGE",UVM_LOW);
    end

    // 3. Increment Rules
    else if (
      (NON_IDLE_EXPLICIT_SEQ_NUM_FLIT_RCVD && !is_valid) ||
      (is_valid && is_payload && !is_explicit && (!NAK_WITHDRAWAL_ALLOWED || prior_was_payload))
    ) begin
      IMPLICIT_RX_FLIT_SEQ_NUM = mod1023_add(IMPLICIT_RX_FLIT_SEQ_NUM,10'h1);
      `uvm_info("EP_DL_MODEL","IMPLICIT_NUMBER_INCREMENTED",UVM_LOW);
    end

    // 4. Decrement Rules
    else if (
      is_valid &&
      is_nop &&
      !is_explicit &&
      NAK_WITHDRAWAL_ALLOWED &&
      !prior_was_payload
    ) begin
      IMPLICIT_RX_FLIT_SEQ_NUM = mod1023_sub(IMPLICIT_RX_FLIT_SEQ_NUM,10'h1);
      `uvm_info("EP_DL_MODEL","IMPLICIT_NUMBER_DECREMENTED",UVM_LOW);
    end
  endfunction

  // DL model consumes TL output, creates the DLP, then publishes to PL.
  function void write(PCIe_sequence_item item);
    `uvm_info("EP_DL_MODEL",$sformatf("DL -> PL: item from driver = %p",item.tlp_data),UVM_LOW)
    form_dl_packet(item.tlp_data,item.is_payload,item.dlp_flit_out);

    // [DL_ASSERT] used by DL_TLP_ONLY_IN_ACTIVE_CHECK (TLP flit only in DL_ACTIVE)
    if (dl_aif != null && item.is_payload) begin
      dl_aif.tx_payload_dl_state = DL_STATE;
      dl_aif.tx_payload_cnt++;
    end
    flit_cnt_count(1'b1, item.dlp_flit_out);   // [FLIT_CNT] TX
    dl_ap.write(item);
  endfunction


  // =========================================================================
  // [MERGED] write_ep_mon_242b : EP Controller Monitor -> EP DL Model
  // Called by the EP controller monitor once per RC->EP flit. Receives the
  // 242B flit (256B minus 8B CRC and 6B FEC) and its is_valid status.
  //   Monitor convention : is_valid = 0 -> FEC/CRC match    (good flit)
  //                        is_valid = 1 -> FEC/CRC mismatch (bad flit)
  //   handle_incoming_flit() convention is the opposite (1 = good, 0 = NAK),
  //   so the flag is inverted before the flit is handed to the RX path.
  // The flit is (1) collected in ep_rx_242b_flit_q / ep_rx_flit_is_valid_q
  // and (2) its DLP bytes are passed to handle_incoming_flit().
  // =========================================================================
 function void write_ep_mon_242b(PCIe_sequence_item item);

    string flit_242b_str;

    bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] received_dlp;
    bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] received_tlp;
    bit rx_flit_good;
    bit is_payload_flit;
    bit is_non_posted;
    bit [7:0] fmt_type;

    PCIe_sequence_item cov_item;   // [DL_COV] decoded DLP -> subscriber

    bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp_copy;
    bit good_copy;


    // ============================================================
    // 1. Collect the complete 242-byte Flit
    // ============================================================

    ep_rx_242b_flit_q.push_back(item.dlp_flit_out);
    ep_rx_flit_is_valid_q.push_back(item.is_valid);
    ep_rx_242b_flit_cnt++;
    flit_cnt_count(1'b0, item.dlp_flit_out, item.is_valid);   // [FLIT_CNT] RX

    flit_242b_str = "";

    for (int i = 0; i < `PCIe_DLP_FLIT_BYTE_W; i++)
        flit_242b_str =
            $sformatf("%s%0d ",
                      flit_242b_str,
                      item.dlp_flit_out[i]);

    `uvm_info("EP_DL_MODEL",
              $sformatf(
                "EP_DL_COLLECTED_242B_FLIT : FLIT_%0d is_valid=%0b total_collected=%0d = %s",
                ep_rx_242b_flit_cnt,
                item.is_valid,
                ep_rx_242b_flit_q.size(),
                flit_242b_str),
              UVM_LOW);


    // ============================================================
    // 2. Extract DLP = last 6 bytes
    // ============================================================

    for (int i = 0; i < `PCIe_DLP_BYTE_W; i++)
        received_dlp[i] =
            item.dlp_flit_out[`PCIe_TLP_DATA_BYTE_W + i];


    // ============================================================
    // 3. Extract TLP = first 236 bytes
    // ============================================================

    for (int i = 0; i < `PCIe_TLP_DATA_BYTE_W; i++)
        received_tlp[i] =
            item.dlp_flit_out[i];


    // ============================================================
    // 4. is_valid convention
    //
    // The EP controller monitor drives (check_rc_to_ep_flit_fec_crc):
    //   is_valid = 1 --> FEC & CRC MATCH    (GOOD Flit)
    //   is_valid = 0 --> FEC / CRC MISMATCH (BAD Flit)
    // which is already the handle_incoming_flit() convention
    // (1 = GOOD, 0 = BAD), so NO inversion is needed.
    // ============================================================

    rx_flit_good = item.is_valid;


    `uvm_info("EP_DL_MODEL",
              $sformatf(
                "RX_FLIT_STATUS : monitor_is_valid=%0b -> rx_flit_good=%0b",
                item.is_valid,
                rx_flit_good),
              UVM_LOW);


    // ============================================================
    // [DL_COV] 4a. Decode the 6 DLP bytes and send to the subscriber
    //   Same style as TL : the model decodes, the subscriber only samples
    //   Sent for GOOD and BAD flits (coverage needs both)
    // ============================================================

    cov_item = PCIe_sequence_item::type_id::create("ep_dl_cov_item");
    cov_item.dl_flit_usage = received_dlp[0][7:6];                 // 00 = NOP/idle, 01 = payload
    cov_item.dl_prior_pay  = received_dlp[0][5];                   // prior flit was payload
    cov_item.dl_replay_cmd = received_dlp[0][3:2];                 // replay command
    cov_item.dl_seq_num    = {received_dlp[0][1:0], received_dlp[1]};  // 10-bit sequence number
    cov_item.dl_dllp_type  = received_dlp[2];                      // first DLLP byte
    // [DL_COV] DLP0[4] + DLP2..DLP5 : 32-bit DLLP decoded with the FC helpers
    cov_item.dl_dllp_pay_type = received_dlp[0][4];                // 0 = DLLP, 1 = Opt_Update_FC / Flit_Marker
    cov_item.dl_is_fc         = PCIe_sequence_item::fc_is_dllp(
                                  {received_dlp[2], received_dlp[3], received_dlp[4], received_dlp[5]});
    PCIe_sequence_item::fc_decode({received_dlp[2], received_dlp[3], received_dlp[4], received_dlp[5]},
                                  cov_item.dl_fc_type,   cov_item.dl_fc_cls,
                                  cov_item.dl_fc_shared, cov_item.dl_fc_vc,
                                  cov_item.dl_fc_hscale, cov_item.dl_fc_hdr,
                                  cov_item.dl_fc_dscale, cov_item.dl_fc_data);
    cov_item.is_valid      = rx_flit_good;                         // 1 = good, 0 = bad flit
    cov_item.pkt_mode      = dl_rx_pkt_mode;
    ep_dl_cov_ap.write(cov_item);


    // ============================================================
    // 5. Send DLP to DL processing
    //
    // This must happen even for a BAD Flit because DL needs
    // to process sequence number / ACK / NAK information.
    // ============================================================

    is_payload_flit = (received_dlp[0][7:6] == 2'b01);

    rx_flit_tlp = received_tlp;      // [SEL_NAK] TLP bytes, used if the flit is stored
    dlp_copy    = received_dlp;
    good_copy   = rx_flit_good;
    handle_incoming_flit(dlp_copy, good_copy);


    // ============================================================
    // 6. [SEL_NAK] Use the DL decision for the TLP
    //
    //   RX_FLIT_ACCEPT : in order -> TLP to the TL now.
    //                    If it was the replayed (lost) flit, the
    //                    flits stored in the RX retry buffer go to
    //                    the TL right after it, in sequence order.
    //   RX_FLIT_STORE  : kept in the RX retry buffer (Selective NAK)
    //   RX_FLIT_DROP   : bad / duplicate / out of order / NOP flit
    // ============================================================

    case (rx_flit_action)

      RX_FLIT_ACCEPT: begin
        if (is_payload_flit) begin
          send_tlp_to_tl(received_tlp, IMPLICIT_RX_FLIT_SEQ_NUM,
                         rx_release_stored_flits ? "REPLAYED (lost) FLIT" : "IN-ORDER FLIT");

          // Non-posted request : send the ACK right away
          fmt_type = (received_tlp[0] == `PCIe_FLITTYPE_PREFIX) ? received_tlp[4] : received_tlp[0];
          case (fmt_type)
            8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h20, 8'h21: is_non_posted = 1'b1;
            default: is_non_posted = 1'b0;
          endcase
          if (is_non_posted && ACK_SCHEDULED && !ack_hold && !rx_release_stored_flits)
            send_dl_control_flit();
        end
        if (rx_release_stored_flits)
          release_stored_flits_to_tl();
      end

      RX_FLIT_STORE: begin
        `uvm_info("EP_DL_TL", $sformatf("TLP NOT sent to TL yet :: SEQ_NUM=%0d is in the RX retry buffer (Selective NAK)",
                  IMPLICIT_RX_FLIT_SEQ_NUM), UVM_LOW)
      end

      default: begin
        `uvm_info("EP_DL_TL", $sformatf("TLP NOT sent to TL :: good=%0b payload=%0b (dropped by DL rules)",
                  rx_flit_good, is_payload_flit), UVM_LOW)
      end

    endcase


/*// Send data to TL only when:
// 1. Flit is good
// 2. Flit is a Payload Flit
if (rx_flit_good && is_payload_flit) begin

    string dump;
    string line;

    tl_item = PCIe_sequence_item::type_id::create("ep_dl_to_tl_item");

    // 236B TLP region -> tlp_data (the only field the EP TL model reads)
    foreach (received_tlp[i])
        tl_item.tlp_data[i] = received_tlp[i];

    // [FIX] Same side-band fields the monitor used to set.
    tl_item.pkt_mode   = dl_rx_pkt_mode;
    tl_item.is_payload = 1'b1;
    tl_item.drive_flit = (dl_rx_pkt_mode == FLIT);

    // 236B dump of exactly what is handed to the EP TL model
    dump = "\n";
    line = "";
    for (int b = 0; b < `PCIe_TLP_DATA_BYTE_W; b++) begin
      if ((b % `PCIe_FLIT_DUMP_BPL) == 0)
        line = $sformatf("  [%3d] :", b);
      line = {line, $sformatf(" %02h", tl_item.tlp_data[b])};
      if (((b % `PCIe_FLIT_DUMP_BPL) == `PCIe_FLIT_DUMP_BPL-1) ||
          (b == `PCIe_TLP_DATA_BYTE_W-1))
        dump = {dump, line, "\n"};
    end

    `uvm_info("EP_DL_TL",
              $sformatf("GOOD PAYLOAD FLIT: 236B TLP sent to TL mode=%s DW0_BYTE0=0x%02h%s",
                        tl_item.pkt_mode.name(), tl_item.tlp_data[0], dump),
              UVM_LOW)

    ep_dl_tl_ap.write(tl_item);
end
else begin

    `uvm_info("EP_DL_TL",
              $sformatf("TLP NOT sent to TL: good=%0b payload=%0b",
                        rx_flit_good, is_payload_flit),
              UVM_LOW)
end*/
endfunction

  // [SEL_NAK] Sends one 236B TLP to the EP TL model (with a byte dump)
  function void send_tlp_to_tl(bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp,
                               bit [`PCIe_SEQ_NUM_W-1:0]                         seq_num,
                               string                                            tag);
    PCIe_sequence_item tl_item;
    string dump;
    string line;

    tl_item = PCIe_sequence_item::type_id::create("ep_dl_to_tl_item");
    foreach (tlp[i]) tl_item.tlp_data[i] = tlp[i];   // 236B TLP region (the only field the EP TL model reads)
    tl_item.pkt_mode   = dl_rx_pkt_mode;
    tl_item.is_payload = 1'b1;
    tl_item.drive_flit = (dl_rx_pkt_mode == FLIT);

    dump = "\n";
    line = "";
    for (int b = 0; b < `PCIe_TLP_DATA_BYTE_W; b++) begin
      if ((b % `PCIe_FLIT_DUMP_BPL) == 0)
        line = $sformatf("  [%3d] :", b);
      line = {line, $sformatf(" %02h", tl_item.tlp_data[b])};
      if (((b % `PCIe_FLIT_DUMP_BPL) == `PCIe_FLIT_DUMP_BPL-1) ||
          (b == `PCIe_TLP_DATA_BYTE_W-1))
        dump = {dump, line, "\n"};
    end

    `uvm_info("EP_DL_TL",
              $sformatf("GOOD PAYLOAD FLIT (%s) SEQ_NUM=%0d : 236B TLP sent to TL mode=%s DW0_BYTE0=0x%02h%s",
                        tag, seq_num, tl_item.pkt_mode.name(), tl_item.tlp_data[0], dump),
              UVM_LOW)
    if (n_rx_tlp_to_tl == 0) first_rx_seq = seq_num;                        // [FLOW_SUM]
    last_rx_seq = seq_num;
    n_rx_tlp_to_tl++;
    rx_accept_cnt[tlp_kind(tlp[0], tlp[4])]++;
    ep_dl_tl_ap.write(tl_item);
  endfunction

  // [SEL_NAK] After the replayed (lost) flit is accepted, the flits stored in
  // the RX retry buffer go to the TL, oldest first (sequence order).
  function void release_stored_flits_to_tl();
    `uvm_info("EP_DL_TL", $sformatf("RX_RETRY_BUFFER_RELEASE :: sending %0d stored flit(s) to TL in sequence order",
              rx_retry_buffer.size()), UVM_NONE)
    while (rx_retry_buffer.size() > 0) begin
      rx_retry_entry_t entry = rx_retry_buffer.pop_front();
      `uvm_info("EP_DL_TL", $sformatf("RX_RETRY_BUFFER_RELEASE :: SEQ_NUM=%0d -> TL", entry.seq_num), UVM_NONE)
      send_tlp_to_tl(entry.tlp_data, entry.seq_num, "STORED FLIT");
      n_rx_flits_released++;
    end
    rx_release_stored_flits = 1'b0;
  endfunction

  // =========================================================================
  // FLOW CONTROL  (PCIe Base 6.0 Sec 3.4 / Sec 2.6)  -  DEDICATED + SHARED credits, PER VC
  //
  //   [TC_VC] every FC value is kept per VC ([vc][class]) and every FC DLLP
  //   carries its VC ID (DLLP payload bits [26:24]).
  //   Like the Gen3 bench (rc/ep_send_initfc1_dllps loop "for vc < NUM_VC"),
  //   one InitFC1 / InitFC2 round of the DLCMSM sends the six Flit Mode DLLPs
  //   (P / NP / Cpl dedicated, then P / NP / Cpl shared, Sec 3.4.1 order) of
  //   VC0, then of VC1 ... of every ENABLED VC. FI1 is Set once all six values
  //   of every enabled VC are recorded, FI2 once an InitFC2 / UpdateFC was seen
  //   for every enabled VC. With one VC (default) it is exactly the old VC0 flow.
  //   TL -> DL : write_fc_from_tl()  local credits  PH PD NPH NPD CPLH CPLD of it.fc_vc
  //                                  dedicated AND shared (printed as the TL sent them)
  //   DL -> PL : InitFC1 / InitFC2 rounds during DL_INIT, UpdateFC DLLPs during DL_ACTIVE
  //   PL -> DL : fc_rx_flit()        peer InitFC / UpdateFC  ==> CREDIT_LIMIT of
  //                                  the DLLP's VC, handed to the TL through fc_tl_ap
  //   DLLP layout / encode / decode helpers are static functions of PCIe_sequence_item
  //   index : vc 0..7, class 0 = P, 1 = NP, 2 = CPL
  // =========================================================================
  function bit fc_multi_vc();
    return (PCIe_sequence_item::num_vc > 1);
  endfunction

  function bit fc_vc_on(int unsigned v);
    return PCIe_sequence_item::vc_enabled(v);
  endfunction

  function void fc_dl_init();
    for (int v = 0; v < FC_NVC; v++) begin
      for (int c = 0; c < 3; c++) begin
        adv_h[v][c] = 0; adv_d[v][c] = 0;
        peer_h[v][c] = 0; peer_d[v][c] = 0; peer_hinf[v][c] = 0; peer_dinf[v][c] = 0;
        fi1_ded[v][c] = 0; fi1_shr[v][c] = 0; peer_init_fwd[v][c] = 0;
        adv_h_shr[v][c] = 0; adv_d_shr[v][c] = 0;                                           // [FC SHARED]
        peer_h_shr[v][c] = 0; peer_d_shr[v][c] = 0; peer_hinf_shr[v][c] = 0; peer_dinf_shr[v][c] = 0;
        peer_init_fwd_shr[v][c] = 0;
      end
      fi2[v] = 0; adv_valid[v] = 0; pend_mask[v] = 3'b000; pend_mask_shr[v] = 3'b000;
    end
    n_initfc1_tx = 0; n_initfc1_rx = 0; n_initfc2_tx = 0; n_initfc2_rx = 0; n_updfc_tx = 0; n_updfc_rx = 0;
    n_updfc_tx_shr = 0; n_updfc_rx_shr = 0; n_fc_dllp_dis_vc = 0;
  endfunction

  // link (re)training : restart only the handshake flags, keep local values
  function void fc_restart_init();
    for (int v = 0; v < FC_NVC; v++) begin
      for (int c = 0; c < 3; c++) begin fi1_ded[v][c] = 0; fi1_shr[v][c] = 0; peer_init_fwd[v][c] = 0; peer_init_fwd_shr[v][c] = 0; end
      fi2[v] = 0;
      pend_mask[v] = 3'b000; pend_mask_shr[v] = 3'b000;
    end
  endfunction

  // Flit Mode : FI1 of VCx is Set once all SIX FC unit values were recorded (Sec 3.4.1)
  function bit fi1_vc_done(int unsigned v);
    return fi1_ded[v][0] && fi1_ded[v][1] && fi1_ded[v][2] && fi1_shr[v][0] && fi1_shr[v][1] && fi1_shr[v][2];
  endfunction
  // [TC_VC] DLCMSM : FI1 / FI2 of EVERY enabled VC
  function bit fi1_done();
    for (int v = 0; v < FC_NVC; v++) if (fc_vc_on(v) && !fi1_vc_done(v)) return 1'b0;
    return 1'b1;
  endfunction
  // FI2 is Set on ANY InitFC2 or UpdateFC of VCx (or, for VC0, any TLP)
  function bit fi2_done();
    for (int v = 0; v < FC_NVC; v++) if (fc_vc_on(v) && !fi2[v]) return 1'b0;
    return 1'b1;
  endfunction

  function void write_fc_from_tl(PCIe_sequence_item it);
    int unsigned v;
    v = it.fc_vc;
    `uvm_info("EP_DL_FC", $sformatf("[FC_TL->DL] %s VC%0d :: DL_EXTRACTED %s  (from %s, reason=%s)",
              it.fc_kind.name(), v, it.fc_values_str(), it.fc_origin, it.fc_reason), UVM_LOW)
    if (it.fc_kind == FC_ADV_INIT || it.fc_kind == FC_ADV_UPDATE) begin
      for (int c = 0; c < 3; c++)
        begin
          if (it.fc_cls_mask[c]) begin
            adv_h[v][c] = it.fc_hdr[c];
            adv_d[v][c] = it.fc_dat[c];
            adv_valid[v] = 1'b1;
          end
          if (it.fc_cls_mask_shr[c]) begin                       // [FC SHARED]
            adv_h_shr[v][c] = it.fc_hdr_shr[c];
            adv_d_shr[v][c] = it.fc_dat_shr[c];
          end
          // [FC SHARED] each value must fit its DLLP field (HdrFC 8 bit, DataFC 12 bit)
          if (adv_h[v][c] >= 256 || adv_d[v][c] >= 4096 || adv_h_shr[v][c] >= 256 || adv_d_shr[v][c] >= 4096)
            `uvm_error("EP_DL_FC", $sformatf("ADVERTISED_CREDITS_DO_NOT_FIT_DLLP_FIELD VC%0d class %0d : ded %0d/%0d shr %0d/%0d",
                       v, c, adv_h[v][c], adv_d[v][c], adv_h_shr[v][c], adv_d_shr[v][c]))
        end
      if (it.fc_kind == FC_ADV_UPDATE) begin
        pend_mask[v]     |= it.fc_cls_mask;
        pend_mask_shr[v] |= it.fc_cls_mask_shr;                  // [FC SHARED]
      end
    end
  endfunction

  // dedicated FC DLLP of VC v / class c carrying the credits the TL advertised
  function bit [31:0] fc_build_dedicated(bit [1:0] typ, int unsigned c, int unsigned v);
    return PCIe_sequence_item::fc_encode(typ, c[1:0], 1'b0, v[2:0],
                                         `PCIe_FC_SCALE_1X, adv_h[v][c][7:0],
                                         `PCIe_FC_SCALE_1X, adv_d[v][c][11:0]);
  endfunction

  // [FC SHARED] shared FC DLLP of VC v / class c carrying the shared credits the TL advertised
  function bit [31:0] fc_build_shared(bit [1:0] typ, int unsigned c, int unsigned v);
    return PCIe_sequence_item::fc_encode(typ, c[1:0], 1'b1, v[2:0],
                                         `PCIe_FC_SCALE_1X, adv_h_shr[v][c][7:0],
                                         `PCIe_FC_SCALE_1X, adv_d_shr[v][c][11:0]);
  endfunction

  // EP : the PL model queues every flit (ep_tx_flit_q) and the EP controller
  // driver drains it whenever the link is up, so no driver handshake is needed.
  task fc_send_active(bit [31:0] content);
    PCIe_sequence_item fc_item_pkt;
    fc_item_pkt = PCIe_sequence_item::type_id::create("fc_dllp_item");
    dllp_content = content;
    form_dl_packet(fc_item_pkt.tlp_data, 1'b0, fc_item_pkt.dlp_flit_out);   // is_payload=0
    dllp_content = '0;          // belongs to this flit only
    flit_cnt_count(1'b1, fc_item_pkt.dlp_flit_out);   // [FLIT_CNT] TX
    dl_ap.write(fc_item_pkt);
    `uvm_info("EP_DL_FC", $sformatf("[FC_DL_TX] DLLP flit handed to PL : %08h", content), UVM_LOW)
  endtask

  // One complete InitFC round. Flit Mode, for every enabled VC (VC0 first) :
  //   P / NP / Cpl dedicated, then P / NP / Cpl shared.
  task fc_send_init_round(bit [1:0] typ);
    bit [31:0] q[$];
    string nm;
    nm = PCIe_sequence_item::fc_type_name(typ);
    for (int v = 0; v < FC_NVC; v++) begin
      if (!fc_vc_on(v)) continue;
      if (!adv_valid[v])
        `uvm_warning("EP_DL_FC", $sformatf("InitFC round of VC%0d started before the TL advertised its credits", v))
      q.delete();
      for (int c = 0; c < 3; c++) q.push_back(fc_build_dedicated(typ, c, v));
      for (int c = 0; c < 3; c++) q.push_back(fc_build_shared(typ, c, v));     // [FC SHARED]
      `uvm_info("EP_DL_FC", $sformatf("[FC_DL_TX] %s ROUND VC%0d :: advertising  DED: PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d  SHR: PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d",
                nm, v, adv_h[v][0], adv_d[v][0], adv_h[v][1], adv_d[v][1], adv_h[v][2], adv_d[v][2],
                adv_h_shr[v][0], adv_d_shr[v][0], adv_h_shr[v][1], adv_d_shr[v][1], adv_h_shr[v][2], adv_d_shr[v][2]), UVM_LOW)
      foreach (q[i]) begin
        `uvm_info("EP_DL_FC", $sformatf("[FC_DL_TX] %s VC%0d %0d/6 : %s", nm, v, i+1, PCIe_sequence_item::fc_dllp_str(q[i])), UVM_LOW)
        send_dllp_flit(q[i]);
        if (typ == `PCIe_FC_TYPE_INITFC1) n_initfc1_tx++; else n_initfc2_tx++;
      end
    end
  endtask

  // UpdateFC for every VC / class that is pending (dedicated and / or shared)
  //   [TC_VC] with more than one VC a batch can be long, so every DLLP waits for
  //   fc_tx_allowed : a DL flit can never land on top of a TLP flit.
  task fc_send_pending_updates();
    bit [31:0] v;
    for (int vc = 0; vc < FC_NVC; vc++) begin
      for (int c = 0; c < 3; c++) begin
        if (pend_mask[vc][c]) begin
          pend_mask[vc][c] = 1'b0;
          v = fc_build_dedicated(`PCIe_FC_TYPE_UPDATEFC, c, vc);
          `uvm_info("EP_DL_FC", $sformatf("[FC_DL_TX] UpdateFC VC%0d class %s : CREDITS_ALLOCATED %s=%0d %s=%0d :: %s",
                    vc, PCIe_sequence_item::fc_cls_name(c), PCIe_sequence_item::fc_hdr_name(c), adv_h[vc][c],
                    PCIe_sequence_item::fc_dat_name(c), adv_d[vc][c], PCIe_sequence_item::fc_dllp_str(v)), UVM_LOW)
          if (fc_multi_vc()) wait (fc_tx_allowed);
          fc_send_active(v);
          n_updfc_tx++;
        end
        // [OPT_UPDATE_FC] shared Posted credits go out as ONE Optimized_Update_FC
        //   (Shared PH + PD + NPH in DLP2..5) instead of an UpdateFC-SHARED DLLP
        if (USE_OPT_UPDATE_FC && (c == 0) && pend_mask_shr[vc][0]) begin
          pend_mask_shr[vc][0] = 1'b0;
          if (fc_multi_vc()) wait (fc_tx_allowed);
          fc_send_opt_update(vc);
        end
        if (pend_mask_shr[vc][c]) begin                            // [FC SHARED]
          pend_mask_shr[vc][c] = 1'b0;
          v = fc_build_shared(`PCIe_FC_TYPE_UPDATEFC, c, vc);
          `uvm_info("EP_DL_FC", $sformatf("[FC_DL_TX] UpdateFC-SHARED VC%0d class %s : SHARED CREDITS_ALLOCATED %s=%0d %s=%0d :: %s",
                    vc, PCIe_sequence_item::fc_cls_name(c), PCIe_sequence_item::fc_hdr_name(c), adv_h_shr[vc][c],
                    PCIe_sequence_item::fc_dat_name(c), adv_d_shr[vc][c], PCIe_sequence_item::fc_dllp_str(v)), UVM_LOW)
          if (fc_multi_vc()) wait (fc_tx_allowed);
          fc_send_active(v);
          n_updfc_tx_shr++;
        end
      end
    end
  endtask

  function bit fc_any_pending();
    for (int vc = 0; vc < FC_NVC; vc++)
      if (pend_mask[vc] != 3'b000 || pend_mask_shr[vc] != 3'b000) return 1'b1;
    return 1'b0;
  endfunction

  // Runs in parallel with the DLCMSM. When the TL scheduled an UpdateFC (or
  // DL_ACTIVE was just entered) it forms and sends the DLLP. The first UpdateFC
  // after DL_ACTIVE also satisfies the peer's FI2.
  task run_fc_update_loop();
    wait (dl_link_active);
    // [FC_OPT] the 6 UpdateFC at DL_ACTIVE are optional : PCIe_FC_SEND_INITIAL_UPDATEFC = 0 skips them
    for (int v = 0; v < FC_NVC; v++) if (fc_vc_on(v)) begin
      pend_mask[v]     = `PCIe_FC_SEND_INITIAL_UPDATEFC ? 3'b111 : 3'b000;
      pend_mask_shr[v] = `PCIe_FC_SEND_INITIAL_UPDATEFC ? 3'b111 : 3'b000;   // [FC SHARED]
    end
    `uvm_info("EP_DL_FC", "[FC_DL] DL_ACTIVE :: INITIAL UpdateFC (dedicated + shared) FOR P/NP/CPL (completes FC_INIT2 at the peer)", UVM_LOW)
    forever begin
      if (fc_any_pending() && fc_tx_allowed) fc_send_pending_updates();
      else #1ns;
    end
  endtask

  // Receive side : called for every received flit from handle_incoming_flit()
  function void fc_rx_flit(bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp, bit is_valid);
    bit [31:0]         v;
    bit [1:0]          typ, cls, hs, ds;
    bit                shared, hinf, dinf, fwd, upd;
    bit [2:0]          vc;
    bit [7:0]          hfc;
    bit [11:0]         dfc;
    int unsigned       c;
    PCIe_sequence_item it;
    if (!is_valid) return;
    // Spec 3.4.1 : any TLP received on the VC also sets FI2. The DL cannot see
    // the VC of a TLP; a TLP during FC init can only be VC0 traffic.
    if (dlp[0][7:6] == 2'b01) fi2[0] = 1'b1;
    v = {dlp[2], dlp[3], dlp[4], dlp[5]};
    if (!PCIe_sequence_item::fc_is_dllp(v)) return;
    PCIe_sequence_item::fc_decode(v, typ, cls, shared, vc, hs, hfc, ds, dfc);
    `uvm_info("EP_DL_FC", $sformatf("[FC_DL_RX] %s", PCIe_sequence_item::fc_dllp_str(v)), UVM_LOW)
    // [TC_VC] OLD : if (vc != `PCIe_FC_VC0) return;   // only VC0 exists
    if (!fc_vc_on(vc)) begin
      n_fc_dllp_dis_vc++;
      `uvm_info("EP_DL_FC", $sformatf("[FC_DL_RX] VC%0d is not enabled on this Port -> FC DLLP ignored", vc), UVM_LOW)
      return;
    end
    c    = cls;
    hinf = (hs == 2'b00) && (hfc == 0);
    dinf = (ds == 2'b00) && (dfc == 0);
    fwd  = 1'b0;
    upd  = 1'b0;
    case (typ)
      `PCIe_FC_TYPE_INITFC1,
      `PCIe_FC_TYPE_INITFC2: begin
        if (typ == `PCIe_FC_TYPE_INITFC1) n_initfc1_rx++; else n_initfc2_rx++;
        if (shared) begin                           // [FC SHARED]
          peer_h_shr[vc][c] = hfc; peer_hinf_shr[vc][c] = hinf;
          peer_d_shr[vc][c] = dfc; peer_dinf_shr[vc][c] = dinf;
          fi1_shr[vc][c] = 1'b1;
          fwd = 1'b1;
        end
        else begin
          peer_h[vc][c] = hfc; peer_hinf[vc][c] = hinf;
          peer_d[vc][c] = dfc; peer_dinf[vc][c] = dinf;
          fi1_ded[vc][c] = 1'b1;
          fwd = 1'b1;
        end
        if (typ == `PCIe_FC_TYPE_INITFC2) fi2[vc] = 1'b1;
      end
      `PCIe_FC_TYPE_UPDATEFC: begin
        if (shared) n_updfc_rx_shr++; else n_updfc_rx++;
        fi2[vc] = 1'b1;
        if (!shared) begin
          peer_h[vc][c] = hfc; peer_hinf[vc][c] = hinf;
          peer_d[vc][c] = dfc; peer_dinf[vc][c] = dinf;
        end
        else begin                                  // [FC SHARED]
          peer_h_shr[vc][c] = hfc; peer_hinf_shr[vc][c] = hinf;
          peer_d_shr[vc][c] = dfc; peer_dinf_shr[vc][c] = dinf;
        end
        fwd = 1'b1;
        upd = 1'b1;
      end
      default: ;
    endcase
    if (!fwd) return;
    if (!upd) begin
      if (shared) begin                                          // [FC SHARED]
        if (peer_init_fwd_shr[vc][c]) return;  // initial shared limit already applied
        peer_init_fwd_shr[vc][c] = 1'b1;
      end
      else begin
        if (peer_init_fwd[vc][c]) return;      // initial limit already applied
        peer_init_fwd[vc][c] = 1'b1;
      end
    end
    it = PCIe_sequence_item::type_id::create("fc_peer_item");
    it.fc_kind   = upd ? FC_PEER_UPDATE : FC_PEER_INIT;
    it.fc_vc     = vc;
    it.fc_origin = "EP_DL";
    it.fc_reason = PCIe_sequence_item::fc_type_name(typ);
    if (shared) begin                                            // [FC SHARED]
      it.set_fc_cls_shr(c, hfc, dfc);
      it.fc_hdr_inf_shr[c] = hinf;
      it.fc_dat_inf_shr[c] = dinf;
    end
    else begin
      it.set_fc_cls(c, hfc, dfc);
      it.fc_hdr_inf[c] = hinf;
      it.fc_dat_inf[c] = dinf;
    end
    `uvm_info("EP_DL_FC", $sformatf("[FC_DL->TL] %s VC%0d class %s : %s=%0d %s=%0d  (%s %s)",
              it.fc_kind.name(), vc, PCIe_sequence_item::fc_cls_name(c),
              PCIe_sequence_item::fc_hdr_name(c), hfc, PCIe_sequence_item::fc_dat_name(c), dfc,
              PCIe_sequence_item::fc_type_name(typ), shared ? "SHARED" : "DEDICATED"), UVM_LOW)
    fc_tl_ap.write(it);
  endfunction

  // [TC_VC] per-VC lines for the report (only when more than one VC is enabled)
  function string fc_vc_report_str();
    string s;
    s = "";
    if (!fc_multi_vc()) return s;
    for (int v = 0; v < FC_NVC; v++) begin
      if (!fc_vc_on(v)) continue;
      s = {s, $sformatf("\n  VC%0d : FI1=%0b FI2=%0b | local DED PH=%0d PD=%0d NPH=%0d NPD=%0d CPLH=%0d CPLD=%0d SHR PH=%0d PD=%0d NPH=%0d NPD=%0d CPLH=%0d CPLD=%0d | peer DED PH=%0d PD=%0d NPH=%0d NPD=%0d CPLH=%0d CPLD=%0d SHR PH=%0d PD=%0d NPH=%0d NPD=%0d CPLH=%0d CPLD=%0d",
          v, fi1_vc_done(v), fi2[v],
          adv_h[v][0], adv_d[v][0], adv_h[v][1], adv_d[v][1], adv_h[v][2], adv_d[v][2],
          adv_h_shr[v][0], adv_d_shr[v][0], adv_h_shr[v][1], adv_d_shr[v][1], adv_h_shr[v][2], adv_d_shr[v][2],
          peer_h[v][0], peer_d[v][0], peer_h[v][1], peer_d[v][1], peer_h[v][2], peer_d[v][2],
          peer_h_shr[v][0], peer_d_shr[v][0], peer_h_shr[v][1], peer_d_shr[v][1], peer_h_shr[v][2], peer_d_shr[v][2])};
    end
    s = {s, $sformatf("\n  FC DLLPs received for a VC that is not enabled : %0d", n_fc_dllp_dis_vc)};
    return s;
  endfunction


  // =========================================================================
  // [FLIT_CNT] FLIT SUMMARY
  //   TX : every flit this DL model hands to the PL model (counted at the
  //        analysis-port write, so only flits really sent are counted)
  //   RX : every flit received from the controller monitor (write_*_mon_242b)
  //   Type is decoded from the flit itself :
  //     payload flit (DLP0[7:6]=01)   -> TL flit, TLP type from byte 0
  //     DLLP in DLP2-5 (non zero)      -> Feature / InitFC1 / InitFC2 / UpdateFC
  //     no DLLP, replay_cmd 10/11      -> NAK flit
  //     no DLLP, replay_cmd 01         -> ACK flit
  //     no DLLP, replay_cmd 00         -> NOP / idle flit
  //   The summary is printed in report_phase.
  // =========================================================================
  function void flit_cnt_count(bit is_tx,
                               bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] f,
                               bit is_good  = 1'b1,
                               bit is_retx  = 1'b0);   // [FLOW_SUM] 1 : replayed flit
    bit [7:0]  dlp0;
    bit [1:0]  rcmd;
    bit [31:0] v;
    bit [7:0]  t;
    flit_cnt_e k;
    dlp0 = f[`PCIe_TLP_DATA_BYTE_W];
    rcmd = dlp0[3:2];
    v    = {f[`PCIe_TLP_DATA_BYTE_W+2], f[`PCIe_TLP_DATA_BYTE_W+3],
            f[`PCIe_TLP_DATA_BYTE_W+4], f[`PCIe_TLP_DATA_BYTE_W+5]};
    if (is_tx) flit_tx_total++; else flit_rx_total++;
    if (!is_good) begin
      flit_rx_bad++;
      return;
    end
    if (dlp0[7:6] == 2'b01) begin                    // payload flit -> TLP
      k = tlp_kind(f[0], f[4]);                      // [FLOW_SUM] same decode as before, now a function
    end
    else if (v != 32'h0) begin                       // DLLP flit
      if (dlp0[4]) k = FLTC_OPT_UPDATEFC;            // [OPT_UPDATE_FC] Optimized_Update_FC / Flit_Marker
      else if (PCIe_sequence_item::fc_is_dllp(v)) begin
        case (v[31:30])
          `PCIe_FC_TYPE_INITFC1 : k = FLTC_INITFC1;
          `PCIe_FC_TYPE_INITFC2 : k = FLTC_INITFC2;
          default               : k = FLTC_UPDATEFC;
        endcase
      end
      else if (v[31:24] == FEATURE_DLLP[31:24]) k = FLTC_FEATURE;
      else if (v[31:24] == 8'h31)                k = FLTC_NOP_DLLP;         // [FLOW_SUM] NOP DLLP
      else if (v[31:24] == 8'h28)                k = FLTC_LINK_MGMT_DLLP;   // [FLOW_SUM] Link Management DLLP
      else                                       k = FLTC_OTHER_DLLP;
    end
    else if (rcmd[1])          k = FLTC_NAK;         // 10 = standard NAK, 11 = selective NAK
    else if (rcmd == 2'b01)    k = FLTC_ACK;
    else                       k = FLTC_NOP;
    if (is_tx) flit_tx_cnt[k]++; else flit_rx_cnt[k]++;
    if (is_tx && !is_retx) flit_tx_new_cnt[k]++;     // [FLOW_SUM]
    if (rcmd[1] && (k != FLTC_NAK)) begin
      if (is_tx) flit_tx_nak_piggy++; else flit_rx_nak_piggy++;
    end
  endfunction

  function string flit_cnt_row(string name, string tx, string rx);
    return $sformatf("  %-26s %-22s %s\n", name, tx, rx);
  endfunction

  // Row name for each TLP type
  function string flit_tlp_name(flit_cnt_e k);
    case (k)
      FLTC_MWR   : return "MemWr TLP (TL)";
      FLTC_MRD   : return "MemRd TLP (TL)";
      FLTC_CFGRD : return "CfgRd TLP (TL)";
      FLTC_CFGWR : return "CfgWr TLP (TL)";
      FLTC_MSG   : return "Msg TLP (TL)";
      FLTC_MSGD  : return "MsgD TLP (TL)";
      default    : return "Other TLP (TL)";
    endcase
  endfunction

  // =========================================================================
  // [FLOW_SUM] helpers + EP FLIT SUMMARY text
  //   The summary is printed at the end of the test by flit_summary_report()
  //   (called from report_phase of this DL model) :
  //     1. FLIT COUNT   2. SEQUENCE NUMBERS   3. ACK / NAK   4. REPLAY
  //     5. COMPLETIONS (from the EP TL model)  6. DL ERRORS LOGGED
  // =========================================================================

  // TLP type of a payload flit : byte 0 of the TLP
  // (byte 4 when byte 0 is the Flit Mode prefix)
  function flit_cnt_e tlp_kind(bit [7:0] b0, bit [7:0] b4);
    bit [7:0] t;
    t = (b0 == `PCIe_FLITTYPE_PREFIX) ? b4 : b0;
    case (t)
      8'h40, 8'h60                      : return FLTC_MWR;
      8'h00, 8'h01, 8'h03, 8'h20, 8'h21 : return FLTC_MRD;
      8'h04, 8'h05                      : return FLTC_CFGRD;
      8'h44, 8'h45                      : return FLTC_CFGWR;
      8'h0A, 8'h0B                      : return FLTC_CPL;
      8'h4A, 8'h4B                      : return FLTC_CPLD;
      default : begin
        if      (t[7:3] == 5'b00110) return FLTC_MSG;
        else if (t[7:3] == 5'b01110) return FLTC_MSGD;
        else                         return FLTC_OTHER_TLP;
      end
    endcase
  endfunction

  // Credit value for the log : "INF" when the credit is infinite
  function string fc_val_str(int unsigned v, bit inf);
    if (inf) return "INF";
    return $sformatf("%0d", v);
  endfunction

  // ACK / NAK received from the RC. A flit repeats the same ACK/NAK until a new
  // one is scheduled, so only a NEW {command, seq num} is counted.
  function void note_acknak_rcvd(bit [`PCIe_SEQ_NUM_W-1:0] N, bit [`PCIe_REPLAY_CMD_W-1:0] cmd);
    int key;
    key = int'({cmd, N});
    acknak_rx_is_new = (key != last_rx_acknak_key);
    if (!acknak_rx_is_new) return;
    last_rx_acknak_key = key;
    if (cmd == 2'b01) n_ack_rcvd++;
    else if (cmd[1]) begin
      if (cmd == 2'b11) n_sel_nak_rcvd++;
      else              n_std_nak_rcvd++;
      nak_rcvd_lost_seq_q.push_back(mod1023_add(N, 10'h1));
      PCIe_flow_log::print("NAK", $sformatf("EP got %s NAK(%0d), lost seq %0d", (cmd == 2'b11) ? "SEL" : "STD", N, mod1023_add(N, 10'h1)));   // [FLOW]
    end
  endfunction

  // ACK put in a flit sent to the RC (only a NEW ack number is counted).
  // NAKs are counted where they are scheduled (schedule_new_nak).
  function void note_acknak_sent(bit [`PCIe_SEQ_NUM_W-1:0] N, bit [`PCIe_REPLAY_CMD_W-1:0] cmd);
    int key;
    if (cmd != 2'b01) return;              // only ACK here
    key = int'({cmd, N});
    if (key == last_tx_acknak_key) return;
    last_tx_acknak_key = key;
    n_ack_sent++;
  endfunction

  // "5, 11, 12" (at most 20 numbers) or "none"
  function string seq_list_str(bit [`PCIe_SEQ_NUM_W-1:0] q[$]);
    string s;
    s = "";
    if (q.size() == 0) return "none";
    foreach (q[i]) begin
      if (i == 20) begin
        s = {s, $sformatf(" ... (+%0d more)", q.size() - 20)};
        break;
      end
      if (i != 0) s = {s, ", "};
      s = {s, $sformatf("%0d", q[i])};
    end
    return s;
  endfunction

  // one "name : value" line of the summary
  function string sum_line(string name, string val);
    return $sformatf("  %-33s : %s\n", name, val);
  endfunction

  // one row of the flit count table for flit type k
  function string flit_cnt_row_k(string name, flit_cnt_e k);
    return flit_cnt_row(name, $sformatf("%0d", flit_tx_cnt[k]), $sformatf("%0d", flit_rx_cnt[k]));
  endfunction

  // RX payload flits that were good (bad flits are counted in flit_rx_bad)
  function int unsigned rx_good_payload_flits();
    int unsigned n;
    n = 0;
    for (int i = FLTC_MWR; i < FLTC_NUM; i++) n += flit_rx_cnt[i];
    return n;
  endfunction

  // Sections 1 .. 4 of the EP FLIT SUMMARY
  function string flit_summary_part1();
    string s, v;
    int unsigned dl_tx, dl_rx, tl_tx, tl_rx, rx_good;
    dl_tx = 0; dl_rx = 0; tl_tx = 0; tl_rx = 0;
    for (int i = 0; i < FLTC_NUM; i++) begin
      if (i < FLTC_MWR) begin dl_tx += flit_tx_cnt[i]; dl_rx += flit_rx_cnt[i]; end
      else              begin tl_tx += flit_tx_cnt[i]; tl_rx += flit_rx_cnt[i]; end
    end

    // ---------------- 1. FLIT COUNT ----------------
    s = {" 1. FLIT COUNT  (TX also counts replayed flits)\n",
         flit_cnt_row("Flit type", "Sent (TX)", "Received (RX)"),
         "  -------------------------------------------------------------------\n",
         flit_cnt_row_k("Feature (DL)",              FLTC_FEATURE),
         flit_cnt_row_k("InitFC1 (DL)",              FLTC_INITFC1),
         flit_cnt_row_k("InitFC2 (DL)",              FLTC_INITFC2),
         flit_cnt_row_k("UpdateFC (DL)",             FLTC_UPDATEFC),
         flit_cnt_row_k("Optimized_Update_FC (DL)",  FLTC_OPT_UPDATEFC),
         flit_cnt_row_k("NOP DLLP (DL)",             FLTC_NOP_DLLP),
         flit_cnt_row_k("Link Management DLLP (DL)", FLTC_LINK_MGMT_DLLP),
         flit_cnt_row_k("Other / unsupported DLLP",  FLTC_OTHER_DLLP)};
    if (flit_tx_cnt[FLTC_NOP] != 0 || flit_rx_cnt[FLTC_NOP] != 0)
      s = {s, flit_cnt_row_k("Idle flit (no DLLP)",  FLTC_NOP)};
    s = {s, flit_cnt_row_k("ACK (DL)", FLTC_ACK),
            flit_cnt_row_k("NAK (DL)", FLTC_NAK)};
    // one row for every TLP type seen (TX or RX); Completion / CplD always printed
    for (int i = FLTC_MWR; i < FLTC_NUM; i++) begin
      if (i == FLTC_CPL || i == FLTC_CPLD) continue;
      if (flit_tx_cnt[i] != 0 || flit_rx_cnt[i] != 0)
        s = {s, flit_cnt_row_k(flit_tlp_name(flit_cnt_e'(i)), flit_cnt_e'(i))};
    end
    s = {s, flit_cnt_row("Completion / CplD (TL)",
                         $sformatf("%0d", flit_tx_cnt[FLTC_CPL] + flit_tx_cnt[FLTC_CPLD]),
                         $sformatf("%0d", flit_rx_cnt[FLTC_CPL] + flit_rx_cnt[FLTC_CPLD])),
            "  -------------------------------------------------------------------\n",
            flit_cnt_row("Total", $sformatf("%0d (%0d DL + %0d TL)", flit_tx_total, dl_tx, tl_tx),
                                  $sformatf("%0d", flit_rx_total)),
            sum_line("Bad flits received (CRC/FEC fail)", $sformatf("%0d", flit_rx_bad)),
            "\n"};

    // ---------------- 2. SEQUENCE NUMBERS ----------------
    rx_good = rx_good_payload_flits();
    s = {s, " 2. SEQUENCE NUMBERS\n"};
    if (n_tx_new_payload == 0) v = "0";
    else v = $sformatf("%0d   (seq %0d -> %0d)", n_tx_new_payload, first_tx_seq, last_tx_seq);
    s = {s, sum_line("TX payload flits sent (new)", v)};
    if ((n_ack_rcvd + n_std_nak_rcvd + n_sel_nak_rcvd) == 0) v = "none yet";
    else v = $sformatf("seq %0d", ACKD_FLIT_SEQ_NUM);
    s = {s, sum_line("Last ACK received from RC", v)};
    if (n_rx_tlp_to_tl == 0) v = "0";
    else v = $sformatf("%0d   (seq %0d -> %0d, given to the EP TL)", n_rx_tlp_to_tl, first_rx_seq, last_rx_seq);
    s = {s, sum_line("RX payload flits accepted", v),
            sum_line("RX payload flits dropped", $sformatf("%0d   (good flits not given to the TL)",
                     (rx_good > n_rx_tlp_to_tl) ? (rx_good - n_rx_tlp_to_tl) : 0)),
            sum_line("  of which duplicates discarded", $sformatf("%0d", n_rx_dup_discarded)),
            sum_line("Out-of-order flits stored", $sformatf("%0d   (Selective NAK RX retry buffer)", n_rx_flits_stored)),
            sum_line("Stored flits released to TL", $sformatf("%0d", n_rx_flits_released))};
    if ((n_ack_sent + n_std_nak_scheduled + n_sel_nak_scheduled) == 0) v = "none yet";
    else v = $sformatf("seq %0d", TX_ACKNAK_FLIT_SEQ_NUM);
    s = {s, sum_line("Last ACK/NAK seq sent to RC", v), "\n"};

    // ---------------- 3. ACK / NAK ----------------
    s = {s, " 3. ACK / NAK  (a NEW ack/nak number is counted once)\n",
            "   Received from RC :\n",
            sum_line("ACK received", $sformatf("%0d", n_ack_rcvd)),
            sum_line("Standard NAK received", $sformatf("%0d", n_std_nak_rcvd)),
            sum_line("Selective NAK received", $sformatf("%0d", n_sel_nak_rcvd)),
            sum_line("Lost flits reported by these NAKs", seq_list_str(nak_rcvd_lost_seq_q)),
            sum_line("NAKs ignored (Nak Ignore Window)", $sformatf("%0d", n_nak_ignored)),
            "   Sent to RC :\n",
            sum_line("ACK sent", $sformatf("%0d", n_ack_sent)),
            sum_line("Standard NAK sent", $sformatf("%0d", n_std_nak_scheduled)),
            sum_line("Selective NAK sent", $sformatf("%0d", n_sel_nak_scheduled)),
            sum_line("Lost flits reported by these NAKs", seq_list_str(nak_sent_lost_seq_q)),
            sum_line("Replayed (lost) flits accepted", $sformatf("%0d", n_rx_replayed_accepted)),
            "\n"};

    // ---------------- 4. REPLAY ----------------
    s = {s, " 4. REPLAY (EP -> RC)\n",
            sum_line("Standard replays (after NAK)", $sformatf("%0d", n_std_replay)),
            sum_line("Selective replays (after NAK)", $sformatf("%0d", n_sel_replay)),
            sum_line("Replay timer timeouts", "not modelled on the EP"),
            sum_line("Replayed seq numbers", seq_list_str(replayed_seq_q)),
            sum_line("REPLAY_NUM now / rollovers", $sformatf("%0d / %0d", FLIT_REPLAY_NUM, err_replay_num_rollover)),
            sum_line("Retry buffer : max used", $sformatf("%0d flits  (limit %0d)", max_tx_retry_used, MAX_UNACKNOWLEDGED_FLITS)),
            sum_line("Retry buffer : at end", $sformatf("%0d flits", tx_retry_buffer.size())),
            "\n"};
    return s;
  endfunction

  // Section 6 of the EP FLIT SUMMARY
  function string flit_summary_errors();
    return {" 6. DL ERRORS LOGGED (Sec 6.2)\n",
            sum_line("Invalid flit (bad CRC/FEC)", $sformatf("%0d", err_invalid_flit)),
            sum_line("Replay timer timeout", $sformatf("%0d", err_replay_timer_timeout)),
            sum_line("REPLAY_NUM rollover", $sformatf("%0d", err_replay_num_rollover)),
            sum_line("DL protocol error", $sformatf("%0d", err_dl_protocol)),
            sum_line("Total DL errors", $sformatf("%0d", dl_error_total()))};
  endfunction

  // Section 5 of the EP FLIT SUMMARY : completions (numbers from the EP TL model)
  function string flit_summary_cpl(PCIe_EP_TL_model tl);
    int unsigned n_mrd, n_cfgrd, n_cfgwr;
    if (tl == null) return " 5. COMPLETIONS (EP side)\n  (EP TL model not found)\n\n";
    n_mrd   = rx_accept_cnt[FLTC_MRD];
    n_cfgrd = rx_accept_cnt[FLTC_CFGRD];
    n_cfgwr = rx_accept_cnt[FLTC_CFGWR];
    return {" 5. COMPLETIONS (EP side)\n",
            sum_line("Non-posted requests received", $sformatf("%0d   (MemRd %0d, CfgRd %0d, CfgWr %0d)",
                     n_mrd + n_cfgrd + n_cfgwr, n_mrd, n_cfgrd, n_cfgwr)),
            sum_line("Completions sent", $sformatf("%0d   (CplD %0d, Cpl %0d)",
                     tl.n_cpld_sent + tl.n_cpl_nodata_sent, tl.n_cpld_sent, tl.n_cpl_nodata_sent)),
            sum_line("Status  SC / UR / CA / CRS", $sformatf("%0d / %0d / %0d / %0d",
                     tl.n_cpl_status_sent[`PCIe_CPL_STATUS_SC], tl.n_cpl_status_sent[`PCIe_CPL_STATUS_UR],
                     tl.n_cpl_status_sent[`PCIe_CPL_STATUS_CA], tl.n_cpl_status_sent[`PCIe_CPL_STATUS_CRS])),
            sum_line("Split completions (CplD parts)", $sformatf("%0d   (%0d parts)",
                     tl.n_cpl_split_txn, tl.n_cpl_split_parts)),
            "\n"};
  endfunction

  // Prints the EP FLIT SUMMARY (called from report_phase).
  // The EP TL model is the sibling "ep_tl_model" in the same agent.
  function void flit_summary_report();
    PCIe_EP_TL_model tl;
    uvm_component    p;
    p = get_parent();
    if (p != null) void'($cast(tl, p.get_child("ep_tl_model")));
    `uvm_info("EP_FLIT_SUMMARY", {"\n==========================================================================\n",
                                  "                      EP FLIT SUMMARY  (end of test)\n",
                                  "==========================================================================\n",
                                  flit_summary_part1(),
                                  flit_summary_cpl(tl),
                                  flit_summary_errors(),
                                  "=========================================================================="}, UVM_NONE)
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("EP_DL_FC", $sformatf({"\n  ========== EP DL FLOW CONTROL SUMMARY ==========\n",
        "  local credits (from TL) dedicated : PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d\n",
        "  local credits (from TL) shared    : PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d\n",
        "  peer credits (from DLLP) dedicated: PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d\n",
        "  peer credits (from DLLP) shared   : PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d\n",
        "  InitFC1 tx/rx=%0d/%0d  InitFC2 tx/rx=%0d/%0d  UpdateFC tx/rx=%0d/%0d  UpdateFC-SHR tx/rx=%0d/%0d  FI1=%0b FI2=%0b (all enabled VCs)%s"},
        adv_h[0][0], adv_d[0][0], adv_h[0][1], adv_d[0][1], adv_h[0][2], adv_d[0][2],
        adv_h_shr[0][0], adv_d_shr[0][0], adv_h_shr[0][1], adv_d_shr[0][1], adv_h_shr[0][2], adv_d_shr[0][2],
        peer_h[0][0], peer_d[0][0], peer_h[0][1], peer_d[0][1], peer_h[0][2], peer_d[0][2],
        peer_h_shr[0][0], peer_d_shr[0][0], peer_h_shr[0][1], peer_d_shr[0][1], peer_h_shr[0][2], peer_d_shr[0][2],
        n_initfc1_tx, n_initfc1_rx, n_initfc2_tx, n_initfc2_rx, n_updfc_tx, n_updfc_rx,
        n_updfc_tx_shr, n_updfc_rx_shr,
        fi1_done(), fi2_done(), fc_vc_report_str()), UVM_LOW)
    flit_summary_report();   // [FLIT_CNT] [FLOW_SUM] EP FLIT SUMMARY (6 sections)

    // [SEL_NAK] [REPLAY] summary
    `uvm_info("EP_DL_NAK_REPLAY", $sformatf({"\n",
        "  ========== EP DL NAK / REPLAY SUMMARY ==========\n",
        "  RX (flits from RC)\n",
        "    Standard NAKs scheduled     : %0d\n",
        "    Selective NAKs scheduled    : %0d\n",
        "    Flits stored in RX buffer   : %0d\n",
        "    Stored flits sent to TL     : %0d\n",
        "    Lost flits received again   : %0d\n",
        "    RX retry buffer at end      : %0d (must be 0)\n",
        "  TX (flits to RC)\n",
        "    Standard replays            : %0d\n",
        "    Selective replays           : %0d\n",
        "    Replayed flit seq numbers   : %p\n",
        "  OTHER\n",
        "    Duplicate flits dropped     : %0d\n",
        "    Optimized_Update_FC sent    : %0d\n",
        "    DLLPs rx NOP/LinkMgmt/PM    : %0d / %0d / %0d\n",
        "    DLLPs rx Unsupported type   : %0d (discarded, not an error)\n",
        "  ERRORS LOGGED (Sec 6.2)\n",
        "    Invalid flit                : %0d\n",
        "    REPLAY_NUM Rollover         : %0d\n",
        "    Data Link Protocol Error    : %0d\n",
        "  ================================================"},
        n_std_nak_scheduled, n_sel_nak_scheduled, n_rx_flits_stored, n_rx_flits_released,
        n_rx_replayed_accepted, rx_retry_buffer.size(),
        n_std_replay, n_sel_replay, replayed_seq_q,
        n_rx_dup_discarded, n_opt_updfc_tx,
        n_rx_nop_dllp, n_rx_link_mgmt_dllp, n_rx_pm_dllp, n_rx_unsupported_dllp,
        err_invalid_flit, err_replay_num_rollover, err_dl_protocol), UVM_LOW)
  endfunction


endclass

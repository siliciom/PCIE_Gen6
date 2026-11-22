//=========================================================================================
// File         : PCIe_RC_DL_model.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_RC_controller_agent\PCIe_RC_DL_model.sv
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

import typedef_enums :: *;

// [ADDED] RC controller monitor -> RC DL : 242B EP->RC flit + is_valid
`uvm_analysis_imp_decl(_rc_mon_242b)
// FLOW CONTROL : TL -> DL local credits (suffix may be declared only once per package)
`uvm_analysis_imp_decl(_fc_from_tl)

class PCIe_RC_DL_model extends uvm_component;

  `uvm_component_utils(PCIe_RC_DL_model)

  // TL -> DL and DL -> PL TLM connections.
  uvm_analysis_imp #(PCIe_sequence_item,PCIe_RC_DL_model) tlp_dl_imp;
  uvm_analysis_port #(PCIe_sequence_item) dlp_pl_ap;

  // [ADDED] RC controller monitor -> RC DL : per EP->RC flit, 242B + is_valid
  uvm_analysis_imp_rc_mon_242b #(PCIe_sequence_item,PCIe_RC_DL_model) dl_mon_242b_imp;

  // [ADDED] RC DL -> RC TL : good 236B payload TLP
  uvm_analysis_port #(PCIe_sequence_item) rc_dl_tl_ap;

  // [DL_COV] RC DL -> Subscriber : decoded DLP fields of every received flit
  uvm_analysis_port #(PCIe_sequence_item) rc_dl_cov_ap;

  // [ADDED] RX flit collection, same structure as EP DL model
  pkt_mode_e dl_rx_pkt_mode = FLIT;
  bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] rc_rx_242b_flit_q[$];
  bit                                                rc_rx_flit_is_valid_q[$];
  int                                                rc_rx_242b_flit_cnt = 0;

  bit [`PCIe_DLLP_CONTENT_W-1:0] dllp_content;
  bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] dl_flit_out;
  bit success;
  bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] current_flit_data;
  bit received_explicit_seq;
  bit [`PCIe_REPLAY_CMD_W-1:0] replay_cmd;
  bit [`PCIe_SEQ_NUM_W-1:0] last_sent;

  tx_buffer_t tx_retry_buffer[$];

  // Retry buffers for retry logic at TX and RX side
  bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] rx_retry_buffer[$];

  // Usage in DL Model or Struct
  replay_scheduled_type_e REPLAY_SCHEDULED_TYPE;

  // Sequence numbers for handshake
  bit [`PCIe_SEQ_NUM_W-1:0] TX_ACKNAK_FLIT_SEQ_NUM = {`PCIe_SEQ_NUM_W{1'b1}};
  bit [`PCIe_SEQ_NUM_W-1:0] NEXT_TX_FLIT_SEQ_NUM = {{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1};
  bit [`PCIe_SEQ_NUM_W-1:0] NEXT_EXPECTED_RX_FLIT_SEQ_NUM = {{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1};
  bit [`PCIe_SEQ_NUM_W-1:0] IMPLICIT_RX_FLIT_SEQ_NUM = '0;
  bit [`PCIe_SEQ_NUM_W-1:0] ACKD_FLIT_SEQ_NUM = {`PCIe_SEQ_NUM_W{1'b1}};
  bit [`PCIe_SEQ_NUM_W-1:0] TX_REPLAY_FLIT_SEQ_NUM = '0;
  bit [`PCIe_SEQ_NUM_W-1:0] NAK_IGNORE_FLIT_SEQ_NUM = '0;
  bit NON_IDLE_EXPLICIT_SEQ_NUM_FLIT_RCVD;
  bit [`PCIe_FLIT_REPLAY_NUM_W-1:0] FLIT_REPLAY_NUM = '0;
  bit REPLAY_SCHEDULED;
  int unsigned MAX_UNACKNOWLEDGED_FLITS = `PCIe_MAX_UNACK_FLITS;

  bit [`PCIe_SEQ_NUM_W-1:0] RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM;
  bit [`PCIe_SEQ_NUM_W-1:0] NEXT_RX_FLIT_SEQ_NUM_TO_STORE;
  bit RX_RETRY_BUFFER_OVERFLOW;
  bit ALLOW_SELECTIVE_OVERFLOW;
  bit USE_STANDARD_NAK_ONLY = 1'b0;

  // Protocol Violation Flags
  bit received_explicit_seq_0;

  // Replay scheduling
  bit NAK_SCHEDULED;
  bit ACK_SCHEDULED;
  bit NAK_SCHEDULED_TYPE;
  bit STANDARD_NAK;
  bit NAK_WITHDRAWAL_ALLOWED;
  bit RC_REPLAY_IN_PROGRESS;

  // Payload related information
  bit last_flit_was_payload;

  // Credit related information
  bit credit;
  bit form_dlp_flit;

  // DLLP content encodings (FEATURE; InitFC/UpdateFC are built by the FC functions below)
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
  int unsigned flit_tx_new_cnt [FLTC_NUM];           // [FLOW_SUM] TX flits WITHOUT replays / duplicates
  int unsigned rx_accept_cnt   [FLTC_NUM];           // [FLOW_SUM] RX TLPs given to the TL, per TLP type

  // [FLOW_SUM] numbers for the end-of-test RC FLIT SUMMARY (flit_summary_report)
  int unsigned              n_tx_new_payload;        // NEW payload flits sent (replays not counted)
  bit [`PCIe_SEQ_NUM_W-1:0] first_tx_seq, last_tx_seq;
  int unsigned              n_rx_tlp_to_tl;          // RX payload flits accepted and given to the RC TL
  int unsigned              max_tx_retry_used;       // biggest TX retry buffer size seen
  int unsigned              n_ack_rcvd, n_std_nak_rcvd, n_sel_nak_rcvd, n_nak_ignored;
  bit [`PCIe_SEQ_NUM_W-1:0] nak_rcvd_lost_seq_q[$];  // lost flit (N+1) of every NAK(N) received
  int unsigned              n_ack_sent, n_std_nak_sent, n_sel_nak_sent;
  bit [`PCIe_SEQ_NUM_W-1:0] nak_sent_lost_seq_q[$];  // lost flit (N+1) of every NAK(N) sent
  int                       last_rx_acknak_key = -1; // {cmd, seq} of the last ACK/NAK received
  int                       last_tx_acknak_key = -1; // {cmd, seq} of the last ACK/NAK sent
  bit                       acknak_rx_is_new;        // 1 : the ACK/NAK just received is a NEW one

  // Declared here (before their first use) : Questa needs a class variable
  // to be declared before the first line that uses it.
  int unsigned n_tx_flits_dropped_on_reset;            // [DL_RESET] unACKed flits thrown away by the last reset
  int unsigned REPLAY_TIMEOUT_FLIT_COUNT;              // [REPLAY_TIMER] spec counter : 11 bit, saturates at 7FFh
  int unsigned REPLAY_TIMEOUT_LIMIT = 1500;            // [REPLAY_TIMER] spec value (test may lower it)
  int unsigned n_replay_timeouts;                      // [REPLAY_TIMER] Replay Timer Timeout errors logged
  tx_buffer_t  last_tx_payload_flit;                   // [DUP_FLIT] last NEW payload flit sent
  bit          last_tx_payload_valid;                  // [DUP_FLIT]
  bit          duplicate_flit_request;                 // [DUP_FLIT] test sets it : send the last flit again
  int unsigned n_duplicate_flits_sent;                 // [DUP_FLIT]

   // localparam bit [31:0] INITFC1_DLLP = 32'h0200_0000;
    //localparam bit [31:0] INITFC2_DLLP = 32'h0300_0000;
        // ---- DLCMSM additions ----
    dl_state_e          DL_STATE = DL_INACTIVE;
    // [DL_ASSERT] DL state machine assertions live inside PCIe_RC_interface (PCIe_top/PCIe_PIPE_interface.sv)
    virtual PCIe_RC_interface dl_aif;
    dl_init_substate_e  dl_init_substate;
    uvm_event           uvm_rc_l0_to_dl_ev;   // fired by PL model when LTSSM reaches L0
    int                 fc1_sent_count, fc1_rcvd_count;
    int                 fc2_sent_count, fc2_rcvd_count;
    bit                 phy_linkup;          

    // ---- DLCMSM FSM additions (dependency-driven, mirrors LTSSM style) ----
    // NOTE: these are NOT hardcoded magic numbers scattered in a while() loop -
    // they are named, single-source-of-truth completion targets that every
    // debug print below references, exactly like `PCIe_TS1_RX_COUNT`/`PCIe_TS2_RX_COUNT`
    // are used in the LTSSM (rc_check_ep_ts1/ts2).
    localparam int NUM_INITFC1_DLLP = 4;   // FC_INIT1 is "done" once this many INITFC1 DLLPs sent
    localparam int NUM_INITFC2_DLLP = 4;   // FC_INIT2 is "done" once this many INITFC2 DLLPs sent
    uvm_event dl_active_event;                  // fires once, the instant DL_ACTIVE is entered
    bit   dl_link_active;                   // stays 1 while in DL_ACTIVE - TL/driver can gate on this
    // Driver handshake for DLCMSM packets:
    //   DL model sets it to 1 when it hands a DLLP flit to the PL model.
    //   RC controller driver clears it to 0 once that flit is on the PIPE.
    // DLCMSM waits for it to clear, so every DLLP flit is really transmitted
    // (in order) before the next DLCMSM state runs.
    bit   dllp_tx_pending;
    // [DLLP_LOCK] only ONE DLLP flit at a time in the RC PL model : the DLCMSM,
    // the UpdateFC loop and a test (DLLP injection) all use send_dllp_flit()
    semaphore dllp_tx_lock;
    // --------------------------------------------------------------------

    // ---- FLOW CONTROL (dedicated + shared credits, PER VC) ------------------
    //   [TC_VC] OLD : VC0 only, every array was [class].
    //   [TC_VC] NEW : [vc][class]. Like the Gen3 bench, every ENABLED VC is
    //   initialised in DL_Init : each InitFC1 / InitFC2 round carries the six
    //   DLLPs (P/NP/Cpl dedicated + shared) of VC0, then VC1, ... and FI1 / FI2
    //   are Set once all enabled VCs have them. Every FC DLLP carries its VC ID.
    uvm_analysis_imp_fc_from_tl #(PCIe_sequence_item, PCIe_RC_DL_model) fc_tl_imp;  // TL -> DL : local credits
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
    bit          fc_tx_allowed = 1'b0;   // gate for DL-initiated DLLPs after DL_ACTIVE
    int unsigned n_initfc1_tx, n_initfc1_rx, n_initfc2_tx, n_initfc2_rx, n_updfc_tx, n_updfc_rx;
    int unsigned n_fc_dllp_dis_vc;         // [TC_VC] FC DLLPs received for a VC that is not enabled

  function new(string name="PCIe_RC_DL_model",uvm_component parent);
    super.new(name,parent);
  endfunction


function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    tlp_dl_imp = new("tlp_dl_imp",this);
    dlp_pl_ap = new("dlp_pl_ap",this);
    dl_mon_242b_imp = new("dl_mon_242b_imp",this);
    rc_dl_tl_ap = new("rc_dl_tl_ap",this);
    rc_dl_cov_ap = new("rc_dl_cov_ap",this);   // [DL_COV]
    dl_active_event = uvm_event_pool::get_global("dl_active_event");
    uvm_rc_l0_to_dl_ev = uvm_event_pool::get_global("rc_l0_to_dl_event");
    fc_tl_imp = new("fc_tl_imp", this);
    fc_tl_ap  = new("fc_tl_ap",  this);
    dllp_tx_lock = new(1);   // [DLLP_LOCK]
    fc_dl_init();

    void'(uvm_config_db#(pkt_mode_e)::get(this, "", "link_mode", dl_rx_pkt_mode));
    // [DL_ASSERT] PIPE interface also holds the DL assertions (set in PCIe_top)
    if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", dl_aif))
      `uvm_warning("RC_DL_ASSERT", "PCIe_RC_INTERFACE not found :: DL assertions are OFF for RC")
  endfunction

// DL model consumes TL output, creates the DLP, then publishes to PL.
function void write(PCIe_sequence_item item);
  `uvm_info("RC_DL_MODEL","TL -> DL",UVM_LOW);
  // item.print();
  form_dl_packet(item.tlp_data,item.is_payload,item.dlp_flit_out);

  print_dlp_packet(item.tlp_data,item.dlp_flit_out);
  `uvm_info("RC_DL_MODEL","SENT_DLP_TO_PL_236B", UVM_LOW)
   // [DL_ASSERT] used by DL_TLP_ONLY_IN_ACTIVE_CHECK (TLP flit only in DL_ACTIVE)
   if (dl_aif != null && item.is_payload) begin
     dl_aif.tx_payload_dl_state = DL_STATE;
     dl_aif.tx_payload_cnt++;
   end
   flit_cnt_count(1'b1, item.dlp_flit_out);   // [FLIT_CNT] TX
   dlp_pl_ap.write(item);
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
  // Structured exactly like PCIe_RC_PL_model::rc_ltssm(): a forever+case loop,
  // one task per state/substate, each task prints its own entry banner, checks
  // its own dependency condition, prints the check, and only transitions when
  // that condition is actually satisfied - never a blind one-shot sequence.
  //
  // Dependency chain enforced (matches your LTSSM style 1:1):
  //   DL_INACTIVE  --(phy_linkup && link_enabled)-->  DL_FEATURE
  //   DL_FEATURE   --(FEATURE_DLLP sent)-->            DL_INIT.FC_INIT1
  //   FC_INIT1     --(fc1_sent_count >= NUM_INITFC1_DLLP)--> FC_INIT2
  //   FC_INIT2     --(fc2_sent_count >= NUM_INITFC2_DLLP)--> DL_ACTIVE
  //   DL_ACTIVE    --> dl_link_active=1, dl_active_event fires -> TL may send TLPs
  // =========================================================================

  // =========================================================================
  // [DL_ASSERT] MIRROR FOR THE DL ASSERTIONS
  // Copies the DLCMSM variables into dl_aif on every pclk negedge, so the assertions
  // in PCIe_RC_interface (sampled on posedge) always sees stable values.
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
    dl_aif.replay_in_progress     = RC_REPLAY_IN_PROGRESS;
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
     `uvm_info("RC_DLCMSM","[DLCMSM_TRACE] WAITING_FOR_rc_l0_to_dl_event (fired by PL model on LTSSM L0 entry)",UVM_LOW)
     forever begin
       //@(rc_l0_to_dl_event);
       uvm_rc_l0_to_dl_ev.wait_trigger();
      `uvm_info("RC_DLCMSM","DLCMSM_RC_TO_DL_EVENT_TRIGGRED",UVM_LOW)
        wait(phy_linkup == 1);
        `uvm_info("RC_DLCMSM","[DLCMSM_TRACE] rc_l0_to_dl_event_FIRED :: LTSSM_REACHED_L0 :: STARTING_DLCMSM_FSM",UVM_LOW)
        PCIe_flow_log::print("LTSSM", "RC L0, LINK_UP=1");   // [FLOW]
        // Reset FSM state on every (re)start so a re-training link re-runs FC-Init cleanly.
        DL_STATE       = DL_INACTIVE;
        dl_link_active = 1'b0;
        fc1_sent_count = 0;
        fc2_sent_count = 0;
        dllp_tx_pending        = 1'b0;
        NAK_SCHEDULED          = 1'b0;
        ACK_SCHEDULED          = 1'b0;
        REPLAY_SCHEDULED       = 1'b0;
        RC_REPLAY_IN_PROGRESS  = 1'b0;
        dl_reset_state("DL_INACTIVE (link up, DLCMSM starts)");   // [DL_RESET]
        // Run the DLCMSM FSM and the concurrent DL data-processing thread
        // (ACK/NAK/REPLAY) together. The fork returns as soon as run_dlcmsm()
        // exits - which only happens in DL_ACTIVE when phy_linkup drops - and
        // then the data-processing loop is killed so the link re-initializes.
        fc_restart_init();
        fc_tx_allowed = 1'b0;      // driver releases it once the link-up TLP has been driven
        fork : rc_dl_run
           run_dlcmsm();
           run_dl_data_processing();
           run_fc_update_loop();
           run_replay_timer();     // [REPLAY_TIMER]
        join_any
        disable fork;
        DL_STATE       = DL_INACTIVE;
        dl_link_active = 1'b0;
        dl_reset_state("DL_INACTIVE (Physical LinkUp = 0)");      // [DL_RESET]
        PCIe_flow_log::print("DLCMSM", $sformatf("RC DL_Inactive (link down), %0d unACKed flit(s) dropped", n_tx_flits_dropped_on_reset));   // [FLOW]
        `uvm_info("RC_DLCMSM","[DLCMSM_TRACE] phy_linkup=0 :: DL_RUN_TERMINATED :: WAITING_FOR_NEXT_LINKUP",UVM_LOW)
     end
  endtask

  // ===========================================================================
  // DL DATA PROCESSING THREAD  (runs while DL_ACTIVE)
  //   [REPLAY] The replay is NOT done here. The RC PL model holds ONE flit, so
  //   the RC controller driver drives the replay flits one by one
  //   (PCIe_RC_controller_driver::drive_replay -> start_replay / send_replay_flit).
  // ===========================================================================
  task run_dl_data_processing();
     wait(dl_link_active);
     `uvm_info("RC_DL_PROC","[DL_DATA_PROC] DL_ACTIVE :: STARTING_ACK_NAK_PROCESSING (replay is driven by the RC driver)",UVM_LOW)
     forever begin
        if (NAK_SCHEDULED) begin
           `uvm_info("RC_DL_PROC","[DL_DATA_PROC] NAK_SCHEDULED :: SENDING_NAK_FLIT",UVM_LOW)
           send_dl_control_flit();
           // Transmitted: once a NAK is put on the wire it is consumed. Any
           // further NAK scheduling comes from the RX path (handle_incoming_flit).
           NAK_SCHEDULED = 1'b0;
        end
        else if (ACK_SCHEDULED) begin
           `uvm_info("RC_DL_PROC","[DL_DATA_PROC] ACK_SCHEDULED :: SENDING_ACK_FLIT",UVM_LOW)
           // form_dl_packet() clears ACK_SCHEDULED itself when building an ACK.
           send_dl_control_flit();
        end
        else begin
           // Nothing to send right now - yield so other processes can run.
           #1ns;
        end
     end
  endtask

  // Builds a control flit (ACK or NAK, is_payload=0) using the currently
  // scheduled state, and pushes it to the PL model.
  task send_dl_control_flit();
     PCIe_sequence_item ctl_item;
     bit                prior_payload_saved;
     ctl_item = PCIe_sequence_item::type_id::create("ctl_item");
     // [REPLAY] This flit is NOT put on the wire (write below is commented),
     // so it must not change the "Prior Flit was Payload" bit of the next flit.
     prior_payload_saved = last_flit_was_payload;
     form_dl_packet(ctl_item.tlp_data, 1'b0, ctl_item.dlp_flit_out);
     last_flit_was_payload = prior_payload_saved;
     //dlp_pl_ap.write(ctl_item);
  endtask

  // ===========================================================================
  // [REPLAY] TX REPLAY  (PCIe 6.1 Sec 4.2.3.4.2.1.6 and 4.2.3.4.2.1.7)
  //
  //   Step 1 : EP sends NAK(N) -> process_received_ack_nak() -> schedule_replay_on_nak()
  //              REPLAY_SCHEDULED = 1, TX_REPLAY_FLIT_SEQ_NUM = N+1
  //   Step 2 : RC driver sees REPLAY_SCHEDULED -> drive_replay() :
  //              start_replay()      : list of flits from the TX retry buffer
  //                                    STANDARD_REPLAY  : flit N+1 and every flit after it
  //                                    SELECTIVE_REPLAY : only flit N+1
  //              send_replay_flit()  : ONE flit -> RC PL model, then the driver drives it
  //                                    * ORIGINAL sequence number (Explicit Sequence
  //                                      Number flit, Replay Command 00b)
  //                                    * NEXT_TX_FLIT_SEQ_NUM does not change
  //                                    * flit is NOT stored again
  //              finish_replay()
  //   Step 3 : EP sends ACK -> purge_tx_retry_buffer() removes the flits
  // ===========================================================================
  bit [`PCIe_SEQ_NUM_W-1:0] replayed_seq_q[$];          // seq num of every replayed flit (for tests)
  int unsigned n_std_replay, n_sel_replay;             // replays started
  real         NAK_IGNORE_WINDOW_NS = 300.0;           // spec : lesser of Ack/Nak latency + 2 flits, or 300 ns
  real         nak_ignore_window_start_ns = -1.0;      // -1 : window not started

  // Makes the list of flits to replay. REPLAY_SCHEDULED -> RC_REPLAY_IN_PROGRESS.
  function void start_replay(output tx_buffer_t replay_q[$]);
     int    start_idx = -1;
     string seq_list  = "";

     replay_q.delete();
     REPLAY_SCHEDULED      = 1'b0;
     RC_REPLAY_IN_PROGRESS = 1'b1;

     foreach (tx_retry_buffer[i]) begin
        if (tx_retry_buffer[i].seq_num == TX_REPLAY_FLIT_SEQ_NUM) begin
           start_idx = i;
           break;
        end
     end

     if (start_idx < 0) begin
        `uvm_warning("RC_REPLAY", $sformatf("REPLAY_SKIPPED :: flit SEQ_NUM=%0d is not in the TX retry buffer (already ACKed)",
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
     `uvm_info("RC_REPLAY", $sformatf({"\n",
        "  ==================== RC REPLAY START ====================\n",
        "   Replay type        : %s\n",
        "   Flits to replay    : %0d\n",
        "   Sequence numbers   : %s\n",
        "   FLIT_REPLAY_NUM    : %0d\n",
        "  =========================================================="},
        REPLAY_SCHEDULED_TYPE.name(), replay_q.size(), seq_list, FLIT_REPLAY_NUM), UVM_NONE)
     PCIe_flow_log::print("REPLAY", $sformatf("RC %s seq %s", (REPLAY_SCHEDULED_TYPE == SELECTIVE_REPLAY) ? "SEL" : "STD", seq_list));   // [FLOW]
  endfunction

  // Sends ONE replayed flit to the RC PL model, with its ORIGINAL sequence number.
  // The caller (RC driver) must drive it on the PIPE before calling this again.
  function void send_replay_flit(tx_buffer_t entry, int unsigned num, int unsigned total);
     PCIe_sequence_item r_item;
     r_item = PCIe_sequence_item::type_id::create("rc_replay_item");
     r_item.tlp_data   = entry.tlp_data;
     r_item.seq_num    = entry.seq_num;
     r_item.is_payload = 1'b1;
     form_replay_flit(r_item.tlp_data, entry.seq_num, r_item.dlp_flit_out);
     nak_ignore_window_check_start(entry.seq_num);
     flit_cnt_count(1'b1, r_item.dlp_flit_out, 1'b1, 1'b1);   // [FLIT_CNT] TX (replayed flit)
     flit_tx_replay++;                             // [FLIT_CNT] replayed flit
     replayed_seq_q.push_back(entry.seq_num);
     `uvm_info("RC_REPLAY", $sformatf("REPLAY_FLIT %0d/%0d :: SEQ_NUM=%0d :: %s :: sent to RC PL",
               num, total, entry.seq_num, REPLAY_SCHEDULED_TYPE.name()), UVM_NONE)
     dlp_pl_ap.write(r_item);
  endfunction

  function void finish_replay(int unsigned n_flits);
     RC_REPLAY_IN_PROGRESS = 1'b0;
     `uvm_info("RC_REPLAY", $sformatf("REPLAY_DONE :: %0d flit(s) replayed :: waiting for ACK from EP", n_flits), UVM_NONE)
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
    `uvm_info("RC_DL_ERROR", $sformatf("DL ERROR LOGGED :: %s :: %s (total DL errors = %0d)",
              error_name, detail, dl_error_total()), UVM_NONE)
    PCIe_flow_log::print("DL_ERROR", $sformatf("RC %s", error_name));   // [FLOW]
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
  //   flags are cleared and BOTH retry buffers are emptied (unACKed flits are lost).
  // ===========================================================================
  // (declaration moved to the top of the class : Questa needs it before its first use)

  function void dl_reset_state(string why);
    n_tx_flits_dropped_on_reset = tx_retry_buffer.size();
    NEXT_TX_FLIT_SEQ_NUM                = 10'h001;
    TX_ACKNAK_FLIT_SEQ_NUM              = 10'h3FF;
    NEXT_EXPECTED_RX_FLIT_SEQ_NUM       = 10'h001;
    IMPLICIT_RX_FLIT_SEQ_NUM            = 10'h000;
    ACKD_FLIT_SEQ_NUM                   = 10'h3FF;
    TX_REPLAY_FLIT_SEQ_NUM              = 10'h000;
    NAK_IGNORE_FLIT_SEQ_NUM             = 10'h000;
    FLIT_REPLAY_NUM                     = '0;
    REPLAY_TIMEOUT_FLIT_COUNT           = 0;
    NON_IDLE_EXPLICIT_SEQ_NUM_FLIT_RCVD = 1'b0;
    NAK_SCHEDULED                       = 1'b0;
    ACK_SCHEDULED                       = 1'b0;
    REPLAY_SCHEDULED                    = 1'b0;
    RC_REPLAY_IN_PROGRESS               = 1'b0;
    NAK_WITHDRAWAL_ALLOWED              = 1'b0;
    RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM   = 10'h000;
    NEXT_RX_FLIT_SEQ_NUM_TO_STORE       = 10'h000;
    RX_RETRY_BUFFER_OVERFLOW            = 1'b0;
    last_flit_was_payload               = 1'b0;
    nak_ignore_window_start_ns          = -1.0;
    duplicate_flit_request              = 1'b0;
    last_tx_payload_valid               = 1'b0;
    dllp_tx_pending                     = 1'b0;
    dllp_tx_lock                        = new(1);   // a killed sender may have kept the key
    tx_retry_buffer.delete();
    rx_retry_buffer.delete();
    `uvm_info("RC_DL_RESET", $sformatf("DL_RESET :: %s :: sequence numbers back to start (NEXT_TX=1, ACKD=1023), flags cleared, retry buffers emptied (%0d unACKed flit(s) dropped)",
              why, n_tx_flits_dropped_on_reset), UVM_LOW)
  endfunction

  // ===========================================================================
  // [REPLAY_TIMER] Replay timeout  (PCIe 6.1 Sec 4.2.3.4.2.1.6, Replay Schedule Rule 0)
  //   REPLAY_TIMEOUT_FLIT_COUNT counts the flits sent while the TX retry buffer
  //   is not empty. It goes back to 0 when an ACK/NAK purges a flit.
  //   When it reaches REPLAY_TIMEOUT_LIMIT (1500 flits) a STANDARD replay of all
  //   unACKed flits is scheduled, starting at ACKD_FLIT_SEQ_NUM + 1.
  //
  //   Model : a real link sends a flit in every flit time (NOP flits when it is
  //   idle), so the counter goes up once per flit time
  //   (`PCIe_LANES_PER_FLIT pclk cycles) while the TX retry buffer is not empty.
  // ===========================================================================
  // (declaration moved to the top of the class : Questa needs it before its first use)

  task run_replay_timer();
    wait (dl_link_active);
    forever begin
      wait_one_flit_time();
      if ((tx_retry_buffer.size() > 0) && (REPLAY_TIMEOUT_FLIT_COUNT < 11'h7FF))
        REPLAY_TIMEOUT_FLIT_COUNT++;
      if ((REPLAY_TIMEOUT_FLIT_COUNT >= REPLAY_TIMEOUT_LIMIT) && !REPLAY_SCHEDULED && !RC_REPLAY_IN_PROGRESS) begin
        REPLAY_SCHEDULED          = 1'b1;
        REPLAY_SCHEDULED_TYPE     = STANDARD_REPLAY;
        TX_REPLAY_FLIT_SEQ_NUM    = mod1023_add(ACKD_FLIT_SEQ_NUM, 10'h1);
        REPLAY_TIMEOUT_FLIT_COUNT = 0;
        n_replay_timeouts++;
        err_replay_timer_timeout++;   // [DL_ERR]
        log_dl_error("REPLAY_TIMER_TIMEOUT", $sformatf("no ACK progress for %0d flits -> STANDARD replay", REPLAY_TIMEOUT_LIMIT));
        `uvm_info("RC_REPLAY", $sformatf({"\n",
           "  ==================== RC REPLAY TIMER TIMEOUT ====================\n",
           "   No ACK for %0d flit times with %0d flit(s) waiting in the TX retry buffer\n",
           "   Replay Timer Timeout error logged (correctable, Sec 6.2)\n",
           "   -> STANDARD_REPLAY scheduled from SEQ_NUM=%0d (ACKD_FLIT_SEQ_NUM + 1)\n",
           "  ================================================================"},
           REPLAY_TIMEOUT_LIMIT, tx_retry_buffer.size(), TX_REPLAY_FLIT_SEQ_NUM), UVM_NONE)
        PCIe_flow_log::print("REPLAY_TIMER", $sformatf("RC timeout (%0d flits, no ACK) -> STD replay from seq %0d", REPLAY_TIMEOUT_LIMIT, TX_REPLAY_FLIT_SEQ_NUM));   // [FLOW]
      end
    end
  endtask

  task wait_one_flit_time();
    if (dl_aif != null) repeat (`PCIe_LANES_PER_FLIT) @(posedge dl_aif.pclk);
    else                #(`PCIe_LANES_PER_FLIT * 1ns);
  endtask

  // ===========================================================================
  // [TX_BUF_LIMIT] TX retry buffer limit
  //   Spec : at most 511 flits may be unACKed (MAX_UNACKNOWLEDGED_FLITS). When
  //   the TX retry buffer is full the transmitter must not send a NEW payload
  //   flit. The RC driver waits on tx_retry_buffer_full() before each TLP.
  //   A test may lower TX_RETRY_BUFFER_MAX_FLITS to reach the limit quickly.
  // ===========================================================================
  int unsigned TX_RETRY_BUFFER_MAX_FLITS = `PCIe_MAX_UNACK_FLITS;
  int unsigned n_tx_retry_buffer_full_waits;           // TLPs that had to wait for space

  function bit tx_retry_buffer_full();
    return (tx_retry_buffer.size() >= TX_RETRY_BUFFER_MAX_FLITS);
  endfunction

  // ===========================================================================
  // [SEQ_LOG] Sequence number of every NEW payload flit sent (tests read it)
  //   and a test helper to move the sequence numbers near the wrap point.
  // ===========================================================================
  bit [`PCIe_SEQ_NUM_W-1:0] tx_payload_seq_q[$];

  // Only when nothing is waiting for an ACK : NEXT_TX = next_seq, ACKD = next_seq - 1
  function void set_tx_seq_for_test(bit [`PCIe_SEQ_NUM_W-1:0] next_seq);
    if (tx_retry_buffer.size() != 0)
      `uvm_error("RC_SEQ_TEST", $sformatf("set_tx_seq_for_test : %0d flit(s) still unACKed", tx_retry_buffer.size()))
    NEXT_TX_FLIT_SEQ_NUM    = next_seq;
    ACKD_FLIT_SEQ_NUM       = mod1023_sub(next_seq, 10'h1);
    TX_REPLAY_FLIT_SEQ_NUM  = 10'h000;
    NAK_IGNORE_FLIT_SEQ_NUM = 10'h000;
    `uvm_info("RC_SEQ_TEST", $sformatf("TX SEQUENCE NUMBER MOVED :: NEXT_TX_FLIT_SEQ_NUM=%0d ACKD_FLIT_SEQ_NUM=%0d",
              NEXT_TX_FLIT_SEQ_NUM, ACKD_FLIT_SEQ_NUM), UVM_NONE)
  endfunction

  // ===========================================================================
  // [DUP_FLIT] Duplicate flit injection (test only)
  //   The last NEW payload flit is kept. When a test sets duplicate_flit_request,
  //   the RC driver sends it once more with its ORIGINAL sequence number.
  //   The EP has already ACKed it, so it must drop it (Flit Discard 0).
  // ===========================================================================
  // (declaration moved to the top of the class : Questa needs it before its first use)

  function void send_duplicate_flit();
    PCIe_sequence_item d_item;
    if (!last_tx_payload_valid) begin
      `uvm_warning("RC_DUP_FLIT", "no payload flit sent yet : nothing to duplicate")
      return;
    end
    d_item = PCIe_sequence_item::type_id::create("rc_duplicate_item");
    d_item.tlp_data   = last_tx_payload_flit.tlp_data;
    d_item.seq_num    = last_tx_payload_flit.seq_num;
    d_item.is_payload = 1'b1;
    form_replay_flit(d_item.tlp_data, last_tx_payload_flit.seq_num, d_item.dlp_flit_out);
    flit_cnt_count(1'b1, d_item.dlp_flit_out, 1'b1, 1'b1);   // [FLIT_CNT] TX (duplicate flit)
    n_duplicate_flits_sent++;
    PCIe_flow_log::print("TEST", $sformatf("RC sent duplicate seq %0d", last_tx_payload_flit.seq_num));                                   // [FLOW]
    `uvm_info("RC_DUP_FLIT", $sformatf("DUPLICATE_FLIT :: SEQ_NUM=%0d sent again (already ACKed by EP)",
              last_tx_payload_flit.seq_num), UVM_NONE)
    dlp_pl_ap.write(d_item);
  endfunction

  // ===========================================================================
  // [OPT_UPDATE_FC] Optimized_Update_FC receive  (PCIe 6.1 Table 4-17 / Table 4-18)
  //   DLP0[4] = 1 : DLP2..5 hold an Optimized_Update_FC (bit 31 = 0) or a
  //                 Flit_Marker (bit 31 = 1), NOT a DLLP.
  //   Optimized_Update_FC : [30:28] VC  [27:20] Shared NPH  [19:12] Shared PH
  //                         [11:0] Shared PD
  //   The new SHARED limits go to the TL like a shared UpdateFC
  //   (P : PH + PD, NP : NPH + last known NPD).
  // ===========================================================================
  int unsigned n_opt_updfc_rx;

  function void fc_rx_opt_update(bit [31:0] v);
    bit [2:0]          vc;
    PCIe_sequence_item p_item, np_item;
    vc = v[30:28];
    n_opt_updfc_rx++;
    `uvm_info("RC_DL_FC", $sformatf("[FC_DL_RX] OPTIMIZED_UPDATE_FC VC%0d : SHARED NPH=%0d PH=%0d PD=%0d (raw %08h)",
              vc, v[27:20], v[19:12], v[11:0], v), UVM_LOW)
    if (!fc_vc_on(vc)) begin
      n_fc_dllp_dis_vc++;
      `uvm_info("RC_DL_FC", $sformatf("[FC_DL_RX] VC%0d is not enabled on this Port -> Optimized_Update_FC ignored", vc), UVM_LOW)
      return;
    end
    fi2[vc] = 1'b1;
    peer_h_shr[vc][0] = v[19:12];
    peer_d_shr[vc][0] = v[11:0];
    peer_h_shr[vc][1] = v[27:20];

    p_item = PCIe_sequence_item::type_id::create("fc_opt_p_item");
    p_item.fc_kind   = FC_PEER_UPDATE;
    p_item.fc_vc     = vc;
    p_item.fc_origin = "RC_DL";
    p_item.fc_reason = "OPTIMIZED_UPDATE_FC";
    p_item.set_fc_cls_shr(0, peer_h_shr[vc][0], peer_d_shr[vc][0]);
    p_item.fc_hdr_inf_shr[0] = peer_hinf_shr[vc][0];
    p_item.fc_dat_inf_shr[0] = peer_dinf_shr[vc][0];
    fc_tl_ap.write(p_item);

    np_item = PCIe_sequence_item::type_id::create("fc_opt_np_item");
    np_item.fc_kind   = FC_PEER_UPDATE;
    np_item.fc_vc     = vc;
    np_item.fc_origin = "RC_DL";
    np_item.fc_reason = "OPTIMIZED_UPDATE_FC";
    np_item.set_fc_cls_shr(1, peer_h_shr[vc][1], peer_d_shr[vc][1]);
    np_item.fc_hdr_inf_shr[1] = peer_hinf_shr[vc][1];
    np_item.fc_dat_inf_shr[1] = peer_dinf_shr[vc][1];
    fc_tl_ap.write(np_item);
  endfunction

  // ===========================================================================
  // [LOST_UPDATEFC] Test knob : while drop_p_updatefc = 1 every received
  //   UpdateFC for the Posted class is thrown away (as if the DLLP was lost).
  //   The EP must recover the credits with its periodic UpdateFC (30 us).
  // ===========================================================================
  bit          drop_p_updatefc;
  int unsigned n_p_updatefc_dropped;

  // ===========================================================================
  // [LOST_NAK] Test knob : while drop_naks = 1 every received NAK is thrown
  //   away (as if it was lost on the link). No NAK replay happens, so the
  //   REPLAY TIMER must recover the lost flit (Replay Schedule Rule 0).
  // ===========================================================================
  bit          drop_naks;
  int unsigned n_naks_dropped;

   task run_dlcmsm();
      forever begin
         case (DL_STATE)

            DL_INACTIVE: begin
               `uvm_info("RC_DLCMSM","==========================================",UVM_LOW)
               `uvm_info("RC_DLCMSM","DLCMSM_STATE = DL_INACTIVE",UVM_LOW)
               `uvm_info("RC_DLCMSM","==========================================",UVM_LOW)
               dlcmsm_state_dl_inactive();
            end

            DL_FEATURE: begin
               `uvm_info("RC_DLCMSM","==========================================",UVM_LOW)
               `uvm_info("RC_DLCMSM","DLCMSM_STATE = DL_FEATURE",UVM_LOW)
               `uvm_info("RC_DLCMSM","==========================================",UVM_LOW)
               dlcmsm_state_dl_feature();
            end

            DL_INIT: begin
               case (dl_init_substate)
                  INIT_FC1: begin
                     `uvm_info("RC_DLCMSM","SUB_STATE = DL_INIT.FC_INIT1",UVM_LOW)
                     dlcmsm_state_init_fc1();
                  end
                  INIT_FC2: begin
                     `uvm_info("RC_DLCMSM","SUB_STATE = DL_INIT.FC_INIT2",UVM_LOW)
                     dlcmsm_state_init_fc2();
                  end
                  default: `uvm_error("RC_DLCMSM","INVALID_DL_INIT_SUBSTATE")
               endcase
            end

            DL_ACTIVE: begin
               `uvm_info("RC_DLCMSM","==========================================",UVM_LOW)
               `uvm_info("RC_DLCMSM","DLCMSM_STATE = DL_ACTIVE :: LINK_READY_FOR_TLP_TRAFFIC",UVM_LOW)
               `uvm_info("RC_DLCMSM","==========================================",UVM_LOW)
               dlcmsm_state_dl_active();
               // Wait here for phy_linkup to drop before allowing a re-entry via run_phase.
               wait (!phy_linkup);
               DL_STATE       = DL_INACTIVE;
               dl_link_active = 1'b0;
               `uvm_info("RC_DLCMSM","[DL_ACTIVE] phy_linkup=0 :: BACK_TO_DL_INACTIVE",UVM_LOW)
               return;  // hand control back to run_phase's forever; will re-enter on next L0 event
            end

            default: `uvm_error("RC_DLCMSM","INVALID_DLCMSM_STATE")
         endcase
      end
   endtask

   // ---------------- DL_INACTIVE ----------------
   task dlcmsm_state_dl_inactive();
      `uvm_info("RC_DLCMSM",$sformatf(
         "[DL_INACTIVE] CHECKING_DEPENDENCY :: phy_linkup=%0b (LTSSM link_up by the driver) ",
         phy_linkup),UVM_LOW)
      wait (phy_linkup );
      `uvm_info("RC_DLCMSM",$sformatf(
         "[DL_INACTIVE] DEPENDENCY_SATISFIED :: phy_linkup=%0b :: TRANSITION -> DL_FEATURE",
         phy_linkup),UVM_LOW)
      DL_STATE = DL_FEATURE;
   endtask

   // ---------------- DL_FEATURE ----------------
   task dlcmsm_state_dl_feature();
      send_dllp_flit(FEATURE_DLLP);
      `uvm_info("RC_DLCMSM",$sformatf("[DL_FEATURE] FEATURE_DLLP_SENT=%08h :: TRANSITION -> DL_INIT.FC_INIT1",FEATURE_DLLP),UVM_LOW)
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
      `uvm_info("RC_DLCMSM",$sformatf(
         "[DL_INIT.FC_INIT1] ROUND_%0d_DONE :: FI1 dedicated P/NP/CPL=%0b%0b%0b shared P/NP/CPL=%0b%0b%0b",
         fc1_sent_count, fi1_ded[0][0], fi1_ded[0][1], fi1_ded[0][2],
         fi1_shr[0][0], fi1_shr[0][1], fi1_shr[0][2]),UVM_LOW)
      if (fi1_done()) begin
         `uvm_info("RC_DLCMSM",$sformatf(
            "[DL_INIT.FC_INIT1] FI1_SET :: peer credits recorded PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d :: TRANSITION -> DL_INIT.FC_INIT2",
            peer_h[0][0], peer_d[0][0], peer_h[0][1], peer_d[0][1], peer_h[0][2], peer_d[0][2]),UVM_LOW)
         dl_init_substate = INIT_FC2;
      end
      else if (fc1_sent_count >= `PCIe_FC_INIT_MAX_ROUNDS) begin
         `uvm_error("RC_DLCMSM",$sformatf("[DL_INIT.FC_INIT1] FI1_NOT_SET_AFTER_%0d_ROUNDS :: peer never sent all six InitFC DLLPs :: FORCING FC_INIT2",fc1_sent_count))
         dl_init_substate = INIT_FC2;
      end
      else begin
         `uvm_info("RC_DLCMSM","[DL_INIT.FC_INIT1] FI1_NOT_SET :: STAYING_IN_FC_INIT1 (resend InitFC1 round)",UVM_LOW)
         #(`PCIe_FC_INIT_ROUND_GAP_NS * 1ns);
      end
   endtask

   // ---------------- DL_INIT : FC_INIT2 ----------------
   task dlcmsm_state_init_fc2();
      fc_send_init_round(`PCIe_FC_TYPE_INITFC2);
      fc2_sent_count++;
      // [FC_OPT] NEW : wait (up to PCIe_FC_INIT_WAIT_NS) for FI2 (peer InitFC2 / UpdateFC / TLP) before deciding to resend
      for (int w = 0; w < `PCIe_FC_INIT_WAIT_NS && !fi2_done(); w++) #1ns;
      `uvm_info("RC_DLCMSM",$sformatf("[DL_INIT.FC_INIT2] ROUND_%0d_DONE :: FI2=%0b",fc2_sent_count,fi2_done()),UVM_LOW)
      if (fi2_done()) begin
         `uvm_info("RC_DLCMSM","[DL_INIT.FC_INIT2] FI2_SET :: TRANSITION -> DL_ACTIVE",UVM_LOW)
         PCIe_flow_log::print("FC_INIT", "RC FC init done");   // [FLOW]
         DL_STATE = DL_ACTIVE;
      end
      else if (fc2_sent_count >= `PCIe_FC_INIT_MAX_ROUNDS) begin
         `uvm_error("RC_DLCMSM",$sformatf("[DL_INIT.FC_INIT2] FI2_NOT_SET_AFTER_%0d_ROUNDS :: FORCING DL_ACTIVE",fc2_sent_count))
         DL_STATE = DL_ACTIVE;
      end
      else begin
         `uvm_info("RC_DLCMSM","[DL_INIT.FC_INIT2] FI2_NOT_SET :: STAYING_IN_FC_INIT2 (resend InitFC2 round)",UVM_LOW)
         #(`PCIe_FC_INIT_ROUND_GAP_NS * 1ns);
      end
   endtask

   // ---------------- DL_ACTIVE ----------------
   task dlcmsm_state_dl_active();
      `uvm_info("RC_DLCMSM","ENTERED_INTO_DL_ACTIVE_STATE",UVM_LOW)
      PCIe_flow_log::print("DLCMSM", "RC DL_Active");   // [FLOW]
      dl_link_active = 1'b1;
         dl_active_event.trigger();
      `uvm_info("RC_DLCMSM",$sformatf("[DL_ACTIVE] dl_active_event_TRIGGERED :: TL_MAY_NOW_SEND_TLPs link_active=%0d",dl_link_active),UVM_LOW)
   endtask

    // Builds a NOP/DLLP-only flit (is_payload=0) with given dllp_content and
    // pushes it through the SAME path normal flits use (dlp_pl_ap -> PL model).
    // The task then BLOCKS until the RC controller driver has put that flit on
    // the PIPE (driver clears dllp_tx_pending), so the DLCMSM packets are
    // transmitted one by one, in order, and never overwrite each other in the
    // PL model.
    task send_dllp_flit(bit [31:0] content);
       PCIe_sequence_item dcm_item;
       semaphore          my_lock;
       my_lock = dllp_tx_lock;   // [DLLP_LOCK] keep the handle : a reset may create a new one
       my_lock.get(1);           // [DLLP_LOCK] one DLLP flit at a time
       dcm_item = PCIe_sequence_item::type_id::create("dcm_item");
       dllp_content = content;
       form_dl_packet(dcm_item.tlp_data, 1'b0, dcm_item.dlp_flit_out); // is_payload=0
       // dllp_content belongs to THIS flit only. Clear it so it does not leak
       // into the TLP flit that write() forms after DL_ACTIVE (DLP2-DLP5 of a
       // TLP flit must stay 0, exactly as before the DLCMSM packets were driven).
       dllp_content = '0;

       //print_dlp_packet(tlp_data,dlp);
       dllp_tx_pending = 1'b1;
       // [DL_ASSERT] used by DL_NO_DLLP_IN_INACTIVE_CHECK (no DLLP in DL_INACTIVE)
       if (dl_aif != null) begin
         dl_aif.tx_dllp_dl_state = DL_STATE;
         dl_aif.tx_dllp_content  = content;
         dl_aif.tx_dllp_cnt++;
       end
       flit_cnt_count(1'b1, dcm_item.dlp_flit_out);   // [FLIT_CNT] TX
       dlp_pl_ap.write(dcm_item);   // actually push this DLLP-only flit out to the PL model
       `uvm_info("RC_DLCMSM",$sformatf("SENT_DLLP_FLIT content=%08h :: WAITING_FOR_DRIVER_TO_DRIVE_IT_ON_PIPE",content),UVM_LOW)
       wait (dllp_tx_pending == 1'b0);
       `uvm_info("RC_DLCMSM",$sformatf("DLLP_FLIT_DRIVEN_ON_PIPE content=%08h",content),UVM_LOW)
       my_lock.put(1);           // [DLLP_LOCK]
    endtask
  // =========================================================================
  // END DLCMSM FSM BLOCK
  // =========================================================================

  // Standard NAK implementation
  task standard_nak_procedure();
    if(duplicate_sequence_number()) begin
      if(NAK_SCHEDULED)
        discard_flit(0);
      else
        execute_nak_schedule(2);
    end
    else if(received_explicit_seq && (IMPLICIT_RX_FLIT_SEQ_NUM == NEXT_EXPECTED_RX_FLIT_SEQ_NUM)) begin
      execute_ack_schedule(1);
    end
    else begin
      if(NAK_SCHEDULED)
        discard_flit(0);
      else
        execute_nak_schedule(2);
    end
  endtask


  // Selective NAK implementation
  task selective_nak_procedure();
    if(duplicate_sequence_number())
      discard_flit(0);
    else if(received_explicit_seq && (IMPLICIT_RX_FLIT_SEQ_NUM == NEXT_EXPECTED_RX_FLIT_SEQ_NUM)) begin
      if(RX_RETRY_BUFFER_OVERFLOW)
        execute_nak_schedule(5);
      else
        execute_ack_schedule(2);
    end
    else if(IMPLICIT_RX_FLIT_SEQ_NUM == NEXT_RX_FLIT_SEQ_NUM_TO_STORE) begin
      if(rx_retry_buffer.size() >= `PCIe_MAX_UNACK_FLITS)
        execute_nak_schedule(4);
      else
        execute_nak_schedule(3);
    end
    else
      execute_nak_schedule(2);
  endtask


  // Retry buffer manipulation
  task store_flit_in_rx_retry_buffer();
    rx_retry_buffer.push_back(current_flit_data);
    RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM;
    NEXT_RX_FLIT_SEQ_NUM_TO_STORE = mod1023_add(NEXT_RX_FLIT_SEQ_NUM_TO_STORE,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
  endtask


  // Handle payload with failure
  task handle_payload_withdrawal_failure(bit is_nop);
    NAK_WITHDRAWAL_ALLOWED = 1'b0;

    if(is_nop) begin
      NAK_SCHEDULED = 1'b1;
      TX_ACKNAK_FLIT_SEQ_NUM = mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
    end
    else begin
      if(USE_STANDARD_NAK_ONLY)
        standard_nak_procedure();
      else begin
        NEXT_RX_FLIT_SEQ_NUM_TO_STORE = mod1023_add(NEXT_EXPECTED_RX_FLIT_SEQ_NUM,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
        selective_nak_procedure();
      end
    end
  endtask


  function bit bad_sequence_number();
    return (mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM,IMPLICIT_RX_FLIT_SEQ_NUM) > 511);
  endfunction


  function bit bad_nop_sequence_number();
    return bad_sequence_number() || (IMPLICIT_RX_FLIT_SEQ_NUM == NEXT_EXPECTED_RX_FLIT_SEQ_NUM);
  endfunction


  // Check the duplicate sequence number
  function bit duplicate_sequence_number();
    return (mod1023_sub(TX_ACKNAK_FLIT_SEQ_NUM,IMPLICIT_RX_FLIT_SEQ_NUM) < 511);
  endfunction


  // FLIT MODE PACKET CREATION DLP
  function void form_dl_packet(input bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_data,input bit is_payload,output bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] dl_flit_out);

    bit [`PCIe_SEQ_NUM_W-1:0] seq_num_to_send;
    bit [`PCIe_REPLAY_CMD_W-1:0] replay_command;
    bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp;

    // Determine Replay Command and Sequence Number
    if(NAK_SCHEDULED) begin
      replay_command = (NAK_SCHEDULED_TYPE == STANDARD_NAK) ? 2'b10 : 2'b11;
      seq_num_to_send = TX_ACKNAK_FLIT_SEQ_NUM;
    end
    else if(is_payload) begin
      replay_command = 2'b00;
      seq_num_to_send = NEXT_TX_FLIT_SEQ_NUM;
    end
    else begin
      replay_command = 2'b01;
      seq_num_to_send = TX_ACKNAK_FLIT_SEQ_NUM;
    end
    note_acknak_sent(seq_num_to_send, replay_command);   // [FLOW_SUM]

    // Construct DLP0
    dlp[0][7:6] = is_payload ? 2'b01 : 2'b00;
    dlp[0][5] = last_flit_was_payload;
    dlp[0][4] = 1'b0;
    dlp[0][3:2] = replay_command;
    dlp[0][1:0] = seq_num_to_send[`PCIe_SEQ_NUM_W-1:`PCIe_SEQ_NUM_W-2];

    // Construct DLP1
    dlp[1] = seq_num_to_send[`PCIe_SEQ_NUM_W-3:0];

    // Construct DLP2-DLP5
    dlp[2] = dllp_content[31:24];
    dlp[3] = dllp_content[23:16];
    dlp[4] = dllp_content[15:8];
    dlp[5] = dllp_content[7:0];

    // Update DL Internal State
    // [REPLAY] A NEW payload flit always gets NEXT_TX_FLIT_SEQ_NUM (also when it
    // carries an ACK/NAK) and only payload flits are stored in the TX retry
    // buffer. Replayed flits do NOT come here (see form_replay_flit).
    if(is_payload) begin
      store_tx_retry_buffer(tlp_data,NEXT_TX_FLIT_SEQ_NUM);
      nak_ignore_window_check_start(NEXT_TX_FLIT_SEQ_NUM);
      tx_payload_seq_q.push_back(NEXT_TX_FLIT_SEQ_NUM);                       // [SEQ_LOG]
      if (n_tx_new_payload == 0) first_tx_seq = NEXT_TX_FLIT_SEQ_NUM;          // [FLOW_SUM]
      last_tx_seq = NEXT_TX_FLIT_SEQ_NUM;
      n_tx_new_payload++;
      last_tx_payload_flit  = '{tlp_data:tlp_data, seq_num:NEXT_TX_FLIT_SEQ_NUM};   // [DUP_FLIT]
      last_tx_payload_valid = 1'b1;
      `uvm_info("RC_DL_MODEL",$sformatf("TX_RETRY_BUFFER_STORE :: new payload flit SEQ_NUM=%0d stored (buffer size=%0d)",
                NEXT_TX_FLIT_SEQ_NUM, tx_retry_buffer.size()),UVM_LOW);
      NEXT_TX_FLIT_SEQ_NUM = mod1023_add(NEXT_TX_FLIT_SEQ_NUM,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
      `uvm_info("RC_DL_MODEL",$sformatf("NEXT_TX_FLIT_SEQ_NUM INSIDE THE DL INTERNAL STATE IS %d",NEXT_TX_FLIT_SEQ_NUM),UVM_LOW);
    end

    // Update ACK Flag / clear it 
    if(replay_command == 2'b01) begin
	 ACK_SCHEDULED=	1'b0;
    end

    last_flit_was_payload = is_payload;

    print_dlp(dlp);
    //print_dlp_packet(tlp_data,dlp);
  // Assemble Output
    for(int i=0;i<`PCIe_TLP_DATA_BYTE_W;i++)
      dl_flit_out[i] = tlp_data[i];

    for(int i=0;i<`PCIe_DLP_BYTE_W;i++)
      dl_flit_out[`PCIe_TLP_DATA_BYTE_W+i] = dlp[i];

    `uvm_info("RC_DL_MODEL",$sformatf("replay_cmd=%d :: is_payload=%d :: dllp_sequence_number=%0h :: dlp=%p",replay_command,is_payload,{dlp[0][1:0],dlp[1]},dl_flit_out),UVM_LOW);
  endfunction

  
  //--------------------------------------------------------------------------
  // ADDITIONAL DEBUG ONLY: TLP + Sequence Number + ECRC style dump.
  // Existing model code is intentionally unchanged.
  //--------------------------------------------------------------------------
  function void print_dlp_packet(
    input bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_data,
    input bit [`PCIe_DLP_BYTE_W-1:0][`PCIe_BYTE_W-1:0] dlp
  );

    string dump;

    dump = $sformatf({"\n",
      "============================================================\n",
      "                 DLP PACKET \n",
      "============================================================\n",
      "TLP\n",
      "------------------------------------------------------------\n",
      "  TLP SIZE = %0d bytes\n",
      "  TLP HEADER + PAYLOAD:\n",
      "  %p\n",
      "\n",
      "SEQUENCE NUMBER\n",
      "------------------------------------------------------------\n",
      "  SEQ_NUM = %0h\n",
      "\n",
      "COMPLETE DLP FORMAT\n",
      "------------------------------------------------------------\n",
      "  TLP + SEQUENCE NUMBER\n",
      "============================================================\n"},
      `PCIe_TLP_DATA_BYTE_W,
      tlp_data,
      {dlp[0][1:0],dlp[1]}
      );

    `uvm_info("RC_DL_TLP_SEQ_ECRC_DUMP", dump, UVM_LOW)

  endfunction


  //--------------------------------------------------------------------------
  // ADDITIONAL DEBUG ONLY: Print complete DLP and individual DLP fields.
  // Existing model code is intentionally unchanged.
  //--------------------------------------------------------------------------
  function void print_dlp(bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp);

    string dump;

    dump = $sformatf({"\n",
      "         ============================================================\n",
      "                           DLP BYTES FORMAT \n",
      "         ============================================================\n",
      "         DLP SIZE : %0d bytes\n",
      "         ------------------------------------------------------------\n",
      "         COMPLETE DLP BYTES:\n",
      "         ------------------------------------------------------------\n",
      "           DLP[0] = %02h\n",
      "           DLP[1] = %02h\n",
      "           DLP[2] = %02h\n",
      "           DLP[3] = %02h\n",
      "           DLP[4] = %02h\n",
      "           DLP[5] = %02h\n",
      "         ------------------------------------------------------------\n",
      "         DLP0 FIELDS:\n",
      "         ------------------------------------------------------------\n",
      "           FLIT_USAGE        [%0d:%0d] = %02h\n",
      "           LAST_FLIT_PAYLOAD [%0d]    = %0b\n",
      "           DLLP_TYPE         [%0d]    = %0b\n",
      "           REPLAY_CMD        [%0d:%0d] = %02h\n",
      "           SEQ_NUM[%0d:%0d]  [%0d:%0d] = %02h\n",
      "         ------------------------------------------------------------\n",
      "         DLP1 FIELDS:\n",
      "         ------------------------------------------------------------\n",
      "           SEQ_NUM[%0d:%0d]  [%0d:%0d] = %02h\n",
      "         ------------------------------------------------------------\n",
      "         DLP2-DLP5 DLLP CONTENT:\n",
      "         ------------------------------------------------------------\n",
      "           DLLP_CONTENT[31:24] = %02h\n",
      "           DLLP_CONTENT[23:16] = %02h\n",
      "           DLLP_CONTENT[15:8]  = %02h\n",
      "           DLLP_CONTENT[7:0]   = %02h\n",
      "           DLLP_CONTENT        = %08h\n",
      "         ============================================================\n"},
      `PCIe_DLP_BYTE_W,
      dlp[0], dlp[1], dlp[2], dlp[3], dlp[4], dlp[5],

      `PCIe_DLP0_FLIT_USAGE_HI, `PCIe_DLP0_FLIT_USAGE_LO, dlp[0][7:6],
      `PCIe_DLP0_LAST_FLIT_PAYLOAD, dlp[0][5],
      `PCIe_DLP0_DLLP_TYPE, dlp[0][4],
      `PCIe_DLP0_REPLAY_CMD_HI, `PCIe_DLP0_REPLAY_CMD_LO, dlp[0][3:2],
      `PCIe_SEQ_NUM_W-1, `PCIe_SEQ_NUM_W-2, 1, 0, {dlp[0][1:0]},
      `PCIe_SEQ_NUM_W-3, 0, 7, 0, dlp[1],

      dlp[2], dlp[3], dlp[4], dlp[5],
      {dlp[2], dlp[3], dlp[4], dlp[5]});

    `uvm_info("RC_DL_DLP_DUMP", dump, UVM_LOW)

  endfunction

  // Create NOP2 DLLP
  task create_no2_dllp(output bit [`PCIe_DLLP_CONTENT_W-1:0] dllp_content);
    dllp_content = '0;
  endtask


  // Discard the flit
  task discard_flit(int discard_type);
    `uvm_info("RC_DL_MODEL","Entered the discard flit task 0",UVM_LOW);

    NAK_WITHDRAWAL_ALLOWED = 1'b0;

    case(discard_type)
      0: begin
        `uvm_info("RC_DL_MODEL","VIP RX: Flit Discard 0 - Valid/Duplicate/NOP discarded. Sequence maintained",UVM_LOW);
      end

      1: begin
        `uvm_info("RC_DL_MODEL","VIP RX: Flit Discard 1 - Invalid flit dropped during outstanding Nak.",UVM_LOW);
      end

      2: begin
        log_data_link_protocol_error();
        `uvm_info("RC_DL_MODEL","VIP FATAL: Flit Discard 2 - Protocol Violation detected.",UVM_LOW);
      end
    endcase
  endtask


  // Log the receiver error in register
  task log_data_link_protocol_error();
    err_dl_protocol++;   // [DL_ERR]
    log_dl_error("DATA_LINK_PROTOCOL_ERROR", "bad ACK/NAK sequence number or protocol violation");
  endtask


  // NAK Schedule Implementation
  task execute_nak_schedule(int id);
    `uvm_info("RC_DL_MODEL",$sformatf("Entered nak schedule task with id=%d",id),UVM_LOW);

    case(id)
      0: begin
        discard_flit(1);
        NAK_WITHDRAWAL_ALLOWED = 1'b1;
      end

      1: begin
        discard_flit(1);
        NAK_SCHEDULED = 1'b1;
        TX_ACKNAK_FLIT_SEQ_NUM = mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
        NAK_WITHDRAWAL_ALLOWED = 1'b0;
      end

      2: begin
        TX_ACKNAK_FLIT_SEQ_NUM = mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
        NAK_SCHEDULED = 1'b1;
        NAK_SCHEDULED_TYPE = STANDARD_NAK;
        RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = '0;
        NAK_WITHDRAWAL_ALLOWED = 1'b0;
      end

      3: begin
        RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM;
        NEXT_RX_FLIT_SEQ_NUM_TO_STORE = mod1023_add(NEXT_RX_FLIT_SEQ_NUM_TO_STORE,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
        NAK_WITHDRAWAL_ALLOWED = 1'b0;
      end

      4: begin
        discard_flit(0);

        if(ALLOW_SELECTIVE_OVERFLOW)
          RX_RETRY_BUFFER_OVERFLOW = 1'b1;
        else begin
          NAK_SCHEDULED_TYPE = STANDARD_NAK;
          TX_ACKNAK_FLIT_SEQ_NUM = mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
          rx_retry_buffer.delete();
          RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = '0;
          NAK_WITHDRAWAL_ALLOWED = 1'b0;
        end
      end

      5: begin
        NAK_SCHEDULED = 1'b1;
        NAK_SCHEDULED_TYPE = STANDARD_NAK;
        TX_ACKNAK_FLIT_SEQ_NUM = RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM;
        RX_RETRY_BUFFER_OVERFLOW = 1'b0;
        NAK_WITHDRAWAL_ALLOWED = 1'b0;
        NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
        RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = '0;
      end

      6: begin
        discard_flit(1);
        NAK_SCHEDULED = 1'b1;
        NAK_SCHEDULED_TYPE = STANDARD_NAK;
        RX_RETRY_BUFFER_OVERFLOW = 1'b0;
        NAK_WITHDRAWAL_ALLOWED = 1'b0;
        TX_ACKNAK_FLIT_SEQ_NUM = mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
        rx_retry_buffer.delete();
      end

      7: begin
        NAK_SCHEDULED_TYPE = STANDARD_NAK;
      end
    endcase
  endtask


  // ACK Schedule Implementation
  task execute_ack_schedule(int id);
    `uvm_info("RC_DL_MODEL","Entered execute ack schedule",UVM_LOW);

    case(id)
      0: begin
        TX_ACKNAK_FLIT_SEQ_NUM = NEXT_EXPECTED_RX_FLIT_SEQ_NUM;
        NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(NEXT_EXPECTED_RX_FLIT_SEQ_NUM,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
        `uvm_info("RC_DL_MODEL",$sformatf("TX_ACKNAK_FLIT_SEQ_NUM updated after collecting the packet=%d",TX_ACKNAK_FLIT_SEQ_NUM),UVM_LOW);
      end

      1: begin
        NAK_SCHEDULED = 1'b0;
        TX_ACKNAK_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM;
        NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(IMPLICIT_RX_FLIT_SEQ_NUM,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
      end

      2: begin
        NAK_SCHEDULED = 1'b0;

        if(rx_retry_buffer.size() == 0) begin
          TX_ACKNAK_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM;
          NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(IMPLICIT_RX_FLIT_SEQ_NUM,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
        end
        else begin
          TX_ACKNAK_FLIT_SEQ_NUM = RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM;
          NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
          RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = '0;
        end
      end

      3: begin
        NAK_WITHDRAWAL_ALLOWED = 1'b0;
        TX_ACKNAK_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM;
        NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(IMPLICIT_RX_FLIT_SEQ_NUM,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
      end
    endcase
  endtask


  // =========================================================================
  // [ADDED] write_rc_mon_242b : RC Controller Monitor -> RC DL Model
  // Called once per EP->RC flit. Receives the 242B flit and its is_valid status.
  //
  // Flow:
  //   RC Controller Monitor
  //          |
  //          | 242B + is_valid
  //          v
  //   write_rc_mon_242b()
  //          |
  //          +--> collect complete 242B flit
  //          |
  //          +--> extract DLP (last 6B)
  //          |       |
  //          |       +--> handle_incoming_flit()
  //          |
  //          +--> extract TLP (first 236B)
  //                  |
  //                  +--> RC TL through rc_dl_tl_ap
  //
  // Same convention used by the supplied EP DL RX path:
  //   is_valid = 1 -> GOOD flit
  //   is_valid = 0 -> BAD flit
  // =========================================================================
  function void write_rc_mon_242b(PCIe_sequence_item item);

    string flit_242b_str;

    bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] received_dlp;
    bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] received_tlp;
    bit rx_flit_good;
    bit is_payload_flit;

    PCIe_sequence_item tl_item;
    PCIe_sequence_item cov_item;   // [DL_COV] decoded DLP -> subscriber

    // ============================================================
    // 1. Collect complete 242-byte flit
    // ============================================================

    rc_rx_242b_flit_q.push_back(item.dlp_flit_out);
    rc_rx_flit_is_valid_q.push_back(item.is_valid);
    rc_rx_242b_flit_cnt++;
    flit_cnt_count(1'b0, item.dlp_flit_out, item.is_valid);   // [FLIT_CNT] RX

    flit_242b_str = "";

    for (int i = 0; i < `PCIe_DLP_FLIT_BYTE_W; i++)
      flit_242b_str =
        $sformatf("%s%0d ", flit_242b_str, item.dlp_flit_out[i]);

    `uvm_info("RC_DL_MODEL",
              $sformatf(
                "RC_DL_COLLECTED_242B_FLIT : FLIT_%0d is_valid=%0b total_collected=%0d = %s",
                rc_rx_242b_flit_cnt,
                item.is_valid,
                rc_rx_242b_flit_q.size(),
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
      received_tlp[i] = item.dlp_flit_out[i];

    // ============================================================
    // 4. is_valid convention
    //
    // Same convention as the supplied EP DL model:
    //   is_valid = 1 -> GOOD flit
    //   is_valid = 0 -> BAD flit
    //
    // handle_incoming_flit() expects:
    //   1 -> GOOD
    //   0 -> BAD
    // ============================================================

    rx_flit_good = item.is_valid;

    `uvm_info("RC_DL_MODEL",
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

    cov_item = PCIe_sequence_item::type_id::create("rc_dl_cov_item");
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
    rc_dl_cov_ap.write(cov_item);


    // ============================================================
    // 5. Send DLP to DL processing
    //
    // DLP must be processed even for a BAD flit because the DL
    // state machine needs sequence / ACK / NAK information.
    // Use a copy because handle_incoming_flit() is a task.
    // ============================================================

    is_payload_flit = (received_dlp[0][7:6] == 2'b01);

    fork
      begin
        automatic bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp_copy =
          received_dlp;
        automatic bit good_copy = rx_flit_good;

        handle_incoming_flit(dlp_copy, good_copy);
      end
    join_none

    // ============================================================
    // 6. Send only GOOD PAYLOAD flit TLP data to RC TL
    //
    // First 236 bytes = TLP
    // Last   6 bytes = DLP
    // ============================================================

    if (rx_flit_good && is_payload_flit) begin

      string dump;
      string line;

      tl_item = PCIe_sequence_item::type_id::create("rc_dl_to_tl_item");

      foreach (received_tlp[i])
        tl_item.tlp_data[i] = received_tlp[i];

      tl_item.pkt_mode   = dl_rx_pkt_mode;
      tl_item.is_payload = 1'b1;
      tl_item.drive_flit = (dl_rx_pkt_mode == FLIT);

      // 236B dump of exactly what is handed to RC TL
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

      `uvm_info("RC_DL_TL",
                $sformatf(
                  "GOOD PAYLOAD FLIT: 236B TLP sent to TL mode=%s DW0_BYTE0=0x%02h%s",
                  tl_item.pkt_mode.name(),
                  tl_item.tlp_data[0],
                  dump),
                UVM_LOW);

      n_rx_tlp_to_tl++;                                                       // [FLOW_SUM]
      rx_accept_cnt[tlp_kind(received_tlp[0], received_tlp[4])]++;
      rc_dl_tl_ap.write(tl_item);
    end
    else begin

      `uvm_info("RC_DL_TL",
                $sformatf(
                  "TLP NOT sent to TL: good=%0b payload=%0b",
                  rx_flit_good,
                  is_payload_flit),
                UVM_LOW);
    end

  endfunction


  /*********************************************************************************/
  // RX_RC
  /*********************************************************************************/

  // Handling the incoming flit and passing info to RC
  task handle_incoming_flit(bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp,bit is_valid);

    bit [`PCIe_FLIT_USAGE_W-1:0] is_nop;
    bit prior_was_payload;
    bit [`PCIe_SEQ_NUM_W-1:0] sequence_number;
    bit is_idle;
    bit is_payload;
    bit is_explicit;
    bit [`PCIe_FLIT_USAGE_W-1:0] flit_usage;

    fc_rx_flit(dlp, is_valid);   // FLOW CONTROL : InitFC / UpdateFC DLLP processing
    sequence_number = {dlp[0][1:0],dlp[1]};
    is_nop = (!(sequence_number == '0) && dlp[0][7:6] == 2'b00);
    prior_was_payload = dlp[0][5];
    replay_cmd = dlp[0][3:2];
    flit_usage = dlp[0][7:6];
    is_payload = (flit_usage == 2'b01);
    is_explicit = (replay_cmd == 2'b00);
    is_idle = (sequence_number == '0) && (replay_cmd == 2'b00) && (flit_usage == 2'b00);
    received_explicit_seq_0 = (sequence_number == 10'h0) && (replay_cmd == 2'b00);
    received_explicit_seq = (replay_cmd == 2'b00);

    update_implicit_rx_sequence_number(sequence_number,is_valid,is_nop,is_payload,is_explicit,is_idle,prior_was_payload);

    // Invalid Flit Handling
    if(!is_valid) begin
      err_invalid_flit++;   // [DL_ERR]
      log_dl_error("INVALID_FLIT", "CRC fails after FEC correction -> flit dropped");
      if(NAK_SCHEDULED) begin
        if(NAK_SCHEDULED_TYPE == STANDARD_NAK)
          discard_flit(1);
        else
          execute_nak_schedule(6);
      end
      else begin
        if(NAK_WITHDRAWAL_ALLOWED)
          execute_nak_schedule(1);
        else
          execute_nak_schedule(0);
      end
      return;
    end

    // TX side ACK/NAK purge buffer and replay logic
    if (replay_cmd != 2'b00) begin
    process_received_ack_nak(sequence_number,replay_cmd);
    end

    // Protocol Violation Check
    if(received_explicit_seq_0 && !is_idle) begin
      log_data_link_protocol_error();
      return;
    end

    // Resolve NAK Withdrawal
    if(NAK_WITHDRAWAL_ALLOWED) begin
      if(prior_was_payload)
        handle_payload_withdrawal_failure(is_nop);
      else begin
        if(bad_sequence_number())
          execute_nak_schedule(2);
        else
          execute_ack_schedule(3);
      end
      return;
    end

    // Normal Processing
    if(is_nop) begin
      if(bad_nop_sequence_number())
        execute_nak_schedule(2);
      else
        discard_flit(0);
    end
    else begin
      if(NAK_SCHEDULED) begin
        if(NAK_SCHEDULED_TYPE == STANDARD_NAK)
          standard_nak_procedure();
        else
          selective_nak_procedure();
      end
      else begin
        if(duplicate_sequence_number())
          discard_flit(0);
        else if(bad_sequence_number())
          execute_nak_schedule(2);
        else begin
          execute_ack_schedule(0);
	  ACK_SCHEDULED=1;
          success = 1;
        end
      end
    end
  endtask


  /***********************************************************************************************/
  // RC_TX logic
  /***********************************************************************************************/

  // TX logic handling
  task process_received_ack_nak(bit [`PCIe_SEQ_NUM_W-1:0] N,bit [`PCIe_REPLAY_CMD_W-1:0] replay_cmd);

    bit guard_future;
    bit guard_past;
    bit is_ack;
    bit is_nak;

    is_ack = (replay_cmd == 2'b01);
    is_nak = (replay_cmd == 2'b10) || (replay_cmd == 2'b11);   // 10b Standard NAK, 11b Selective NAK

    // ACK/NAK with Sequence Number 0 must be ignored
    if(N == '0)
      return;

    note_acknak_rcvd(N, replay_cmd);   // [FLOW_SUM] counts + [FLOW] line for a new NAK

    // [LOST_NAK] test knob : while drop_naks = 1 every received NAK is thrown
    // away (as if the flit with the NAK was lost). The replay timer must recover.
    if (is_nak && drop_naks) begin
      n_naks_dropped++;
      if (acknak_rx_is_new)
        PCIe_flow_log::print("TEST", $sformatf("RC dropped NAK(%0d) (lost-NAK test)", N));   // [FLOW]
      `uvm_info("RC_DL_MODEL", $sformatf("TEST : %s(%0d) DROPPED (lost NAK) :: waiting for the replay timer",
                (replay_cmd == 2'b11) ? "SELECTIVE_NAK" : "STANDARD_NAK", N), UVM_NONE)
      return;
    end

    `uvm_info("RC_DL_MODEL",$sformatf("NEXT_TX_FLIT_SEQ_NUM=%d, N=%d", NEXT_TX_FLIT_SEQ_NUM,N),UVM_LOW);
    // Guard 1: Future Check
    guard_future = (mod1023_sub(NEXT_TX_FLIT_SEQ_NUM-10'h1,N) <= MAX_UNACKNOWLEDGED_FLITS);

    // Guard 2: Past Check
    guard_past = (mod1023_sub(N,ACKD_FLIT_SEQ_NUM) <= MAX_UNACKNOWLEDGED_FLITS);

    `uvm_info("RC_DL_MODEL",$sformatf("ACKD_FLIT_SEQ_NUM=%d :: gaurd_future=%d :: gaurd_past=%d",ACKD_FLIT_SEQ_NUM,guard_future,guard_past),UVM_LOW);

    if(!(guard_future && guard_past)) begin
      log_data_link_protocol_error();
      return;
    end

    purge_tx_retry_buffer(N);   // flit N and all older flits were received by the EP

    if(mod1023_sub(N,ACKD_FLIT_SEQ_NUM) > 0) begin
      FLIT_REPLAY_NUM = '0;
      ACKD_FLIT_SEQ_NUM = N;
    end

    if(is_ack) begin
      `uvm_info("RC_DL_MODEL",$sformatf("ACK(%0d) RECEIVED :: TX retry buffer size=%0d", N, tx_retry_buffer.size()),UVM_LOW);
      NAK_IGNORE_FLIT_SEQ_NUM    = '0;
      nak_ignore_window_start_ns = -1.0;

      if(mod1023_sub(N,TX_REPLAY_FLIT_SEQ_NUM) < MAX_UNACKNOWLEDGED_FLITS)
        TX_REPLAY_FLIT_SEQ_NUM = '0;
    end
    else if(is_nak) begin
      `uvm_info("RC_DL_MODEL",$sformatf("%s(%0d) RECEIVED from EP :: flit %0d was lost",
                (replay_cmd == 2'b11) ? "SELECTIVE_NAK" : "STANDARD_NAK", N, mod1023_add(N,10'h1)),UVM_NONE);

      // NAK_IGNORE_FLIT_SEQ_NUM rules (spec 4.2.3.4.2.1.4), before the replay rules
      if(N == mod1023_sub(NEXT_TX_FLIT_SEQ_NUM,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1}))
        NAK_IGNORE_FLIT_SEQ_NUM = N;
      else if(N != NAK_IGNORE_FLIT_SEQ_NUM)
        NAK_IGNORE_FLIT_SEQ_NUM = '0;

      schedule_replay_on_nak(N, (replay_cmd == 2'b11));
    end
  endtask


  // Modulo 1023 check: Is sequence S older than or including N?
  function automatic bit is_older_than_or_including(bit [`PCIe_SEQ_NUM_W-1:0] S,bit [`PCIe_SEQ_NUM_W-1:0] N);
    return (mod1023_sub(N,S) <= MAX_UNACKNOWLEDGED_FLITS);
  endfunction


  task purge_tx_retry_buffer(bit [`PCIe_SEQ_NUM_W-1:0] N);
    while(tx_retry_buffer.size() > 0) begin
      if(is_older_than_or_including(tx_retry_buffer[0].seq_num,N)) begin
        `uvm_info("RC_DL_MODEL",$sformatf("TX_RETRY_BUFFER_PURGE :: SEQ_NUM=%0d acknowledged by EP, removed",tx_retry_buffer[0].seq_num),UVM_LOW);
        void'(tx_retry_buffer.pop_front());
        REPLAY_TIMEOUT_FLIT_COUNT = 0;   // [REPLAY_TIMER] forward progress -> timer restarts
      end
      else
        break;
    end
  endtask


  // ---------------------------------------------------------------------------
  // [REPLAY] Replay scheduling on a received NAK(N)  (spec 4.2.3.4.2.1.6)
  //   Rule 1 : flit N+1 is in the TX retry buffer and no replay is running
  //            -> schedule a Standard or Selective replay of flit N+1
  //   Rule 2 : Standard NAK after a Selective NAK, replay not started yet
  //            -> change the scheduled replay to a Standard replay
  //   A repeated NAK(N) inside the Nak Ignore Window is ignored.
  //   The RC driver then runs the replay (drive_replay).
  // ---------------------------------------------------------------------------
  function void schedule_replay_on_nak(bit [`PCIe_SEQ_NUM_W-1:0] N, bit is_selective_nak);
    bit [`PCIe_SEQ_NUM_W-1:0] lost_seq;
    bit lost_flit_in_buffer;

    lost_seq            = mod1023_add(N, 10'h1);
    lost_flit_in_buffer = 1'b0;
    foreach (tx_retry_buffer[i])
      if (tx_retry_buffer[i].seq_num == lost_seq) lost_flit_in_buffer = 1'b1;

    // Rule 2
    if (!is_selective_nak && REPLAY_SCHEDULED && !RC_REPLAY_IN_PROGRESS &&
        (REPLAY_SCHEDULED_TYPE == SELECTIVE_REPLAY) && (TX_REPLAY_FLIT_SEQ_NUM == lost_seq)) begin
      REPLAY_SCHEDULED_TYPE = STANDARD_REPLAY;
      `uvm_info("RC_REPLAY", $sformatf("REPLAY_UPGRADED :: Standard NAK(%0d) after Selective NAK -> STANDARD_REPLAY from SEQ_NUM=%0d", N, lost_seq), UVM_NONE)
      return;
    end

    // Rule 1
    if (!lost_flit_in_buffer) begin
      `uvm_info("RC_REPLAY", $sformatf("NAK(%0d) IGNORED :: flit SEQ_NUM=%0d is not in the TX retry buffer", N, lost_seq), UVM_LOW)
      return;
    end
    if (REPLAY_SCHEDULED || RC_REPLAY_IN_PROGRESS) begin
      `uvm_info("RC_REPLAY", $sformatf("NAK(%0d) IGNORED :: a replay is already scheduled / in progress", N), UVM_LOW)
      return;
    end
    if ((NAK_IGNORE_FLIT_SEQ_NUM == N) && nak_ignore_window_open()) begin
      `uvm_info("RC_REPLAY", $sformatf("NAK(%0d) IGNORED :: repeated NAK inside the Nak Ignore Window", N), UVM_LOW)
      if (acknak_rx_is_new) n_nak_ignored++;   // [FLOW_SUM]
      return;
    end

    REPLAY_SCHEDULED        = 1'b1;
    TX_REPLAY_FLIT_SEQ_NUM  = lost_seq;
    NAK_IGNORE_FLIT_SEQ_NUM = N;
    REPLAY_SCHEDULED_TYPE   = is_selective_nak ? SELECTIVE_REPLAY : STANDARD_REPLAY;
    if (is_selective_nak) n_sel_replay++;
    else                  n_std_replay++;
    `uvm_info("RC_REPLAY", $sformatf("REPLAY_SCHEDULED :: %s NAK(%0d) received -> %s starting at SEQ_NUM=%0d",
              is_selective_nak ? "SELECTIVE" : "STANDARD", N, REPLAY_SCHEDULED_TYPE.name(), lost_seq), UVM_NONE)
  endfunction

  // Storing the tx_retry_buffer
  function void store_tx_retry_buffer(input bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_data,input bit [`PCIe_SEQ_NUM_W-1:0] seq_num);
    tx_retry_buffer.push_back('{tlp_data:tlp_data,seq_num:seq_num});
    if (tx_retry_buffer.size() > max_tx_retry_used) max_tx_retry_used = tx_retry_buffer.size();   // [FLOW_SUM]
  //  `uvm_info("RC_DL_MODEL",$sformatf("The Retry Buffer Content is %p",tx_retry_buffer),UVM_LOW);
  endfunction


  task update_implicit_rx_sequence_number(input bit [`PCIe_SEQ_NUM_W-1:0] N,input bit is_valid,input bit is_nop,input bit is_payload,input bit is_explicit,input bit is_idle,input bit prior_was_payload);

    // Set to N Rule
    if(is_valid && !is_idle && is_explicit && (N != '0)) begin
      IMPLICIT_RX_FLIT_SEQ_NUM = N;
      NON_IDLE_EXPLICIT_SEQ_NUM_FLIT_RCVD = 1'b1;
      `uvm_info("RC_DL_MODEL","IMPLICIT_NUMBER_ASSIGNED_TO_N",UVM_LOW);
    end

    // No Change Rules
    else if(is_idle ||
            (is_explicit && (N == '0)) ||
            (!NON_IDLE_EXPLICIT_SEQ_NUM_FLIT_RCVD && (!is_valid || !is_explicit)) ||
            (is_valid && is_nop && !is_explicit && (!NAK_WITHDRAWAL_ALLOWED || prior_was_payload)) ||
            (is_valid && is_payload && !is_explicit && (NAK_WITHDRAWAL_ALLOWED && !prior_was_payload))) begin

      IMPLICIT_RX_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM;
      `uvm_info("RC_DL_MODEL","IMPLICIT_NUMBER_NO_CHANGE",UVM_LOW);
    end

    // Increment Rules
    else if((NON_IDLE_EXPLICIT_SEQ_NUM_FLIT_RCVD && !is_valid) ||
            (is_valid && is_payload && !is_explicit && (!NAK_WITHDRAWAL_ALLOWED || prior_was_payload))) begin

      IMPLICIT_RX_FLIT_SEQ_NUM = mod1023_add(IMPLICIT_RX_FLIT_SEQ_NUM,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
      `uvm_info("RC_DL_MODEL","IMPLICIT_NUMBER_INCREMENTED",UVM_LOW);
    end

    // Decrement Rules
    else if(is_valid && is_nop && !is_explicit && NAK_WITHDRAWAL_ALLOWED && !prior_was_payload) begin
      IMPLICIT_RX_FLIT_SEQ_NUM = mod1023_sub(IMPLICIT_RX_FLIT_SEQ_NUM,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
      `uvm_info("RC_DL_MODEL","IMPLICIT_NUMBER_DECREMENTED",UVM_LOW);
    end

  endtask


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
    `uvm_info("RC_DL_FC", $sformatf("[FC_TL->DL] %s VC%0d :: DL_EXTRACTED %s  (from %s, reason=%s)",
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
            `uvm_error("RC_DL_FC", $sformatf("ADVERTISED_CREDITS_DO_NOT_FIT_DLLP_FIELD VC%0d class %0d : ded %0d/%0d shr %0d/%0d",
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

  // RC : the PL model has no queue, so the flit is handed over with the same
  // handshake the DLCMSM uses; the RC controller driver puts it on the PIPE and
  // clears dllp_tx_pending (see PCIe_RC_controller_driver).
  task fc_send_active(bit [31:0] content);
    send_dllp_flit(content);
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
        `uvm_warning("RC_DL_FC", $sformatf("InitFC round of VC%0d started before the TL advertised its credits", v))
      q.delete();
      for (int c = 0; c < 3; c++) q.push_back(fc_build_dedicated(typ, c, v));
      for (int c = 0; c < 3; c++) q.push_back(fc_build_shared(typ, c, v));     // [FC SHARED]
      `uvm_info("RC_DL_FC", $sformatf("[FC_DL_TX] %s ROUND VC%0d :: advertising  DED: PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d  SHR: PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d",
                nm, v, adv_h[v][0], adv_d[v][0], adv_h[v][1], adv_d[v][1], adv_h[v][2], adv_d[v][2],
                adv_h_shr[v][0], adv_d_shr[v][0], adv_h_shr[v][1], adv_d_shr[v][1], adv_h_shr[v][2], adv_d_shr[v][2]), UVM_LOW)
      foreach (q[i]) begin
        `uvm_info("RC_DL_FC", $sformatf("[FC_DL_TX] %s VC%0d %0d/6 : %s", nm, v, i+1, PCIe_sequence_item::fc_dllp_str(q[i])), UVM_LOW)
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
          `uvm_info("RC_DL_FC", $sformatf("[FC_DL_TX] UpdateFC VC%0d class %s : CREDITS_ALLOCATED %s=%0d %s=%0d :: %s",
                    vc, PCIe_sequence_item::fc_cls_name(c), PCIe_sequence_item::fc_hdr_name(c), adv_h[vc][c],
                    PCIe_sequence_item::fc_dat_name(c), adv_d[vc][c], PCIe_sequence_item::fc_dllp_str(v)), UVM_LOW)
          if (fc_multi_vc()) wait (fc_tx_allowed);
          fc_send_active(v);
          n_updfc_tx++;
        end
        if (pend_mask_shr[vc][c]) begin                            // [FC SHARED]
          pend_mask_shr[vc][c] = 1'b0;
          v = fc_build_shared(`PCIe_FC_TYPE_UPDATEFC, c, vc);
          `uvm_info("RC_DL_FC", $sformatf("[FC_DL_TX] UpdateFC-SHARED VC%0d class %s : SHARED CREDITS_ALLOCATED %s=%0d %s=%0d :: %s",
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
    `uvm_info("RC_DL_FC", "[FC_DL] DL_ACTIVE :: INITIAL UpdateFC (dedicated + shared) FOR P/NP/CPL (completes FC_INIT2 at the peer)", UVM_LOW)
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
    // [OPT_UPDATE_FC] DLP0[4] = 1 : Optimized_Update_FC (bit 31 = 0) or Flit_Marker (bit 31 = 1), not a DLLP
    if (dlp[0][4]) begin
      if (!v[31]) fc_rx_opt_update(v);
      return;
    end
    if (!PCIe_sequence_item::fc_is_dllp(v)) return;
    PCIe_sequence_item::fc_decode(v, typ, cls, shared, vc, hs, hfc, ds, dfc);
    `uvm_info("RC_DL_FC", $sformatf("[FC_DL_RX] %s", PCIe_sequence_item::fc_dllp_str(v)), UVM_LOW)
    // [TC_VC] OLD : if (vc != `PCIe_FC_VC0) return;   // only VC0 exists
    if (!fc_vc_on(vc)) begin
      n_fc_dllp_dis_vc++;
      `uvm_info("RC_DL_FC", $sformatf("[FC_DL_RX] VC%0d is not enabled on this Port -> FC DLLP ignored", vc), UVM_LOW)
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
        // [LOST_UPDATEFC] test knob : this Posted UpdateFC is "lost on the link"
        if (drop_p_updatefc && (c == 0)) begin
          n_p_updatefc_dropped++;
          `uvm_info("RC_DL_FC", $sformatf("[FC_DL_RX] TEST : UpdateFC%s VC%0d class P DROPPED (lost DLLP) :: %s",
                    shared ? "-SHARED" : "", vc, PCIe_sequence_item::fc_dllp_str(v)), UVM_NONE)
          return;
        end
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
    it.fc_origin = "RC_DL";
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
    `uvm_info("RC_DL_FC", $sformatf("[FC_DL->TL] %s VC%0d class %s : %s=%0d %s=%0d  (%s %s)",
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
                               bit is_retx  = 1'b0);   // [FLOW_SUM] 1 : replayed / duplicate flit
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
  // [FLOW_SUM] helpers + RC FLIT SUMMARY text
  //   The summary is printed at the end of the test by flit_summary_report()
  //   (called from report_phase of this DL model) :
  //     1. FLIT COUNT   2. SEQUENCE NUMBERS   3. ACK / NAK   4. REPLAY
  //     5. COMPLETIONS (from the RC TL model)  6. DL ERRORS LOGGED
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

  // ACK / NAK received from the EP. A flit repeats the same ACK/NAK until a new
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
      PCIe_flow_log::print("NAK", $sformatf("RC got %s NAK(%0d), lost seq %0d", (cmd == 2'b11) ? "SEL" : "STD", N, mod1023_add(N, 10'h1)));   // [FLOW]
    end
  endfunction

  // ACK / NAK put in a flit sent to the EP (only a NEW {command, seq num} is counted)
  function void note_acknak_sent(bit [`PCIe_SEQ_NUM_W-1:0] N, bit [`PCIe_REPLAY_CMD_W-1:0] cmd);
    int key;
    if (cmd == 2'b00) return;              // payload flit with its own sequence number
    key = int'({cmd, N});
    if (key == last_tx_acknak_key) return;
    last_tx_acknak_key = key;
    if (cmd == 2'b01) n_ack_sent++;
    else begin
      if (cmd == 2'b11) n_sel_nak_sent++;
      else              n_std_nak_sent++;
      nak_sent_lost_seq_q.push_back(mod1023_add(N, 10'h1));
      PCIe_flow_log::print("NAK", $sformatf("RC sent %s NAK(%0d), lost seq %0d", (cmd == 2'b11) ? "SEL" : "STD", N, mod1023_add(N, 10'h1)));   // [FLOW]
    end
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

  // Sections 1 .. 4 of the RC FLIT SUMMARY
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
    s = {s, sum_line("Last ACK received from EP", v),
            sum_line("RX payload flits accepted", $sformatf("%0d   (given to the RC TL)", n_rx_tlp_to_tl)),
            sum_line("RX payload flits dropped", $sformatf("%0d   (good flits not given to the TL)",
                     (rx_good > n_rx_tlp_to_tl) ? (rx_good - n_rx_tlp_to_tl) : 0))};
    if ((n_ack_sent + n_std_nak_sent + n_sel_nak_sent) == 0) v = "none yet";
    else v = $sformatf("seq %0d", TX_ACKNAK_FLIT_SEQ_NUM);
    s = {s, sum_line("Last ACK/NAK seq sent to EP", v), "\n"};

    // ---------------- 3. ACK / NAK ----------------
    s = {s, " 3. ACK / NAK  (a NEW ack/nak number is counted once)\n",
            "   Received from EP :\n",
            sum_line("ACK received", $sformatf("%0d", n_ack_rcvd)),
            sum_line("Standard NAK received", $sformatf("%0d", n_std_nak_rcvd)),
            sum_line("Selective NAK received", $sformatf("%0d", n_sel_nak_rcvd)),
            sum_line("Lost flits reported by these NAKs", seq_list_str(nak_rcvd_lost_seq_q)),
            sum_line("NAKs ignored (Nak Ignore Window)", $sformatf("%0d", n_nak_ignored)),
            sum_line("NAKs dropped by test (lost NAK)", $sformatf("%0d", n_naks_dropped)),
            "   Sent to EP :\n",
            sum_line("ACK sent", $sformatf("%0d", n_ack_sent)),
            sum_line("Standard NAK sent", $sformatf("%0d", n_std_nak_sent)),
            sum_line("Selective NAK sent", $sformatf("%0d", n_sel_nak_sent)),
            sum_line("Lost flits reported by these NAKs", seq_list_str(nak_sent_lost_seq_q)),
            "\n"};

    // ---------------- 4. REPLAY ----------------
    s = {s, " 4. REPLAY (RC -> EP)\n",
            sum_line("Standard replays (after NAK)", $sformatf("%0d", n_std_replay)),
            sum_line("Selective replays (after NAK)", $sformatf("%0d", n_sel_replay)),
            sum_line("Replay timer timeouts", $sformatf("%0d", n_replay_timeouts)),
            sum_line("Replayed seq numbers", seq_list_str(replayed_seq_q)),
            sum_line("Duplicate flits sent (test)", $sformatf("%0d", n_duplicate_flits_sent)),
            sum_line("REPLAY_NUM now / rollovers", $sformatf("%0d / %0d", FLIT_REPLAY_NUM, err_replay_num_rollover)),
            sum_line("Retry buffer : max used", $sformatf("%0d flits  (limit %0d)", max_tx_retry_used, TX_RETRY_BUFFER_MAX_FLITS)),
            sum_line("Retry buffer : at end", $sformatf("%0d flits", tx_retry_buffer.size())),
            sum_line("Retry buffer : full waits", $sformatf("%0d", n_tx_retry_buffer_full_waits)),
            "\n"};
    return s;
  endfunction

  // Section 6 of the RC FLIT SUMMARY
  function string flit_summary_errors();
    return {" 6. DL ERRORS LOGGED (Sec 6.2)\n",
            sum_line("Invalid flit (bad CRC/FEC)", $sformatf("%0d", err_invalid_flit)),
            sum_line("Replay timer timeout", $sformatf("%0d", err_replay_timer_timeout)),
            sum_line("REPLAY_NUM rollover", $sformatf("%0d", err_replay_num_rollover)),
            sum_line("DL protocol error", $sformatf("%0d", err_dl_protocol)),
            sum_line("Total DL errors", $sformatf("%0d", dl_error_total()))};
  endfunction

  // Section 5 of the RC FLIT SUMMARY : completions (numbers from the RC TL model)
  function string flit_summary_cpl(PCIe_RC_TL_model tl);
    int unsigned n_mrd, n_cfgrd, n_cfgwr;
    if (tl == null) return " 5. COMPLETIONS (RC side)\n  (RC TL model not found)\n\n";
    n_mrd   = flit_tx_new_cnt[FLTC_MRD];
    n_cfgrd = flit_tx_new_cnt[FLTC_CFGRD];
    n_cfgwr = flit_tx_new_cnt[FLTC_CFGWR];
    return {" 5. COMPLETIONS (RC side)\n",
            sum_line("Non-posted requests sent", $sformatf("%0d   (MemRd %0d, CfgRd %0d, CfgWr %0d)",
                     n_mrd + n_cfgrd + n_cfgwr, n_mrd, n_cfgrd, n_cfgwr)),
            sum_line("Completions received", $sformatf("%0d   (CplD %0d, Cpl %0d)",
                     tl.n_cpld_rcvd + tl.n_cpl_nodata_rcvd, tl.n_cpld_rcvd, tl.n_cpl_nodata_rcvd)),
            sum_line("Status  SC / UR / CA / CRS", $sformatf("%0d / %0d / %0d / %0d",
                     tl.n_cpl_status_rcvd[`PCIe_CPL_STATUS_SC], tl.n_cpl_status_rcvd[`PCIe_CPL_STATUS_UR],
                     tl.n_cpl_status_rcvd[`PCIe_CPL_STATUS_CA], tl.n_cpl_status_rcvd[`PCIe_CPL_STATUS_CRS])),
            sum_line("Read data DW match / mismatch", $sformatf("%0d / %0d",
                     tl.n_rd_cpl_dw_match, tl.n_rd_cpl_dw_mismatch)),
            sum_line("Still waiting (no completion)", $sformatf("%0d", tl.n_outstanding())),
            sum_line("Completion timeouts", $sformatf("%0d", tl.n_cpl_timeouts)),
            "\n"};
  endfunction

  // Prints the RC FLIT SUMMARY (called from report_phase).
  // The RC TL model is the sibling "rc_tl_model" in the same agent.
  function void flit_summary_report();
    PCIe_RC_TL_model tl;
    uvm_component    p;
    p = get_parent();
    if (p != null) void'($cast(tl, p.get_child("rc_tl_model")));
    `uvm_info("RC_FLIT_SUMMARY", {"\n==========================================================================\n",
                                  "                      RC FLIT SUMMARY  (end of test)\n",
                                  "==========================================================================\n",
                                  flit_summary_part1(),
                                  flit_summary_cpl(tl),
                                  flit_summary_errors(),
                                  "=========================================================================="}, UVM_NONE)
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("RC_DL_FC", $sformatf({"\n  ========== RC DL FLOW CONTROL SUMMARY ==========\n",
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
    flit_summary_report();   // [FLIT_CNT] [FLOW_SUM] RC FLIT SUMMARY (6 sections)

    // [REPLAY] summary
    `uvm_info("RC_DL_REPLAY", $sformatf({"\n",
        "  ========== RC DL REPLAY SUMMARY ==========\n",
        "    Standard replays            : %0d\n",
        "    Selective replays           : %0d\n",
        "    Replayed flits (total)      : %0d\n",
        "    Replayed flit seq numbers   : %p\n",
        "    TX retry buffer at end      : %0d (0 = every flit ACKed by EP)\n",
        "    Replay timer timeouts       : %0d\n",
        "    TLPs waited (buffer full)   : %0d\n",
        "    Duplicate flits sent (test) : %0d\n",
        "    Optimized_Update_FC rx      : %0d\n",
        "    P UpdateFC dropped (test)   : %0d\n",
        "    NAKs dropped (test)         : %0d\n",
        "  ERRORS LOGGED (Sec 6.2)\n",
        "    Invalid flit                : %0d\n",
        "    Replay Timer Timeout        : %0d\n",
        "    REPLAY_NUM Rollover         : %0d\n",
        "    Data Link Protocol Error    : %0d\n",
        "  =========================================="},
        n_std_replay, n_sel_replay, flit_tx_replay, replayed_seq_q, tx_retry_buffer.size(),
        n_replay_timeouts, n_tx_retry_buffer_full_waits, n_duplicate_flits_sent, n_opt_updfc_rx,
        n_p_updatefc_dropped, n_naks_dropped,
        err_invalid_flit, err_replay_timer_timeout, err_replay_num_rollover, err_dl_protocol), UVM_LOW)
  endfunction

   
endclass

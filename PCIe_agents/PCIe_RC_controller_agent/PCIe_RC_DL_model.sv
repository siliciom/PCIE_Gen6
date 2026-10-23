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
    localparam bit [31:0] FEATURE_DLLP = 32'h0100_0000;
   // localparam bit [31:0] INITFC1_DLLP = 32'h0200_0000;
    //localparam bit [31:0] INITFC2_DLLP = 32'h0300_0000;
        // ---- DLCMSM additions ----
    dl_state_e          DL_STATE = DL_INACTIVE;
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
    // --------------------------------------------------------------------

    // ---- FLOW CONTROL (dedicated + shared credits, VC0) ----------------------
    uvm_analysis_imp_fc_from_tl #(PCIe_sequence_item, PCIe_RC_DL_model) fc_tl_imp;  // TL -> DL : local credits
    uvm_analysis_port #(PCIe_sequence_item)                  fc_tl_ap;   // DL -> TL : peer credit limits
    int unsigned adv_h [3];          // local CREDITS_ALLOCATED to advertise (from the TL)
    int unsigned adv_d [3];
    bit          adv_valid;
    int unsigned peer_h [3];         // peer values = transmitter CREDIT_LIMIT (from InitFC / UpdateFC)
    int unsigned peer_d [3];
    bit          peer_hinf [3];
    bit          peer_dinf [3];
    bit          fi1_ded [3];        // FI1 : dedicated values recorded
    bit          fi1_shr [3];        // FI1 : shared values recorded (Flit Mode needs all six)
    bit          fi2;                // FI2
    bit [2:0]    pend_mask;          // classes that need an UpdateFC DLLP on the wire
    bit          peer_init_fwd [3];  // initial limit of the class already given to the TL
    // [FC SHARED] Flit Mode shared pool (same meaning as the dedicated fields above)
    int unsigned adv_h_shr [3];      // local shared CREDITS_ALLOCATED to advertise (from the TL)
    int unsigned adv_d_shr [3];
    int unsigned peer_h_shr [3];     // peer shared values = transmitter SHARED_CREDIT_LIMIT
    int unsigned peer_d_shr [3];
    bit          peer_hinf_shr [3];
    bit          peer_dinf_shr [3];
    bit          peer_init_fwd_shr [3];
    bit [2:0]    pend_mask_shr;      // classes that need an UpdateFC (shared) DLLP on the wire
    int unsigned n_updfc_tx_shr, n_updfc_rx_shr;
    bit          fc_tx_allowed = 1'b0;   // gate for DL-initiated DLLPs after DL_ACTIVE
    int unsigned n_initfc1_tx, n_initfc1_rx, n_initfc2_tx, n_initfc2_rx, n_updfc_tx, n_updfc_rx;

  function new(string name="PCIe_RC_DL_model",uvm_component parent);
    super.new(name,parent);
  endfunction


function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    tlp_dl_imp = new("tlp_dl_imp",this);
    dlp_pl_ap = new("dlp_pl_ap",this);
    dl_mon_242b_imp = new("dl_mon_242b_imp",this);
    rc_dl_tl_ap = new("rc_dl_tl_ap",this);
    dl_active_event = uvm_event_pool::get_global("dl_active_event");
    uvm_rc_l0_to_dl_ev = uvm_event_pool::get_global("rc_l0_to_dl_event");
    fc_tl_imp = new("fc_tl_imp", this);
    fc_tl_ap  = new("fc_tl_ap",  this);
    fc_dl_init();


  endfunction

// DL model consumes TL output, creates the DLP, then publishes to PL.
function void write(PCIe_sequence_item item);
  `uvm_info("RC_DL_MODEL","TL -> DL",UVM_LOW);
  // item.print();
  form_dl_packet(item.tlp_data,item.is_payload,item.dlp_flit_out);

  print_dlp_packet(item.tlp_data,item.dlp_flit_out);
  `uvm_info("RC_DL_MODEL","SENT_DLP_TO_PL_236B", UVM_LOW)
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
  // DLCMSM FSM — ADDED / ACTIVATED BLOCK
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

  task run_phase(uvm_phase phase);
     `uvm_info("RC_DLCMSM","[DLCMSM_TRACE] WAITING_FOR_rc_l0_to_dl_event (fired by PL model on LTSSM L0 entry)",UVM_LOW)
     forever begin
       //@(rc_l0_to_dl_event);
       uvm_rc_l0_to_dl_ev.wait_trigger();
      `uvm_info("RC_DLCMSM","DLCMSM_RC_TO_DL_EVENT_TRIGGRED",UVM_LOW)
        wait(phy_linkup == 1);
        `uvm_info("RC_DLCMSM","[DLCMSM_TRACE] rc_l0_to_dl_event_FIRED :: LTSSM_REACHED_L0 :: STARTING_DLCMSM_FSM",UVM_LOW)
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
        join_any
        disable fork;
        DL_STATE       = DL_INACTIVE;
        dl_link_active = 1'b0;
        `uvm_info("RC_DLCMSM","[DLCMSM_TRACE] phy_linkup=0 :: DL_RUN_TERMINATED :: WAITING_FOR_NEXT_LINKUP",UVM_LOW)
     end
  endtask

  task run_dl_data_processing();
     wait(dl_link_active);
     `uvm_info("RC_DL_PROC","[DL_DATA_PROC] DL_ACTIVE :: STARTING_ACK_NAK_REPLAY_PROCESSING",UVM_LOW)
     forever begin
        if (RC_REPLAY_IN_PROGRESS) begin
           `uvm_info("RC_DL_PROC","[DL_DATA_PROC] REPLAY_IN_PROGRESS :: REPLAYING_TX_RETRY_BUFFER",UVM_LOW)
           handle_replay_from_buffer();
        end
        else if (NAK_SCHEDULED) begin
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
     ctl_item = PCIe_sequence_item::type_id::create("ctl_item");
     form_dl_packet(ctl_item.tlp_data, 1'b0, ctl_item.dlp_flit_out);
     //dlp_pl_ap.write(ctl_item);
  endtask

  // Re-sends flits from the TX retry buffer that the peer has NAKed.
  // Standard replay: all flits with seq_num >= the replay start point.
  // Selective replay: only the single NAKed flit.
  task handle_replay_from_buffer();
     foreach (tx_retry_buffer[i]) begin
        if ((REPLAY_SCHEDULED_TYPE == STANDARD_REPLAY) &&
            (tx_retry_buffer[i].seq_num >= TX_REPLAY_FLIT_SEQ_NUM)) begin
           send_replayed_buffer_entry(i);
        end
        else if (REPLAY_SCHEDULED_TYPE == SELECTIVE_REPLAY) begin
           send_replayed_buffer_entry(i);
           break;
        end
     end
     RC_REPLAY_IN_PROGRESS = 1'b0;
  endtask

  // Re-forms a single retry-buffer entry as a payload flit and writes it to PL,
  // bypassing the TL (the original driver sent replays back through tx_ap).
  task send_replayed_buffer_entry(int unsigned idx);
     PCIe_sequence_item r_item;
     r_item = PCIe_sequence_item::type_id::create("r_item");
     r_item.tlp_data = tx_retry_buffer[idx].tlp_data;
     r_item.seq_num  = tx_retry_buffer[idx].seq_num;
     form_dl_packet(r_item.tlp_data, 1'b1, r_item.dlp_flit_out);
     `uvm_info("RC_DL_MODEL",$sformatf("SENDING_DLP_TO_PL_MODEL"),UVM_LOW)
     //dlp_pl_ap.write(r_item);
  endtask

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
      for (int w = 0; w < 100 && !fi1_done(); w++) #1ns;
      `uvm_info("RC_DLCMSM",$sformatf(
         "[DL_INIT.FC_INIT1] ROUND_%0d_DONE :: FI1 dedicated P/NP/CPL=%0b%0b%0b shared P/NP/CPL=%0b%0b%0b",
         fc1_sent_count, fi1_ded[0], fi1_ded[1], fi1_ded[2],
         fi1_shr[0], fi1_shr[1], fi1_shr[2]),UVM_LOW)
      if (fi1_done()) begin
         `uvm_info("RC_DLCMSM",$sformatf(
            "[DL_INIT.FC_INIT1] FI1_SET :: peer credits recorded PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d :: TRANSITION -> DL_INIT.FC_INIT2",
            peer_h[0], peer_d[0], peer_h[1], peer_d[1], peer_h[2], peer_d[2]),UVM_LOW)
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
      `uvm_info("RC_DLCMSM",$sformatf("[DL_INIT.FC_INIT2] ROUND_%0d_DONE :: FI2=%0b",fc2_sent_count,fi2_done()),UVM_LOW)
      if (fi2_done()) begin
         `uvm_info("RC_DLCMSM","[DL_INIT.FC_INIT2] FI2_SET :: TRANSITION -> DL_ACTIVE",UVM_LOW)
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
       dcm_item = PCIe_sequence_item::type_id::create("dcm_item");
       dllp_content = content;
       form_dl_packet(dcm_item.tlp_data, 1'b0, dcm_item.dlp_flit_out); // is_payload=0
       // dllp_content belongs to THIS flit only. Clear it so it does not leak
       // into the TLP flit that write() forms after DL_ACTIVE (DLP2-DLP5 of a
       // TLP flit must stay 0, exactly as before the DLCMSM packets were driven).
       dllp_content = '0;

       //print_dlp_packet(tlp_data,dlp);
       dllp_tx_pending = 1'b1;
       dlp_pl_ap.write(dcm_item);   // actually push this DLLP-only flit out to the PL model
       `uvm_info("RC_DLCMSM",$sformatf("SENT_DLLP_FLIT content=%08h :: WAITING_FOR_DRIVER_TO_DRIVE_IT_ON_PIPE",content),UVM_LOW)
       wait (dllp_tx_pending == 1'b0);
       `uvm_info("RC_DLCMSM",$sformatf("DLLP_FLIT_DRIVEN_ON_PIPE content=%08h",content),UVM_LOW)
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
  task form_dl_packet(input bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_data,input bit is_payload,output bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] dl_flit_out);

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
    if((replay_command == 2'b00) && is_payload) begin
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

    store_tx_retry_buffer(tlp_data,seq_num_to_send);
  endtask

  
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
    `uvm_info("RC_DL_MODEL","ERROR: Data Link Protocol Error Logged",UVM_LOW);
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

    // ============================================================
    // 1. Collect complete 242-byte flit
    // ============================================================

    rc_rx_242b_flit_q.push_back(item.dlp_flit_out);
    rc_rx_flit_is_valid_q.push_back(item.is_valid);
    rc_rx_242b_flit_cnt++;

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

    is_ack = 1'b0;
    is_nak = 1'b0;

    if(replay_cmd == 2'b01)
      is_ack = 1'b1;
    else if(replay_cmd == 2'b10) begin
      is_nak = 1'b1;
      REPLAY_SCHEDULED_TYPE = STANDARD_REPLAY;
    end
    else if(replay_cmd == 2'b11) begin
      is_nak = 1'b1;
      REPLAY_SCHEDULED_TYPE = SELECTIVE_REPLAY;
    end

    // ACK/NAK with Sequence Number 0 must be ignored
    if(N == '0)
      return;

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

    purge_tx_retry_buffer(N);

    if(mod1023_sub(N,ACKD_FLIT_SEQ_NUM) > 0) begin
      FLIT_REPLAY_NUM = '0;
      ACKD_FLIT_SEQ_NUM = N;
    end

    if(is_ack) begin
      NAK_IGNORE_FLIT_SEQ_NUM = '0;

      if(mod1023_sub(N,TX_REPLAY_FLIT_SEQ_NUM) < MAX_UNACKNOWLEDGED_FLITS)
        TX_REPLAY_FLIT_SEQ_NUM = '0;
    end
    else if(is_nak) begin
      `uvm_info("RC_DL_MODEL","Entered the nak logic",UVM_LOW);

      if(N == mod1023_sub(NEXT_TX_FLIT_SEQ_NUM,{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1}))
        NAK_IGNORE_FLIT_SEQ_NUM = N;
      else if(N != NAK_IGNORE_FLIT_SEQ_NUM)
        NAK_IGNORE_FLIT_SEQ_NUM = '0;

      schedule_replay(N+{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1});
    end
  endtask


  // Modulo 1023 check: Is sequence S older than or including N?
  function automatic bit is_older_than_or_including(bit [`PCIe_SEQ_NUM_W-1:0] S,bit [`PCIe_SEQ_NUM_W-1:0] N);
    return (mod1023_sub(N,S) <= MAX_UNACKNOWLEDGED_FLITS);
  endfunction


  task purge_tx_retry_buffer(bit [`PCIe_SEQ_NUM_W-1:0] N);
    `uvm_info("RC_DL_MODEL",$sformatf("PURGING: Entry size of buffer :: %d",tx_retry_buffer.size()),UVM_LOW);

    while(tx_retry_buffer.size() > 0) begin
      bit [`PCIe_SEQ_NUM_W-1:0] S = tx_retry_buffer[0].seq_num;

      `uvm_info("RC_DL_MODEL",$sformatf("Sequence number flit deleted from the buffer is ::S=%d, tx_retry_buffer=%p",S,tx_retry_buffer),UVM_LOW);

      if(is_older_than_or_including(S,N))
        tx_retry_buffer.pop_front();
      else
        break;
    end

    `uvm_info("RC_DL_MODEL",$sformatf("PURGING: Final buffer size is %d",tx_retry_buffer.size()),UVM_LOW);
  endtask


  task schedule_replay(bit [`PCIe_SEQ_NUM_W-1:0] start_seq);
    `uvm_info("RC_DL_MODEL","Entered the replay schedule task_",UVM_LOW);

    REPLAY_SCHEDULED = 1'b1;
    RC_REPLAY_IN_PROGRESS = 1'b1;
    TX_REPLAY_FLIT_SEQ_NUM = start_seq;
  endtask


  // Storing the tx_retry_buffer
  task store_tx_retry_buffer(input bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_data,input bit [`PCIe_SEQ_NUM_W-1:0] seq_num);
    tx_retry_buffer.push_back('{tlp_data:tlp_data,seq_num:seq_num});
  //  `uvm_info("RC_DL_MODEL",$sformatf("The Retry Buffer Content is %p",tx_retry_buffer),UVM_LOW);
  endtask


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
  // FLOW CONTROL  (PCIe Base 6.0 Sec 3.4 / Sec 2.6)  -  DEDICATED + SHARED credits, VC0
  //
  //   TL -> DL : write_fc_from_tl()  local credits  PH PD NPH NPD CPLH CPLD
  //                                  dedicated AND shared (printed as the TL sent them)
  //   [FC SHARED] InitFC rounds carry the real shared values (not 0 any more),
  //   UpdateFC is sent for the dedicated and/or the shared pool, and the peer
  //   shared values are forwarded to the TL (SHARED_CREDIT_LIMIT).
  //   DL -> PL : InitFC1 / InitFC2 rounds (6 DLLPs each in Flit Mode) during
  //              DL_INIT, UpdateFC DLLPs during DL_ACTIVE
  //   PL -> DL : fc_rx_flit()        peer InitFC / UpdateFC  ==> CREDIT_LIMIT,
  //                                  handed to the TL through fc_tl_ap
  //   DLLP layout / encode / decode helpers are static functions of PCIe_sequence_item
  //   index 0 = P, 1 = NP, 2 = CPL
  // =========================================================================
  function void fc_dl_init();
    for (int c = 0; c < 3; c++) begin
      adv_h[c] = 0; adv_d[c] = 0;
      peer_h[c] = 0; peer_d[c] = 0; peer_hinf[c] = 0; peer_dinf[c] = 0;
      fi1_ded[c] = 0; fi1_shr[c] = 0; peer_init_fwd[c] = 0;
      adv_h_shr[c] = 0; adv_d_shr[c] = 0;                                           // [FC SHARED]
      peer_h_shr[c] = 0; peer_d_shr[c] = 0; peer_hinf_shr[c] = 0; peer_dinf_shr[c] = 0;
      peer_init_fwd_shr[c] = 0;
    end
    fi2 = 0; adv_valid = 0; pend_mask = 3'b000; pend_mask_shr = 3'b000;
    n_initfc1_tx = 0; n_initfc1_rx = 0; n_initfc2_tx = 0; n_initfc2_rx = 0; n_updfc_tx = 0; n_updfc_rx = 0;
    n_updfc_tx_shr = 0; n_updfc_rx_shr = 0;
  endfunction

  // link (re)training : restart only the handshake flags, keep local values
  function void fc_restart_init();
    for (int c = 0; c < 3; c++) begin fi1_ded[c] = 0; fi1_shr[c] = 0; peer_init_fwd[c] = 0; peer_init_fwd_shr[c] = 0; end
    fi2 = 0;
    pend_mask = 3'b000; pend_mask_shr = 3'b000;
  endfunction

  // Flit Mode : FI1 is Set once all SIX FC unit values were recorded (Sec 3.4.2)
  function bit fi1_done();
    return fi1_ded[0] && fi1_ded[1] && fi1_ded[2] && fi1_shr[0] && fi1_shr[1] && fi1_shr[2];
  endfunction
  // FI2 is Set on ANY InitFC2, ANY UpdateFC or ANY TLP on VC0
  function bit fi2_done(); return fi2; endfunction

  function void write_fc_from_tl(PCIe_sequence_item it);
    `uvm_info("RC_DL_FC", $sformatf("[FC_TL->DL] %s :: DL_EXTRACTED %s  (from %s, reason=%s)",
              it.fc_kind.name(), it.fc_values_str(), it.fc_origin, it.fc_reason), UVM_LOW)
    if (it.fc_kind == FC_ADV_INIT || it.fc_kind == FC_ADV_UPDATE) begin
      for (int c = 0; c < 3; c++)
        begin
          if (it.fc_cls_mask[c]) begin
            adv_h[c] = it.fc_hdr[c];
            adv_d[c] = it.fc_dat[c];
            adv_valid = 1'b1;
          end
          if (it.fc_cls_mask_shr[c]) begin                       // [FC SHARED]
            adv_h_shr[c] = it.fc_hdr_shr[c];
            adv_d_shr[c] = it.fc_dat_shr[c];
          end
          // [FC SHARED] each value must fit its DLLP field (HdrFC 8 bit, DataFC 12 bit)
          if (adv_h[c] >= 256 || adv_d[c] >= 4096 || adv_h_shr[c] >= 256 || adv_d_shr[c] >= 4096)
            `uvm_error("RC_DL_FC", $sformatf("ADVERTISED_CREDITS_DO_NOT_FIT_DLLP_FIELD class %0d : ded %0d/%0d shr %0d/%0d",
                       c, adv_h[c], adv_d[c], adv_h_shr[c], adv_d_shr[c]))
        end
      if (it.fc_kind == FC_ADV_UPDATE) begin
        pend_mask     |= it.fc_cls_mask;
        pend_mask_shr |= it.fc_cls_mask_shr;                     // [FC SHARED]
      end
    end
  endfunction

  // dedicated FC DLLP of class c carrying the credits the TL advertised
  function bit [31:0] fc_build_dedicated(bit [1:0] typ, int unsigned c);
    return PCIe_sequence_item::fc_encode(typ, c[1:0], 1'b0, `PCIe_FC_VC0,
                                         `PCIe_FC_SCALE_1X, adv_h[c][7:0],
                                         `PCIe_FC_SCALE_1X, adv_d[c][11:0]);
  endfunction

  // [FC SHARED] shared FC DLLP of class c carrying the shared credits the TL advertised
  function bit [31:0] fc_build_shared(bit [1:0] typ, int unsigned c);
    return PCIe_sequence_item::fc_encode(typ, c[1:0], 1'b1, `PCIe_FC_VC0,
                                         `PCIe_FC_SCALE_1X, adv_h_shr[c][7:0],
                                         `PCIe_FC_SCALE_1X, adv_d_shr[c][11:0]);
  endfunction

  // RC : the PL model has no queue, so the flit is handed over with the same
  // handshake the DLCMSM uses; the RC controller driver puts it on the PIPE and
  // clears dllp_tx_pending (see PCIe_RC_controller_driver).
  task fc_send_active(bit [31:0] content);
    send_dllp_flit(content);
  endtask

  // One complete InitFC round. Flit Mode : P / NP / Cpl dedicated, then P / NP / Cpl shared.
  task fc_send_init_round(bit [1:0] typ);
    bit [31:0] q[$];
    string nm;
    nm = PCIe_sequence_item::fc_type_name(typ);
    if (!adv_valid)
      `uvm_warning("RC_DL_FC", "InitFC round started before the TL advertised its credits")
    for (int c = 0; c < 3; c++) q.push_back(fc_build_dedicated(typ, c));
    for (int c = 0; c < 3; c++) q.push_back(fc_build_shared(typ, c));     // [FC SHARED]
    `uvm_info("RC_DL_FC", $sformatf("[FC_DL_TX] %s ROUND :: advertising  DED: PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d  SHR: PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d",
              nm, adv_h[0], adv_d[0], adv_h[1], adv_d[1], adv_h[2], adv_d[2],
              adv_h_shr[0], adv_d_shr[0], adv_h_shr[1], adv_d_shr[1], adv_h_shr[2], adv_d_shr[2]), UVM_LOW)
    foreach (q[i]) begin
      `uvm_info("RC_DL_FC", $sformatf("[FC_DL_TX] %s %0d/6 : %s", nm, i+1, PCIe_sequence_item::fc_dllp_str(q[i])), UVM_LOW)
      send_dllp_flit(q[i]);
      if (typ == `PCIe_FC_TYPE_INITFC1) n_initfc1_tx++; else n_initfc2_tx++;
    end
  endtask

  // UpdateFC for every class that is pending (dedicated and / or shared)
  task fc_send_pending_updates();
    bit [31:0] v;
    for (int c = 0; c < 3; c++) begin
      if (pend_mask[c]) begin
        pend_mask[c] = 1'b0;
        v = fc_build_dedicated(`PCIe_FC_TYPE_UPDATEFC, c);
        `uvm_info("RC_DL_FC", $sformatf("[FC_DL_TX] UpdateFC class %s : CREDITS_ALLOCATED %s=%0d %s=%0d :: %s",
                  PCIe_sequence_item::fc_cls_name(c), PCIe_sequence_item::fc_hdr_name(c), adv_h[c],
                  PCIe_sequence_item::fc_dat_name(c), adv_d[c], PCIe_sequence_item::fc_dllp_str(v)), UVM_LOW)
        fc_send_active(v);
        n_updfc_tx++;
      end
      if (pend_mask_shr[c]) begin                                // [FC SHARED]
        pend_mask_shr[c] = 1'b0;
        v = fc_build_shared(`PCIe_FC_TYPE_UPDATEFC, c);
        `uvm_info("RC_DL_FC", $sformatf("[FC_DL_TX] UpdateFC-SHARED class %s : SHARED CREDITS_ALLOCATED %s=%0d %s=%0d :: %s",
                  PCIe_sequence_item::fc_cls_name(c), PCIe_sequence_item::fc_hdr_name(c), adv_h_shr[c],
                  PCIe_sequence_item::fc_dat_name(c), adv_d_shr[c], PCIe_sequence_item::fc_dllp_str(v)), UVM_LOW)
        fc_send_active(v);
        n_updfc_tx_shr++;
      end
    end
  endtask

  // Runs in parallel with the DLCMSM. When the TL scheduled an UpdateFC (or
  // DL_ACTIVE was just entered) it forms and sends the DLLP. The first UpdateFC
  // after DL_ACTIVE also satisfies the peer's FI2.
  task run_fc_update_loop();
    wait (dl_link_active);
    pend_mask     = 3'b111;
    pend_mask_shr = 3'b111;                                      // [FC SHARED]
    `uvm_info("RC_DL_FC", "[FC_DL] DL_ACTIVE :: INITIAL UpdateFC (dedicated + shared) FOR P/NP/CPL (completes FC_INIT2 at the peer)", UVM_LOW)
    forever begin
      if ((pend_mask != 3'b000 || pend_mask_shr != 3'b000) && fc_tx_allowed) fc_send_pending_updates();
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
    // Spec 3.4.2 : any TLP received on the VC also sets FI2
    if (dlp[0][7:6] == 2'b01) fi2 = 1'b1;
    v = {dlp[2], dlp[3], dlp[4], dlp[5]};
    if (!PCIe_sequence_item::fc_is_dllp(v)) return;
    PCIe_sequence_item::fc_decode(v, typ, cls, shared, vc, hs, hfc, ds, dfc);
    `uvm_info("RC_DL_FC", $sformatf("[FC_DL_RX] %s", PCIe_sequence_item::fc_dllp_str(v)), UVM_LOW)
    if (vc != `PCIe_FC_VC0) return;                 // only VC0 exists
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
          peer_h_shr[c] = hfc; peer_hinf_shr[c] = hinf;
          peer_d_shr[c] = dfc; peer_dinf_shr[c] = dinf;
          fi1_shr[c] = 1'b1;
          fwd = 1'b1;
        end
        else begin
          peer_h[c] = hfc; peer_hinf[c] = hinf;
          peer_d[c] = dfc; peer_dinf[c] = dinf;
          fi1_ded[c] = 1'b1;
          fwd = 1'b1;
        end
        if (typ == `PCIe_FC_TYPE_INITFC2) fi2 = 1'b1;
      end
      `PCIe_FC_TYPE_UPDATEFC: begin
        if (shared) n_updfc_rx_shr++; else n_updfc_rx++;
        fi2 = 1'b1;
        if (!shared) begin
          peer_h[c] = hfc; peer_hinf[c] = hinf;
          peer_d[c] = dfc; peer_dinf[c] = dinf;
          //fwd = 1'b1;
          //upd = 1'b1;
        end
        else begin                                  // [FC SHARED]
          peer_h_shr[c] = hfc; peer_hinf_shr[c] = hinf;
          peer_d_shr[c] = dfc; peer_dinf_shr[c] = dinf;
        end
        fwd = 1'b1;
        upd = 1'b1;
      end
      default: ;
    endcase
    if (!fwd) return;
    if (!upd) begin
      if (shared) begin                                          // [FC SHARED]
        if (peer_init_fwd_shr[c]) return;  // initial shared limit already applied
        peer_init_fwd_shr[c] = 1'b1;
      end
      else begin
        if (peer_init_fwd[c]) return;      // initial limit already applied
        peer_init_fwd[c] = 1'b1;
      end
    end
    it = PCIe_sequence_item::type_id::create("fc_peer_item");
    it.fc_kind   = upd ? FC_PEER_UPDATE : FC_PEER_INIT;
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
    `uvm_info("RC_DL_FC", $sformatf("[FC_DL->TL] %s class %s : %s=%0d %s=%0d  (%s %s)",
              it.fc_kind.name(), PCIe_sequence_item::fc_cls_name(c),
              PCIe_sequence_item::fc_hdr_name(c), hfc, PCIe_sequence_item::fc_dat_name(c), dfc,
              PCIe_sequence_item::fc_type_name(typ), shared ? "SHARED" : "DEDICATED"), UVM_LOW)
    fc_tl_ap.write(it);
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("RC_DL_FC", $sformatf({"\n  ========== RC DL FLOW CONTROL SUMMARY ==========\n",
        "  local credits (from TL) dedicated : PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d\n",
        "  local credits (from TL) shared    : PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d\n",
        "  peer credits (from DLLP) dedicated: PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d\n",
        "  peer credits (from DLLP) shared   : PH=%0d PD=%0d | NPH=%0d NPD=%0d | CPLH=%0d CPLD=%0d\n",
        "  InitFC1 tx/rx=%0d/%0d  InitFC2 tx/rx=%0d/%0d  UpdateFC tx/rx=%0d/%0d  UpdateFC-SHR tx/rx=%0d/%0d  FI1=%0b FI2=%0b"},
        adv_h[0], adv_d[0], adv_h[1], adv_d[1], adv_h[2], adv_d[2],
        adv_h_shr[0], adv_d_shr[0], adv_h_shr[1], adv_d_shr[1], adv_h_shr[2], adv_d_shr[2],
        peer_h[0], peer_d[0], peer_h[1], peer_d[1], peer_h[2], peer_d[2],
        peer_h_shr[0], peer_d_shr[0], peer_h_shr[1], peer_d_shr[1], peer_h_shr[2], peer_d_shr[2],
        n_initfc1_tx, n_initfc1_rx, n_initfc2_tx, n_initfc2_rx, n_updfc_tx, n_updfc_rx,
        n_updfc_tx_shr, n_updfc_rx_shr,
        fi1_done(), fi2_done()), UVM_LOW)
  endfunction

    // =========================================================================
    // TASK 2: Background keep-alive loop that automatically runs during DL_Active
    // =========================================================================
    /*task automatic run_updatefc_loop();
        bit [31:0] tx_payload;
        bit        opt_flag;

        `uvm_info("DL_FC", "Periodic UpdateFC loop started successfully!", UVM_LOW)

        forever begin
            #30us; // Strict spec keep-alive timing rule to prevent link timeouts [4]
            
            if (!EP_REPLAY_IN_PROGRESS) begin
                // Recalculate remaining buffer space and get updated payload
                calculate_and_build_updatefc(tx_payload, opt_flag);

                // Load directly into your DL model transmit registers
                dllp_content        = tx_payload; // Assign 32-bit payload (DLP2..5)
                credit              = 1'b1;       // Set flag to tell TX driver to inject DLLP
                credit_is_optimized = opt_flag;   // Selects Optimized format type
                
                `uvm_info("DL_FC", $sformatf("Transmitted UpdateFC: %h (Buffer Slots Occupied: %0d)", 
                          tx_payload, rx_retry_buffer.size()), UVM_MEDIUM)
            end
        end
    endtask*/ 

endclass

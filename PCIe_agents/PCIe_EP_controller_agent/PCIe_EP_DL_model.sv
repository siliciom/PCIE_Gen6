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

class PCIe_EP_DL_model extends uvm_component;

  `uvm_component_utils(PCIe_EP_DL_model)

  // TL -> DL and DL -> PL TLM connections.
  uvm_analysis_imp #(PCIe_sequence_item,PCIe_EP_DL_model) dl_imp;
  uvm_analysis_port #(PCIe_sequence_item) dl_ap;

  bit [31:0] dllp_content;
  bit [`PCIe_DLP_FLIT_BYTE_W-1:0][`PCIe_BYTE_W-1:0] dl_flit_out;
  bit success;
  bit [`PCIe_DLP_FLIT_BYTE_W-1:0][`PCIe_BYTE_W-1:0] current_flit_data;
  bit received_explicit_seq;
  bit [`PCIe_REPLAY_CMD_W-1:0] replay_cmd;
  bit [`PCIe_SEQ_NUM_W-1:0] last_sent;


  bit [`PCIe_DLP_FLIT_BYTE_W-1:0][`PCIe_BYTE_W-1:0] rx_retry_buffer[$];
  tx_buffer_t tx_retry_buffer[$];

  // ---- LCRC additions: mode awareness (mirrors PL model pattern) ----
  // Per-transaction mode comes from item.pkt_mode in write() and check_lcrc_on_rx()
  PCIe_env_config   pcie_ecfg;
  // ---------------------------------------------------------------

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
  bit STANDARD_NAK;
  bit NAK_WITHDRAWAL_ALLOWED;
  bit EP_REPLAY_IN_PROGRESS;

  bit last_flit_was_payload;
  bit credit;
  bit form_dlp_flit;

   // Simplified DLLP content encodings for DLCMSM simulation
    localparam bit [31:0] FEATURE_DLLP = 32'h0100_0000;
    localparam bit [31:0] INITFC1_DLLP = 32'h0200_0000;
    localparam bit [31:0] INITFC2_DLLP = 32'h0300_0000;
        // ---- DLCMSM additions ----
    dl_state_e          DL_STATE = DL_INACTIVE;
    dl_init_substate_e  dl_init_substate;
    //event               ep_l0_to_dl_event;   // fired by PL model when LTSSM reaches L0
    int                 fc1_sent_count, fc1_rcvd_count;
    int                 fc2_sent_count, fc2_rcvd_count;
    bit                 phy_linkup;      
    bit                 link_enabled = 1'b1;

    // ---- DLCMSM FSM additions (dependency-driven, mirrors LTSSM style) ----
    // Named, single-source-of-truth completion targets — no magic numbers
    // scattered in a bare while() loop, referenced by every debug print below.
    localparam int NUM_INITFC1_DLLP = 4;   // FC_INIT1 is "done" once this many INITFC1 DLLPs sent
    localparam int NUM_INITFC2_DLLP = 4;   // FC_INIT2 is "done" once this many INITFC2 DLLPs sent
   // event dl_active_event;                  // fires once, the instant DL_ACTIVE is entered
    bit   dl_link_active;                   // stays 1 while in DL_ACTIVE - TL/driver can gate on this
    // --------------------------------------------------------------------

  function new(string name = "PCIe_RC_DL_model", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    dl_imp = new("dl_imp", this);
    dl_ap = new("dl_ap", this);
  //   if (!uvm_config_db#(event)::get(this, "", "PCIE_ep_l0_to_dl_event", ep_l0_to_dl_event))
   //   `uvm_fatal("EVENT","ep_l0_to_dl_event not found") 

    // ---- LCRC additions: mode comes from transaction (item.pkt_mode) in write() and check_lcrc_on_rx() ----
    if (!uvm_config_db#(PCIe_env_config)::get(this, "", "PCIe_env_config", pcie_ecfg))
      `uvm_fatal("EP_DL_MODEL","Cannot_get_PCIe_env_config");
    `uvm_info("EP_DL_MODEL","LCRC_MODE_PER_TRANSACTION_FROM_ITEM_PKT_MODE",UVM_LOW)
    // ------------------------------------------------------------------

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
  // LCRC LOGIC — ADDED BLOCK (Gen5 non-flit + Gen6 flit, shared CRC-32 core)
  // Polynomial 0x04C11DB7 (reflected form 0xEDB88320), init all-1s,
  // final complement. Identical algorithm to Ethernet FCS / standard PCIe LCRC.
  // =========================================================================

  // ---- Core byte-serial CRC-32 update ----
  function automatic bit [31:0] lcrc_byte_update(bit [31:0] crc_in, bit [7:0] data_byte);
    bit [31:0] crc;
    bit [7:0]  b;
    crc = crc_in;
    b   = data_byte;
    for (int i = 0; i < 8; i++) begin
      if ((crc[0] ^ b[0]) == 1'b1)
        crc = (crc >> 1) ^ 32'hEDB88320;
      else
        crc = crc >> 1;
      b = b >> 1;
    end
    return crc;
  endfunction

  // ---- FLIT MODE (Gen6) LCRC generate: covers full 242-byte flit ----
  function automatic bit [`PCIe_DL_LCRC_W-1:0] generate_lcrc_flit(
    input bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] flit_data
  );
    bit [31:0] crc;
    crc = 32'hFFFF_FFFF;

    `uvm_info("LCRC_FLIT_MODE",
      $sformatf("FLIT_LCRC :: STARTING :: bytes_to_cover=%0d",`PCIe_DLP_FLIT_BYTE_W),UVM_LOW)

    for (int i = 0; i < `PCIe_DLP_FLIT_BYTE_W; i++) begin
      crc = lcrc_byte_update(crc, flit_data[i]);
      `uvm_info("LCRC_FLIT_MODE",
        $sformatf("FLIT_LCRC :: byte[%0d]=%02h :: running_crc=%08h",i,flit_data[i],crc),
        UVM_HIGH)
    end

    crc = ~crc;
    `uvm_info("LCRC_FLIT_MODE",
      $sformatf("FLIT_LCRC :: GENERATED :: FINAL_LCRC=%08h",crc),UVM_LOW)
    return crc;
  endfunction

  // ---- NON-FLIT MODE (Gen5/legacy) LCRC generate: covers only valid TLP bytes ----
  function automatic bit [`PCIe_DL_LCRC_W-1:0] generate_lcrc_non_flit(
    input bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_data,
    input int unsigned tlp_byte_len
  );
    bit [31:0] crc;
    crc = 32'hFFFF_FFFF;

    `uvm_info("LCRC_NONFLIT_MODE",
      $sformatf("NONFLIT_LCRC :: STARTING :: bytes_to_cover=%0d",tlp_byte_len),UVM_LOW)

    for (int i = 0; i < tlp_byte_len; i++) begin
      crc = lcrc_byte_update(crc, tlp_data[i]);
      `uvm_info("LCRC_NONFLIT_MODE",
        $sformatf("NONFLIT_LCRC :: byte[%0d]=%02h :: running_crc=%08h",i,tlp_data[i],crc),
        UVM_HIGH)
    end

    crc = ~crc;
    `uvm_info("LCRC_NONFLIT_MODE",
      $sformatf("NONFLIT_LCRC :: GENERATED :: bytes_covered=%0d :: FINAL_LCRC=%08h",
                tlp_byte_len,crc),UVM_LOW)
    return crc;
  endfunction

  // ---- RX-side compare (works for either mode) ----
  function automatic bit lcrc_check(bit [`PCIe_DL_LCRC_W-1:0] computed_crc,
                                     bit [`PCIe_DL_LCRC_W-1:0] received_crc,
                                     string mode_tag);
    bit pass;
    pass = (computed_crc == received_crc);
    if (pass)
      `uvm_info({"LCRC_CHECK_",mode_tag},
        $sformatf("LCRC_MATCH :: computed=%08h received=%08h",computed_crc,received_crc),UVM_LOW)
    else
      `uvm_error({"LCRC_CHECK_",mode_tag},
        $sformatf("LCRC_MISMATCH :: computed=%08h received=%08h",computed_crc,received_crc))
    return pass;
  endfunction
  // =========================================================================
  // END LCRC LOGIC BLOCK
  // =========================================================================

  // =========================================================================
  // DLCMSM FSM — ADDED / ACTIVATED BLOCK
  // Mirrors PCIe_RC_DL_model's DLCMSM implementation exactly (EP side).
  // Dependency chain enforced:
  //   DL_INACTIVE  --(phy_linkup && link_enabled)-->  DL_FEATURE
  //   DL_FEATURE   --(FEATURE_DLLP sent)-->            DL_INIT.FC_INIT1
  //   FC_INIT1     --(fc1_sent_count >= NUM_INITFC1_DLLP)--> FC_INIT2
  //   FC_INIT2     --(fc2_sent_count >= NUM_INITFC2_DLLP)--> DL_ACTIVE
  //   DL_ACTIVE    --> dl_link_active=1, dl_active_event fires -> TL may send TLPs
  // =========================================================================

  task run_phase(uvm_phase phase);
     `uvm_info("EP_DLCMSM","[DLCMSM_TRACE] WAITING_FOR_ep_l0_to_dl_event (fired by PL model on LTSSM L0 entry)",UVM_LOW)
     forever begin
        //@(ep_l0_to_dl_event);
         wait(phy_linkup == 1);
        `uvm_info("EP_DLCMSM","[DLCMSM_TRACE] ep_l0_to_dl_event_FIRED :: LTSSM_REACHED_L0 :: STARTING_DLCMSM_FSM",UVM_LOW)
        DL_STATE       = DL_INACTIVE;
        dl_link_active = 1'b0;
        fc1_sent_count = 0;
        fc2_sent_count = 0;
        run_dlcmsm();
     end
  endtask

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
       send_dllp_flit(INITFC1_DLLP);
       fc1_sent_count++;
       `uvm_info("EP_DLCMSM",$sformatf(
          "[DL_INIT.FC_INIT1] INITFC1_DLLP_SENT :: fc1_sent_count=%0d / target=%0d",
          fc1_sent_count, NUM_INITFC1_DLLP),UVM_LOW)

       if (fc1_sent_count >= NUM_INITFC1_DLLP) begin
          `uvm_info("EP_DLCMSM",$sformatf(
             "[DL_INIT.FC_INIT1] TARGET_REACHED(%0d/%0d) :: TRANSITION -> DL_INIT.FC_INIT2",
             fc1_sent_count, NUM_INITFC1_DLLP),UVM_LOW)
          dl_init_substate = INIT_FC2;
       end
       else begin
          `uvm_info("EP_DLCMSM","[DL_INIT.FC_INIT1] TARGET_NOT_REACHED :: STAYING_IN_FC_INIT1",UVM_LOW)
       end
    endtask

    // ---------------- DL_INIT : FC_INIT2 ----------------
    task dlcmsm_state_init_fc2();
       send_dllp_flit(INITFC2_DLLP);
       fc2_sent_count++;
       `uvm_info("EP_DLCMSM",$sformatf(
          "[DL_INIT.FC_INIT2] INITFC2_DLLP_SENT :: fc2_sent_count=%0d / target=%0d",
          fc2_sent_count, NUM_INITFC2_DLLP),UVM_LOW)

       if (fc2_sent_count >= NUM_INITFC2_DLLP) begin
          `uvm_info("EP_DLCMSM",$sformatf(
             "[DL_INIT.FC_INIT2] TARGET_REACHED(%0d/%0d) :: TRANSITION -> DL_ACTIVE",
             fc2_sent_count, NUM_INITFC2_DLLP),UVM_LOW)
          DL_STATE = DL_ACTIVE;
       end
       else begin
          `uvm_info("EP_DLCMSM","[DL_INIT.FC_INIT2] TARGET_NOT_REACHED :: STAYING_IN_FC_INIT2",UVM_LOW)
       end
    endtask

    // ---------------- DL_ACTIVE ----------------
    task dlcmsm_state_dl_active();
       dl_link_active = 1'b1;
       //-> dl_active_event;
       `uvm_info("EP_DLCMSM",
          "[DL_ACTIVE] dl_link_active=1 :: dl_active_event_TRIGGERED :: TL_MAY_NOW_SEND_TLPs",UVM_LOW)
    endtask

    // Builds a NOP/DLLP-only flit (is_payload=0) with given dllp_content and
    // pushes it through the SAME path normal flits use (dl_ap -> PL model)
    task send_dllp_flit(bit [31:0] content);
       PCIe_sequence_item dcm_item;
       dcm_item = PCIe_sequence_item::type_id::create("dcm_item");
       dllp_content = content;
       form_dl_packet(dcm_item.tlp_data, 1'b0, dcm_item.dlp_flit_out); // is_payload=0
       // ---- LCRC addition: stamp LCRC on this DLCMSM flit before sending ----
       dcm_item.dl_lcrc = generate_lcrc_flit(dcm_item.dlp_flit_out);
       `uvm_info("EP_DLCMSM",$sformatf("DLCMSM_FLIT_LCRC_STAMPED :: dl_lcrc=%08h",dcm_item.dl_lcrc),UVM_LOW)
       // -----------------------------------------------------------------
       dl_ap.write(dcm_item);
       `uvm_info("EP_DLCMSM",$sformatf("SENT_DLLP_FLIT content=%08h",content),UVM_LOW)
    endtask
  // =========================================================================
  // END DLCMSM FSM BLOCK
  // =========================================================================

  // Standard NAK implementation
  task standard_nak_procedure();
    if (duplicate_sequence_number()) begin
      if (NAK_SCHEDULED) discard_flit(0);
      else execute_nak_schedule(2);
    end
    else if (received_explicit_seq && (IMPLICIT_RX_FLIT_SEQ_NUM == NEXT_EXPECTED_RX_FLIT_SEQ_NUM)) begin
      execute_ack_schedule(1);
    end
    else begin
      if (NAK_SCHEDULED) discard_flit(0);
      else execute_nak_schedule(2);
    end
  endtask

  // Selective NAK implementation
  task selective_nak_procedure();
    if (duplicate_sequence_number()) discard_flit(0);
    else if (received_explicit_seq && (IMPLICIT_RX_FLIT_SEQ_NUM == NEXT_EXPECTED_RX_FLIT_SEQ_NUM)) begin
      if (RX_RETRY_BUFFER_OVERFLOW) execute_nak_schedule(5);
      else execute_ack_schedule(2);
    end
    else if (IMPLICIT_RX_FLIT_SEQ_NUM == NEXT_RX_FLIT_SEQ_NUM_TO_STORE) begin
      if (rx_retry_buffer.size() >= `PCIe_MAX_UNACK_FLITS) execute_nak_schedule(4);
      else execute_nak_schedule(3);
    end
    else execute_nak_schedule(2);
  endtask

  // Retry buffer manipulation
  task store_flit_in_rx_retry_buffer();
    rx_retry_buffer.push_back(current_flit_data);
    RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM;
    NEXT_RX_FLIT_SEQ_NUM_TO_STORE = mod1023_add(NEXT_RX_FLIT_SEQ_NUM_TO_STORE, 10'h1);
  endtask

  // Handle payload with failure
  task handle_payload_withdrawal_failure(bit is_nop);
    NAK_WITHDRAWAL_ALLOWED = 1'b0;
    if (is_nop) begin
      NAK_SCHEDULED = 1'b1;
      TX_ACKNAK_FLIT_SEQ_NUM = mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1);
    end
    else begin
      if (USE_STANDARD_NAK_ONLY) begin
        standard_nak_procedure();
      end
      else begin
        NEXT_RX_FLIT_SEQ_NUM_TO_STORE = mod1023_add(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1);
        selective_nak_procedure();
      end
    end
  endtask

  function bit bad_sequence_number();
    `uvm_info("EP_DL_MODEL",$sformatf("BAD_SEQUENCE_NUMBER :: NEXT_EXPECTED_RX_FLIT_SEQ_NUM = %d :: IMPLICIT_RX_FLIT_SEQ_NUM = %d",NEXT_EXPECTED_RX_FLIT_SEQ_NUM,IMPLICIT_RX_FLIT_SEQ_NUM),UVM_LOW);
    return (mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, IMPLICIT_RX_FLIT_SEQ_NUM) > 511);
  endfunction

  function bit bad_nop_sequence_number();
    return bad_sequence_number() || (IMPLICIT_RX_FLIT_SEQ_NUM == NEXT_EXPECTED_RX_FLIT_SEQ_NUM);
  endfunction

  // Check the duplicate sequence number
  function bit duplicate_sequence_number();
    return (mod1023_sub(TX_ACKNAK_FLIT_SEQ_NUM, IMPLICIT_RX_FLIT_SEQ_NUM) < 511);
  endfunction

  // FLIT MODE PACKET CREATION DLP
  task form_dl_packet(
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
      seq_num_to_send = TX_ACKNAK_FLIT_SEQ_NUM;
    end

    // 2. Construct DLP0
    dlp[0][7:6] = is_payload ? 2'b01 : 2'b00;
    dlp[0][5] = last_flit_was_payload;
    dlp[0][4] = 1'b0;
    dlp[0][3:2] = replay_command;
    dlp[0][1:0] = seq_num_to_send[9:8];

    // 3. Construct DLP1
    dlp[1] = seq_num_to_send[7:0];

    // 4. Construct DLP2-DLP5
    if (credit) begin
      dlp[2] = dllp_content[31:24];
      dlp[3] = dllp_content[23:16];
      dlp[4] = dllp_content[15:8];
      dlp[5] = dllp_content[7:0];
    end
    else begin
      dlp[2] = dllp_content[31:24];
      dlp[3] = dllp_content[23:16];
      dlp[4] = dllp_content[15:8];
      dlp[5] = dllp_content[7:0];
    end

    // 5. Update DL Internal State
    if ((replay_command == 2'b00) && is_payload) begin
      NEXT_TX_FLIT_SEQ_NUM = mod1023_add(NEXT_TX_FLIT_SEQ_NUM, 10'h1);
      `uvm_info("EP_DL_MODEL",$sformatf("NEXT_TX_FLIT_SEQ_NUM INSIDE THE DL INTERNAL STATE IS %d",NEXT_TX_FLIT_SEQ_NUM),UVM_LOW);
    end

   // clear ACK flag here
   if(replay_command == 2'b01) begin
	   ACK_SCHEDULED=1'b0;
   end

    last_flit_was_payload = is_payload;

    // 6. Assemble Output
    for (int i = 0; i < `PCIe_TLP_DATA_BYTE_W; i++) dl_flit_out[i] = tlp_data[i];
    for (int i = 0; i < `PCIe_DLP_BYTE_W; i++) dl_flit_out[`PCIe_TLP_DATA_BYTE_W+i] = dlp[i];

    `uvm_info("EP_DL_MODEL",$sformatf("replay_cmd = %d :: is_payload = %d :: dllp_sequence_number = %0h :: dlp = %p",replay_cmd,is_payload,{dlp[0][1:0],dlp[1]},dl_flit_out),UVM_LOW);

    store_tx_retry_buffer(tlp_data, seq_num_to_send);
  endtask

  // Discard the flit
  task discard_flit(int discard_type);
    `uvm_info("EP_DL_MODEL","Entered the discard flit task 0",UVM_LOW);
    NAK_WITHDRAWAL_ALLOWED = 1'b0;

    case (discard_type)
      0: begin
        `uvm_info("EP_DL_MODEL","VIP RX: Flit Discard 0 - Valid/Duplicate/NOP discarded. Sequence maintained",UVM_LOW);
      end

      1: begin
        `uvm_info("EP_DL_MODEL","VIP RX: Flit Discard 1 - Invalid flit dropped during outstanding Nak.",UVM_LOW);
      end

      2: begin
        log_data_link_protocol_error();
        `uvm_info("EP_DL_MODEL","VIP FATAL: Flit Discard 2 - Protocol Violation detected.",UVM_LOW);
      end
    endcase
  endtask

  // Log the receiver error in register
  task log_data_link_protocol_error();
    `uvm_info("EP_DL_MODEL","ERROR: Data Link Protocol Error Logged",UVM_LOW);
  endtask

  // NAK Schedule Implementation
  task execute_nak_schedule(int id);
    `uvm_info("EP_DL_MODEL","Entered nak schedule task",UVM_LOW);

    case (id)
      0: begin
        discard_flit(1);
        NAK_WITHDRAWAL_ALLOWED = 1'b1;
      end

      1: begin
        discard_flit(1);
        NAK_SCHEDULED = 1'b1;
        TX_ACKNAK_FLIT_SEQ_NUM = mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1);
        NAK_WITHDRAWAL_ALLOWED = 1'b0;
      end

      2: begin
        TX_ACKNAK_FLIT_SEQ_NUM = mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1);
        NAK_SCHEDULED = 1'b1;
        NAK_SCHEDULED_TYPE = STANDARD_NAK;
        RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = 10'h0;
        NAK_WITHDRAWAL_ALLOWED = 1'b0;
      end

      3: begin
        RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM;
        NEXT_RX_FLIT_SEQ_NUM_TO_STORE = mod1023_add(NEXT_RX_FLIT_SEQ_NUM_TO_STORE, 10'h1);
        NAK_WITHDRAWAL_ALLOWED = 1'b0;
      end

      4: begin
        discard_flit(0);
        if (ALLOW_SELECTIVE_OVERFLOW) begin
          RX_RETRY_BUFFER_OVERFLOW = 1'b1;
        end
        else begin
          NAK_SCHEDULED_TYPE = STANDARD_NAK;
          TX_ACKNAK_FLIT_SEQ_NUM = mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1);
          rx_retry_buffer.delete();
          RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = 10'h0;
          NAK_WITHDRAWAL_ALLOWED = 1'b0;
        end
      end

      5: begin
        NAK_SCHEDULED = 1'b1;
        NAK_SCHEDULED_TYPE = STANDARD_NAK;
        TX_ACKNAK_FLIT_SEQ_NUM = RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM;
        RX_RETRY_BUFFER_OVERFLOW = 1'b0;
        NAK_WITHDRAWAL_ALLOWED = 1'b0;
        NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM, 10'h1);
        RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = 10'h0;
      end

      6: begin
        discard_flit(1);
        NAK_SCHEDULED = 1'b1;
        NAK_SCHEDULED_TYPE = STANDARD_NAK;
        RX_RETRY_BUFFER_OVERFLOW = 1'b0;
        NAK_WITHDRAWAL_ALLOWED = 1'b0;
        TX_ACKNAK_FLIT_SEQ_NUM = mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1);
        rx_retry_buffer.delete();
      end

      7: begin
        NAK_SCHEDULED_TYPE = STANDARD_NAK;
      end
    endcase
  endtask

  // ACK Schedule Implementation
  task execute_ack_schedule(int id);
    `uvm_info("EP_DL_MODEL","Entered execute ack schedule",UVM_LOW);

    case (id)
      0: begin
        TX_ACKNAK_FLIT_SEQ_NUM = NEXT_EXPECTED_RX_FLIT_SEQ_NUM;
        NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1);
        `uvm_info("EP_DL_MODEL",$sformatf("TX_ACKNAK_FLIT_SEQ_NUM updated after collecting the packet = %d",TX_ACKNAK_FLIT_SEQ_NUM),UVM_LOW);
      end

      1: begin
        NAK_SCHEDULED = 1'b0;
        TX_ACKNAK_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM;
        NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(IMPLICIT_RX_FLIT_SEQ_NUM, 10'h1);
      end

      2: begin
        NAK_SCHEDULED = 1'b0;
        if (rx_retry_buffer.size() == 0) begin
          TX_ACKNAK_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM;
          NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(IMPLICIT_RX_FLIT_SEQ_NUM, 10'h1);
        end
        else begin
          TX_ACKNAK_FLIT_SEQ_NUM = RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM;
          NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM, 10'h1);
          RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = 10'h0;
        end
      end

      3: begin
        NAK_WITHDRAWAL_ALLOWED = 1'b0;
        TX_ACKNAK_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM;
        NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(IMPLICIT_RX_FLIT_SEQ_NUM, 10'h1);
      end
    endcase
  endtask

  // RX_EP
  // Handling the incoming flit and passing info to EP
  task handle_incoming_flit(bit [0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dlp, bit is_valid);
    bit [`PCIe_FLIT_USAGE_W-1:0] is_nop;
    bit prior_was_payload;
    bit [`PCIe_SEQ_NUM_W-1:0] sequence_number;
    bit is_idle;
    bit is_payload;
    bit is_explicit;
    bit [`PCIe_FLIT_USAGE_W-1:0] flit_usage;

    `uvm_info("EP_CON_MONITOR",$sformatf("DEBUG_HANDLE_INCOMING_FLIT_collected dlp_ep from ep monitor is dlp=%p",dlp),UVM_LOW)
    sequence_number = {dlp[0][1:0],dlp[1]};
    is_nop = (!(sequence_number == 10'h0) && dlp[0][7:6] == 2'b00);
    prior_was_payload = dlp[0][5];
    `uvm_info("SEQ_DEBUG",$sformatf("dlp=%p :: %b :: %b",dlp,dlp[0][1:0],dlp[1]),UVM_LOW)
    replay_cmd = dlp[4][3:2];
    flit_usage = dlp[0][7:6];
    is_payload = (flit_usage == 2'b01);
    is_explicit = (replay_cmd == 2'b00);
    is_idle = (sequence_number == 10'h0) && (replay_cmd == 2'b00) && (flit_usage == 2'b00);
    received_explicit_seq_0 = (sequence_number == 10'h0) && (replay_cmd == 2'b00);
    received_explicit_seq = (replay_cmd == 2'b00);

    `uvm_info("EP_DL_MODEL",$sformatf("HANDLE_INCOMING_FLIT::DLP = %p, valid = %d, sequence_number = %d, is_nop = %d, prior_was_payload = %d,is_idle = %d,is_explicit = %d, is_payload = %d",dlp,is_valid,sequence_number,is_nop,prior_was_payload,is_idle,is_explicit,is_payload),UVM_LOW);

    update_implicit_rx_sequence_number(sequence_number,is_valid,is_nop,is_payload,is_explicit,is_idle,prior_was_payload);

    `uvm_info("EP_DL_MODEL",$sformatf("HANDLE_INCOMING_FLIT :: NEXT_TX_FLIT_SEQ_NUM = %h, NEXT_EXPECTED_RX_FLIT_SEQ_NUM = %h,IMPLICIT_RX_FLIT_SEQ_NUM = %h,ACKD_FLIT_SEQ_NUM = %h",NEXT_TX_FLIT_SEQ_NUM,NEXT_EXPECTED_RX_FLIT_SEQ_NUM,IMPLICIT_RX_FLIT_SEQ_NUM,ACKD_FLIT_SEQ_NUM),UVM_LOW);

    if (!is_valid) begin
      if (NAK_SCHEDULED) begin
        if (NAK_SCHEDULED_TYPE == STANDARD_NAK) discard_flit(1);
        else execute_nak_schedule(6);
      end
      else begin
        if (NAK_WITHDRAWAL_ALLOWED) execute_nak_schedule(1);
        else execute_nak_schedule(0);
      end
      return;
    end

    `uvm_info("EP_DL_MODEL",$sformatf("DEBUG_HANDLE_IMCOMING_FLIT::DLP = %p, valid = %d, sequence_number = %d, is_nop = %d, prior_was_payload = %d,is_idle = %d,is_explicit = %d, is_payload = %d",dlp,is_valid,sequence_number,is_nop,prior_was_payload,is_idle,is_explicit,is_payload),UVM_LOW);

    if (replay_cmd != 2'b00) begin
      process_received_ack_nak(sequence_number,replay_cmd);
    end

    if (received_explicit_seq_0 && !is_idle) begin
      log_data_link_protocol_error();
      return;
    end

    if (NAK_WITHDRAWAL_ALLOWED) begin
      if (prior_was_payload) begin
        handle_payload_withdrawal_failure(is_nop);
      end
      else begin
        if (bad_sequence_number()) execute_nak_schedule(2);
        else execute_ack_schedule(3);
      end
      return;
    end

    if (is_nop) begin
      if (bad_nop_sequence_number()) execute_nak_schedule(2);
      else discard_flit(0);
    end
    else begin
      `uvm_info("EP_DL_MODEL","ENTERED_NORMAL_DL_TASK",UVM_LOW);

      if (NAK_SCHEDULED) begin
        if (NAK_SCHEDULED_TYPE == STANDARD_NAK) standard_nak_procedure();
        else selective_nak_procedure();
      end
      else begin
        `uvm_info("EP_DL_MODEL","ENTERED_NORMAL_DL_TASK",UVM_LOW);
        if (duplicate_sequence_number()) discard_flit(0);
        else if (bad_sequence_number()) begin
          `uvm_info("EP_DL_MODEL","ENTERED_NAK_SCHEDULE_TASK",UVM_LOW);
          execute_nak_schedule(2);
        end
        else begin
          `uvm_info("EP_DL_MODEL","ENTERED_ACK_SCHEDULE_TASK",UVM_LOW);
          execute_ack_schedule(0);
	  ACK_SCHEDULED=1;
          success = 1;
        end
      end
    end
  endtask

  // ---- LCRC addition: RX-side check, called before handle_incoming_flit() ----
  // Works off the item's own dlp_flit_out/tlp_data + dl_lcrc — item already
  // carries both through the analysis port, so no raw PIPE reassembly needed.
  task check_lcrc_on_rx(PCIe_sequence_item item);
    bit [`PCIe_DL_LCRC_W-1:0] computed;
    bit pass;

    if (item.pkt_mode == FLIT) begin
      computed = generate_lcrc_flit(item.dlp_flit_out);
      pass = lcrc_check(computed, item.dl_lcrc, "FLIT");
    end
    else begin
      int unsigned byte_len;
      byte_len = (item.tlp_total_dw_count > 0) ? (item.tlp_total_dw_count * 4) : `PCIe_TLP_DATA_BYTE_W;
      computed = generate_lcrc_non_flit(item.tlp_data, byte_len);
      pass = lcrc_check(computed, item.dl_lcrc, "NONFLIT");
    end

    if (!pass) begin
      log_data_link_protocol_error();
      discard_flit(2);
    end
    else begin
      handle_incoming_flit(item.dlp, 1'b1);
    end
  endtask
  // -----------------------------------------------------------------------

  // RC_TX logic
  // TX logic handling
  task process_received_ack_nak(bit [`PCIe_SEQ_NUM_W-1:0] N, bit [`PCIe_REPLAY_CMD_W-1:0] replay_cmd);
    bit guard_future;
    bit guard_past;
    bit is_ack;
    bit is_nak;

    if (replay_cmd == 2'b01) begin
      is_ack = 1'b1;
    end
    else if (replay_cmd == 2'b10) begin
      is_nak = 1'b1;
      REPLAY_SCHEDULED_TYPE = STANDARD_REPLAY;
    end
    else if (replay_cmd == 2'b11) begin
      is_nak = 1'b1;
      REPLAY_SCHEDULED_TYPE = SELECTIVE_REPLAY;
    end

    `uvm_info("EP_DL_MODEL",$sformatf("PROCESS_RECIEVED_ACK_NACK :: N = %d :: is_nak = %d :: is_ack = %d",N,is_nak,is_ack),UVM_LOW);

    if (N == 10'h0) return;

    guard_future = (mod1023_sub(NEXT_TX_FLIT_SEQ_NUM - 10'h1,N) <= MAX_UNACKNOWLEDGED_FLITS);
    guard_past = (mod1023_sub(N,ACKD_FLIT_SEQ_NUM) <= MAX_UNACKNOWLEDGED_FLITS);

    `uvm_info("EP_DL_MODEL",$sformatf("ACKD_FLIT_SEQ_NUM = %d :: gaurd_future = %d :: guard_past = %d",ACKD_FLIT_SEQ_NUM,guard_future,guard_past),UVM_LOW);

    if (!(guard_future && guard_past)) begin
      log_data_link_protocol_error();
      return;
    end

    purge_tx_retry_buffer(N);

    if (mod1023_sub(N,ACKD_FLIT_SEQ_NUM) > 0) begin
      FLIT_REPLAY_NUM = 3'h0;
      ACKD_FLIT_SEQ_NUM = N;
    end

    if (is_ack) begin
      NAK_IGNORE_FLIT_SEQ_NUM = 10'h0;
      if (mod1023_sub(N,TX_REPLAY_FLIT_SEQ_NUM) < MAX_UNACKNOWLEDGED_FLITS) begin
        TX_REPLAY_FLIT_SEQ_NUM = 10'h0;
      end
    end
    else if (is_nak) begin
      `uvm_info("EP_DL_MODEL","Entered the nak logic",UVM_LOW);

      if (N == mod1023_sub(NEXT_TX_FLIT_SEQ_NUM,10'h1)) begin
        NAK_IGNORE_FLIT_SEQ_NUM = N;
      end
      else if (N != NAK_IGNORE_FLIT_SEQ_NUM) begin
        NAK_IGNORE_FLIT_SEQ_NUM = 10'h0;
      end

      schedule_replay(N + 10'h1);
    end
  endtask

  // Modulo 1023 check: Is sequence S "older than or including" N?
  function automatic bit is_older_than_or_including(bit [`PCIe_SEQ_NUM_W-1:0] S, bit [`PCIe_SEQ_NUM_W-1:0] N);
    return (mod1023_sub(N,S) <= MAX_UNACKNOWLEDGED_FLITS);
  endfunction

  task purge_tx_retry_buffer(bit [`PCIe_SEQ_NUM_W-1:0] N);
    `uvm_info("EP_DL_MODEL",$sformatf("PURGING: Entry size of buffer :: %d",tx_retry_buffer.size()),UVM_LOW);

    while (tx_retry_buffer.size() > 0) begin
      bit [`PCIe_SEQ_NUM_W-1:0] S = tx_retry_buffer[0].seq_num;

      `uvm_info("EP_DL_MODEL",$sformatf("Sequence number flit deleted from the buffer is :: S = %d",S),UVM_LOW);

      if (is_older_than_or_including(S,N)) begin
        tx_retry_buffer.pop_front();
      end
      else begin
        break;
      end
    end
  endtask

  task schedule_replay(bit [`PCIe_SEQ_NUM_W-1:0] start_seq);
    `uvm_info("EP_DL_MODEL","Entered the replay schedule task_",UVM_LOW);
    REPLAY_SCHEDULED = 1'b1;
    EP_REPLAY_IN_PROGRESS = 1'b1;
    TX_REPLAY_FLIT_SEQ_NUM = start_seq;
  endtask

  // Storing the tx_retry_buffer
  task store_tx_retry_buffer(
    input bit [`PCIe_TLP_DATA_BYTE_W-1:0][`PCIe_BYTE_W-1:0] tlp_data,
    input bit [`PCIe_SEQ_NUM_W-1:0] seq_num
  );
    tx_retry_buffer.push_back('{tlp_data:tlp_data,seq_num:seq_num});
  endtask

  task update_implicit_rx_sequence_number(
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
  endtask

  // DL model consumes TL output, creates the DLP, then publishes to PL.
  function void write(PCIe_sequence_item item);
    `uvm_info("EP_DL_MODEL",$sformatf("DL -> PL: item from driver = %p",item.tlp_data),UVM_LOW)
    form_dl_packet(item.tlp_data,item.is_payload,item.dlp_flit_out);

    // ---- LCRC addition: stamp LCRC based on configured mode ----
    if (item.pkt_mode == FLIT) begin
      item.dl_lcrc = generate_lcrc_flit(item.dlp_flit_out);
      `uvm_info("LCRC_FLIT_MODE",$sformatf("STAMPED_ON_ITEM :: dl_lcrc=%08h",item.dl_lcrc),UVM_LOW)
    end
    else begin
      int unsigned byte_len;
      byte_len = (item.tlp_total_dw_count > 0) ? (item.tlp_total_dw_count * 4) : `PCIe_TLP_DATA_BYTE_W;
      item.dl_lcrc = generate_lcrc_non_flit(item.tlp_data, byte_len);
      `uvm_info("LCRC_NONFLIT_MODE",$sformatf("STAMPED_ON_ITEM :: bytes_covered=%0d :: dl_lcrc=%08h",byte_len,item.dl_lcrc),UVM_LOW)
    end
    // -------------------------------------------------------------

    dl_ap.write(item);
  endfunction


  // =========================================================================
  // PCIe 6.0 Flow Control DLLP Payload Generator
  // Returns a 32-bit vector ready to map to DLP2 (MSB) through DLP5 (LSB)
  // =========================================================================
  function automatic bit [`PCIe_DLLP_CONTENT_W-1:0] create_fc_dllp(
    input bit [`PCIe_FC_PHASE_W-1:0] fc_phase,
    input bit [`PCIe_FC_CLASS_W-1:0] fc_class,
    input bit shared_fc,
    input bit [`PCIe_FC_VC_W-1:0] vc,
    input bit [`PCIe_FC_SCALE_W-1:0] hdr_scale,
    input bit [`PCIe_FC_SCALE_W-1:0] data_scale,
    input bit [`PCIe_FC_HDR_W-1:0] hdr_fc,
    input bit [`PCIe_FC_DATA_W-1:0] data_fc,
    input bit is_infinite_hdr,
    input bit is_infinite_data
  );

    bit [`PCIe_DLLP_TYPE_PREFIX_W-1:0] dllp_type_prefix;
    bit [`PCIe_FC_HDR_TX_W-1:0] hdr_fc_tx;
    bit [`PCIe_FC_DATA_TX_W-1:0] data_fc_tx;
    bit [`PCIe_FC_SCALE_W-1:0] hdr_scale_tx;
    bit [`PCIe_FC_SCALE_W-1:0] data_scale_tx;
    bit [`PCIe_DLLP_CONTENT_W-1:0] dllp_content;

    // 1. Determine DLLP Type Prefix based on Phase & TLP Class
    if (fc_phase == 2'b01) begin
      case (fc_class)
        2'b00: dllp_type_prefix = 4'b0100;
        2'b01: dllp_type_prefix = 4'b0101;
        2'b10: dllp_type_prefix = 4'b0110;
        default: dllp_type_prefix = 4'b0100;
      endcase
    end
    else if (fc_phase == 2'b10) begin
      case (fc_class)
        2'b00: dllp_type_prefix = 4'b1100;
        2'b01: dllp_type_prefix = 4'b1101;
        2'b10: dllp_type_prefix = 4'b1110;
        default: dllp_type_prefix = 4'b1100;
      endcase
    end
    else begin
      case (fc_class)
        2'b00: dllp_type_prefix = 4'b1000;
        2'b01: dllp_type_prefix = 4'b1001;
        2'b10: dllp_type_prefix = 4'b1010;
        default: dllp_type_prefix = 4'b1000;
      endcase
    end

    // 2. Handle Infinite Credit Rules
    if (is_infinite_hdr) begin
      hdr_scale_tx = 2'b00;
      hdr_fc_tx = 8'h00;
    end
    else begin
      hdr_scale_tx = hdr_scale;
      case (hdr_scale)
        2'b00,2'b01: hdr_fc_tx = hdr_fc[7:0];
        2'b10: hdr_fc_tx = hdr_fc[9:2];
        2'b11: hdr_fc_tx = hdr_fc[11:4];
      endcase
    end

    if (is_infinite_data) begin
      data_scale_tx = 2'b00;
      data_fc_tx = 12'h000;
    end
    else begin
      data_scale_tx = data_scale;
      case (data_scale)
        2'b00,2'b01: data_fc_tx = data_fc[11:0];
        2'b10: data_fc_tx = data_fc[13:2];
        2'b11: data_fc_tx = data_fc[15:4];
      endcase
    end

    // 3. Assemble 32-bit DLLP Payload
    dllp_content[31:28] = dllp_type_prefix;
    dllp_content[12] = shared_fc;
    dllp_content[26:24] = vc;
    dllp_content[23:22] = hdr_scale_tx;
    dllp_content[21:16] = hdr_fc_tx[7:2];
    dllp_content[15:14] = hdr_fc_tx[1:0];
    dllp_content[13:12] = data_scale_tx;
    dllp_content[11:8] = data_fc_tx[11:8];
    dllp_content[7:0] = data_fc_tx[7:0];

    return dllp_content;
  endfunction

  // Task to build InitFC1 packet contents
  task build_initfc1_packet(
    input bit [`PCIe_FC_CLASS_W-1:0] fc_class,
    input bit shared,
    input bit [`PCIe_FC_VC_W-1:0] vc,
    input bit [`PCIe_FC_SCALE_W-1:0] hdr_scale,
    input bit [`PCIe_FC_SCALE_W-1:0] data_scale,
    input bit [`PCIe_FC_HDR_W-1:0] hdr_fc,
    input bit [`PCIe_FC_DATA_W-1:0] data_fc,
    input bit is_inf_hdr,
    input bit is_inf_data,
    output bit [`PCIe_DLLP_CONTENT_W-1:0] dllp_out
  );

    dllp_out = create_fc_dllp(
      .fc_phase(2'b01),
      .fc_class(fc_class),
      .shared_fc(shared),
      .vc(vc),
      .hdr_scale(hdr_scale),
      .data_scale(data_scale),
      .hdr_fc(hdr_fc),
      .data_fc(data_fc),
      .is_infinite_hdr(is_inf_hdr),
      .is_infinite_data(is_inf_data)
    );
  endtask

  // Task to build InitFC2 packet contents
  task build_initfc2_packet(
    input bit [`PCIe_FC_CLASS_W-1:0] fc_class,
    input bit shared,
    input bit [`PCIe_FC_VC_W-1:0] vc,
    input bit [`PCIe_FC_SCALE_W-1:0] hdr_scale,
    input bit [`PCIe_FC_SCALE_W-1:0] data_scale,
    input bit [`PCIe_FC_HDR_W-1:0] hdr_fc,
    input bit [`PCIe_FC_DATA_W-1:0] data_fc,
    input bit is_inf_hdr,
    input bit is_inf_data,
    output bit [`PCIe_DLLP_CONTENT_W-1:0] dllp_out
  );

    dllp_out = create_fc_dllp(
      .fc_phase(2'b10),
      .fc_class(fc_class),
      .shared_fc(shared),
      .vc(vc),
      .hdr_scale(hdr_scale),
      .data_scale(data_scale),
      .hdr_fc(hdr_fc),
      .data_fc(data_fc),
      .is_infinite_hdr(is_inf_hdr),
      .is_infinite_data(is_inf_data)
    );
  endtask

  // Task to drive the 6 initialization DLLPs during FC_INIT1 or FC_INIT2
task dlcssm_initialization_sequence(
    input bit [1:0] fc_phase, // 2'b01 = InitFC1, 2'b10 = InitFC2
    input bit [2:0] vc_id     // 3'b000 for VC0
);
    bit [31:0] init_dllp;

    `uvm_info("DL_CSSM", $sformatf("Transmitting Phase %0d Flow Control DLLPs", fc_phase), UVM_LOW)

    // =========================================================================
    // PART 1: TRANSMIT 3 DEDICATED PACKETS (Zero Credits for Single VC)
    // =========================================================================
    
    // 1. Dedicated Posted (P)
    init_dllp = create_fc_dllp(
        .fc_phase(fc_phase), .fc_class(2'b00), .shared_fc(1'b0), .vc(vc_id),
        .hdr_scale(2'b01), .data_scale(2'b01), .hdr_fc(12'd0), .data_fc(16'd0),
        .is_infinite_hdr(1'b0), .is_infinite_data(1'b0)
    );

    // 2. Dedicated Non-Posted (NP)
    init_dllp = create_fc_dllp(
        .fc_phase(fc_phase), .fc_class(2'b01), .shared_fc(1'b0), .vc(vc_id),
        .hdr_scale(2'b01), .data_scale(2'b01), .hdr_fc(12'd0), .data_fc(16'd0),
        .is_infinite_hdr(1'b0), .is_infinite_data(1'b0)
    );

    // 3. Dedicated Completions (Cpl)
    init_dllp = create_fc_dllp(
        .fc_phase(fc_phase), .fc_class(2'b10), .shared_fc(1'b0), .vc(vc_id),
        .hdr_scale(2'b01), .data_scale(2'b01), .hdr_fc(12'd0), .data_fc(16'd0),
        .is_infinite_hdr(1'b0), .is_infinite_data(1'b0)
    );

    // =========================================================================
    // PART 2: TRANSMIT 3 SHARED PACKETS (Actual credits & Infinite Completions) [16]
    // =========================================================================

    // 4. Shared Posted (P) - Standard Posted values (Scale Factor 1)
    init_dllp = create_fc_dllp(
        .fc_phase(fc_phase), .fc_class(2'b00), .shared_fc(1'b1), .vc(vc_id),
        .hdr_scale(2'b01), .data_scale(2'b01), .hdr_fc(12'd8), .data_fc(16'd64), // Assuming 1024B MPS
        .is_infinite_hdr(1'b0), .is_infinite_data(1'b0)
    );

    // 5. Shared Non-Posted (NP) - Standard NP values
    init_dllp = create_fc_dllp(
        .fc_phase(fc_phase), .fc_class(2'b01), .shared_fc(1'b1), .vc(vc_id),
        .hdr_scale(2'b01), .data_scale(2'b01), .hdr_fc(12'd8), .data_fc(16'd4),  // NP Data = 4 (64B payload)
        .is_infinite_hdr(1'b0), .is_infinite_data(1'b0)
    );

    // 6. Shared Completions (Cpl) - Infinite for EP / standard RC
    init_dllp = create_fc_dllp(
        .fc_phase(fc_phase), .fc_class(2'b10), .shared_fc(1'b1), .vc(vc_id),
        .hdr_scale(2'b00), .data_scale(2'b00), .hdr_fc(12'd0), .data_fc(16'd0),  // Scale/credits are ignored
        .is_infinite_hdr(1'b1), .is_infinite_data(1'b1)                          // Triggers Infinite Advertisement
    );

endtask

    /*// =========================================================================
    // PCIe 6.0 Dynamic Flow Control Initialization Sequence
    // Grounded in Section 3.4 & Section 2.6.1.2 of the Base Spec
    // =========================================================================
    
    // Define your physical maximum queue configurations (matches actual FIFO sizes)
    const int MAX_TX_RETRY_DEPTH = 512; 
    const int MAX_RX_RETRY_DEPTH = 512;

    task automatic drive_initialization_sequence(
        input bit [1:0] fc_phase, // 2'b01 = InitFC1, 2'b10 = InitFC2
        input bit [2:0] vc_id     // 3'b000 for VC0
    );
        bit [31:0] init_dllp;
        
        // Calculated variables
        int rx_free_slots;
        int tx_free_slots;
        
        bit [11:0] calc_rx_hdr_fc;
        bit [15:0] calc_rx_data_fc;
        bit [1:0]  calc_rx_hdr_scale;
        bit [1:0]  calc_rx_data_scale;
        
        // 1. Calculate remaining slots in your EP Rx Retry Buffer
        rx_free_slots = MAX_RX_RETRY_DEPTH - rx_retry_buffer.size();
        if (rx_free_slots < 0) rx_free_slots = 0;
        
        // 2. Calculate remaining slots in your RC Tx Retry Buffer (useful for sanity logs)
        tx_free_slots = MAX_TX_RETRY_DEPTH - tx_retry_buffer.size();
        if (tx_free_slots < 0) tx_free_slots = 0;

        // 3. Map free RX slots to unscaled Credits (Hdr = 1 unit, Data = 16 Bytes)
        calc_rx_hdr_fc  = rx_free_slots;              // 1 Header Credit per free slot
        calc_rx_data_fc = (rx_free_slots * 236) / 16; // ~14 Data Credits per free slot

        // 4. Calculate Scale Factors on the fly (Table 2-46 / 2-47)
        // Header Scale
        if (calc_rx_hdr_fc <= 127) begin
            calc_rx_hdr_scale = 2'b01; // SF = 1
        end else if (calc_rx_hdr_fc <= 508) begin
            calc_rx_hdr_scale = 2'b10; // SF = 4 (Shifted right by 2 before DLLP packing)
        end else begin
            calc_rx_hdr_scale = 2'b11; // SF = 16 (Shifted right by 4 before DLLP packing)
        end

        // Data Scale
        if (calc_rx_data_fc <= 2047) begin
            calc_rx_data_scale = 2'b01; // SF = 1
        end else if (calc_rx_data_fc <= 8188) begin
            calc_rx_data_scale = 2'b10; // SF = 4
        end else begin
            calc_rx_data_scale = 2'b11; // SF = 16
        end

        `uvm_info("DL_INIT", $sformatf("Driving Init Sequence Phase %0d. RX Queue Space: %0d/%0d. Calculated Shared HdrFC: %0d, DataFC: %0d", 
                  fc_phase, rx_free_slots, MAX_RX_RETRY_DEPTH, calc_rx_hdr_fc, calc_rx_data_fc), UVM_LOW)

        // =========================================================================
        // PART 1: TRANSMIT 3 DEDICATED PACKETS (Zero Credits for Single VC0 Mode)
        // =========================================================================
        
        // 1. Dedicated Posted (P)
        init_dllp = create_fc_dllp(
            .fc_phase(fc_phase), .fc_class(2'b00), .shared_fc(1'b0), .vc(vc_id),
            .hdr_scale(2'b01), .data_scale(2'b01), .hdr_fc(12'd0), .data_fc(16'd0),
            .is_infinite_hdr(1'b0), .is_infinite_data(1'b0)
        );

        // 2. Dedicated Non-Posted (NP)
        init_dllp = create_fc_dllp(
            .fc_phase(fc_phase), .fc_class(2'b01), .shared_fc(1'b0), .vc(vc_id),
            .hdr_scale(2'b01), .data_scale(2'b01), .hdr_fc(12'd0), .data_fc(16'd0),
            .is_infinite_hdr(1'b0), .is_infinite_data(1'b0)
        );

        // 3. Dedicated Completions (Cpl)
        init_dllp = create_fc_dllp(
            .fc_phase(fc_phase), .fc_class(2'b10), .shared_fc(1'b0), .vc(vc_id),
            .hdr_scale(2'b01), .data_scale(2'b01), .hdr_fc(12'd0), .data_fc(16'd0),
            .is_infinite_hdr(1'b0), .is_infinite_data(1'b0)
        );

        // =========================================================================
        // PART 2: TRANSMIT 3 SHARED PACKETS (Dynamically Calculated)
        // =========================================================================

        // 4. Shared Posted (P) - Dynamic Shared Credits based on buffer space
        init_dllp = create_fc_dllp(
            .fc_phase(fc_phase), .fc_class(2'b00), .shared_fc(1'b1), .vc(vc_id),
            .hdr_scale(calc_rx_hdr_scale), .data_scale(calc_rx_data_scale), 
            .hdr_fc(calc_rx_hdr_fc), .data_fc(calc_rx_data_fc),
            .is_infinite_hdr(1'b0), .is_infinite_data(1'b0)
        );

        // 5. Shared Non-Posted (NP) - Allocate 25% of the calculated total queue pool
        init_dllp = create_fc_dllp(
            .fc_phase(fc_phase), .fc_class(2'b01), .shared_fc(1'b1), .vc(vc_id),
            .hdr_scale(calc_rx_hdr_scale), .data_scale(calc_rx_data_scale), 
            .hdr_fc(calc_rx_hdr_fc / 4), .data_fc(calc_rx_data_fc / 4),
            .is_infinite_hdr(1'b0), .is_infinite_data(1'b0)
        );

        // 6. Shared Completions (Cpl) - Endpoints must always advertise Infinite Cpl
        init_dllp = create_fc_dllp(
            .fc_phase(fc_phase), .fc_class(2'b10), .shared_fc(1'b1), .vc(vc_id),
            .hdr_scale(2'b00), .data_scale(2'b00), .hdr_fc(12'd0), .data_fc(16'd0),
            .is_infinite_hdr(1'b1), .is_infinite_data(1'b1)
        );

    endtask*/
   // =========================================================================
    // TASK 1: Calculates credits based on free queue slots and builds the 32-bit payload
    // =========================================================================
    /*task automatic calculate_and_build_updatefc(
        output bit [31:0] dllp_out,
        output bit        is_optimized
    );
        int max_slots = 512; // Maximum physical capacity of your rx_retry_buffer
        int free_slots = max_slots - rx_retry_buffer.size();
        bit [7:0]  calc_hdr;
        bit [11:0] calc_data;

        if (free_slots < 0) free_slots = 0;

        // 1. Calculate unscaled credits (1 header credit per slot, ~14 data credits per slot)
        calc_hdr  = free_slots[7:0];
        calc_data = ((free_slots * 236) / 16) & 12'hFFF;

        // 2. Assemble 32-bit Optimized Update FC DLLP (Layout from Fig 4-31)
        dllp_out[3]    = 1'b0;      // Indicator bit for Optimized Update FC (Must be 0)
        dllp_out[30:28] = 3'b000;    // Virtual Channel ID (VC0)
        dllp_out[27:20] = calc_hdr;  // Shared NP Header credits (NPRH) [1]
        dllp_out[19:12] = calc_hdr;  // Shared Posted Header credits (PRH) [1]
        dllp_out[11:0]  = calc_data; // Shared Posted Data credits (PRD) [1]

        is_optimized = 1'b1;         // Set DLP0 Bit 4 to 1'b1 (Optimized format indicator) [2]
    endtask

    // =========================================================================
    // TASK 2: Background keep-alive loop that automatically runs during DL_Active
    // =========================================================================
    task automatic run_updatefc_loop();
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

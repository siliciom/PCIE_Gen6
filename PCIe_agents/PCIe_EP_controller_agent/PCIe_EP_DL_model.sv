//=========================================================================================
// File         : PCIe_EP_DL_model.sv
// Project      : PCIe_Gen6
// Description  : PCIe_environment\PCIe_EP_DL_model.sv
// Author       :
// Date         : 2026-08-14
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document, including by copying, saving,
* iistributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

import typedef_enums::*;

class PCIe_EP_DL_model extends uvm_component;

  `uvm_component_utils(PCIe_EP_DL_model)

  // TL -> DL and DL -> PL TLM connections.
  uvm_analysis_imp #(PCIe_sequence_item, PCIe_EP_DL_model) dl_imp;
  uvm_analysis_port #(PCIe_sequence_item) dl_ap;

  bit [31:0] dllp_content;
  bit [`PCIe_DLP_FLIT_BYTE_W-1:0][`PCIe_BYTE_W-1:0] dl_flit_out;
  bit success;
  bit [`PCIe_DLP_FLIT_BYTE_W-1:0][`PCIe_BYTE_W-1:0] current_flit_data;
  bit received_explicit_seq;
  bit [`PCIe_REPLAY_CMD_W-1:0] replay_cmd;
  bit [`PCIe_SEQ_NUM_W-1:0] last_sent;
  bit IS_PAYLOAD;

  typedef struct {
    bit [`PCIe_TLP_DATA_BYTE_W-1:0][`PCIe_BYTE_W-1:0] tlp_data;
    bit [`PCIe_SEQ_NUM_W-1:0] seq_num;
  } tx_buffer_t;

  bit [`PCIe_DLP_FLIT_BYTE_W-1:0][`PCIe_BYTE_W-1:0] rx_retry_buffer[$];
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
  bit NAK_SCHEDULED_TYPE;
  bit STANDARD_NAK;
  bit NAK_WITHDRAWAL_ALLOWED;
  bit EP_REPLAY_IN_PROGRESS;

  bit last_flit_was_payload;
  bit credit;
  bit form_dlp_flit;

  function new(string name = "PCIe_RC_DL_model", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    dl_imp = new("dl_imp", this);
    dl_ap = new("dl_ap", this);
  endfunction

  // Modulo 1023 helper for sequence number increments (1 to 1023)
  function bit [`PCIe_SEQ_NUM_W-1:0] mod1023_add(bit [`PCIe_SEQ_NUM_W-1:0] a, bit [`PCIe_SEQ_NUM_W-1:0] b_inc);
    int sum = int'(a) + int'(b_inc);
    while (sum > 1023) sum -= 1023;
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
    input bit [`PCIe_TLP_DATA_BYTE_W-1:0][`PCIe_BYTE_W-1:0] tlp_data,
    input bit is_payload,
    output bit [`PCIe_DLP_FLIT_BYTE_W-1:0][`PCIe_BYTE_W-1:0] dl_flit_out
  );
    bit [`PCIe_SEQ_NUM_W-1:0] seq_num_to_send;
    bit [`PCIe_REPLAY_CMD_W-1:0] replay_command;
    bit [`PCIe_DLP_BYTE_W-1:0][`PCIe_BYTE_W-1:0] dlp;

    IS_PAYLOAD = is_payload;

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
  task handle_incoming_flit(bit [`PCIe_DLP_BYTE_W-1:0][`PCIe_BYTE_W-1:0] dlp, bit is_valid);
    bit [`PCIe_FLIT_USAGE_W-1:0] is_nop;
    bit prior_was_payload;
    bit [`PCIe_SEQ_NUM_W-1:0] sequence_number;
    bit is_idle;
    bit is_payload;
    bit is_explicit;
    bit [`PCIe_FLIT_USAGE_W-1:0] flit_usage;

    is_nop = (!(sequence_number == 10'h0) && dlp[0][7:6] == 2'b00);
    prior_was_payload = dlp[0][5];
    sequence_number = {dlp[0][1:0],dlp[1]};
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
          success = 1;
        end
      end
    end
  endtask

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

endclass

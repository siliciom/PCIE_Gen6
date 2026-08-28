//=========================================================================================
// File         : PCIe_RC_DL_model.sv
// Project      : PCIe_Gen6
// Description  : PCIe_environment\PCIe_RC_DL_model.sv
// Author       :
// Date         : 2026-08-14
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound by the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

import typedef_enums :: *;

class PCIe_RC_DL_model extends uvm_component;

  `uvm_component_utils(PCIe_RC_DL_model)

  // TL -> DL and DL -> PL TLM connections.
  uvm_analysis_imp #(PCIe_sequence_item,PCIe_RC_DL_model) dl_imp;
  uvm_analysis_port #(PCIe_sequence_item) dl_ap;

  bit [`PCIe_DLLP_CONTENT_W-1:0] dllp_content;
  bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] dl_flit_out;
  bit success;
  bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] current_flit_data;
  bit received_explicit_seq;
  bit [`PCIe_REPLAY_CMD_W-1:0] replay_cmd;
  bit [`PCIe_SEQ_NUM_W-1:0] last_sent;

  typedef struct {
    bit [0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_data;
    bit [`PCIe_SEQ_NUM_W-1:0] seq_num;
  } tx_buffer_t;

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
  bit NAK_SCHEDULED_TYPE;
  bit STANDARD_NAK;
  bit NAK_WITHDRAWAL_ALLOWED;
  bit RC_REPLAY_IN_PROGRESS;

  // Payload related information
  bit last_flit_was_payload;

  // Credit related information
  bit credit;
  bit form_dlp_flit;


  function new(string name="PCIe_RC_DL_model",uvm_component parent);
    super.new(name,parent);
  endfunction


  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    dl_imp = new("dl_imp",this);
    dl_ap = new("dl_ap",this);
  endfunction


  // Modulo 1023 helper for sequence number increments (1 to 1023)
  function bit [`PCIe_SEQ_NUM_W-1:0] mod1023_add(bit [`PCIe_SEQ_NUM_W-1:0] a,bit [`PCIe_SEQ_NUM_W-1:0] b_inc);
    int sum = int'(a) + int'(b_inc);
    while(sum > (`PCIe_MAX_UNACK_FLITS + 512)) sum -= (`PCIe_MAX_UNACK_FLITS + 512);
    return sum;
  endfunction


  // Modulo 1023 helper function for PCIe 6.0 wrap-around (1 to 1023)
  function automatic bit [`PCIe_SEQ_NUM_W-1:0] mod1023_sub(bit [`PCIe_SEQ_NUM_W-1:0] a,bit [`PCIe_SEQ_NUM_W-1:0] b);
    int diff = int'(a) - int'(b);
    if(diff <= 0) diff += (`PCIe_MAX_UNACK_FLITS + 512);
    return diff;
  endfunction


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

    last_flit_was_payload = is_payload;

    // Assemble Output
    for(int i=0;i<`PCIe_TLP_DATA_BYTE_W;i++)
      dl_flit_out[i] = tlp_data[i];

    for(int i=0;i<`PCIe_DLP_BYTE_W;i++)
      dl_flit_out[`PCIe_TLP_DATA_BYTE_W+i] = dlp[i];

    `uvm_info("RC_DL_MODEL",$sformatf("replay_cmd=%d :: is_payload=%d :: dllp_sequence_number=%0h :: dlp=%p",replay_command,is_payload,{dlp[0][1:0],dlp[1]},dl_flit_out),UVM_LOW);

    store_tx_retry_buffer(tlp_data,seq_num_to_send);
  endtask


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
    `uvm_info("RC_DL_MODEL","Entered nak schedule task",UVM_LOW);

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


  /*********************************************************************************/
  // RX_RC
  /*********************************************************************************/

  // Handling the incoming flit and passing info to RC
  task handle_incoming_flit(bit [`PCIe_DLP_BYTE_W-1:0][`PCIe_BYTE_W-1:0] dlp,bit is_valid);

    bit [1:0] is_nop;
    bit prior_was_payload;
    bit [`PCIe_SEQ_NUM_W-1:0] sequence_number;
    bit is_idle;
    bit is_payload;
    bit is_explicit;
    bit [1:0] flit_usage;

    sequence_number = {dlp[0][1:0],dlp[1]};
    is_nop = (!(sequence_number == '0) && dlp[0][7:6] == 2'b00);
    prior_was_payload = dlp[0][5];
    replay_cmd = dlp[0][3:2];
    flit_usage = dlp[0][7:6];
    is_payload = (flit_usage == 2'b01);
    is_explicit = (replay_cmd == 2'b00);
    is_idle = (sequence_number == '0) && (replay_cmd == 2'b00) && (flit_usage == 2'b00);
    received_explicit_seq_0 = (sequence_number == '0) && (replay_cmd == 2'b00);
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
    process_received_ack_nak(sequence_number,replay_cmd);

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

    // Guard 1: Future Check
    guard_future = (mod1023_sub(NEXT_TX_FLIT_SEQ_NUM-{{(`PCIe_SEQ_NUM_W-1){1'b0}},1'b1},N) <= MAX_UNACKNOWLEDGED_FLITS);

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

      `uvm_info("RC_DL_MODEL",$sformatf("Sequence number flit deleted from the buffer is ::S=%d",S),UVM_LOW);

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


  // DL model consumes TL output, creates the DLP, then publishes to PL.
  function void write(PCIe_sequence_item item);
    `uvm_info("RC_DL_MODEL",$sformatf("DL -> PL: item from driver=%p",item.tlp_data),UVM_LOW);

    form_dl_packet(item.tlp_data,item.is_payload,item.dlp_flit_out);

    dl_ap.write(item);
  endfunction

endclass

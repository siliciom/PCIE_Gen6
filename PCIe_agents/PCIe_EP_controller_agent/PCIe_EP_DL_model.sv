//=========================================================================================
// File         : PCIe_EP_DL_model.sv
// Project      : PCIe_Gen6
// Description  : PCIe_environment\PCIe_EP_DL_model.sv
// Author       : 
// Date         : 2026-08-14
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* iistributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

import typedef_enums :: *;
class PCIe_EP_DL_model extends uvm_component;

  `uvm_component_utils(PCIe_EP_DL_model)

    // TL -> DL and DL -> PL TLM connections.
    uvm_analysis_imp #(PCIe_sequence_item, PCIe_EP_DL_model) dl_imp;
    uvm_analysis_port #(PCIe_sequence_item) dl_ap;


    bit [31:0] dllp_content;   // 4-byte DLLP (e.g. UpdateFC or NOP)
    bit[0:241][7:0]dl_flit_out;
    bit success;
    bit [0:241][7:0] current_flit_data;
    bit received_explicit_seq; 
    bit [1:0] replay_cmd;
    bit[9:0]last_sent;
    typedef struct {
	    bit[0:235][7:0]tlp_data;
	    bit[9:0]seq_num;
	    } tx_buffer_t;

    // retry buffers for the retry logic at tx and rx side 
    bit[0:241][7:0]rx_retry_buffer[$];
    // debugging.....
    tx_buffer_t tx_retry_buffer[$];
    

    // Usage in your DL Model or Struct:
    replay_scheduled_type_e REPLAY_SCHEDULED_TYPE;

    // sequence numbers for handshake
    bit[9:0] TX_ACKNAK_FLIT_SEQ_NUM=10'h3FF;
    bit[9:0] NEXT_TX_FLIT_SEQ_NUM=10'h001;
    bit[9:0]NEXT_EXPECTED_RX_FLIT_SEQ_NUM=10'h001;
    bit[9:0]IMPLICIT_RX_FLIT_SEQ_NUM=10'h000;
    bit[9:0] ACKD_FLIT_SEQ_NUM=10'h3FF; 
    bit [9:0] TX_REPLAY_FLIT_SEQ_NUM=10'h000; 
    bit [9:0] NAK_IGNORE_FLIT_SEQ_NUM=10'h000;
    bit NON_IDLE_EXPLICIT_SEQ_NUM_FLIT_RCVD;  
    bit [2:0] FLIT_REPLAY_NUM=3'b000; 
    bit       REPLAY_SCHEDULED; 
    int unsigned MAX_UNACKNOWLEDGED_FLITS = 511; 

    bit [9:0] RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM; // Stores ID of last flit before overflow
    bit [9:0] NEXT_RX_FLIT_SEQ_NUM_TO_STORE;     // ID of next flit to go in buffer
    bit RX_RETRY_BUFFER_OVERFLOW;                // Flag set when RX buffer hits capacity
    bit ALLOW_SELECTIVE_OVERFLOW;                // Config bit to allow/deny selective overflow
    bit USE_STANDARD_NAK_ONLY = 1'b0; 
   // --- Protocol Violation Flags ---
    bit received_explicit_seq_0;                 // Temporary flag for violation check
    // Replay scheduling
    bit NAK_SCHEDULED;
    bit NAK_SCHEDULED_TYPE;
    bit STANDARD_NAK;
    bit NAK_WITHDRAWAL_ALLOWED;
    bit EP_REPLAY_IN_PROGRESS;
    // Payload related information
    bit last_flit_was_payload;
    // credit related information
    bit credit;
    bit form_dlp_flit;


    function new(string name="PCIe_RC_DL_model",uvm_component parent);
      super.new(name,parent);
    endfunction

    function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    dl_imp = new("dl_imp", this);
    dl_ap  = new("dl_ap",  this);
    endfunction


    // Modulo 1023 helper for sequence number increments (1 to 1023)
    function  bit [9:0] mod1023_add(bit [9:0] a, bit [9:0] b_inc);
    int sum = int'(a) + int'(b_inc);
    while (sum > 1023) sum -= 1023;
    return sum;
    endfunction

    // Modulo 1023 helper function for PCIe 6.0 wrap-around (1 to 1023) 
    function automatic bit [9:0] mod1023_sub(bit [9:0] a, bit [9:0] b); 
    int diff = int'(a) - int'(b); 
    if (diff <= 0) diff += 1023; 
    return diff; 
    endfunction
  // Standard nak implementation
    task standard_nak_procedure(); 
    if (duplicate_sequence_number()) begin 
        if (NAK_SCHEDULED) discard_flit(0); else execute_nak_schedule(2); 
    end else if (received_explicit_seq && (IMPLICIT_RX_FLIT_SEQ_NUM == NEXT_EXPECTED_RX_FLIT_SEQ_NUM)) begin 
        execute_ack_schedule(1); // Re-sync [5]
    end else begin 
        if (NAK_SCHEDULED) discard_flit(0); else execute_nak_schedule(2); 
    end 
endtask
// selective nak implementation
task selective_nak_procedure(); 
    if (duplicate_sequence_number()) discard_flit(0); 
    else if (received_explicit_seq && (IMPLICIT_RX_FLIT_SEQ_NUM == NEXT_EXPECTED_RX_FLIT_SEQ_NUM)) begin 
        if (RX_RETRY_BUFFER_OVERFLOW) execute_nak_schedule(5); 
        else execute_ack_schedule(2); // Missing flit replayed [5]
    end else if (IMPLICIT_RX_FLIT_SEQ_NUM == NEXT_RX_FLIT_SEQ_NUM_TO_STORE) begin 
        if (rx_retry_buffer.size() >= 511) execute_nak_schedule(4); // Buffer full [6]
        else execute_nak_schedule(3); // Store the flit [7]
    end else execute_nak_schedule(2); // Gap detected
endtask
    
    // retry buffer manipulation
    task store_flit_in_rx_retry_buffer();
    // Nak Schedule 3 logic [13]
    rx_retry_buffer.push_back(current_flit_data); 
    RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM;
    NEXT_RX_FLIT_SEQ_NUM_TO_STORE = mod1023_add(NEXT_RX_FLIT_SEQ_NUM_TO_STORE, 10'h1);
    endtask

   // Handle payload with failure
task handle_payload_withdrawal_failure(bit is_nop); 
    NAK_WITHDRAWAL_ALLOWED = 1'b0; 
    if (is_nop) begin 
        // Schedule Nak Schedule 1 
        NAK_SCHEDULED = 1'b1; 
        TX_ACKNAK_FLIT_SEQ_NUM = mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1); 
        // NAK_SCHEDULED_TYPE is set based on receiver capability [7] 
    end else begin 
        // Current flit is Payload: Choose Standard or Selective path [8] 
        if (USE_STANDARD_NAK_ONLY) begin 
            standard_nak_procedure(); 
        end else begin 
            NEXT_RX_FLIT_SEQ_NUM_TO_STORE = mod1023_add(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1); 
            selective_nak_procedure(); 
        end 
    end 
endtask

   function bit bad_sequence_number(); 
    return (mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, IMPLICIT_RX_FLIT_SEQ_NUM) > 511); 
endfunction

function bit bad_nop_sequence_number(); 
    return bad_sequence_number() || (IMPLICIT_RX_FLIT_SEQ_NUM == NEXT_EXPECTED_RX_FLIT_SEQ_NUM); 
endfunction

 //check the duplicate sequence number
    function bit duplicate_sequence_number(); 
    	return (mod1023_sub(TX_ACKNAK_FLIT_SEQ_NUM, IMPLICIT_RX_FLIT_SEQ_NUM) < 511); 
    endfunction

    // FLIT MODE PACKET CREATION DLP
    task  form_dl_packet(
    input  bit [0:235][7:0] tlp_data,       // Incoming 236 bytes from TL
    input  bit               is_payload,     // 1=Payload flit, 0=NOP/IDLE flit
    output bit [0:241][7:0] dl_flit_out     // 242-byte output (TLPs + DLP)
);
    bit [9:0] seq_num_to_send;
    bit [1:0] replay_command;
    bit [0:5][7:0] dlp;
 
    // --- 1. Determine Replay Command and Sequence Number [4, 6] ---
    if (NAK_SCHEDULED) begin
        // If an error was detected, schedule a Standard (10b) or Selective (11b) Nak
        replay_command = (NAK_SCHEDULED_TYPE == STANDARD_NAK) ? 2'b10 : 2'b11;
        seq_num_to_send = TX_ACKNAK_FLIT_SEQ_NUM; // Last valid flit received
    end 
    else if (is_payload) begin
        // Normal data transmission: Use Explicit Sequence Number (00b)
        replay_command = 2'b00; 
        seq_num_to_send = NEXT_TX_FLIT_SEQ_NUM;   // ID assigned to this flit
    end 
    else begin
        // NOP flit: Usually carries an Ack (01b) for partner progress
        replay_command = 2'b01;
        seq_num_to_send = TX_ACKNAK_FLIT_SEQ_NUM; // Last valid flit received
    end
 
    // --- 2. Construct DLP0 (Status and SeqNum bits 9:8) [4, 6, 7] ---
    dlp[0][7:6] = is_payload ? 2'b01 : 2'b00;    // Flit Usage
    dlp[0][5]    = last_flit_was_payload;        // History bit for Nak Withdrawal
    dlp[0][4]    = 1'b0;                         // 0b=Regular DLLP,1b=Optimized/Marker
    dlp[0][3:2]  = replay_command;               // Ack/Nak/Explicit state
    dlp[0][1:0]  = seq_num_to_send[9:8];         // High bits of Seq Num
 
    // --- 3. Construct DLP1 (SeqNum bits 7:0) [6] ---
    dlp[1] = seq_num_to_send[7:0];

    if(credit)
    begin 
    // --- 4. Construct DLP2-DLP5 (DLLP Payload) [3, 11] ---
    //dllp_content=create_update_dllp();
    dlp[2] = dllp_content[31:24];
    dlp[3] = dllp_content[23:16];
    dlp[4] = dllp_content[15:8];
    dlp[5] = dllp_content[7:0];
    end
    else
    begin
     // --- 4. Construct DLP2-DLP5 (DLLP Payload) [3, 11] ---
     //dllp_content=create_nop2_dllp();
    dlp[2] = dllp_content[31:24];
    dlp[3] = dllp_content[23:16];
    dlp[4] = dllp_content[15:8];
    dlp[5] = dllp_content[7:0];
    end
 
    // --- 5. Update DL Internal State [4, 14] ---
    if (replay_command == 2'b00 && is_payload) begin
        // Only increment local count if we sent a new unique Payload flit
        NEXT_TX_FLIT_SEQ_NUM = mod1023_add(NEXT_TX_FLIT_SEQ_NUM, 1);
    `uvm_info("EP_DL_MODEL",$sformatf("NEXT_TX_FLIT_SEQ_NUM INSIDE THE DL INTERNAL STATE IS %d",NEXT_TX_FLIT_SEQ_NUM),UVM_LOW);
    end
    last_flit_was_payload = is_payload; // Record for bit 5 of the next flit
 
    // --- 6. Assemble Output (236 Bytes TLP + 6 Bytes DLP) [1, 2] ---
    for (int i = 0; i < 236; i++) dl_flit_out[i]     = tlp_data[i];
    for (int i = 0; i < 6; i++)   dl_flit_out[236+i] = dlp[i];
    //`uvm_info("EP_DL_MODEL",$sformatf("is_payload=%h :: dllp_sequence_number=%0h :: dlp=%p",is_payload,{dlp[0][1:0], dlp[1]},dl_flit_out),UVM_LOW);
    `uvm_info("EP_DL_MODEL",$sformatf("replay_cmd=%d :: is_payload=%d :: dllp_sequence_number=%0h :: dlp=%p",replay_cmd,is_payload,{dlp[0][1:0], dlp[1]},dl_flit_out),UVM_LOW);
    store_tx_retry_buffer(tlp_data,seq_num_to_send);
  endtask

   // discard the flit 
    task discard_flit(int discard_type);
	   `uvm_info("EP_DL_MODEL","Entered the discard flit task 0",UVM_LOW); 
    // Rule: NAK_WITHDRAWAL_ALLOWED is always cleared on any discard.
    NAK_WITHDRAWAL_ALLOWED = 1'b0; 
    case (discard_type) 
        0: begin 
            /* 
             * Flit Discard 0: Valid but duplicate or NOP flit.
             * Implementation: 
             * 1. DO NOT pass the 236 TLP bytes to the Transaction Layer.
             * 2. DO NOT increment NEXT_EXPECTED_RX_FLIT_SEQ_NUM.
             */
             `uvm_info("EP_DL_MODEL", "VIP RX: Flit Discard 0 - Valid/Duplicate/NOP discarded. Sequence maintained",UVM_LOW);
        end 
        
        1: begin 
            /* 
             * Flit Discard 1: Invalid flit (CRC/ECC error) received during Standard Nak.
             * Implementation:
             * 1. Drop the entire 256-byte flit.
             * 2. No action taken on sequence numbers.
             * 3. No error reporting here to avoid "Error Pollution" (Physical Layer already handles it).
             */
             `uvm_info("EP_DL_MODEL","VIP RX: Flit Discard 1 - Invalid flit dropped during outstanding Nak.",UVM_LOW);
        end 
        
        2: begin  
            /* 
             * Flit Discard 2: Protocol violation (e.g., received Explicit Seq 0 in Normal Phase) [1, 6].
             * Implementation:
             * 1. Drop the flit.
             * 2. LOG a Data Link Protocol Error (Fatal) in AER/Status registers [1, 7].
             */
            log_data_link_protocol_error();  
            `uvm_info("EP_DL_MODEL","VIP FATAL: Flit Discard 2 - Protocol Violation detected.",UVM_LOW);
        end 
    endcase 
endtask 
    // log the reciever error in register
    task log_data_link_protocol_error(); 
    // Implementation specific: Set the DLPE bit in AER/Status registers [2] 
    `uvm_info("EP_DL_MODEL","ERROR: Data Link Protocol Error Logged",UVM_LOW); 
    endtask  

  // --- Nak Schedule Implementation --- 
 
   task execute_nak_schedule(int id);
	  `uvm_info("EP_DL_MODEL","Entered nak schedule task",UVM_LOW); 
    case (id) 
        0: begin // Tentative Wait (Initial Error Detection) 
           discard_flit(1); // Discard the invalid flit [1, 2] 
            NAK_WITHDRAWAL_ALLOWED = 1'b1; // Set withdrawal flag [2] 
            // NEXT_EXPECTED_RX_FLIT_SEQ_NUM does not change [2] 
        end 
 
        1: begin // Immediate Nak (Withdrawal not possible/failed) 
            discard_flit(1);  
            NAK_SCHEDULED = 1'b1; // [2] 
            TX_ACKNAK_FLIT_SEQ_NUM = mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1); // [2] 
            // NAK_SCHEDULED_TYPE set by calling procedure (Standard or Selective) [2] 
            NAK_WITHDRAWAL_ALLOWED = 1'b0; // Clear withdrawal [2] 
        end 
 
        2: begin // Standard Nak Escalation (Gap detected) 
            // TLP Bytes of the received Flit are discarded [3] 
            TX_ACKNAK_FLIT_SEQ_NUM = mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1); // [3] 
            NAK_SCHEDULED = 1'b1;  
            NAK_SCHEDULED_TYPE = STANDARD_NAK; // [3] 
            RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = 10'h0; // [3] 
            NAK_WITHDRAWAL_ALLOWED = 1'b0;  
        end 
 
        3: begin // Store Valid Out-of-Order Flit (Selective Nak) 
            RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM; // [3] 
            NEXT_RX_FLIT_SEQ_NUM_TO_STORE = mod1023_add(NEXT_RX_FLIT_SEQ_NUM_TO_STORE, 10'h1); // [3] 
            NAK_WITHDRAWAL_ALLOWED = 1'b0;  
            //store_flit_in_rx_retry_buffer(); // Implementation specific storage 
        end 
 
        4: begin // Selective Nak Buffer Overflow 
            discard_flit(0); // [4] 
            if (ALLOW_SELECTIVE_OVERFLOW) begin // Logic chooses to continue Selective Nak 
                RX_RETRY_BUFFER_OVERFLOW = 1'b1; // [4] 
            end else begin // Escalate to Standard Nak immediately 
                NAK_SCHEDULED_TYPE = STANDARD_NAK; // [4] 
                TX_ACKNAK_FLIT_SEQ_NUM = mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1); // [4] 
                rx_retry_buffer.delete(); // Purge all stored flits [4] 
                RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = 10'h0; // [4] 
                NAK_WITHDRAWAL_ALLOWED = 1'b0; 
            end 
        end 
 
        5: begin // Standard Nak after Selective Replay (Overflow resolution) 
            NAK_SCHEDULED = 1'b1; // Remains set [5] 
            NAK_SCHEDULED_TYPE = STANDARD_NAK; // [5] 
            TX_ACKNAK_FLIT_SEQ_NUM = RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM; // [5] 
            RX_RETRY_BUFFER_OVERFLOW = 1'b0; // [5] 
            NAK_WITHDRAWAL_ALLOWED = 1'b0;  
            NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM, 10'h1); // [5] 
            RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = 10'h0; // [5] 
        end 
 
        6: begin // Escalation due to new error during Selective Nak 
            discard_flit(1); // [5] 
            NAK_SCHEDULED = 1'b1;  
            NAK_SCHEDULED_TYPE = STANDARD_NAK; // [5] 
            RX_RETRY_BUFFER_OVERFLOW = 1'b0;  
            NAK_WITHDRAWAL_ALLOWED = 1'b0;  
            TX_ACKNAK_FLIT_SEQ_NUM = mod1023_sub(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1); // [5] 
            rx_retry_buffer.delete(); // Purge buffer [5] 
        end 
 
        7: begin // Implementation-specific Escalation 
            // Permitted to change Selective to Standard for any reason [6, 7] 
            NAK_SCHEDULED_TYPE = STANDARD_NAK;  
        end 
    endcase 
endtask

// Ack Schedule Implementation  
task execute_ack_schedule(int id);
       `uvm_info("EP_DL_MODEL","Entered execute ack schedule",UVM_LOW);	
    case (id) 
        0: begin // Normal Forward Progress 
            TX_ACKNAK_FLIT_SEQ_NUM = NEXT_EXPECTED_RX_FLIT_SEQ_NUM; // [6] 
            NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(NEXT_EXPECTED_RX_FLIT_SEQ_NUM, 10'h1); // [6]
       `uvm_info("EP_DL_MODEL",$sformatf("TX_ACKNAK_FLIT_SEQ_NUM updated after collecting the packet=%d",TX_ACKNAK_FLIT_SEQ_NUM),UVM_LOW);	
        end 
 
        1: begin // Standard Nak Recovery Success 
            NAK_SCHEDULED = 1'b0; // Clear Nak flag [6] 
            TX_ACKNAK_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM; // [6] 
            NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(IMPLICIT_RX_FLIT_SEQ_NUM, 10'h1); // [6] 
        end 
 
        2: begin // Selective Nak Recovery Success 
            NAK_SCHEDULED = 1'b0; // Clear Nak flag [6] 
            if (rx_retry_buffer.size() == 0) begin // Buffer is empty [6] 
                // N here represents current Implicit ID 
                TX_ACKNAK_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM;  
                NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(IMPLICIT_RX_FLIT_SEQ_NUM, 10'h1);  
            end else begin // Buffer has valid subsequent flits [6] 
                TX_ACKNAK_FLIT_SEQ_NUM = RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM;  
                NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM, 10'h1);  
                RX_RETRY_BUFFER_LAST_FLIT_SEQ_NUM = 10'h0;  
            end 
        end 
 
        3: begin // Successful Nak Withdrawal (Corrupted flit was a NOP) 
            NAK_WITHDRAWAL_ALLOWED = 1'b0; // [8] 
            TX_ACKNAK_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM; // [8] 
            NEXT_EXPECTED_RX_FLIT_SEQ_NUM = mod1023_add(IMPLICIT_RX_FLIT_SEQ_NUM, 10'h1); // [8] 
        end 
    endcase 
endtask 
/*********************************************************************************/
//					RX_EP
/*********************************************************************************/

// Handling the incoming flit and passing info to EP
  task handle_incoming_flit(bit[5:0][7:0]dlp, bit is_valid);

    bit[1:0]is_nop;
    bit prior_was_payload;
    bit[9:0]sequence_number;
    bit is_idle;
    bit is_payload;
    bit is_explicit;
    bit [1:0] flit_usage;

    //is_nop=(!(sequence_number == 10'h0) && dlp[0][7:6]==2'b00);
    is_nop=1;
    prior_was_payload=dlp[0][5];
    sequence_number={dlp[0][1:0], dlp[1]};
    replay_cmd = dlp[4][3:2];
    flit_usage = dlp[0][7:6]; 
    //is_payload=(flit_usage == 2'b01);
    is_payload=1;
    is_explicit=(replay_cmd == 2'b00);
    is_idle = (sequence_number == 10'h0) && (replay_cmd == 2'b00) && (flit_usage == 2'b00);   
    received_explicit_seq_0 = (sequence_number == 10'h0) && (replay_cmd == 2'b00); 
    received_explicit_seq = (replay_cmd == 2'b00);

   // `uvm_info("EP_DL_MODEL",$sformatf("DLP=%p, valid=%d, sequence_number=%d, is_nop=%d, prior_was_payload=%d,is_idle=%d,is_explicit=%d",dlp,is_valid,sequence_number,is_nop,prior_was_payload,is_idle,is_explicit),UVM_LOW);

    update_implicit_rx_sequence_number(sequence_number,is_valid,is_nop,is_payload,is_explicit,is_idle,prior_was_payload);
    
    //`uvm_info("EP_DL_MODEL",$sformatf("NEXT_TX_FLIT_SEQ_NUM = %h, NEXT_EXPECTED_RX_FLIT_SEQ_NUM = %h,IMPLICIT_RX_FLIT_SEQ_NUM = %h,ACKD_FLIT_SEQ_NUM = %h",NEXT_TX_FLIT_SEQ_NUM,NEXT_EXPECTED_RX_FLIT_SEQ_NUM,IMPLICIT_RX_FLIT_SEQ_NUM,ACKD_FLIT_SEQ_NUM),UVM_LOW);
	  
    // 1. Invalid Flit Handling
    if (!is_valid) begin 
        if (NAK_SCHEDULED) begin 
            if (NAK_SCHEDULED_TYPE == STANDARD_NAK) discard_flit(1); 
            else execute_nak_schedule(6); // Escalate Selective to Standard
        end else begin 
            if (NAK_WITHDRAWAL_ALLOWED) execute_nak_schedule(1); // Immediate Nak
            else execute_nak_schedule(0); // Initial detection, set withdrawal flag
        end 
        return; 
    end

    //2. TX side ack_nack purge buffer and replay logic
    process_received_ack_nak(sequence_number,replay_cmd);  //1. pass sequence_number, replay_cmd to debug and check purge logic.					  //2. Pass nak=1 to check the replay logic
       
    // 3. Protocol Violation Check 
    if (received_explicit_seq_0 && !is_idle) begin 
    log_data_link_protocol_error(); // Properly handles Flit Discard 2
    return; 
    end 
   
    // 4. Resolve Nak Withdrawal
    if (NAK_WITHDRAWAL_ALLOWED) begin 
        if (prior_was_payload) begin 
             handle_payload_withdrawal_failure(is_nop); // Calls Schedules 1 or procedures
        end else begin 
            if (bad_sequence_number()) execute_nak_schedule(2); 
            else execute_ack_schedule(3); // Withdrawal Succeeded!
        end 
        return; 
    end 
 
    // 5. Normal Processing
    if (is_nop) begin
        if (bad_nop_sequence_number()) execute_nak_schedule(2); 
        else discard_flit(0); 
    end else begin 
        if (NAK_SCHEDULED) begin 
            if (NAK_SCHEDULED_TYPE == STANDARD_NAK) standard_nak_procedure(); 
            else selective_nak_procedure(); 
        end else begin 
            if (duplicate_sequence_number()) discard_flit(0);
            else if (bad_sequence_number()) execute_nak_schedule(2); 
	    else begin
		    execute_ack_schedule(0); // Success!
		    success=1;
	    end 
        end 
    end 
endtask

/***********************************************************************************************/
// 				RC_TX logic
/***********************************************************************************************/
 // 2. TX logic handling
    task process_received_ack_nak(bit [9:0] N, bit[1:0]replay_cmd); 
       bit guard_future, guard_past; 
       bit is_ack, is_nak;
       
       if(replay_cmd==2'b01)
	       is_ack=1'b1;
       else if(replay_cmd==2'b10)
       	begin
	       is_nak=1'b1;
	       REPLAY_SCHEDULED_TYPE=STANDARD_REPLAY;
       	end
	else if (replay_cmd==2'b11)
	begin
		is_nak=1'b1;
	       REPLAY_SCHEDULED_TYPE=SELECTIVE_REPLAY;
	end

       //`uvm_info("EP_DL_MODEL",$sformatf("N=%d :: is_nak=%d :: is_ack=%d", N,is_nak,is_ack),UVM_LOW);

       // Rule: Ack/Nak with Sequence Number 0 must be ignored 
       if (N == 10'h0) return;
        
       // Guard 1: Future Check (Is partner Ack'ing unsent flits?) 
       guard_future = (mod1023_sub(NEXT_TX_FLIT_SEQ_NUM - 10'h1, N) <= MAX_UNACKNOWLEDGED_FLITS); 
       // Guard 2: Past Check (Is partner Ack'ing already-purged flits?) 
       guard_past   = (mod1023_sub(N, ACKD_FLIT_SEQ_NUM) <= MAX_UNACKNOWLEDGED_FLITS); 
       `uvm_info("EP_DL_MODEL",$sformatf("ACKD_FLIT_SEQ_NUM=%d :: gaurd_future=%d :: gaurd_past=%d", ACKD_FLIT_SEQ_NUM,guard_future,guard_past),UVM_LOW);
 
       if (!(guard_future && guard_past)) begin 
          log_data_link_protocol_error();
        return; 
       end 
       
     // Common Buffer Management for valid N 
     purge_tx_retry_buffer(N);   // current debug by passing N value from our end.
     
     if (mod1023_sub(N, ACKD_FLIT_SEQ_NUM) > 0) begin 
        FLIT_REPLAY_NUM = 3'h0; // Clear replay attempts on progress 
        ACKD_FLIT_SEQ_NUM = N; 
    end 
 
    if (is_ack) begin 
        NAK_IGNORE_FLIT_SEQ_NUM = 10'h0; 
        if (mod1023_sub(N, TX_REPLAY_FLIT_SEQ_NUM) < MAX_UNACKNOWLEDGED_FLITS) begin 
            TX_REPLAY_FLIT_SEQ_NUM = 10'h0; 
        end 
    end  
    else if (is_nak) begin 
       `uvm_info("EP_DL_MODEL", "Entered the nak logic",UVM_LOW);	
        // Handle Nak Ignore Window 
        if (N == mod1023_sub(NEXT_TX_FLIT_SEQ_NUM, 10'h1)) begin 
            NAK_IGNORE_FLIT_SEQ_NUM = N; 
        end else if (N != NAK_IGNORE_FLIT_SEQ_NUM) begin 
            NAK_IGNORE_FLIT_SEQ_NUM = 10'h0; 
        end 
        // Trigger Replay Scheduler 
        schedule_replay(N + 10'h1);
    end 
endtask

// Modulo 1023 check: Is sequence S "older than or including" N? 
function automatic bit is_older_than_or_including(bit [9:0] S, bit [9:0] N); 
    // Distance formula: (N - S) mod 1023 
    return (mod1023_sub(N, S) <= MAX_UNACKNOWLEDGED_FLITS); 
endfunction 


task purge_tx_retry_buffer(bit [9:0] N); 
	`uvm_info("EP_DL_MODEL",$sformatf("PURGING: Entry size of buffer ::  %d",tx_retry_buffer.size()),UVM_LOW); 
    while (tx_retry_buffer.size()>0) begin 
        // Identify flit sequence number S stored in buffer at index i 
        bit [9:0] S = tx_retry_buffer[0].seq_num; 
	    `uvm_info("EP_DL_MODEL",$sformatf("Sequence number flit deleted from the buffer is ::S=%d",S),UVM_LOW); 
        if (is_older_than_or_including(S, N)) begin 
            tx_retry_buffer.pop_front(); // Remove flit older than or including N
        end
	else begin
		break;
	end	
    end 
    //`uvm_info("EP_DL_MODEL",$sformatf("PURGING: Final buffer size is %d", tx_retry_buffer.size()),UVM_LOW);
endtask

task schedule_replay(bit [9:0] start_seq);
       `uvm_info("EP_DL_MODEL", "Entered the replay schedule task_",UVM_LOW);	
    REPLAY_SCHEDULED = 1'b1; 
    EP_REPLAY_IN_PROGRESS = 1'b1; 
    TX_REPLAY_FLIT_SEQ_NUM = start_seq; 
    // Type (Standard/Selective) is set by calling logic based on Nak type [5] 
endtask

// storing the tx_retry_buffer
task store_tx_retry_buffer(input bit [235:0][7:0] tlp_data,input bit [9:0]seq_num);
tx_retry_buffer.push_back('{tlp_data: tlp_data, seq_num : seq_num});
//`uvm_info("EP_DL_MODEL",$sformatf("The content of the retry buffer is %p",tx_retry_buffer),UVM_LOW);
endtask

task update_implicit_rx_sequence_number(
    input bit [9:0] N,           // Extracted Flit Sequence Number from DLP
    input bit is_valid,          // CRC/ECC check result
    input bit is_nop,            // Flit Usage = 00b and not IDLE
    input bit is_payload,        // Flit Usage = 01b
    input bit is_explicit,       // Replay Command = 00b
    input bit is_idle,           // IDLE Flit per Table 4-16 [2]
    input bit prior_was_payload  // DLP0[4] from current flit [3]
);

    // 1. "Set to N" Rule
    // If a valid non-IDLE Explicit Flit is received with N != 0, 
    // the counter is set directly to N.
    if (is_valid && !is_idle && is_explicit && (N != 10'h0)) begin
        IMPLICIT_RX_FLIT_SEQ_NUM = N;
        NON_IDLE_EXPLICIT_SEQ_NUM_FLIT_RCVD = 1'b1; // Mark that handshake has progressed
    `uvm_info("EP_DL_MODEL","IMPLICIT_NUMBER_ASSIGNED_TO_N",UVM_LOW);
    end

    // 2. "No Change" Rules
    else if (
        is_idle ||                                     // IDLE Flit received
        (is_explicit && (N == 10'h0)) ||               // Explicit Seq 0 received
        (!NON_IDLE_EXPLICIT_SEQ_NUM_FLIT_RCVD &&       // Handshake not finished AND
         (!is_valid || !is_explicit)) ||               // (Invalid OR non-explicit)
        (is_valid && is_nop && !is_explicit &&         // Valid non-explicit NOP AND
         (!NAK_WITHDRAWAL_ALLOWED || prior_was_payload)) || 
        (is_valid && is_payload && !is_explicit &&    // Valid non-explicit Payload AND
         (NAK_WITHDRAWAL_ALLOWED && !prior_was_payload))
    ) begin
        // IMPLICIT_RX_FLIT_SEQ_NUM does not change
        IMPLICIT_RX_FLIT_SEQ_NUM = IMPLICIT_RX_FLIT_SEQ_NUM;
    `uvm_info("EP_DL_MODEL","IMPLICIT_NUMBER_NO_CHANGE",UVM_LOW);
    end

    // 3. "Increment" Rules
    else if (
        (NON_IDLE_EXPLICIT_SEQ_NUM_FLIT_RCVD && !is_valid) || // Invalid flit after handshake
        (is_valid && is_payload && !is_explicit &&            // Valid non-explicit Payload AND
         (!NAK_WITHDRAWAL_ALLOWED || prior_was_payload))      // (No withdrawal OR prior was payload)
    ) begin
        IMPLICIT_RX_FLIT_SEQ_NUM = mod1023_add(IMPLICIT_RX_FLIT_SEQ_NUM, 10'h1);
    `uvm_info("EP_DL_MODEL","IMPLICIT_NUMBER_INCREMENTED",UVM_LOW);
    end

    // 4. "Decrement" Rules
    else if (
        is_valid && is_nop && !is_explicit &&          // Valid non-explicit NOP AND
        NAK_WITHDRAWAL_ALLOWED && !prior_was_payload   // Withdrawal allowed AND prior was NOP
    ) begin
        IMPLICIT_RX_FLIT_SEQ_NUM = mod1023_sub(IMPLICIT_RX_FLIT_SEQ_NUM, 10'h1);
    `uvm_info("EP_DL_MODEL","IMPLICIT_NUMBER_DECREMENTED",UVM_LOW);
    end

endtask
 
  // DL model consumes TL output, creates the DLP, then publishes to PL.
  function void write(PCIe_sequence_item item);
   //	  if(!item.drive_flit)
   `uvm_info("EP_DL_MODEL",$sformatf("DL -> PL: item from driver=%p", item.tlp_data),UVM_LOW)
   //	else if(item.replay_flit)
   //`uvm_info("EP_DL_MODEL",$sformatf("DL -> PL: replayed_item_from_driver=%p", item.tlp_data),UVM_LOW)
    
    form_dl_packet(item.tlp_data, item.is_payload, item.dlp_flit_out);
    dl_ap.write(item);
  endfunction
   

endclass
 
  


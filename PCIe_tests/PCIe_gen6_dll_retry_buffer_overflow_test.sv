//=========================================================================================
// File         : PCIe_gen6_dll_retry_buffer_overflow_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_retry_buffer_overflow_test.sv
// Author       :
// Date         : 2026-11-21
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

// 188 : Tx retry buffer overflow is avoided
//   - Tx retry buffer depth = 4 flits, EP holds its Ack, RC has 12 MemWr to send.
//   - After 4 flits the buffer is full : RC must STALL (no 5th flit, no overflow,
//     nothing lost) until an Ack frees space (Sec 4.2.3.4.2 : a flit may only be
//     sent when it can be kept for replay).
// Run : +UVM_TESTNAME=PCIe_gen6_dll_retry_buffer_overflow_test   (needs +define+PCIE_GEN6_FEC_CRC)

class PCIe_gen6_dll_retry_buffer_overflow_test extends PCIe_gen6_dll_base_test;

  `uvm_component_utils(PCIe_gen6_dll_retry_buffer_overflow_test)

  function new(string name = "PCIe_gen6_dll_retry_buffer_overflow_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    set_dll_sequence(PCIe_RC_dll_retry_buffer_overflow_sequence::get_type());
    super.build_phase(phase);
  endfunction

  task dll_test_body();
    int unsigned n     = 12;
    int unsigned depth = 4;
    int unsigned sent_while_full, size_full;
    wait_retry_empty();
    rc_dl.tx_retry_depth = depth;
    rc_dl.tx_retry_peak  = 0;
    ep_dl.hold_ack       = 1'b1;
    seq_go.trigger();

    // wait until RC stalls on the full buffer
    repeat (300) begin
      if (rc_dl.n_tx_stall > stall0) break;
      #1us;
    end
    #3us;
    sent_while_full = tlps_rcvd();
    size_full       = rc_dl.tx_retry_buffer.size();
    `uvm_info(get_type_name(), $sformatf("RC STALLED : %0d flits sent, retry buffer %0d/%0d -> RELEASE THE ACK",
              sent_while_full, size_full, depth), UVM_NONE)
    ep_dl.hold_ack = 1'b0;

    seq_done.wait_on();
    wait_tlps(n);
    wait_retry_empty();
    #2us;

    dll_check(rc_dl.n_tx_stall - stall0 >= 1, "RC_STALLED_WHEN_FULL", $sformatf("%0d stall(s)", rc_dl.n_tx_stall - stall0));
    dll_check(size_full == depth, "RETRY_BUFFER_FULL", $sformatf("%0d of %0d entries", size_full, depth));
    dll_check(sent_while_full == depth, "NO_FLIT_SENT_WHILE_FULL", $sformatf("%0d flits sent with no Ack (max %0d)", sent_while_full, depth));
    dll_check(rc_dl.tx_retry_peak <= depth, "NO_OVERFLOW", $sformatf("peak occupancy %0d (max %0d)", rc_dl.tx_retry_peak, depth));
    dll_check(rc_dl.n_replay_events - rep_ev0 == 0, "NO_REPLAY", "no flit was lost");
    check_all_delivered(n);
    rc_dl.tx_retry_depth = `PCIe_MAX_UNACK_FLITS;
  endtask

endclass

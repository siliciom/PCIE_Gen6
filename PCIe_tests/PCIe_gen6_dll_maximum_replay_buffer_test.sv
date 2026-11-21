//=========================================================================================
// File         : PCIe_gen6_dll_maximum_replay_buffer_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_maximum_replay_buffer_test.sv
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

// 187 : replay (Tx retry) buffer with the maximum number of outstanding flits
//   - Tx retry buffer depth = 8 flits (scaled down from 511 to keep the run short).
//   - EP holds its Ack, RC sends 8 MemWr -> 8 unacknowledged flits = buffer FULL.
//   - EP then sends ONE Ack (seq of flit 8) -> all 8 purged (Sec 4.2.3.4.2).
// Run : +UVM_TESTNAME=PCIe_gen6_dll_maximum_replay_buffer_test   (needs +define+PCIE_GEN6_FEC_CRC)

class PCIe_gen6_dll_maximum_replay_buffer_test extends PCIe_gen6_dll_base_test;

  `uvm_component_utils(PCIe_gen6_dll_maximum_replay_buffer_test)

  function new(string name = "PCIe_gen6_dll_maximum_replay_buffer_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    set_dll_sequence(PCIe_RC_dll_maximum_replay_buffer_sequence::get_type());
    super.build_phase(phase);
  endfunction

  task dll_test_body();
    int unsigned n     = 8;
    int unsigned depth = 8;
    int unsigned full_size;
    wait_retry_empty();             // nothing outstanding from the enumeration
    rc_dl.tx_retry_depth = depth;
    rc_dl.tx_retry_peak  = 0;
    ep_dl.hold_ack       = 1'b1;
    seq_go.trigger();

    seq_done.wait_on();
    wait_tlps(n);
    #2us;
    full_size = rc_dl.tx_retry_buffer.size();
    `uvm_info(get_type_name(), $sformatf("RETRY BUFFER = %0d/%0d -> RELEASE THE ACK", full_size, depth), UVM_NONE)
    ep_dl.hold_ack = 1'b0;
    wait_retry_empty();
    #2us;

    dll_check(full_size == depth, "RETRY_BUFFER_FULL", $sformatf("%0d of %0d entries used with no Ack", full_size, depth));
    dll_check(rc_dl.tx_retry_peak <= depth, "NEVER_ABOVE_MAX", $sformatf("peak occupancy %0d (max %0d)", rc_dl.tx_retry_peak, depth));
    dll_check(rc_dl.n_tx_stall - stall0 == 0, "NO_STALL_UP_TO_MAX", "8 flits fit exactly in the buffer");
    dll_check(rc_dl.flit_rx_cnt[PCIe_RC_DL_model::FLTC_ACK] - ack0 >= 1, "ACK_RECEIVED",
          $sformatf("RC received %0d Ack", rc_dl.flit_rx_cnt[PCIe_RC_DL_model::FLTC_ACK] - ack0));
    dll_check(rc_dl.n_replay_events - rep_ev0 == 0, "NO_REPLAY", "no flit was lost");
    check_all_delivered(n);
    rc_dl.tx_retry_depth = `PCIe_MAX_UNACK_FLITS;
  endtask

endclass

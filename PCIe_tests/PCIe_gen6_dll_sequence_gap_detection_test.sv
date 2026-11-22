//=========================================================================================
// File         : PCIe_gen6_dll_sequence_gap_detection_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_sequence_gap_detection_test.sv
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

// 185 : a missing flit sequence number is detected
//   - 6 MemWr. Flit 3 is lost on the link (never reaches the EP DL).
//   - EP gets seq N+2 while it expects N+1 -> sequence gap -> Nak (Sec 4.2.3.4.2.1).
//   - RC replays from the missing flit, nothing is lost.
// Run : +UVM_TESTNAME=PCIe_gen6_dll_sequence_gap_detection_test   (needs +define+PCIE_GEN6_FEC_CRC)

class PCIe_gen6_dll_sequence_gap_detection_test extends PCIe_gen6_dll_base_test;

  `uvm_component_utils(PCIe_gen6_dll_sequence_gap_detection_test)

  function new(string name = "PCIe_gen6_dll_sequence_gap_detection_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    set_dll_sequence(PCIe_RC_dll_sequence_gap_detection_sequence::get_type());
    super.build_phase(phase);
  endfunction

  task dll_test_body();
    int unsigned n = 6;
    ep_dl.drop_rx_skip = 2;         // flits 1, 2 are good
    ep_dl.drop_rx_cnt  = 1;         // flit 3 is lost
    seq_go.trigger();

    seq_done.wait_on();
    wait_tlps(n);
    wait_retry_empty();
    #2us;

    dll_check(ep_dl.n_rx_dropped == 1, "FLIT_LOST_ON_LINK", $sformatf("%0d flit lost", ep_dl.n_rx_dropped));
    dll_check(ep_dl.n_seq_gap_detected >= 1, "SEQUENCE_GAP_DETECTED", $sformatf("%0d gap(s) detected", ep_dl.n_seq_gap_detected));
    dll_check(ep_dl.flit_rx_bad - bad0 == 0, "NO_CRC_ERROR", "gap found by sequence number only, not by CRC");
    dll_check(naks_sent() - nak0 >= 1, "NAK_SENT_FOR_GAP", $sformatf("EP sent %0d Nak", naks_sent() - nak0));
    dll_check(rc_dl.n_replay_events - rep_ev0 >= 1, "REPLAY_DONE", $sformatf("%0d replay(s)", rc_dl.n_replay_events - rep_ev0));
    check_all_delivered(n);
  endtask

endclass

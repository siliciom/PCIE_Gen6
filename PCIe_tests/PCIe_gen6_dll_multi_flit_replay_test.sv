//=========================================================================================
// File         : PCIe_gen6_dll_multi_flit_replay_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_multi_flit_replay_test.sv
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

// 184 : multiple consecutive flits are retransmitted after ONE replay request
//   - 6 MemWr. Flit 2 gets a CRC error at the EP.
//   - EP holds its Nak until all 6 flits arrived (flits 3..6 are discarded :
//     a Nak is pending, Sec 4.2.3.4.2.1).
//   - One Nak -> RC replays flits 2..6 (5 flits) with their own sequence numbers.
// Run : +UVM_TESTNAME=PCIe_gen6_dll_multi_flit_replay_test   (needs +define+PCIE_GEN6_FEC_CRC)

class PCIe_gen6_dll_multi_flit_replay_test extends PCIe_gen6_dll_base_test;

  `uvm_component_utils(PCIe_gen6_dll_multi_flit_replay_test)

  function new(string name = "PCIe_gen6_dll_multi_flit_replay_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    set_dll_sequence(PCIe_RC_dll_multi_flit_replay_sequence::get_type());
    super.build_phase(phase);
  endfunction

  task dll_test_body();
    int unsigned n = 6;
    expect_link_errors(1);
    ep_dl.hold_nak    = 1'b1;
    ep_mon.inj_type   = 2;          // CRC error
    ep_mon.inj_skip   = 1;          // flit 1 is good
    ep_mon.inj_count  = 1;          // flit 2 is bad
    seq_go.trigger();

    seq_done.wait_on();
    wait_flits_at_ep(n);            // all 6 flits are at the EP
    #1us;
    `uvm_info(get_type_name(), "ALL FLITS RECEIVED -> RELEASE THE NAK", UVM_NONE)
    ep_dl.hold_nak = 1'b0;
    wait_tlps(n);
    wait_retry_empty();
    #2us;
    expect_link_errors(0);

    dll_check(ep_dl.flit_rx_bad - bad0 == 1, "BAD_FLIT_DETECTED", $sformatf("%0d bad flit", ep_dl.flit_rx_bad - bad0));
    dll_check(naks_sent() - nak0 >= 1, "NAK_SENT", $sformatf("EP sent %0d Nak", naks_sent() - nak0));
    dll_check(ep_dl.n_rx_rejected >= n - 2, "FLITS_AFTER_BAD_ONE_DISCARDED",
          $sformatf("%0d good flits discarded while the Nak was pending", ep_dl.n_rx_rejected));
    dll_check(rc_dl.n_replay_events - rep_ev0 >= 1, "REPLAY_STARTED", $sformatf("%0d replay(s)", rc_dl.n_replay_events - rep_ev0));
    dll_check(rc_dl.flit_tx_replay - rep_flit0 >= n - 1, "MULTIPLE_FLITS_REPLAYED",
          $sformatf("%0d flits replayed (expected >= %0d : flits 2..%0d)", rc_dl.flit_tx_replay - rep_flit0, n - 1, n));
    check_all_delivered(n);
  endtask

endclass

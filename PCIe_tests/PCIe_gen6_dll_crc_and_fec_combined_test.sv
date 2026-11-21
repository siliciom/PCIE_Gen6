//=========================================================================================
// File         : PCIe_gen6_dll_crc_and_fec_combined_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_crc_and_fec_combined_test.sv
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

// 192 : FEC correction and CRC check working together (Sec 4.2.3.4)
//   Batch 1 (4 MemWr) : 1 byte error in flit 2 -> FEC corrects it, CRC passes,
//                       flit accepted, NO Nak, NO replay.
//   Batch 2 (4 MemWr) : 2 byte errors in flit 2 -> FEC cannot fix, CRC fails,
//                       Nak, replay.
// Run : +UVM_TESTNAME=PCIe_gen6_dll_crc_and_fec_combined_test   (needs +define+PCIE_GEN6_FEC_CRC)

class PCIe_gen6_dll_crc_and_fec_combined_test extends PCIe_gen6_dll_base_test;

  `uvm_component_utils(PCIe_gen6_dll_crc_and_fec_combined_test)

  function new(string name = "PCIe_gen6_dll_crc_and_fec_combined_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    set_dll_sequence(PCIe_RC_dll_crc_and_fec_combined_sequence::get_type());
    super.build_phase(phase);
  endfunction

  task dll_test_body();
    PCIe_RC_dll_crc_and_fec_combined_sequence seq2;
    int unsigned n = 4;
    int unsigned nak1, rep1, crc_bad1, tlp1;

    // ---------------- batch 1 : correctable FEC error ----------------
    expect_link_errors(1);
    ep_mon.inj_type  = 1;
    ep_mon.inj_skip  = 1;
    ep_mon.inj_count = 1;
    seq_go.trigger();
    seq_done.wait_on();
    wait_tlps(n);
    wait_retry_empty();
    #2us;
    dll_check(ep_mon.fec_corrected_flit_cnt - fec_cor0 == 1, "B1_FEC_CORRECTED", "1 symbol corrected by FEC");
    dll_check(ep_mon.n_crc_bad - crc_bad0 == 0, "B1_CRC_PASSES_AFTER_FEC", "CRC matched after the correction");
    dll_check(ep_dl.flit_rx_bad - bad0 == 0, "B1_FLIT_VALID", "flit accepted");
    dll_check(naks_sent() - nak0 == 0, "B1_NO_NAK", "no Nak for a corrected flit");
    dll_check(rc_dl.n_replay_events - rep_ev0 == 0, "B1_NO_REPLAY", "no replay");
    dll_check(tlps_rcvd() == n, "B1_ALL_DELIVERED", $sformatf("%0d of %0d", tlps_rcvd(), n));

    // ---------------- batch 2 : CRC error ----------------
    nak1 = naks_sent(); rep1 = rc_dl.n_replay_events; crc_bad1 = ep_mon.n_crc_bad; tlp1 = tlps_rcvd();
    ep_mon.inj_type  = 2;
    ep_mon.inj_skip  = 1;
    ep_mon.inj_count = 1;
    seq2 = PCIe_RC_dll_crc_and_fec_combined_sequence::type_id::create("seq2");
    seq2.start(pcie_environment.rc_top_agent.rc_controller_agent.rc_controller_sequencer);
    wait_tlps(2 * n);
    wait_retry_empty();
    #2us;
    expect_link_errors(0);
    dll_check(ep_mon.n_crc_bad - crc_bad1 == 1, "B2_CRC_ERROR_DETECTED", "CRC failed after FEC");
    dll_check(naks_sent() - nak1 >= 1, "B2_NAK_SENT", $sformatf("EP sent %0d Nak", naks_sent() - nak1));
    dll_check(rc_dl.n_replay_events - rep1 >= 1, "B2_REPLAY_DONE", $sformatf("%0d replay(s)", rc_dl.n_replay_events - rep1));
    dll_check(tlps_rcvd() - tlp1 == n, "B2_ALL_DELIVERED", $sformatf("%0d of %0d", tlps_rcvd() - tlp1, n));
    check_all_delivered(2 * n);
  endtask

endclass

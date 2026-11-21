//=========================================================================================
// File         : PCIe_gen6_dll_uncorrectable_fec_error_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_uncorrectable_fec_error_test.sv
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

// 191 : an uncorrectable FEC error triggers a replay (Sec 4.2.3.4.2 / 4.2.3.4.4)
//   - 6 MemWr. In flit 2 the Check and Parity byte of ECC group 0 are hit :
//     the decoder points to a non-existing column = UNCORRECTABLE.
//   - "A valid Flit ... none of the ECC groups are reporting an uncorrectable
//     error" -> flit not valid even if its CRC matches -> Nak, replay.
// Run : +UVM_TESTNAME=PCIe_gen6_dll_uncorrectable_fec_error_test   (needs +define+PCIE_GEN6_FEC_CRC)

class PCIe_gen6_dll_uncorrectable_fec_error_test extends PCIe_gen6_dll_base_test;

  `uvm_component_utils(PCIe_gen6_dll_uncorrectable_fec_error_test)

  function new(string name = "PCIe_gen6_dll_uncorrectable_fec_error_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    set_dll_sequence(PCIe_RC_dll_uncorrectable_fec_error_sequence::get_type());
    super.build_phase(phase);
  endfunction

  task dll_test_body();
    int unsigned n = 6;
    expect_link_errors(1);
    ep_mon.inj_type  = 3;           // FEC uncorrectable
    ep_mon.inj_skip  = 1;
    ep_mon.inj_count = 1;
    seq_go.trigger();
    seq_done.wait_on();
    wait_tlps(n);
    wait_retry_empty();
    #2us;
    expect_link_errors(0);

    dll_check(ep_mon.inj_done == 1, "ERROR_INJECTED", "1 flit corrupted");
    dll_check(ep_mon.fec_uncorrectable_flit_cnt - fec_unc0 == 1, "FEC_UNCORRECTABLE_DETECTED",
          $sformatf("%0d uncorrectable flit", ep_mon.fec_uncorrectable_flit_cnt - fec_unc0));
    dll_check(ep_mon.n_crc_bad - crc_bad0 == 0, "CRC_STILL_MATCHES", "data bytes not hit, only the ECC bytes");
    dll_check(ep_dl.flit_rx_bad - bad0 == 1, "FLIT_NOT_VALID", $sformatf("%0d bad flit", ep_dl.flit_rx_bad - bad0));
    dll_check(naks_sent() - nak0 >= 1, "NAK_SENT", $sformatf("EP sent %0d Nak", naks_sent() - nak0));
    dll_check(rc_dl.n_replay_events - rep_ev0 >= 1, "REPLAY_DONE", $sformatf("%0d replay(s)", rc_dl.n_replay_events - rep_ev0));
    check_all_delivered(n);
  endtask

endclass

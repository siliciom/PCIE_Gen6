//=========================================================================================
// File         : PCIe_gen6_dll_flit_crc_generation_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_flit_crc_generation_test.sv
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

// 189 : the transmitter generates the correct 8B flit CRC (Sec 4.2.3.4.3)
//   - Clean link, 8 MemWr.
//   - The EP monitor recomputes the CRC over the 242B (TLP + DLP) of every
//     received flit and compares it with the 8B CRC sent by the RC.
// Run : +UVM_TESTNAME=PCIe_gen6_dll_flit_crc_generation_test   (needs +define+PCIE_GEN6_FEC_CRC)

class PCIe_gen6_dll_flit_crc_generation_test extends PCIe_gen6_dll_base_test;

  `uvm_component_utils(PCIe_gen6_dll_flit_crc_generation_test)

  function new(string name = "PCIe_gen6_dll_flit_crc_generation_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    set_dll_sequence(PCIe_RC_dll_flit_crc_generation_sequence::get_type());
    super.build_phase(phase);
  endfunction

  task dll_test_body();
    int unsigned n = 8;
    seq_go.trigger();
    seq_done.wait_on();
    wait_tlps(n);
    wait_retry_empty();
    #2us;

    dll_check(ep_mon.n_crc_ok - crc_ok0 >= n, "CRC_CORRECT_ON_EVERY_FLIT",
          $sformatf("%0d flits checked, CRC matched", ep_mon.n_crc_ok - crc_ok0));
    dll_check(ep_mon.n_crc_bad == 0, "NO_CRC_MISMATCH", $sformatf("%0d CRC mismatch since link up", ep_mon.n_crc_bad));
    dll_check(ep_mon.fec_corrected_flit_cnt - fec_cor0 == 0, "NO_FEC_CORRECTION", "clean link : FEC had nothing to correct");
    dll_check(ep_dl.flit_rx_bad - bad0 == 0, "NO_BAD_FLIT", "every flit valid");
    dll_check(naks_sent() - nak0 == 0, "NO_NAK", "no Nak");
    dll_check(rc_dl.n_replay_events - rep_ev0 == 0, "NO_REPLAY", "no replay");
    check_all_delivered(n);
  endtask

endclass

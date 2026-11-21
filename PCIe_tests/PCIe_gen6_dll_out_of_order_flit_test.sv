//=========================================================================================
// File         : PCIe_gen6_dll_out_of_order_flit_test.sv
// Project      : PCIE_Gen6
// Description  : PCIe_tests/PCIe_gen6_dll_out_of_order_flit_test.sv
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

// 186 : out-of-order flits are detected and handled
//   - 6 MemWr. Flits 2 and 3 arrive swapped (seq N+1 before seq N).
//   - EP must not accept seq N+1 early : gap -> Nak. The late flit N is then
//     taken, the replayed copy of N is a duplicate and is discarded.
//   - TL gets every MemWr once, in order.
// Run : +UVM_TESTNAME=PCIe_gen6_dll_out_of_order_flit_test   (needs +define+PCIE_GEN6_FEC_CRC)

class PCIe_gen6_dll_out_of_order_flit_test extends PCIe_gen6_dll_base_test;

  `uvm_component_utils(PCIe_gen6_dll_out_of_order_flit_test)

  function new(string name = "PCIe_gen6_dll_out_of_order_flit_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    set_dll_sequence(PCIe_RC_dll_out_of_order_flit_sequence::get_type());
    super.build_phase(phase);
  endfunction

  task dll_test_body();
    int unsigned n = 6;
    ep_dl.swap_rx_skip = 1;         // flit 1 is normal
    ep_dl.swap_rx_cnt  = 1;         // flit 2 arrives after flit 3
    seq_go.trigger();

    seq_done.wait_on();
    wait_tlps(n);
    wait_retry_empty();
    #2us;

    dll_check(ep_dl.n_rx_swapped == 1, "FLITS_SWAPPED", $sformatf("%0d flit pair swapped", ep_dl.n_rx_swapped));
    dll_check(ep_dl.n_seq_gap_detected >= 1, "OUT_OF_ORDER_DETECTED", $sformatf("%0d out-of-order flit(s) seen", ep_dl.n_seq_gap_detected));
    dll_check(ep_dl.n_rx_rejected >= 1, "WRONG_FLIT_NOT_ACCEPTED", $sformatf("%0d flit(s) discarded", ep_dl.n_rx_rejected));
    dll_check(naks_sent() - nak0 >= 1, "NAK_SENT", $sformatf("EP sent %0d Nak", naks_sent() - nak0));
    check_all_delivered(n);
  endtask

endclass

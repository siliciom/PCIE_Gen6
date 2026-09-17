//=========================================================================================
// File         : PCIe_RC_flit_idle_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_flit_idle_sequence.sv
// Author       :
// Date         : 2026-09-15
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

////////////////////////////////////////////////////////////////
// FILE:  PCIe_RC_flit_idle_sequence.sv
// DESC:  RC -> EP.  Drives an IDLE Flit (PCIe Base 6.1, Table 4-16 /
//        Sec 4.2.3.4.2.1.1 "IDLE Flit Handshake Phase"):
//          TLP Bytes [0..235] : NOP TLPs across all 236 Bytes
//          DLP Bytes 0,1      : All 0s (including Flit Sequence Number = 0)
//          DLP Bytes 2..5     : NOP2 DLLP
//        item.flit_type = PCIe_IDLE_flit tells PCIe_RC_TL_model::send_tlp()
//        to take the send_idle_or_nop_flit() bypass path instead of
//        serializing a request - there is no TL request here at all, so no
//        txn_type / address / length fields are set.
////////////////////////////////////////////////////////////////

class PCIe_RC_flit_idle_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_flit_idle_sequence)

  function new(string name="PCIe_RC_flit_idle_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("RC_FLIT_IDLE","ENTERED_INTO_RC_FLIT_IDLE_SEQUENCE_BODY", UVM_LOW)

    pcie_seq_item = PCIe_sequence_item::type_id::create("rc_idle_flit");
    start_item(pcie_seq_item);

    if (!pcie_seq_item.randomize() with {
         electrical_idle_test == 1'b0;
         no_receiver_test     == 1'b0;
         tx_elec_idle         == 1'b1;
         pkt_mode              == FLIT;
       })
      `uvm_error("RC_FLIT_IDLE","randomize failed for RC IDLE flit")

    // Non-rand control field - set directly after randomize(), same pattern
    // PCIe_RC_controller_base_sequence uses for is_payload.
    pcie_seq_item.flit_type = PCIe_IDLE_flit;   // Table 4-16 tag

    `uvm_info("RC_FLIT_IDLE","Sending IDLE flit RC->EP (Table 4-16)", UVM_LOW)
    finish_item(pcie_seq_item);

    `uvm_info("RC_FLIT_IDLE","EXIT_FROM_RC_FLIT_IDLE_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

//=========================================================================================
// File         : PCIe_RC_flit_nop_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_flit_nop_sequence.sv
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
// FILE:  PCIe_RC_flit_nop_sequence.sv
// DESC:  RC -> EP.  Drives a NOP Flit (PCIe Base 6.1, Table 4-16):
//          TLP Bytes [0..235] : NOP TLPs across all 236 Bytes  (same as IDLE)
//          DLP Bytes 0,1      : Flit Usage = 00b,
//                                Flit Sequence Number = NEXT_TX_FLIT_SEQ_NUM - 1
//                                if Replay Command is 00b
//          DLP Bytes 2..5     : Any valid encoding
//        A NOP Flit differs from an IDLE Flit only in the DLP (sequence
//        number / replay command handling in the DL layer) - the TLP bytes
//        are identical (all NOP TLPs). item.flit_type = PCIe_NOP_flit routes
//        this through the same PCIe_RC_TL_model::send_idle_or_nop_flit()
//        bypass as the IDLE sequence, tagged distinctly for logging / any
//        future DL-layer sequence-number handling.
////////////////////////////////////////////////////////////////

class PCIe_RC_flit_nop_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_flit_nop_sequence)

  function new(string name="PCIe_RC_flit_nop_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("RC_FLIT_NOP","ENTERED_INTO_RC_FLIT_NOP_SEQUENCE_BODY", UVM_LOW)

    pcie_seq_item = PCIe_sequence_item::type_id::create("rc_nop_flit");
    start_item(pcie_seq_item);

    if (!pcie_seq_item.randomize() with {
         electrical_idle_test == 1'b0;
         no_receiver_test     == 1'b0;
         tx_elec_idle         == 1'b1;
         pkt_mode              == FLIT;
       })
      `uvm_error("RC_FLIT_NOP","randomize failed for RC NOP flit")

    pcie_seq_item.flit_type = PCIe_NOP_flit;   // Table 4-16 tag

    `uvm_info("RC_FLIT_NOP","Sending NOP flit RC->EP (Table 4-16)", UVM_LOW)
    finish_item(pcie_seq_item);

    `uvm_info("RC_FLIT_NOP","EXIT_FROM_RC_FLIT_NOP_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

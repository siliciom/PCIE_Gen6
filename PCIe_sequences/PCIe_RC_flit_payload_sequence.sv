//=========================================================================================
// File         : PCIe_RC_flit_payload_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_flit_payload_sequence.sv
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
// FILE:  PCIe_RC_flit_payload_sequence.sv
// DESC:  RC -> EP.  Drives a Payload Flit (PCIe Base 6.1, Table 4-16):
//          TLP Bytes [0..235] : a portion of at least one non-NOP TLP
//          DLP Bytes 0,1      : Flit Usage = 01b,
//                                Flit Sequence Number != 00b if Replay
//                                Command is 00b
//          DLP Bytes 2..5     : Any valid encoding
//
//        This is a real TL request (3DW-header Mem Write, same shape as
//        PCIe_RC_3DW_flit_sequence) so it goes through the RC TL model's
//        normal path: PCIe_RC_TL_model::send_tlp() -> serialize_header() ->
//        build_complete_tlp() -> assemble_flit() -> pack_to_tlp_data(),
//        which stamps item.is_payload=1 and item.flit_type=PCIe_PAYLOAD_flit
//        itself (see pack_to_tlp_data() "DL flags" block) - the explicit
//        assignment below is only for readability before finish_item().
////////////////////////////////////////////////////////////////

class PCIe_RC_flit_payload_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_flit_payload_sequence)

  bit [31:0] mem_addr_32 = 32'h0000_2000;
  bit [31:0] wr_data     = 32'hA5A5_1234;

  function new(string name="PCIe_RC_flit_payload_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("RC_FLIT_PAYLOAD","ENTERED_INTO_RC_FLIT_PAYLOAD_SEQUENCE_BODY", UVM_LOW)

    // 3DW Memory Write (MWr_32) carried in a single Payload Flit
    pcie_seq_item = PCIe_sequence_item::type_id::create("rc_payload_flit");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         electrical_idle_test == 1'b0;
         no_receiver_test     == 1'b0;
         tx_elec_idle         == 1'b1;
         pkt_mode             == FLIT;

         txn_type == PCIe_TL_MEM;
         dir      == PCIe_TL_WRITE;

         mem_locked     == 1'b0;
         mem_deferrable == 1'b0;

         address == {32'h0, mem_addr_32};   // 32-bit address
         length  == 10'd1;                  // 1 DW payload

         first_dw_be == 4'hF;
         last_dw_be  == 4'h0;               // Length==1DW -> Last DW BE = 0000b

         ep == 1'b0;   // not poisoned

         tag          == 14'h0020;
         requester_id == 16'h0100;

         tc   == 3'h0;
         ts   == 3'b000;
         attr == 3'b000;
         at   == 2'b00;
       })
      `uvm_error("RC_FLIT_PAYLOAD","randomize failed for RC Payload flit (MWr)")

    pcie_seq_item.data[0]   = wr_data;
    pcie_seq_item.flit_type = PCIe_PAYLOAD_flit;   // Table 4-16 tag

    `uvm_info("RC_FLIT_PAYLOAD",
      $sformatf("Sending Payload flit RC->EP : MWR_32 addr=0x%08h data=0x%08h tag=0x%03h",
                 mem_addr_32, wr_data, pcie_seq_item.tag), UVM_LOW)
    finish_item(pcie_seq_item);

    `uvm_info("RC_FLIT_PAYLOAD","EXIT_FROM_RC_FLIT_PAYLOAD_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

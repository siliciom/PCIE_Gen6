//=========================================================================================
// File         : PCIe_RC_3DW_NonFlit_MemWr_followed_MemRd_MinPayload_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_3DW_NonFlit_MemWr_followed_MemRd_MinPayload_sequence.sv
// Author       :
// Date         : 2026-09-09
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

////////////////////////////////////////////////////////////////
// FILE:  PCIe_RC_3DW_NonFlit_MemWr_followed_MemRd_MinPayload_sequence.sv
// DESC:  3DW-header MemWr immediately followed by MemRd to the same address, NonFlit mode, minpayload.
////////////////////////////////////////////////////////////////

class PCIe_RC_3DW_NonFlit_MemWr_followed_MemRd_MinPayload_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_3DW_NonFlit_MemWr_followed_MemRd_MinPayload_sequence)


  function new(string name="PCIe_RC_3DW_NonFlit_MemWr_followed_MemRd_MinPayload_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("3DW_NONFLIT_MEMWR_FOLLOW","ENTERED_INTO_3DW_NONFLIT_MEMWR_FOLLOW_SEQUENCE_BODY", UVM_LOW)

    pcie_seq_item = PCIe_sequence_item::type_id::create("mwr");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         pkt_mode == NON_FLIT;

         txn_type == PCIe_TL_MEM;
         dir      == PCIe_TL_WRITE;

         mem_locked     == 1'b0;
         mem_deferrable == 1'b0;

         address == 32'h0000_2000;

         length  == `PCIe_TL_LEN_MIN;


         first_dw_be == 4'hF;

         ep == 1'b0;

         tag          == 14'h0011;
         requester_id == 16'h0100;

         tc   == 3'h0;
         ts   == 3'b000;
         attr == 3'b000;

         at == 2'b00;
       })
      `uvm_error("3DW_NONFLIT_MEMWR_FOLLOWED_MEMRD_MINPAYLOAD","randomize failed for mwr")

    `uvm_info("TL_MWR",$sformatf("Sending 3DW NonFlit MemWr (MinPayload) - part of Wr followed by Rd"), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);

    pcie_seq_item = PCIe_sequence_item::type_id::create("mrd");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         pkt_mode == NON_FLIT;

         txn_type == PCIe_TL_MEM;
         dir      == PCIe_TL_READ;

         mem_locked     == 1'b0;
         mem_deferrable == 1'b0;

         address == 32'h0000_2000;

         length  == `PCIe_TL_LEN_MIN;

         first_dw_be == 4'hF;

         ep == 1'b0;

         tag          == 14'h0011;
         requester_id == 16'h0100;

         tc   == 3'h0;
         ts   == 3'b000;
         attr == 3'b000;

         at == 2'b00;
       })
      `uvm_error("3DW_NONFLIT_MEMWR_FOLLOWED_MEMRD_MINPAYLOAD","randomize failed for mrd")

    `uvm_info("TL_MRD",$sformatf("Sending 3DW NonFlit MemRd (MinPayload) - readback of prior MemWr"), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);

    `uvm_info("3DW_NONFLIT_MEMWR_FOLLOW","EXIT_FROM_3DW_NONFLIT_MEMWR_FOLLOW_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

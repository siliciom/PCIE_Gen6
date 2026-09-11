//=========================================================================================
// File         : PCIe_RC_4DW_Flit_MemWr_followed_MemRd_MaxPayload_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_4DW_Flit_MemWr_followed_MemRd_MaxPayload_sequence.sv
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
// FILE:  PCIe_RC_4DW_Flit_MemWr_followed_MemRd_MaxPayload_sequence.sv
// DESC:  4DW-header MemWr immediately followed by MemRd to the same address, Flit mode, maxpayload.
////////////////////////////////////////////////////////////////

class PCIe_RC_4DW_Flit_MemWr_followed_MemRd_MaxPayload_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_4DW_Flit_MemWr_followed_MemRd_MaxPayload_sequence)


  function new(string name="PCIe_RC_4DW_Flit_MemWr_followed_MemRd_MaxPayload_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("4DW_FLIT_MEMWR_FOLLOWED_","ENTERED_INTO_4DW_FLIT_MEMWR_FOLLOWED__SEQUENCE_BODY", UVM_LOW)

    pcie_seq_item = PCIe_sequence_item::type_id::create("mwr");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         pkt_mode == FLIT;

         txn_type == PCIe_TL_MEM;
         dir      == PCIe_TL_WRITE;

         mem_locked     == 1'b0;
         mem_deferrable == 1'b0;

         address == 64'h0000_0001_0000_3000;

         length  == `PCIe_TL_LEN_MAX;

         first_dw_be == 4'hF;
         last_dw_be  == 4'hF;

         ep == 1'b0;

         tag          == 14'h0011;
         requester_id == 16'h0100;

         tc   == 3'h0;
         ts   == 3'b000;
         attr == 3'b000;

         at == 2'b00;
       })
      `uvm_error("4DW_FLIT_MEMWR_FOLLOWED_MEMRD_MAXPAYLOAD","randomize failed for mwr")

    `uvm_info("TL_MWR",$sformatf("Sending 4DW Flit MemWr (MaxPayload) - part of Wr followed by Rd"), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);

    pcie_seq_item = PCIe_sequence_item::type_id::create("mrd");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         pkt_mode == FLIT;

         txn_type == PCIe_TL_MEM;
         dir      == PCIe_TL_READ;

         mem_locked     == 1'b0;
         mem_deferrable == 1'b0;

         address == 64'h0000_0001_0000_3000;

         length  == `PCIe_TL_LEN_MAX;

         first_dw_be == 4'hF;
         last_dw_be  == 4'hF;

         ep == 1'b0;

         tag          == 14'h0011;
         requester_id == 16'h0100;

         tc   == 3'h0;
         ts   == 3'b000;
         attr == 3'b000;

         at == 2'b00;
       })
      `uvm_error("4DW_FLIT_MEMWR_FOLLOWED_MEMRD_MAXPAYLOAD","randomize failed for mrd")

    `uvm_info("TL_MRD",$sformatf("Sending 4DW Flit MemRd (MaxPayload) - readback of prior MemWr"), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);

    `uvm_info("4DW_FLIT_MEMWR_FOLLOWED_","EXIT_FROM_4DW_FLIT_MEMWR_FOLLOWED__SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

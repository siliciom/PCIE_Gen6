//=========================================================================================
// File         : PCIe_RC_3DW_flit_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_3DW_flit_sequence.sv
// Author       : 
// Date         : 2026-08-20
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

////////////////////////////////////////////////////////////////
// FILE:  PCIe_RC_3DW_flit_sequence.sv
// DESC:  Sequence for 3DW-header (32-bit address) Memory traffic.
////////////////////////////////////////////////////////////////

class PCIe_RC_3DW_flit_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_3DW_flit_sequence)

  bit [31:0] mem_addr_32 = 32'h0000_2000;
  bit [31:0] wr_data ;//    = 32'hA5A5_1234;

  function new(string name="PCIe_RC_3DW_flit_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("RC_3DW","ENTERED_INTO_RC_3DW_SEQUENCE_BODY", UVM_LOW)

    // 3DW Memory Write (MWr_32)
    pcie_seq_item = PCIe_sequence_item::type_id::create("mwr_3dw");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         pkt_mode == FLIT;

         txn_type == PCIe_TL_MEM;
         dir      == PCIe_TL_WRITE;

         mem_locked     == 1'b0;
         mem_deferrable == 1'b0;

         // 32-bit address
         address == {32'h0, mem_addr_32};

         // Payload sized to fill the 236 byte FLIT TLP region.
         //   Header Base 3 DW (12 B) + no OHC-A1  ->  payload = 224 B = 56 DW
         //   12 + 224 = 236 bytes
         //length == 10'd5;
         length == 10'd56;

                 // OHC-A1 is NOT emitted (see flit_ohc_c / determine_ohc_a).
         first_dw_be == 4'b1110;
         last_dw_be  == 4'hF;

         // Not a poisoned TLP - ep is rand and unconstrained in the item,
         // so without this it randomizes to 1 about half the time.
         ep == 1'b0;

         tag          == 14'h0010;
         requester_id == 16'h0100;

         tc   == 3'h0;
         ts   == 3'b000;
         attr == 3'b000;

         at == 2'b00;   
       })
      `uvm_error("RC_3DW","randomize failed for 3DW MWr")

    `uvm_info("TL_RC_3DW",$sformatf("Sending 3DW MWr"), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);

//    `uvm_info("TL_RC_3DW",$sformatf("Readback 3DW MRd"), UVM_LOW)
//    // 3DW Memory Read (MRd_32) readback
//    pcie_seq_item = PCIe_sequence_item::type_id::create("mrd_3dw");
//    start_item(pcie_seq_item);
//    if (!pcie_seq_item.randomize() with {
//          pkt_mode       == FLIT;
//          txn_type       == PCIe_TL_MEM;
//          dir            == PCIe_TL_READ;
//          mem_locked     == 1'b0;
//          mem_deferrable == 1'b0;
//          address        == {32'h0, mem_addr_32};
//          length         == 10'd1;
//          tag            == 10'h11;
//          requester_id   == 16'h0000;
//        })
//      `uvm_error("RC_3DW","randomize failed for 3DW MRd readback")
//
//    //`uvm_info("RC_3DW",$sformatf("Readback 3DW MRd: addr=0x%016h len=%0d",pcie_seq_item.address, pcie_seq_item.length), UVM_LOW)
//    `uvm_info("TL_RC_3DW",$sformatf("Readback 3DW MRd"), UVM_LOW)
//    pcie_seq_item.print();
//    finish_item(pcie_seq_item);
//
//    `uvm_info("RC_3DW","EXIT_FROM_RC_3DW_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

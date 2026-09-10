//=========================================================================================
// File         : PCIe_IO_3DW_FLIT_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_IO_3DW_FLIT_sequence.sv
// Author       : 
// Date         : 2026-09-08
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

////////////////////////////////////////////////////////////////
// FILE:  PCIe_IO_3DW_FLIT_sequence.sv
// DESC:  Sequence for 3DW-header (32-bit address) I/O traffic in FLIT mode.
//        Includes both I/O Write and I/O Read transactions.
////////////////////////////////////////////////////////////////

class PCIe_IO_3DW_FLIT_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_IO_3DW_FLIT_sequence)

  bit [31:0] io_addr_32 = 32'h0000_1000;
  bit [31:0] io_wr_data = 32'hDEAD_BEEF;

  function new(string name="PCIe_IO_3DW_FLIT_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("IO_3DW_FLIT","ENTERED_INTO_IO_3DW_FLIT_SEQUENCE_BODY", UVM_LOW)

    // I/O Write (IOWr) - FLIT mode
    pcie_seq_item = PCIe_sequence_item::type_id::create("iowr_3dw_flit");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         pkt_mode == FLIT;

         txn_type == PCIe_TL_IO;
         dir      == PCIe_TL_WRITE;

         // 32-bit I/O address (aligned to 4 bytes)
         address == {32'h0, io_addr_32};

         // I/O transactions always have length = 1 DW
         length == 10'd1;

         io_data == io_wr_data;

         tag          == 14'h0020;
         requester_id == 16'h0100;

         tc   == 3'h0;
         ts   == 3'b000;
         attr == 3'b000;
         at   == 2'b00;
       })
      `uvm_error("IO_3DW_FLIT","randomize failed for 3DW IOWr FLIT")

    `uvm_info("TL_IO_3DW_FLIT",$sformatf("Sending 3DW IOWr FLIT"), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);

    // I/O Read (IORd) - FLIT mode
   /* pcie_seq_item = PCIe_sequence_item::type_id::create("iord_3dw_flit");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
          pkt_mode       == FLIT;
          txn_type       == PCIe_TL_IO;
          dir            == PCIe_TL_READ;
          address        == {32'h0, io_addr_32};
          length         == 10'd1;
          tag            == 10'h21;
          requester_id   == 16'h0000;
          tc             == 3'h0;
          ts             == 3'b000;
          attr           == 3'b000;
          at             == 2'b00;
        })
      `uvm_error("IO_3DW_FLIT","randomize failed for 3DW IORd FLIT")

    `uvm_info("TL_IO_3DW_FLIT",$sformatf("Sending 3DW IORd FLIT"), UVM_LOW)
    pcie_seq_item.print()
    finish_item(pcie_seq_item);

    uvm_info("IO_3DW_FLIT","EXIT_FROM_IO_3DW_FLIT_SEQUENCE_BODY", UVM_LOW)*/
  endtask

endclass

//=========================================================================================
// File         : PCIe_RC_3DW_Flit_DefMemWr_Random_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_3DW_Flit_DefMemWr_Random_sequence.sv
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
// FILE:  PCIe_RC_3DW_Flit_DefMemWr_Random_sequence.sv
// DESC:  3DW-header Deferrable Memory Write, Flit mode, random.
////////////////////////////////////////////////////////////////

class PCIe_RC_3DW_Flit_DefMemWr_Random_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_3DW_Flit_DefMemWr_Random_sequence)


  function new(string name="PCIe_RC_3DW_Flit_DefMemWr_Random_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("3DW_FLIT_DEFMEMWR_RANDOM","ENTERED_INTO_3DW_FLIT_DEFMEMWR_RANDOM_SEQUENCE_BODY", UVM_LOW)

    pcie_seq_item = PCIe_sequence_item::type_id::create("defmwr");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         pkt_mode == FLIT;

         txn_type == PCIe_TL_MEM;
         dir      == PCIe_TL_WRITE;

         mem_locked     == 1'b0;
         mem_deferrable == 1'b1;

         length inside {[2:100]};

         first_dw_be == 4'hF;

         ep == 1'b0;

         tag          == 14'h0010;
         requester_id == 16'h0100;

         tc   == 3'h0;
         ts   == 3'b000;
         attr == 3'b000;

         at == 2'b00;
       })
      `uvm_error("3DW_FLIT_DEFMEMWR_RANDOM","randomize failed for defmwr")

    `uvm_info("TL_DEFMWR",$sformatf("Sending 3DW Flit Deferrable MemWr (Random)"), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);

    `uvm_info("3DW_FLIT_DEFMEMWR_RANDOM","EXIT_FROM_3DW_FLIT_DEFMEMWR_RANDOM_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

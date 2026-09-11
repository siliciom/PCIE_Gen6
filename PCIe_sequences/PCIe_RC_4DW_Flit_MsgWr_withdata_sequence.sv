//=========================================================================================
// File         : PCIe_RC_4DW_Flit_MsgWr_withdata_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_4DW_Flit_MsgWr_withdata_sequence.sv
// Author       :
// Date         : 2026-09-10
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

////////////////////////////////////////////////////////////////
// FILE:  PCIe_RC_4DW_Flit_MsgWr_withdata_sequence.sv
// DESC:  Message (with data), Flit mode.
////////////////////////////////////////////////////////////////

class PCIe_RC_4DW_Flit_MsgWr_withdata_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_4DW_Flit_MsgWr_withdata_sequence)


  function new(string name="PCIe_RC_4DW_Flit_MsgWr_withdata_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("4DW_FLIT_MSGWR_WITHDATA","ENTERED_INTO_4DW_FLIT_MSGWR_WITHDATA_SEQUENCE_BODY", UVM_LOW)

    pcie_seq_item = PCIe_sequence_item::type_id::create("msgwr");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         pkt_mode == FLIT;

         txn_type     == PCIe_TL_MSG;
         msg_code     == 8'h7E;
         msg_route    == PCIe_MSG_ROUTE_TO_RC;
         msg_has_data == 1'b1;

         ep == 1'b0;

         tag          == 14'h0040;
         requester_id == 16'h0100;

         tc   == 3'h0;
         ts   == 3'b000;
         attr == 3'h0;

         at == 2'b00;
       })
      `uvm_error("4DW_FLIT_MSGWR_WITHDATA","randomize failed for msgwr")

    `uvm_info("TL_MSG",$sformatf("Sending 4DW Flit MsgWr (with data)"), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);

    `uvm_info("4DW_FLIT_MSGWR_WITHDATA","EXIT_FROM_4DW_FLIT_MSGWR_WITHDATA_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

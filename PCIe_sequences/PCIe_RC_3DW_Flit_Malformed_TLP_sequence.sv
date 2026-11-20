//=========================================================================================
// File         : PCIe_RC_3DW_Flit_Malformed_TLP_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_3DW_Flit_Malformed_TLP_sequence.sv
// Author       :
// Date         : 2026-11-20
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

////////////////////////////////////////////////////////////////
// FILE:  PCIe_RC_3DW_Flit_Malformed_TLP_sequence.sv
// DESC:  [TL_ERR_INJ] Malformed TLP, Flit mode.
//        3DW Memory Write (Posted) with the Reserved bits = 1111b.
//        RC TL model assembles the flit with the Reserved bits set and sends it.
//        EP TL model : Malformed TLP -> ERR_FATAL, TLP dropped, NO completion.
//        Reserved bits used : DW1[14] + OHC-A1 NW / PMR / ER (PV = 0).
//        Last DW BE = 0111b (explicit byte enables) so OHC-A1 is in the TLP.
////////////////////////////////////////////////////////////////

`ifndef PCIE_RC_3DW_FLIT_MALFORMED_TLP_SEQUENCE_SV
`define PCIE_RC_3DW_FLIT_MALFORMED_TLP_SEQUENCE_SV

class PCIe_RC_3DW_Flit_Malformed_TLP_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_3DW_Flit_Malformed_TLP_sequence)

  // Tag of the request : the test looks for the completion with this tag
  localparam bit [`PCIe_TL_TAG_W-1:0] TLP_TAG = 'h3E1;

  function new(string name="PCIe_RC_3DW_Flit_Malformed_TLP_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("PCIE_RC_3DW_FLIT_MALFORMED_TLP_SEQUENCE", "ENTERED_INTO_SEQUENCE_BODY", UVM_LOW)

    pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         // LTSSM information
         electrical_idle_test == 1'b0;
         no_receiver_test     == 1'b0;
         tx_elec_idle         == 1'b1;
         pkt_mode             == FLIT;

         txn_type       == PCIe_TL_MEM;
         dir            == PCIe_TL_WRITE;
         mem_locked     == 1'b0;
         mem_deferrable == 1'b0;
         atomic_op      == PCIe_ATOMIC_NONE;

         address     == 32'h0000_3000;
         length      == 10'd2;
         first_dw_be == 4'hF;
         last_dw_be  == 4'h7;       // explicit byte enables -> OHC-A1 present

         ep   == 1'b0;
         tc   == 3'h0;
         ts   == 3'b000;
         attr == 3'b000;
         at   == 2'b00;
         io_data == '0;

         tag          == TLP_TAG;
         requester_id == 16'h0100;

         // Fields belonging to other transaction categories MUST be zero
         cfg_reg_num          == '0;
         cfg_ext_reg_num      == '0;
         cfg_bus_num          == '0;
         cfg_dev_num          == '0;
         cfg_fn_num           == '0;
         cfg_type1            == 1'b0;
         msg_code             == '0;
         msg_route            == PCIe_MSG_ROUTE_TO_RC;
         msg_has_data         == 1'b0;
       })
      `uvm_fatal("PCIE_RC_3DW_FLIT_MALFORMED_TLP_SEQUENCE", "randomize failed")

    pcie_seq_item.rsvd_bits = 4'b1111;   // [TL_ERR_INJ] Reserved bits = 1111 -> Malformed TLP

    `uvm_info("PCIE_RC_3DW_FLIT_MALFORMED_TLP_SEQUENCE", "Sending 3DW Flit MemWr with Reserved bits = 1111 (Malformed TLP)", UVM_LOW)
    pcie_seq_item.print();
    finish_item(pcie_seq_item);

    `uvm_info("PCIE_RC_3DW_FLIT_MALFORMED_TLP_SEQUENCE", "EXIT_FROM_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

`endif

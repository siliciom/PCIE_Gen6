//=========================================================================================
// File         : PCIe_RC_3DW_Flit_IOWr_ECRC_Error_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_3DW_Flit_IOWr_ECRC_Error_sequence.sv
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
// FILE:  PCIe_RC_3DW_Flit_IOWr_ECRC_Error_sequence.sv
// DESC:  [TL_ERR_INJ] ECRC error, Flit mode.
//        3DW I/O Write (Non-Posted) with the ECRC trailer (TS = 001b).
//        RC TL model calculates the ECRC, then adds +1 to the 32-bit value.
//        EP TL model recalculates the ECRC -> mismatch -> ECRC Check Failed,
//        request not executed, Completion (no data) with status UR.
////////////////////////////////////////////////////////////////

`ifndef PCIE_RC_3DW_FLIT_IOWR_ECRC_ERROR_SEQUENCE_SV
`define PCIE_RC_3DW_FLIT_IOWR_ECRC_ERROR_SEQUENCE_SV

class PCIe_RC_3DW_Flit_IOWr_ECRC_Error_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_3DW_Flit_IOWr_ECRC_Error_sequence)

  // Tag of the request : the test looks for the completion with this tag
  localparam bit [`PCIe_TL_TAG_W-1:0] TLP_TAG = 'h3E3;

  function new(string name="PCIe_RC_3DW_Flit_IOWr_ECRC_Error_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("PCIE_RC_3DW_FLIT_IOWR_ECRC_ERROR_SEQUENCE", "ENTERED_INTO_SEQUENCE_BODY", UVM_LOW)

    pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         // LTSSM information
         electrical_idle_test == 1'b0;
         no_receiver_test     == 1'b0;
         tx_elec_idle         == 1'b1;
         pkt_mode             == FLIT;

         txn_type    == PCIe_TL_IO;
         dir         == PCIe_TL_WRITE;
         length      == `PCIe_TL_LEN_MIN;
         first_dw_be == 4'hF;
         last_dw_be  == 4'h0;

         ep   == 1'b0;
         ts   == `PCIe_TL_TS_1DW_ECRC;   // 001b : 1 DW Trailer with ECRC (td = 1)

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
      `uvm_fatal("PCIE_RC_3DW_FLIT_IOWR_ECRC_ERROR_SEQUENCE", "randomize failed")

    pcie_seq_item.inject_ecrc_err = 1'b1;   // [TL_ERR_INJ] ECRC + 1 after it is calculated

    `uvm_info("PCIE_RC_3DW_FLIT_IOWR_ECRC_ERROR_SEQUENCE", "Sending 3DW Flit IOWr with ECRC + 1 (ECRC error)", UVM_LOW)
    pcie_seq_item.print();
    finish_item(pcie_seq_item);

    `uvm_info("PCIE_RC_3DW_FLIT_IOWR_ECRC_ERROR_SEQUENCE", "EXIT_FROM_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

`endif

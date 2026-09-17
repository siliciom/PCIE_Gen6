//=========================================================================================
// File         : PCIe_RC_3DW_NonFlit_IORd_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_3DW_NonFlit_IORd_sequence.sv
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
// FILE:  PCIe_RC_3DW_NonFlit_IORd_sequence.sv
// DESC:  I/O Read, NonFlit mode.
////////////////////////////////////////////////////////////////

class PCIe_RC_3DW_NonFlit_IORd_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_3DW_NonFlit_IORd_sequence)


  function new(string name="PCIe_RC_3DW_NonFlit_IORd_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("3DW_NONFLIT_IORD","ENTERED_INTO_3DW_NONFLIT_IORD_SEQUENCE_BODY", UVM_LOW)

    pcie_seq_item = PCIe_sequence_item::type_id::create("io");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         // LTSSM information
         electrical_idle_test == 1'b0;
         no_receiver_test     == 1'b0;
         tx_elec_idle         == 1'b1;
         pkt_mode             == NON_FLIT;

         txn_type == PCIe_TL_IO;
         dir      == PCIe_TL_READ;

         address == 32'h0000_00E0;

         first_dw_be == 4'hF;

         ep == 1'b0;

         tag          == 14'h0020;
         requester_id == 16'h0100;

         tc   == 3'h0;
         ts   == 3'b000;
         attr == 3'b000;

         at == 2'b00;

         // Fields belonging to other transaction categories MUST be zero for an IO transaction
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
      `uvm_error("3DW_NONFLIT_IORD","randomize failed for io")

    `uvm_info("TL_IO",$sformatf("Sending 3DW NonFlit IORd"), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);

    `uvm_info("3DW_NONFLIT_IORD","EXIT_FROM_3DW_NONFLIT_IORD_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

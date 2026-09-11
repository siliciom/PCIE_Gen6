//=========================================================================================
// File         : PCIe_RC_3DW_NonFlit_IORd_Random_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_3DW_NonFlit_IORd_Random_sequence.sv
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
// FILE:  PCIe_RC_3DW_NonFlit_IORd_Random_sequence.sv
// DESC:  I/O Read, NonFlit mode (randomized).
////////////////////////////////////////////////////////////////

class PCIe_RC_3DW_NonFlit_IORd_Random_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_3DW_NonFlit_IORd_Random_sequence)


  function new(string name="PCIe_RC_3DW_NonFlit_IORd_Random_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("3DW_NONFLIT_IORD_RANDOM","ENTERED_INTO_3DW_NONFLIT_IORD_RANDOM_SEQUENCE_BODY", UVM_LOW)

    pcie_seq_item = PCIe_sequence_item::type_id::create("io");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         pkt_mode == NON_FLIT;

         txn_type == PCIe_TL_IO;
         dir      == PCIe_TL_READ;

         first_dw_be == 4'hF;

         requester_id == 16'h0100;

       })
      `uvm_error("3DW_NONFLIT_IORD_RANDOM","randomize failed for io")

    `uvm_info("TL_IO",$sformatf("Sending 3DW NonFlit IORd_Random"), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);

    `uvm_info("3DW_NONFLIT_IORD_RANDOM","EXIT_FROM_3DW_NONFLIT_IORD_RANDOM_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

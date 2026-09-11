//=========================================================================================
// File         : PCIe_RC_3DW_NonFlit_MemRd_Random_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_3DW_NonFlit_MemRd_Random_sequence.sv
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
// FILE:  PCIe_RC_3DW_NonFlit_MemRd_Random_sequence.sv
// DESC:  3DW-header Memory Read, NonFlit mode, random.
////////////////////////////////////////////////////////////////

class PCIe_RC_3DW_NonFlit_MemRd_Random_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_3DW_NonFlit_MemRd_Random_sequence)


  function new(string name="PCIe_RC_3DW_NonFlit_MemRd_Random_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("3DW_NONFLIT_MEMRD_RANDOM","ENTERED_INTO_3DW_NONFLIT_MEMRD_RANDOM_SEQUENCE_BODY", UVM_LOW)

    pcie_seq_item = PCIe_sequence_item::type_id::create("mrd");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         pkt_mode == NON_FLIT;

         txn_type == PCIe_TL_MEM;
         dir      == PCIe_TL_READ;

         mem_locked     == 1'b0;
         mem_deferrable == 1'b0;

         first_dw_be == 4'hF;
         last_dw_be  == 4'hF;

         requester_id == 16'h0100;

       })
      `uvm_error("3DW_NONFLIT_MEMRD_RANDOM","randomize failed for mrd")

    `uvm_info("TL_MRD",$sformatf("Sending 3DW NonFlit MemRd (Random)"), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);

    `uvm_info("3DW_NONFLIT_MEMRD_RANDOM","EXIT_FROM_3DW_NONFLIT_MEMRD_RANDOM_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

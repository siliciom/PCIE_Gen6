//=========================================================================================
// File         : PCIe_RC_dll_sequence_gap_detection_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_dll_sequence_gap_detection_sequence.sv
// Author       :
// Date         : 2026-11-21
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

// Traffic for PCIe_gen6_dll_sequence_gap_detection_test : 6 x 3DW Flit MemWr.
// Flit 3 is lost on the link -> EP sees a sequence number gap.

class PCIe_RC_dll_sequence_gap_detection_sequence extends PCIe_RC_dll_base_sequence;

  `uvm_object_utils(PCIe_RC_dll_sequence_gap_detection_sequence)

  function new(string name = "PCIe_RC_dll_sequence_gap_detection_sequence");
    super.new(name);
    num_txn = 6;
  endfunction

endclass

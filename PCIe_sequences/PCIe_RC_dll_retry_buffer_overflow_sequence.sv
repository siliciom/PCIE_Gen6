//=========================================================================================
// File         : PCIe_RC_dll_retry_buffer_overflow_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_dll_retry_buffer_overflow_sequence.sv
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

// Traffic for PCIe_gen6_dll_retry_buffer_overflow_test : 12 x 3DW Flit MemWr.
// Tx retry buffer depth = 4 and Ack held -> RC must stall, no overflow.

class PCIe_RC_dll_retry_buffer_overflow_sequence extends PCIe_RC_dll_base_sequence;

  `uvm_object_utils(PCIe_RC_dll_retry_buffer_overflow_sequence)

  function new(string name = "PCIe_RC_dll_retry_buffer_overflow_sequence");
    super.new(name);
    num_txn = 12;
  endfunction

endclass

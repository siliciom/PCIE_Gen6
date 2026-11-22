//=========================================================================================
// File         : PCIe_RC_dll_out_of_order_flit_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_dll_out_of_order_flit_sequence.sv
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

// Traffic for PCIe_gen6_dll_out_of_order_flit_test : 6 x 3DW Flit MemWr.
// Flits 2 and 3 arrive swapped -> EP sees seq 3 before seq 2.

class PCIe_RC_dll_out_of_order_flit_sequence extends PCIe_RC_dll_base_sequence;

  `uvm_object_utils(PCIe_RC_dll_out_of_order_flit_sequence)

  function new(string name = "PCIe_RC_dll_out_of_order_flit_sequence");
    super.new(name);
    num_txn = 6;
  endfunction

endclass

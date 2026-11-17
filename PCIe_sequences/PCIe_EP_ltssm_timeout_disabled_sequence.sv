//=========================================================================================
// File         : PCIe_EP_ltssm_timeout_disabled_sequence.sv
// Project      : PCIE_Gen6
// Description  : EP LTSSM DISABLED directed timeout sequence.
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

class PCIe_EP_ltssm_timeout_disabled_sequence extends PCIe_EP_ltssm_timeout_base_sequence;
  `uvm_object_utils(PCIe_EP_ltssm_timeout_disabled_sequence)

  function new(string name = "PCIe_EP_ltssm_timeout_disabled_sequence");
    super.new(name);
    timeout_target = LTSSM_TO_DISABLED;
    state_name     = "DISABLED";
  endfunction

endclass

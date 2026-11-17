//=========================================================================================
// File         : PCIe_EP_ltssm_timeout_config_complete_sequence.sv
// Project      : PCIE_Gen6
// Description  : EP LTSSM CONFIG.COMPLETE directed timeout sequence.
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

class PCIe_EP_ltssm_timeout_config_complete_sequence extends PCIe_EP_ltssm_timeout_base_sequence;
  `uvm_object_utils(PCIe_EP_ltssm_timeout_config_complete_sequence)

  function new(string name = "PCIe_EP_ltssm_timeout_config_complete_sequence");
    super.new(name);
    timeout_target = LTSSM_TO_CFG_COMPLETE;
    state_name     = "CFG_COMPLETE";
  endfunction

endclass

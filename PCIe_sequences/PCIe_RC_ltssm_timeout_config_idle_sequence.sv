//=========================================================================================
// File         : PCIe_RC_ltssm_timeout_config_idle_sequence.sv
// Project      : PCIE_Gen6
// Description  : RC LTSSM CONFIG.IDLE directed timeout sequence.
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

class PCIe_RC_ltssm_timeout_config_idle_sequence extends PCIe_RC_ltssm_timeout_base_sequence;
  `uvm_object_utils(PCIe_RC_ltssm_timeout_config_idle_sequence)

  function new(string name = "PCIe_RC_ltssm_timeout_config_idle_sequence");
    super.new(name);
    timeout_target = LTSSM_TO_CFG_IDLE;
    state_name     = "CFG_IDLE";
  endfunction

endclass

//=========================================================================================
// File         : PCIe_RC_ltssm_timeout_config_lanenum_accept_sequence.sv
// Project      : PCIE_Gen6
// Description  : RC LTSSM CONFIG.LANENUM_ACCEPT directed timeout sequence.
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

class PCIe_RC_ltssm_timeout_config_lanenum_accept_sequence extends PCIe_RC_ltssm_timeout_base_sequence;
  `uvm_object_utils(PCIe_RC_ltssm_timeout_config_lanenum_accept_sequence)

  function new(string name = "PCIe_RC_ltssm_timeout_config_lanenum_accept_sequence");
    super.new(name);
    timeout_target = LTSSM_TO_CFG_LANENUM_ACCEPT;
    state_name     = "CFG_LANENUM_ACCEPT";
  endfunction

endclass

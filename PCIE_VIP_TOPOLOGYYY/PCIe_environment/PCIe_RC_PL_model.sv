//=========================================================================================
// File         : PCIe_RC_PL_model.sv
// Project      : PCIE_Gen6
// Description  : PCIe_environment\PCIe_RC_PL_model.sv
// Author       : 
// Date         : 2026-08-14
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

class PCIe_RC_PL_model extends uvm_component;
   
  `uvm_component_utils(PCIe_RC_PL_model)

   function new(string name="PCIe_RC_PL_model",uvm_component parent);
      super.new(name,parent);
   endfunction


   function void build_phase(uvm_phase phase);
      `uvm_info("PCIe_PL_MODEL","ENTERED_INTO_PL_MODEL_BUILD_PHASE",UVM_LOW)
     super.build_phase(phase);
      `uvm_info("PCIe_PL_MODEL","EXIT_FROM_PL_MODEL_BUILD_PHASE",UVM_LOW)
   endfunction

endclass








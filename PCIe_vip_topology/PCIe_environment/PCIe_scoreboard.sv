//=========================================================================================
// File         : PCIe_scoreboard.sv
// Project      : PCIE_Gen6
// Description  : PCIe_environment\PCIe_scoreboard.sv
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

class PCIe_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(PCIe_scoreboard)

  function new(string name="PCIe_scoreboard",uvm_component parent);
    super.new(name,parent);
  endfunction

  function void build_phase(uvm_phase phase);
   `uvm_info("PCIe_SCOREBOARD","ENTERED_INTO_SB_BUILD_PHASE",UVM_LOW)
    super.build_phase(phase);
   `uvm_info("PCIe_SCOREBOARD","EXIT_FROM_SB_BUILD_PHASE",UVM_LOW)
  endfunction


endclass




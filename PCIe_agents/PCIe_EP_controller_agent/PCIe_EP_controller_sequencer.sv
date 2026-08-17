//=========================================================================================
// File         : PCIe_EP_controller_sequencer.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_EP_controller_agent\PCIe_EP_controller_sequencer.sv
// Author       : 
// Date         : 2026-08-17
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

class PCIe_EP_controller_sequencer extends uvm_sequencer #(PCIe_sequence_item);
  
  `uvm_component_utils(PCIe_EP_controller_sequencer)
  
  function new(string name="PCIe_EP_controller_sequencer",uvm_component parent);
    super.new(name,parent);
  endfunction
  
endclass






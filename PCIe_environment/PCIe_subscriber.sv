//=========================================================================================
// File         : PCIe_subscriber.sv
// Project      : PCIE_Gen6
// Description  : PCIe_environment\PCIe_subscriber.sv
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

class PCIe_subscriber extends uvm_subscriber#(PCIe_sequence_item);
  `uvm_component_utils(PCIe_subscriber)

     PCIe_sequence_item     pcie_seq_item;

  function new(string name="PCIe_subscriber",uvm_component parent);
    super.new(name,parent); 
  endfunction


  function void build_phase(uvm_phase phase);
   `uvm_info("PCIe_SUBSCRIBER","ENTERED_INTO_SUB_BUILD_PHASE",UVM_LOW)
    super.build_phase(phase);
   `uvm_info("PCIe_SUBSCRIBER","EXIT_FROM_SUB_BUILD_PHASE",UVM_LOW)
  endfunction
 
 
  virtual function void write(PCIe_sequence_item t);
      pcie_seq_item = t;
 endfunction
   
endclass


    

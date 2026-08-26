//=========================================================================================
// File         : PCIe_EP_TL_model.sv
// Project      : PCIe_Gen6
// Description  : PCIe_environment\PCIe_EP_TL_model.sv
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

import typedef_enums :: *;
class PCIe_EP_TL_model extends uvm_component;

  `uvm_component_utils(PCIe_EP_TL_model)
  // Input from EP controller driver.
  uvm_analysis_imp #(PCIe_sequence_item, PCIe_EP_TL_model) tl_imp;
  // Output toward EP DL model.
  uvm_analysis_port #(PCIe_sequence_item) tl_ap;
  PCIe_sequence_item item;

  function new(string name="PCIe_EP_TL_model",uvm_component parent);
    super.new(name,parent);
  endfunction

  function void build_phase(uvm_phase phase);
   super.build_phase(phase);
    tl_imp = new("tl_imp", this);
    tl_ap  = new("tl_ap",  this);
  endfunction

  // TL model is the producer for the DL model.
  function void write(PCIe_sequence_item item);
   `uvm_info("EP_TL_MODEL",$sformatf("TL -> DL: item=%p, drive_flit=%d", item.tlp_data, item.drive_flit),UVM_MEDIUM)
    tl_ap.write(item);
  endfunction
  
endclass
  
  



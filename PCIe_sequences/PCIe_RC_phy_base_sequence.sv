//=========================================================================================
// File         : PCIe_RC_phy_base_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences\PCIe_RC_phy_base_sequence.sv
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

class PCIe_RC_phy_base_sequence extends uvm_sequence#(PCIe_sequence_item);
  
	`uvm_object_utils(PCIe_RC_phy_base_sequence)
  	 PCIe_sequence_item       pcie_seq_item;

       function new(string name="PCIe_RC_phy_base_sequence");
            super.new(name);
       endfunction

    task body();
            pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
           `uvm_info("RC_PHY","ENTERED_INTO_RC_PHY_BASE_SEQUENCE_TASK_BODY",UVM_LOW)
          	start_item(pcie_seq_item);
          	finish_item(pcie_seq_item);
           `uvm_info("RC_PHY","EXIT_FROM_RC_PHY_BASE_SEQUENCE_TASK_BODY",UVM_LOW)
    endtask
endclass




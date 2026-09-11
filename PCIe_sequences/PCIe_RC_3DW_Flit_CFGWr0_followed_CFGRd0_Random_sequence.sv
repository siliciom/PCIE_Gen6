//=========================================================================================
// File         : PCIe_RC_3DW_Flit_CFGWr0_followed_CFGRd0_Random_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_3DW_Flit_CFGWr0_followed_CFGRd0_Random_sequence.sv
// Author       :
// Date         : 2026-09-10
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

////////////////////////////////////////////////////////////////
// FILE:  PCIe_RC_3DW_Flit_CFGWr0_followed_CFGRd0_Random_sequence.sv
// DESC:  Configuration Type0 Write immediately followed by Configuration Type0 Read, Flit mode (randomized).
////////////////////////////////////////////////////////////////

class PCIe_RC_3DW_Flit_CFGWr0_followed_CFGRd0_Random_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_3DW_Flit_CFGWr0_followed_CFGRd0_Random_sequence)


  function new(string name="PCIe_RC_3DW_Flit_CFGWr0_followed_CFGRd0_Random_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("3DW_FLIT_CFGRD0_FOLLOW","ENTERED_INTO_3DW_FLIT_CFGRD0_FOLLOW_SEQUENCE_BODY", UVM_LOW)

    pcie_seq_item = PCIe_sequence_item::type_id::create("cfgwr");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         pkt_mode == FLIT;

         txn_type  == PCIe_TL_CFG;
         dir       == PCIe_TL_WRITE;
         cfg_type1 == 1'b0;

         cfg_bus_num     == 8'h00;
         cfg_dev_num     == 5'h01;
         cfg_fn_num      == 3'h0;

         first_dw_be == 4'hF;

         ep == 1'b0;

         requester_id == 16'h0100;

       })
      `uvm_error("3DW_FLIT_CFGRD0_FOLLOWED_CFGRD0_RANDOM","randomize failed for cfgwr")

    `uvm_info("TL_CFG",$sformatf("Sending 3DW Flit CFGWr (Type0)"), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);

    pcie_seq_item = PCIe_sequence_item::type_id::create("cfgrd");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         pkt_mode == FLIT;

         txn_type  == PCIe_TL_CFG;
         dir       == PCIe_TL_READ;
         cfg_type1 == 1'b0;

         cfg_bus_num     == 8'h00;
         cfg_dev_num     == 5'h01;
         cfg_fn_num      == 3'h0;
        
         first_dw_be == 4'hF;
         last_dw_be  == 4'h0;

         requester_id == 16'h0100;

       })
      `uvm_error("3DW_FLIT_CFGRD0_FOLLOWED_CFGRD0_RANDOM","randomize failed for cfgrd")

    `uvm_info("TL_CFG",$sformatf("Sending 3DW Flit CFGRd (Type0) readback"), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);

    `uvm_info("3DW_FLIT_CFGRD0_FOLLOW","EXIT_FROM_3DW_FLIT_CFGRD0_FOLLOW_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

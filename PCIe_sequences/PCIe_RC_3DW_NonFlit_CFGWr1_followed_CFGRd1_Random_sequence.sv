//=========================================================================================
// File         : PCIe_RC_3DW_NonFlit_CFGWr1_followed_CFGRd1_Random_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_3DW_NonFlit_CFGWr1_followed_CFGRd1_Random_sequence.sv
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
// FILE:  PCIe_RC_3DW_NonFlit_CFGWr1_followed_CFGRd1_Random_sequence.sv
// DESC:  Configuration Type1 Write immediately followed by Configuration Type1 Read, NonFlit mode (randomized).
////////////////////////////////////////////////////////////////

class PCIe_RC_3DW_NonFlit_CFGWr1_followed_CFGRd1_Random_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_3DW_NonFlit_CFGWr1_followed_CFGRd1_Random_sequence)


  function new(string name="PCIe_RC_3DW_NonFlit_CFGWr1_followed_CFGRd1_Random_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("3DW_NONFLIT_CFGRD1_FOLLO","ENTERED_INTO_3DW_NONFLIT_CFGRD1_FOLLO_SEQUENCE_BODY", UVM_LOW)

    pcie_seq_item = PCIe_sequence_item::type_id::create("cfgwr");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         pkt_mode == NON_FLIT;

         txn_type  == PCIe_TL_CFG;
         dir       == PCIe_TL_WRITE;
         cfg_type1 == 1'b1;

         cfg_bus_num     == 8'h01;
         cfg_dev_num     == 5'h01;
         cfg_fn_num      == 3'h0;
         cfg_reg_num     == 12'h010;
         cfg_ext_reg_num == 4'h0;

         first_dw_be == 4'hF;

         requester_id == 16'h0100;

       })
      `uvm_error("3DW_NONFLIT_CFGRD1_FOLLOWED_CFGRD1_RANDOM","randomize failed for cfgwr")

    `uvm_info("TL_CFG",$sformatf("Sending 3DW NonFlit CFGWr (Type1)"), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);

    pcie_seq_item = PCIe_sequence_item::type_id::create("cfgrd");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         pkt_mode == NON_FLIT;

         txn_type  == PCIe_TL_CFG;
         dir       == PCIe_TL_READ;
         cfg_type1 == 1'b1;

         cfg_bus_num     == 8'h01;
         cfg_dev_num     == 5'h01;
         cfg_fn_num      == 3'h0;
         cfg_reg_num     == 12'h010;
         cfg_ext_reg_num == 4'h0;

         first_dw_be == 4'hF;

         requester_id == 16'h0100;

       })
      `uvm_error("3DW_NONFLIT_CFGRD1_FOLLOWED_CFGRD1_RANDOM","randomize failed for cfgrd")

    `uvm_info("TL_CFG",$sformatf("Sending 3DW NonFlit CFGRd (Type1) readback"), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);

    `uvm_info("3DW_NONFLIT_CFGRD1_FOLLO","EXIT_FROM_3DW_NONFLIT_CFGRD1_FOLLO_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

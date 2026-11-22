//=========================================================================================
// File         : PCIe_gen6_3DW_E2E_PRFX_Flit__MemWr_Random_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_gen6_3DW_E2E_PRFX_Flit__MemWr_Random_sequence.sv
// Author       :
// Date         : 2026-11-21
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

////////////////////////////////////////////////////////////////
// FILE:  PCIe_gen6_3DW_E2E_PRFX_Flit__MemWr_Random_sequence.sv
// DESC:  3DW-header Memory Write, Flit mode, random length, with an
//        End-End TLP Prefix. In Flit Mode the E-E Prefix is carried in
//        OHC-E (Sec 2.2.11). This sequence adds OHC-E1 (1 DW) :
//          DW0 OHC[4:3] = 01b (OHC-E1 present)
//          OHC-E1 DW : [31:28]=0001b E-E Prefix DW, [27:24]=E[3:0], [23:0] content
////////////////////////////////////////////////////////////////

class PCIe_gen6_3DW_E2E_PRFX_Flit__MemWr_Random_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_gen6_3DW_E2E_PRFX_Flit__MemWr_Random_sequence)

  function new(string name="PCIe_gen6_3DW_E2E_PRFX_Flit__MemWr_Random_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("3DW_E2E_PRFX_FLIT_MEMWR_RANDOM","ENTERED_INTO_3DW_E2E_PRFX_FLIT_MEMWR_RANDOM_SEQUENCE_BODY", UVM_LOW)

    pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         // LTSSM information
         electrical_idle_test == 1'b0;
         no_receiver_test     == 1'b0;
         tx_elec_idle         == 1'b1;
         pkt_mode             == FLIT;

         // 3DW Memory Write
         txn_type == PCIe_TL_MEM;
         dir      == PCIe_TL_WRITE;

         mem_locked     == 1'b0;
         mem_deferrable == 1'b0;

         address == 32'h0000_2000;

         length inside {[2:32]};

         first_dw_be == 4'hF;
         last_dw_be  == 4'hF;

         requester_id == 16'h0100;

         ts == 3'b000;   // no Trailer (TS=1xx would mean a 2-5 DW Trailer that is never sent)
         at == 2'b00;    // untranslated address

         // OHC-E1 (End-End Prefix) ON, no Local Prefix
         lprfx_en  == 1'b0;
         ohc_e1_en == 1'b1;

         // Fields belonging to other transaction categories MUST be zero for a MEM transaction
         cfg_reg_num          == '0;
         cfg_ext_reg_num      == '0;
         cfg_bus_num          == '0;
         cfg_dev_num          == '0;
         cfg_fn_num           == '0;
         cfg_type1            == 1'b0;
         io_data              == '0;
         msg_code             == '0;
         msg_route            == PCIe_MSG_ROUTE_TO_RC;
         msg_has_data         == 1'b0;
       })
      `uvm_error("3DW_E2E_PRFX_FLIT_MEMWR_RANDOM","randomize failed for mwr")

    `uvm_info("TL_MWR",$sformatf("Sending 3DW Flit MemWr with OHC-E1 (E-E Prefix) DW=%08h len=%0d", pcie_seq_item.ohc_e1_dw, pcie_seq_item.length), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);

    `uvm_info("3DW_E2E_PRFX_FLIT_MEMWR_RANDOM","EXIT_FROM_3DW_E2E_PRFX_FLIT_MEMWR_RANDOM_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

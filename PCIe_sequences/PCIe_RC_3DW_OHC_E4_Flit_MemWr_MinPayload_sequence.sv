//=========================================================================================
// File         : PCIe_RC_3DW_OHC_E4_Flit_MemWr_MinPayload_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_3DW_OHC_E4_Flit_MemWr_MinPayload_sequence.sv
// Author       :
// Date         : 2026-11-24
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

////////////////////////////////////////////////////////////////
// FILE:  PCIe_RC_3DW_OHC_E4_Flit_MemWr_MinPayload_sequence.sv
// DESC:  3DW-header Memory Write, Flit mode, min payload (1 DW), with OHC-E4
//        (4 DW, Fig 2-80, Sec 2.2.11) appended after the Header Base.
//          DW0 OHC[4:0] = 11000b (OHC-E4 present)
//          each OHC-E4 DW : [31:28] 0001b E-E Prefix DW  [27:24] E[3:0]  [23:0] content
////////////////////////////////////////////////////////////////

class PCIe_RC_3DW_OHC_E4_Flit_MemWr_MinPayload_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_3DW_OHC_E4_Flit_MemWr_MinPayload_sequence)

  function new(string name="PCIe_RC_3DW_OHC_E4_Flit_MemWr_MinPayload_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("3DW_OHC_E4_FLIT_MEMWR_MINPAYLOAD","ENTERED_INTO_3DW_OHC_E4_FLIT_MEMWR_MINPAYLOAD_SEQUENCE_BODY", UVM_LOW)

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

         length  == `PCIe_TL_LEN_MIN;

         first_dw_be == 4'hF;   // all bytes -> no OHC-A1
         last_dw_be  == 4'h0;   // 1 DW : Last DW BE = 0000b

         tag == 14'h0010;

         ep == 1'b0;

         requester_id == 16'h0100;

         tc   == 3'h0;
         ts   == 3'b000;   // no Trailer
         attr == 3'b000;
         at   == 2'b00;    // untranslated address

         // OHC selection
         lprfx_en  == 1'b0;
         ohc_b_en  == 1'b0;
         ohc_c_en  == 1'b0;
         ohc_e1_en == 1'b0;
         ohc_e4_en == 1'b1;

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
      `uvm_error("3DW_OHC_E4_FLIT_MEMWR_MINPAYLOAD","randomize failed for mwr")

    `uvm_info("TL_MWR",$sformatf("Sending 3DW Flit MemWr (MinPayload) with OHC-E4 DW0..3=%08h %08h %08h %08h", pcie_seq_item.ohc_e4_dw[0], pcie_seq_item.ohc_e4_dw[1], pcie_seq_item.ohc_e4_dw[2], pcie_seq_item.ohc_e4_dw[3]), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);

    // OHC[4:0] in DW0 is rebuilt by the RC TL model (determine_ohc) : check it
    if (pcie_seq_item.ohc !== 5'b11000)
      `uvm_error("3DW_OHC_E4_FLIT_MEMWR_MINPAYLOAD", $sformatf("OHC[4:0]=%05b, expected %05b (OHC-E4)", pcie_seq_item.ohc, 5'b11000))
    else
      `uvm_info("3DW_OHC_E4_FLIT_MEMWR_MINPAYLOAD", $sformatf("OHC[4:0]=%05b (OHC-E4) : PASS", pcie_seq_item.ohc), UVM_LOW)

    `uvm_info("3DW_OHC_E4_FLIT_MEMWR_MINPAYLOAD","EXIT_FROM_3DW_OHC_E4_FLIT_MEMWR_MINPAYLOAD_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

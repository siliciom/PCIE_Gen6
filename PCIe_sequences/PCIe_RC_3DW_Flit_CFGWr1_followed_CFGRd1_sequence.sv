//=========================================================================================
// File         : PCIe_RC_3DW_Flit_CFGWr1_followed_CFGRd1_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_3DW_Flit_CFGWr1_followed_CFGRd1_sequence.sv
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
// FILE:  PCIe_RC_3DW_Flit_CFGWr1_followed_CFGRd1_sequence.sv
// DESC:  Configuration Type1 Write immediately followed by Configuration Type1 Read, Flit mode.
////////////////////////////////////////////////////////////////

class PCIe_RC_3DW_Flit_CFGWr1_followed_CFGRd1_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_3DW_Flit_CFGWr1_followed_CFGRd1_sequence)


  function new(string name="PCIe_RC_3DW_Flit_CFGWr1_followed_CFGRd1_sequence");
    super.new(name);
  endfunction

  task body();
    PCIe_RC_TL_model   rc_tl;
    PCIe_sequence_item cpl;
    bit                timed_out;
    `uvm_info("3DW_FLIT_CFGWR1_FOLLOWED","ENTERED_INTO_3DW_FLIT_CFGWR1_FOLLOWED_SEQUENCE_BODY", UVM_LOW)

    pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         // LTSSM information
         electrical_idle_test == 1'b0;
         no_receiver_test     == 1'b0;
         tx_elec_idle         == 1'b1;
         pkt_mode             == FLIT;

         txn_type  == PCIe_TL_CFG;
         dir       == PCIe_TL_WRITE;
         length   == `PCIe_TL_LEN_MIN;
         cfg_type1 == 1'b1;

        cfg_bus_num == `PCIe_EP_BUS_NUMBER;
        cfg_dev_num == `PCIe_EP_DEVICE_NUMBER;
        cfg_fn_num  == `PCIe_EP_FUNCTION_NUMBER; 
         cfg_reg_num     == 12'h010;
         cfg_ext_reg_num == 4'h0;

         first_dw_be == 4'hF;
 
         ep == 1'b0;

         tag          == 14'h0031;
         requester_id == 16'h0100;

         tc   == 3'h0;
         ts   == 3'b000;
         attr == 3'h0;

         at == 2'b00;

         // Fields belonging to other transaction categories MUST be zero for a CFG transaction
         io_data              == '0;
         msg_code             == '0;
         msg_route            == PCIe_MSG_ROUTE_TO_RC;
         msg_has_data         == 1'b0;
         address              == '0;
       })
      `uvm_error("3DW_FLIT_CFGWR1_FOLLOWED_CFGRD1","randomize failed for cfgwr")

    `uvm_info("TL_CFG",$sformatf("Sending 3DW Flit CFGWr (Type1)"), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);
        // ---- CHECK : Endpoint must reply UR to a Type 1 config request ----
    if (!uvm_config_db#(PCIe_RC_TL_model)::get(m_sequencer, "", "rc_tl_model", rc_tl))
      `uvm_fatal("CFG_TYPE1", "rc_tl_model handle not found")

    rc_tl.wait_completion(pcie_seq_item.tag, 20000, cpl, timed_out);

    if (timed_out)
      `uvm_error("CFG_TYPE1", $sformatf("NO_COMPLETION for tag=0x%0h", pcie_seq_item.tag))
    else if (cpl.cpl_status != `PCIe_CPL_STATUS_UR)
      `uvm_error("CFG_TYPE1", $sformatf("EXPECTED_UR but got %s", rc_tl.cpl_status_str(cpl.cpl_status)))
    else
      `uvm_info("CFG_TYPE1", $sformatf("UR_RECEIVED_AS_EXPECTED tag=0x%0h", pcie_seq_item.tag), UVM_LOW)

    pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         // LTSSM information
         electrical_idle_test == 1'b0;
         no_receiver_test     == 1'b0;
         tx_elec_idle         == 1'b1;
         pkt_mode             == FLIT;

         txn_type  == PCIe_TL_CFG;
         dir       == PCIe_TL_READ;
         length   == `PCIe_TL_LEN_MIN;
         cfg_type1 == 1'b1;

         cfg_bus_num == `PCIe_EP_BUS_NUMBER;
         cfg_dev_num == `PCIe_EP_DEVICE_NUMBER;
         cfg_fn_num  == `PCIe_EP_FUNCTION_NUMBER;
	 cfg_reg_num     == 12'h010;
         cfg_ext_reg_num == 4'h0;

         first_dw_be == 4'hF;
         last_dw_be  == 4'h0;

         ep == 1'b0;

         tag          == 14'h0032;
         requester_id == 16'h0100;

         tc   == 3'h0;
         ts   == 3'b000;
         attr == 3'h0;

         at == 2'b00;

         // Fields belonging to other transaction categories MUST be zero for a CFG transaction
         io_data              == '0;
         msg_code             == '0;
         msg_route            == PCIe_MSG_ROUTE_TO_RC;
         msg_has_data         == 1'b0;
         address              == '0;
       })
      `uvm_error("3DW_FLIT_CFGWR1_FOLLOWED_CFGRD1","randomize failed for cfgrd")

    `uvm_info("TL_CFG",$sformatf("Sending 3DW Flit CFGRd (Type1) readback"), UVM_LOW)
    pcie_seq_item.print();

    finish_item(pcie_seq_item);
    
        // ---- CHECK : Endpoint must reply UR to a Type 1 config request ----
    if (!uvm_config_db#(PCIe_RC_TL_model)::get(m_sequencer, "", "rc_tl_model", rc_tl))
      `uvm_fatal("CFG_TYPE1", "rc_tl_model handle not found")

    rc_tl.wait_completion(pcie_seq_item.tag, 20000, cpl, timed_out);

    if (timed_out)
      `uvm_error("CFG_TYPE1", $sformatf("NO_COMPLETION for tag=0x%0h", pcie_seq_item.tag))
    else if (cpl.cpl_status != `PCIe_CPL_STATUS_UR)
      `uvm_error("CFG_TYPE1", $sformatf("EXPECTED_UR but got %s", rc_tl.cpl_status_str(cpl.cpl_status)))
    else
      `uvm_info("CFG_TYPE1", $sformatf("UR_RECEIVED_AS_EXPECTED tag=0x%0h", pcie_seq_item.tag), UVM_LOW)

    `uvm_info("3DW_FLIT_CFGWR1_FOLLOWED","EXIT_FROM_3DW_FLIT_CFGWR1_FOLLOWED_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

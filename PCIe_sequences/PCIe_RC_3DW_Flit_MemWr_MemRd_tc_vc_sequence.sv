//=========================================================================================
// File         : PCIe_RC_3DW_Flit_MemWr_MemRd_tc_vc_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences\PCIe_RC_3DW_Flit_MemWr_MemRd_tc_vc_sequence.sv
// Author       :
// Date         : 2026-11-03
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/


class PCIe_RC_3DW_Flit_MemWr_MemRd_tc_vc_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_3DW_Flit_MemWr_MemRd_tc_vc_sequence)

  bit [31:0]               p_addr     = 32'h0000_2000;
  int unsigned             p_length   = 10;
  bit [`PCIe_TL_TAG_W-1:0] p_tag_base = 14'h0200;
  bit [2:0]                tc;        // <-- plain bit, driven from the test by direct assignment (as Gen3)

  function new(string name="PCIe_RC_3DW_Flit_MemWr_MemRd_tc_vc_sequence");
    super.new(name);
  endfunction

  // one Memory request : write (Posted), deferrable write (Non-Posted) or read (Non-Posted)
  task send_mem(pcie_tl_dir_e d, bit deferrable, bit [31:0] addr, bit [`PCIe_TL_TAG_W-1:0] t_tag, string what);
    PCIe_sequence_item it;
    it = PCIe_sequence_item::type_id::create($sformatf("tc%0d_%s", tc, what));
    start_item(it);
    if (!it.randomize() with {
         // LTSSM information
         electrical_idle_test == 1'b0;
         no_receiver_test     == 1'b0;
         tx_elec_idle         == 1'b1;
         pkt_mode             == FLIT;

         txn_type       == PCIe_TL_MEM;
         dir            == local::d;
         mem_locked     == 1'b0;
         mem_deferrable == local::deferrable;

         address      == local::addr;
         length       == local::p_length;
         first_dw_be  == 4'hF;
         last_dw_be   == 4'hF;

         tc           == local::tc;           // DO NOT randomize tc - it comes from the test
         ts           == 3'b000;
         attr         == 3'b000;
         ep           == 1'b0;
         tag          == local::t_tag;
         requester_id == 16'h0100;

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
      `uvm_error("TC_VC_SEQ", $sformatf("randomize failed for %s on TC%0d", what, tc))

    `uvm_info("TC_VC_SEQ", $sformatf("%-6s TC = %0d -> VC = %s  tag=0x%0h addr=0x%0h len=%0d DW",
              what, it.tc, it.vc.name(), it.tag, it.address, it.length), UVM_LOW)
    finish_item(it);
  endtask

  task body();
    `uvm_info("TC_VC_SEQ", $sformatf("ENTERED_INTO_TC_VC_SEQUENCE_BODY : TC = %0d (%s)", tc, PCIe_sequence_item::tc_vc_map_str()), UVM_LOW)
    if (!PCIe_sequence_item::tc_enabled(tc)) begin
      `uvm_warning("TC_VC_SEQ", $sformatf("TC%0d is not mapped to an enabled VC - nothing sent for it", tc))
      return;
    end
    send_mem(PCIe_TL_WRITE, 1'b0, p_addr,                  p_tag_base,      "MWr");
    send_mem(PCIe_TL_WRITE, 1'b1, p_addr + (p_length * 4), p_tag_base + 1,  "DMWr");
    send_mem(PCIe_TL_READ,  1'b0, p_addr,                  p_tag_base + 2,  "MRd");
    `uvm_info("TC_VC_SEQ", $sformatf("EXIT_FROM_TC_VC_SEQUENCE_BODY : TC = %0d", tc), UVM_LOW)
  endtask

endclass

//=========================================================================================
// File         : PCIe_RC_3DW_Flit_swap_2dwPayload_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_3DW_Flit_swap_2dwPayload_sequence.sv
// Author       :
// Date         : 2026-11-17
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

////////////////////////////////////////////////////////////////////////////////////////
// FILE:  PCIe_RC_3DW_Flit_swap_2dwPayload_sequence.sv
// DESC:  3DW-header Swap AtomicOp, Flit mode, 2 DW operand (64-bit).
//
//        Flow (all requests go to the SAME address 0x0000_0000_0000_3100) :
//          STEP 1 : MemWr  2 DW  -> put a known start value (seed) in EP memory
//          STEP 2 : Swap   Length = 2 DW -> the AtomicOp request (Non-Posted)
//          STEP 3 : wait for its CplD -> must return the OLD value (= seed)
//          STEP 4 : MemRd  2 DW  -> read memory back
//          STEP 5 : wait for its CplD -> must return the NEW value
//
//        Expected : old = 0x1111_2222_3333_4444, new = 0xDEAD_BEEF_CAFE_F00D
//
//        Payload of the AtomicOp (low DW first) :
//          data[0] = swap value [31:0]   data[1] = swap value [63:32]
////////////////////////////////////////////////////////////////////////////////////////

class PCIe_RC_3DW_Flit_swap_2dwPayload_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_3DW_Flit_swap_2dwPayload_sequence)

  //----------------------------------------------------------------------
  // Test values
  //----------------------------------------------------------------------
  pcie_atomic_op_e m_op         = PCIe_ATOMIC_SWAP;
  int unsigned     m_operand_dw = `PCIe_ATOMIC_OPERAND_64_DW;   // operand size in DW
  bit [63:0]       m_addr       = 64'h0000_0000_0000_3100;
  bit [63:0]       m_seed       = 64'h1111_2222_3333_4444;   // start value in memory
  bit [63:0]       m_operand1   = 64'hDEAD_BEEF_CAFE_F00D;   // swap value
  bit [63:0]       m_operand2   = 64'h0;   // not used

  bit [`PCIe_TL_TAG_W-1:0] m_mwr_tag    = 'h20;
  bit [`PCIe_TL_TAG_W-1:0] m_atomic_tag = 'h21;
  bit [`PCIe_TL_TAG_W-1:0] m_mrd_tag    = 'h22;

  bit [`PCIe_TL_DATA_DW_W-1:0] m_payload[];      // data[] of the request being built
  PCIe_RC_TL_model             rc_tl;            // where the completions arrive

  function new(string name="PCIe_RC_3DW_Flit_swap_2dwPayload_sequence");
    super.new(name);
  endfunction

  task body();
    PCIe_sequence_item cpl;
    bit [63:0]         exp_new;
    bit [63:0]         got;

    `uvm_info("3DW_FLIT_SWAP_2DW","ENTERED_INTO_3DW_FLIT_SWAP_2DW_SEQUENCE_BODY", UVM_LOW)

    if (!uvm_config_db#(PCIe_RC_TL_model)::get(m_sequencer, "", "rc_tl_model", rc_tl))
      `uvm_warning("3DW_FLIT_SWAP_2DW", "rc_tl_model not found in uvm_config_db : completions will not be checked by this sequence")

    // the value memory must hold after the AtomicOp (same function the EP uses)
    exp_new = PCIe_sequence_item::atomic_compute(m_op, m_operand_dw, m_seed, m_operand1, m_operand2);

    //------------------------------------------------------------------
    // STEP 1 : MemWr - seed value
    //------------------------------------------------------------------
    PCIe_sequence_item::atomic_put_operand(m_seed, m_operand_dw, m_payload);
    send_mem_write();

    //------------------------------------------------------------------
    // STEP 2 : AtomicOp request
    //   FetchAdd / Swap : payload = operand1
    //   CAS             : payload = operand1 (compare) then operand2 (swap)
    //------------------------------------------------------------------
    build_atomic_payload();
    send_atomic();

    //------------------------------------------------------------------
    // STEP 3 : AtomicOp CplD must carry the OLD value
    //------------------------------------------------------------------
    wait_cpl(m_atomic_tag, "AtomicOp", cpl);
    if (cpl != null) begin
      got = PCIe_sequence_item::atomic_get_operand(cpl.cpl_data, 0, m_operand_dw);
      if (got == m_seed)
        `uvm_info("3DW_FLIT_SWAP_2DW", $sformatf("ATOMIC_CPL_PASS : old value returned = 0x%0h (expected 0x%0h)", got, m_seed), UVM_LOW)
      else
        `uvm_error("3DW_FLIT_SWAP_2DW", $sformatf("ATOMIC_CPL_FAIL : old value returned = 0x%0h, expected 0x%0h", got, m_seed))
    end

    //------------------------------------------------------------------
    // STEP 4 + 5 : MemRd readback must show the NEW value
    //------------------------------------------------------------------
    send_mem_read();
    wait_cpl(m_mrd_tag, "MemRd", cpl);
    if (cpl != null) begin
      got = PCIe_sequence_item::atomic_get_operand(cpl.cpl_data, 0, m_operand_dw);
      if (got == exp_new)
        `uvm_info("3DW_FLIT_SWAP_2DW", $sformatf("READBACK_PASS : memory after Swap = 0x%0h (expected 0x%0h)", got, exp_new), UVM_LOW)
      else
        `uvm_error("3DW_FLIT_SWAP_2DW", $sformatf("READBACK_FAIL : memory after Swap = 0x%0h, expected 0x%0h", got, exp_new))
    end

    `uvm_info("3DW_FLIT_SWAP_2DW","EXIT_FROM_3DW_FLIT_SWAP_2DW_SEQUENCE_BODY", UVM_LOW)
  endtask

  //----------------------------------------------------------------------
  // payload of the AtomicOp : operand1 (+ operand2 for CAS), low DW first
  //----------------------------------------------------------------------
  function void build_atomic_payload();
    bit [`PCIe_TL_DATA_DW_W-1:0] op1_dws[];
    bit [`PCIe_TL_DATA_DW_W-1:0] op2_dws[];
    PCIe_sequence_item::atomic_put_operand(m_operand1, m_operand_dw, op1_dws);
    if (m_op == PCIe_ATOMIC_CAS) begin
      PCIe_sequence_item::atomic_put_operand(m_operand2, m_operand_dw, op2_dws);
      m_payload = {op1_dws, op2_dws};
    end
    else
      m_payload = op1_dws;
  endfunction

  //----------------------------------------------------------------------
  // STEP 1 : Memory Write of m_payload (m_operand_dw DW)
  //----------------------------------------------------------------------
  task send_mem_write();
    pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         // LTSSM information
         electrical_idle_test == 1'b0;
         no_receiver_test     == 1'b0;
         tx_elec_idle         == 1'b1;
         pkt_mode             == FLIT;

         ep           == 1'b0;
         requester_id == 16'h0100;
         tc           == 3'h0;
         ts           == 3'b000;
         attr         == 3'h0;
         at           == 2'b00;

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

         txn_type       == PCIe_TL_MEM;
         dir            == PCIe_TL_WRITE;
         mem_locked     == 1'b0;
         mem_deferrable == 1'b0;
         atomic_op      == PCIe_ATOMIC_NONE;

         address     == local::m_addr;
         length      == local::m_operand_dw;
         first_dw_be == 4'hF;
         last_dw_be  == ((local::m_operand_dw == 1) ? 4'h0 : 4'hF);
         tag         == local::m_mwr_tag;
         foreach (data[i]) data[i] == local::m_payload[i];
       })
      `uvm_error("3DW_FLIT_SWAP_2DW","randomize failed for seed MemWr")

    `uvm_info("TL_MWR", $sformatf("STEP 1 : Sending 3DW Flit MemWr (seed 0x%0h) addr=0x%0h", m_seed, m_addr), UVM_LOW)
    if (uvm_top.uvm_report_enabled(UVM_HIGH, UVM_INFO, "ITEM_PRINT")) pcie_seq_item.print();
    finish_item(pcie_seq_item);
  endtask

  //----------------------------------------------------------------------
  // STEP 2 : the AtomicOp request (payload = m_payload)
  //----------------------------------------------------------------------
  task send_atomic();
    pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         // LTSSM information
         electrical_idle_test == 1'b0;
         no_receiver_test     == 1'b0;
         tx_elec_idle         == 1'b1;
         pkt_mode             == FLIT;

         ep           == 1'b0;
         requester_id == 16'h0100;
         tc           == 3'h0;
         ts           == 3'b000;
         attr         == 3'h0;
         at           == 2'b00;

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

         // AtomicOp : MEM + WRITE (carries data) + atomic_op, Non-Posted
         txn_type       == PCIe_TL_MEM;
         dir            == PCIe_TL_WRITE;
         mem_locked     == 1'b0;
         mem_deferrable == 1'b0;
         atomic_op      == local::m_op;

         address     == local::m_addr;
         length      == `PCIe_ATOMIC_SWAP_LEN_64;       // Table 2-15
         tag         == local::m_atomic_tag;
         foreach (data[i]) data[i] == local::m_payload[i];
       })
      `uvm_error("3DW_FLIT_SWAP_2DW","randomize failed for Swap AtomicOp")

    `uvm_info("TL_ATOMIC", $sformatf("STEP 2 : Sending 3DW Flit %s addr=0x%0h operand1=0x%0h operand2=0x%0h",
              PCIe_sequence_item::atomic_name(m_op, m_operand_dw), m_addr, m_operand1, m_operand2), UVM_LOW)
    if (uvm_top.uvm_report_enabled(UVM_HIGH, UVM_INFO, "ITEM_PRINT")) pcie_seq_item.print();
    finish_item(pcie_seq_item);
  endtask

  //----------------------------------------------------------------------
  // STEP 4 : Memory Read of m_operand_dw DW (readback)
  //----------------------------------------------------------------------
  task send_mem_read();
    pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
    start_item(pcie_seq_item);
    if (!pcie_seq_item.randomize() with {
         // LTSSM information
         electrical_idle_test == 1'b0;
         no_receiver_test     == 1'b0;
         tx_elec_idle         == 1'b1;
         pkt_mode             == FLIT;

         ep           == 1'b0;
         requester_id == 16'h0100;
         tc           == 3'h0;
         ts           == 3'b000;
         attr         == 3'h0;
         at           == 2'b00;

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

         txn_type       == PCIe_TL_MEM;
         dir            == PCIe_TL_READ;
         mem_locked     == 1'b0;
         mem_deferrable == 1'b0;
         atomic_op      == PCIe_ATOMIC_NONE;

         address     == local::m_addr;
         length      == local::m_operand_dw;
         first_dw_be == 4'hF;
         last_dw_be  == ((local::m_operand_dw == 1) ? 4'h0 : 4'hF);
         tag         == local::m_mrd_tag;
       })
      `uvm_error("3DW_FLIT_SWAP_2DW","randomize failed for readback MemRd")

    `uvm_info("TL_MRD", $sformatf("STEP 4 : Sending 3DW Flit MemRd (readback) addr=0x%0h", m_addr), UVM_LOW)
    if (uvm_top.uvm_report_enabled(UVM_HIGH, UVM_INFO, "ITEM_PRINT")) pcie_seq_item.print();
    finish_item(pcie_seq_item);
  endtask

  //----------------------------------------------------------------------
  // wait for the completion with tag t (stored by the RC TL model)
  //----------------------------------------------------------------------
  task wait_cpl(bit [`PCIe_TL_TAG_W-1:0] t, string what, output PCIe_sequence_item cpl);
    bit timed_out;
    cpl = null;
    if (rc_tl == null) return;
    rc_tl.wait_completion(t, `PCIe_ATOMIC_CPL_TIMEOUT_NS, cpl, timed_out);
    if (timed_out)
      `uvm_error("3DW_FLIT_SWAP_2DW", $sformatf("%s COMPLETION_TIMEOUT tag=0x%0h (no completion in %0d ns)", what, t, `PCIe_ATOMIC_CPL_TIMEOUT_NS))
    else if (cpl.cpl_status != `PCIe_CPL_STATUS_SC)
      `uvm_error("3DW_FLIT_SWAP_2DW", $sformatf("%s tag=0x%0h completed with status %s", what, t, rc_tl.cpl_status_str(cpl.cpl_status)))
  endtask

endclass

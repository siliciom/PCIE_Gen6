//=========================================================================================
// File         : PCIe_RC_3DW_Flit_MemWr_followed_IOWr_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_3DW_Flit_MemWr_followed_IOWr_sequence.sv
// Author       :
// Date         : 2026-10-27
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

////////////////////////////////////////////////////////////////////////////////////////////
// FILE:  PCIe_RC_3DW_Flit_MemWr_followed_IOWr_sequence.sv
// DESC:  3DW Flit Memory Write (MemWr) followed by I/O Write (IOWr), sent with fork ... join.
//
//  ORDERING RULE CHECKED  (PCIe 6.1 Table 2-42)
//  -----------------------------------------------------------------------------------
//    1st (T1, older) : MemWr  -> POSTED
//    2nd (T2, newer) : IOWr   -> NPR_WITH_DATA
//    Table 2-42 row = NPR_WITH_DATA, column = POSTED  ->  rule C2a
//    NPR with Data must NOT pass an older Posted
//
//  ATTRIBUTE BITS  attr[2:0] = {IDO, RO, NS}
//  -----------------------------------------------------------------------------------
//
//    IOWr  : Attr MUST be 000b (Sec 2.2.7) -> RO=0 IDO=0 -> C2b can never apply -> always C2a
//    MemWr : RO = 1, IDO = 1 (attr = 110) (do not change the rule)
//    Traffic Class is 0 for both TLPs (the table applies inside one TC).
//    The sequence prints EXPECTED_ORDERING_RULE after both TLPs are randomized.
//
//  EXPECTED LOG  (grep "ORDERING_RULE_CHECKED\|ORDERING_DECISION" sim/*_log.log)
//    EXPECTED_ORDERING_RULE : ... -> rule C2a ...     (from the sequence)
//    ORDERING_RULE_CHECKED  : Table 2-42 row=NPR_WITH_DATA col=POSTED -> rule C2a ...
//    ORDERING_DECISION      : rule C2a ... -> PASS
////////////////////////////////////////////////////////////////////////////////////////////

class PCIe_RC_3DW_Flit_MemWr_followed_IOWr_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_3DW_Flit_MemWr_followed_IOWr_sequence)

  // [FORK] shared by both branches : who got the sequencer / was sent first
  int unsigned grant_no;
  int unsigned sent_no;

  // [FORK] one handle per branch (1st TLP = t1_item, 2nd TLP = t2_item).
  //        Kept in the class so the 2nd branch can compare both TLPs.
  PCIe_sequence_item t1_item;
  PCIe_sequence_item t2_item;


  function new(string name="PCIe_RC_3DW_Flit_MemWr_followed_IOWr_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("3DW_FLIT_MEMWR_FOLLOWED_IOWR","ENTERED_INTO_3DW_FLIT_MEMWR_FOLLOWED_IOWR_SEQUENCE_BODY", UVM_LOW)

    //------------------------------------------------------------------
    // [FORK] MemWr and IOWr are started in parallel (fork ... join).
    //   * Each branch uses its OWN item handle. The shared pcie_seq_item
    //     would be overwritten by the other branch (race) -> wrong TLP.
    //   * The 2nd branch waits until the 1st branch has the sequencer,
    //     so MemWr is always issued first and rule C2a is checked.
    //   * The ordering checker (ORD_CHK) prints the Table 2-42 rule used
    //     and which TLP went first.
    //------------------------------------------------------------------
    grant_no = 0;     // order in which the sequencer gave the driver each item
    sent_no  = 0;     // order in which each item finished (TLP sent)

    `uvm_info("FORK_SEQ", "FORK_STARTED : MemWr (WRITE) branch and IOWr (WRITE) branch start together. Expected ordering rule : C2a", UVM_LOW)

    fork
      begin : MEMWR_BRANCH
        `uvm_info("FORK_SEQ_MEMWR", $sformatf("MEMWR_BRANCH_STARTED : WRITE sequence item (MemWr) waiting for sequencer @%0t", $time), UVM_LOW)
        t1_item = PCIe_sequence_item::type_id::create("t1_item");
        start_item(t1_item);
        grant_no++;
        `uvm_info("FORK_SEQ_MEMWR", $sformatf("MEMWR_GRANTED : WRITE (MemWr) got the sequencer as item #%0d %s @%0t",
                  grant_no, (grant_no == 1) ? "-> MemWr is ISSUED FIRST" : "-> MemWr is ISSUED SECOND", $time), UVM_LOW)
        if (!t1_item.randomize() with {
             // LTSSM information
             electrical_idle_test == 1'b0;
             no_receiver_test     == 1'b0;
             tx_elec_idle         == 1'b1;
             pkt_mode             == FLIT;

             txn_type == PCIe_TL_MEM;
             dir      == PCIe_TL_WRITE;

             mem_locked     == 1'b0;
             mem_deferrable == 1'b0;

             address == 32'h0000_2000;

             tag          == 14'h0021;
             requester_id == 16'h0100;
             // [ATTR] {IDO, RO, NS} = 110 : IDO = 1 (SET), RO = 1 (SET), NS = 0 (NOT SET)
             attr == 3'b110;

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
          `uvm_error("3DW_FLIT_MEMWR_FOLLOWED_IOWR","randomize failed for MemWr")

        //--------------------------------------------------------------
        // [ATTR] print which attribute bits are SET in this MemWr
        //   attr[2] = IDO : SET -> ID-Based Ordering   (may pass an older Posted
        //                         only if the Requester IDs are different)
        //   attr[1] = RO  : SET -> Relaxed Ordering    (may pass an older Posted;
        //                         does NOT help a Read Request)
        //   attr[0] = NS  : SET -> No Snoop            (no effect on ordering)
        //--------------------------------------------------------------
        `uvm_info("ATTR_BITS", $sformatf("MemWr tag=0x%0h reqid=0x%04h attr=%03b : IDO=%0b (%s)  RO=%0b (%s)  NS=%0b (%s)",
                  t1_item.tag, t1_item.requester_id, t1_item.attr,
                  t1_item.attr[2], t1_item.attr[2] ? "SET -> ID-Based Ordering ENABLED" : "NOT SET",
                  t1_item.attr[1], t1_item.attr[1] ? "SET -> Relaxed Ordering ENABLED"  : "NOT SET",
                  t1_item.attr[0], t1_item.attr[0] ? "SET -> No Snoop"                  : "NOT SET"), UVM_LOW)

        `uvm_info("TL_MEMWR",$sformatf("Sending_3DW_Flit_MemWr (Memory Write, POSTED) - 1st TLP of MemWr followed by IOWr"), UVM_LOW)
        t1_item.print();

        finish_item(t1_item);
        sent_no++;
        `uvm_info("FORK_SEQ_MEMWR", $sformatf("MEMWR_SENT : WRITE (MemWr) tag=0x%0h attr=%03b finished as #%0d %s @%0t",
                  t1_item.tag, t1_item.attr, sent_no, (sent_no == 1) ? "-> MemWr WENT FIRST" : "-> MemWr WENT SECOND", $time), UVM_LOW)
      end : MEMWR_BRANCH
      begin : IOWR_BRANCH
        `uvm_info("FORK_SEQ_IOWR", $sformatf("IOWR_BRANCH_STARTED : WRITE sequence item (IOWr) waiting for sequencer @%0t", $time), UVM_LOW)
        // [FORK] wait until the 1st branch (MemWr) has the sequencer, so the order is
        //        always 1st = MemWr, 2nd = IOWr and the expected rule is checked every run.
        wait (grant_no >= 1);
        t2_item = PCIe_sequence_item::type_id::create("t2_item");
        start_item(t2_item);
        grant_no++;
        `uvm_info("FORK_SEQ_IOWR", $sformatf("IOWR_GRANTED : WRITE (IOWr) got the sequencer as item #%0d %s @%0t",
                  grant_no, (grant_no == 1) ? "-> IOWr is ISSUED FIRST" : "-> IOWr is ISSUED SECOND", $time), UVM_LOW)
        if (!t2_item.randomize() with {
             // LTSSM information
             electrical_idle_test == 1'b0;
             no_receiver_test     == 1'b0;
             tx_elec_idle         == 1'b1;
             pkt_mode             == FLIT;

             txn_type    == PCIe_TL_IO;
             dir         == PCIe_TL_WRITE;
             length      == `PCIe_TL_LEN_MIN;
             first_dw_be == 4'hF;
             last_dw_be  == 4'h0;

             tag          == 14'h0022;
             requester_id == 16'h0100;
             attr == 3'b000;      // [ATTR] Config / I/O request : Attr MUST be 000b (Sec 2.2.7)

             // Fields belonging to other transaction categories MUST be zero for an IO transaction
             cfg_reg_num          == '0;
             cfg_ext_reg_num      == '0;
             cfg_bus_num          == '0;
             cfg_dev_num          == '0;
             cfg_fn_num           == '0;
             cfg_type1            == 1'b0;
             msg_code             == '0;
             msg_route            == PCIe_MSG_ROUTE_TO_RC;
             msg_has_data         == 1'b0;
           })
          `uvm_error("3DW_FLIT_MEMWR_FOLLOWED_IOWR","randomize failed for IOWr")

        //--------------------------------------------------------------
        // [ATTR] print which attribute bits are SET in this IOWr
        //   attr[2] = IDO : SET -> ID-Based Ordering   (may pass an older Posted
        //                         only if the Requester IDs are different)
        //   attr[1] = RO  : SET -> Relaxed Ordering    (may pass an older Posted;
        //                         does NOT help a Read Request)
        //   attr[0] = NS  : SET -> No Snoop            (no effect on ordering)
        //--------------------------------------------------------------
        `uvm_info("ATTR_BITS", $sformatf("IOWr tag=0x%0h reqid=0x%04h attr=%03b : IDO=%0b (%s)  RO=%0b (%s)  NS=%0b (%s)",
                  t2_item.tag, t2_item.requester_id, t2_item.attr,
                  t2_item.attr[2], t2_item.attr[2] ? "SET -> ID-Based Ordering ENABLED" : "NOT SET",
                  t2_item.attr[1], t2_item.attr[1] ? "SET -> Relaxed Ordering ENABLED"  : "NOT SET",
                  t2_item.attr[0], t2_item.attr[0] ? "SET -> No Snoop"                  : "NOT SET"), UVM_LOW)

        //--------------------------------------------------------------
        // [ATTR] both TLPs are randomized now. Work out which Table 2-42
        //        rule these attribute bits / Requester IDs give (same
        //        rules class as the ordering checker) and print it.
        //--------------------------------------------------------------
        begin
          string            exp_rule, exp_why;
          pcie_ord_result_e exp_res;
          exp_res = PCIe_ordering_rules::check_pass(t2_item, t1_item, exp_rule, exp_why);
          `uvm_info("FORK_SEQ", $sformatf({"EXPECTED_ORDERING_RULE : 1st %s (IDO=%0b RO=%0b reqid=0x%04h)  2nd %s (IDO=%0b RO=%0b reqid=0x%04h)",
                    " -> rule %s = %s : %s"},
                    "MemWr", t1_item.attr[2], t1_item.attr[1], t1_item.requester_id,
                    "IOWr", t2_item.attr[2], t2_item.attr[1], t2_item.requester_id,
                    exp_rule, PCIe_ordering_rules::result_name(exp_res), exp_why), UVM_LOW)
        end

        `uvm_info("TL_IOWR",$sformatf("Sending_3DW_Flit_IOWr (I/O Write, NPR_WITH_DATA) - 2nd TLP of MemWr followed by IOWr"), UVM_LOW)
        t2_item.print();

        finish_item(t2_item);
        sent_no++;
        `uvm_info("FORK_SEQ_IOWR", $sformatf("IOWR_SENT : WRITE (IOWr) tag=0x%0h attr=%03b finished as #%0d %s @%0t",
                  t2_item.tag, t2_item.attr, sent_no, (sent_no == 1) ? "-> IOWr WENT FIRST" : "-> IOWr WENT SECOND", $time), UVM_LOW)
      end : IOWR_BRANCH
    join

    `uvm_info("FORK_SEQ", "FORK_JOINED : both MemWr and IOWr are sent. See ORD_CHK ORDERING_DECISION for Table 2-42 rule C2a", UVM_LOW)

    `uvm_info("3DW_FLIT_MEMWR_FOLLOWED_IOWR","EXIT_FROM_3DW_FLIT_MEMWR_FOLLOWED_IOWR_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

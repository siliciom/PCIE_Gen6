//=========================================================================================
// File         : PCIe_RC_3DW_Flit_MemRd_followed_MemWr_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_3DW_Flit_MemRd_followed_MemWr_sequence.sv
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
// FILE:  PCIe_RC_3DW_Flit_MemRd_followed_MemWr_sequence.sv
// DESC:  3DW Flit Memory Read (MemRd) followed by Memory Write (MemWr), sent with fork ... join.
//
//  ORDERING RULE CHECKED  (PCIe 6.1 Table 2-42)
//  -----------------------------------------------------------------------------------
//    1st (T1, older) : MemRd  -> READ_REQ
//    2nd (T2, newer) : MemWr  -> POSTED
//    Table 2-42 row = POSTED, column = READ_REQ  ->  rule A3
//    Posted MUST be ABLE to pass an older Read Request (deadlock avoidance)
//
//  ATTRIBUTE BITS  attr[2:0] = {IDO, RO, NS}
//  -----------------------------------------------------------------------------------
//
//    Both : RO = 1, IDO = 1 (attr = 110), MemWr Requester ID random.
//    A3 has NO RO / IDO condition : it is always YES, whatever the bits are.
//    Traffic Class is 0 for both TLPs (the table applies inside one TC).
//    The sequence prints EXPECTED_ORDERING_RULE after both TLPs are randomized.
//
//  EXPECTED LOG  (grep "ORDERING_RULE_CHECKED\|ORDERING_DECISION" sim/*_log.log)
//    EXPECTED_ORDERING_RULE : ... -> rule A3 ...     (from the sequence)
//    ORDERING_RULE_CHECKED  : Table 2-42 row=POSTED col=READ_REQ -> rule A3 ...
//    ORDERING_DECISION      : rule A3 ... -> PASS
////////////////////////////////////////////////////////////////////////////////////////////

class PCIe_RC_3DW_Flit_MemRd_followed_MemWr_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_3DW_Flit_MemRd_followed_MemWr_sequence)

  // [FORK] shared by both branches : who got the sequencer / was sent first
  int unsigned grant_no;
  int unsigned sent_no;

  // [FORK] one handle per branch (1st TLP = t1_item, 2nd TLP = t2_item).
  //        Kept in the class so the 2nd branch can compare both TLPs.
  PCIe_sequence_item t1_item;
  PCIe_sequence_item t2_item;


  function new(string name="PCIe_RC_3DW_Flit_MemRd_followed_MemWr_sequence");
    super.new(name);
  endfunction

  task body();
    `uvm_info("3DW_FLIT_MEMRD_FOLLOWED_MEMWR","ENTERED_INTO_3DW_FLIT_MEMRD_FOLLOWED_MEMWR_SEQUENCE_BODY", UVM_LOW)

    //------------------------------------------------------------------
    // [FORK] MemRd and MemWr are started in parallel (fork ... join).
    //   * Each branch uses its OWN item handle. The shared pcie_seq_item
    //     would be overwritten by the other branch (race) -> wrong TLP.
    //   * The 2nd branch waits until the 1st branch has the sequencer,
    //     so MemRd is always issued first and rule A3 is checked.
    //   * The ordering checker (ORD_CHK) prints the Table 2-42 rule used
    //     and which TLP went first.
    //------------------------------------------------------------------
    grant_no = 0;     // order in which the sequencer gave the driver each item
    sent_no  = 0;     // order in which each item finished (TLP sent)

    `uvm_info("FORK_SEQ", "FORK_STARTED : MemRd (READ) branch and MemWr (WRITE) branch start together. Expected ordering rule : A3", UVM_LOW)

    fork
      begin : MEMRD_BRANCH
        `uvm_info("FORK_SEQ_MEMRD", $sformatf("MEMRD_BRANCH_STARTED : READ sequence item (MemRd) waiting for sequencer @%0t", $time), UVM_LOW)
        t1_item = PCIe_sequence_item::type_id::create("t1_item");
        start_item(t1_item);
        grant_no++;
        `uvm_info("FORK_SEQ_MEMRD", $sformatf("MEMRD_GRANTED : READ (MemRd) got the sequencer as item #%0d %s @%0t",
                  grant_no, (grant_no == 1) ? "-> MemRd is ISSUED FIRST" : "-> MemRd is ISSUED SECOND", $time), UVM_LOW)
        if (!t1_item.randomize() with {
             // LTSSM information
             electrical_idle_test == 1'b0;
             no_receiver_test     == 1'b0;
             tx_elec_idle         == 1'b1;
             pkt_mode             == FLIT;

             txn_type == PCIe_TL_MEM;
             dir      == PCIe_TL_READ;

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
          `uvm_error("3DW_FLIT_MEMRD_FOLLOWED_MEMWR","randomize failed for MemRd")

        //--------------------------------------------------------------
        // [ATTR] print which attribute bits are SET in this MemRd
        //   attr[2] = IDO : SET -> ID-Based Ordering   (may pass an older Posted
        //                         only if the Requester IDs are different)
        //   attr[1] = RO  : SET -> Relaxed Ordering    (may pass an older Posted;
        //                         does NOT help a Read Request)
        //   attr[0] = NS  : SET -> No Snoop            (no effect on ordering)
        //--------------------------------------------------------------
        `uvm_info("ATTR_BITS", $sformatf("MemRd tag=0x%0h reqid=0x%04h attr=%03b : IDO=%0b (%s)  RO=%0b (%s)  NS=%0b (%s)",
                  t1_item.tag, t1_item.requester_id, t1_item.attr,
                  t1_item.attr[2], t1_item.attr[2] ? "SET -> ID-Based Ordering ENABLED" : "NOT SET",
                  t1_item.attr[1], t1_item.attr[1] ? "SET -> Relaxed Ordering ENABLED"  : "NOT SET",
                  t1_item.attr[0], t1_item.attr[0] ? "SET -> No Snoop"                  : "NOT SET"), UVM_LOW)

        `uvm_info("TL_MEMRD",$sformatf("Sending_3DW_Flit_MemRd (Memory Read, READ_REQ) - 1st TLP of MemRd followed by MemWr"), UVM_LOW)
        t1_item.print();

        finish_item(t1_item);
        sent_no++;
        `uvm_info("FORK_SEQ_MEMRD", $sformatf("MEMRD_SENT : READ (MemRd) tag=0x%0h attr=%03b finished as #%0d %s @%0t",
                  t1_item.tag, t1_item.attr, sent_no, (sent_no == 1) ? "-> MemRd WENT FIRST" : "-> MemRd WENT SECOND", $time), UVM_LOW)
      end : MEMRD_BRANCH
      begin : MEMWR_BRANCH
        `uvm_info("FORK_SEQ_MEMWR", $sformatf("MEMWR_BRANCH_STARTED : WRITE sequence item (MemWr) waiting for sequencer @%0t", $time), UVM_LOW)
        // [FORK] wait until the 1st branch (MemRd) has the sequencer, so the order is
        //        always 1st = MemRd, 2nd = MemWr and the expected rule is checked every run.
        wait (grant_no >= 1);
        t2_item = PCIe_sequence_item::type_id::create("t2_item");
        start_item(t2_item);
        grant_no++;
        `uvm_info("FORK_SEQ_MEMWR", $sformatf("MEMWR_GRANTED : WRITE (MemWr) got the sequencer as item #%0d %s @%0t",
                  grant_no, (grant_no == 1) ? "-> MemWr is ISSUED FIRST" : "-> MemWr is ISSUED SECOND", $time), UVM_LOW)
        if (!t2_item.randomize() with {
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

             tag          == 14'h0022;
             // [ATTR] same or different Requester ID : decides if IDO can apply
             requester_id inside {16'h0100, 16'h0200};
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
          `uvm_error("3DW_FLIT_MEMRD_FOLLOWED_MEMWR","randomize failed for MemWr")

        //--------------------------------------------------------------
        // [ATTR] print which attribute bits are SET in this MemWr
        //   attr[2] = IDO : SET -> ID-Based Ordering   (may pass an older Posted
        //                         only if the Requester IDs are different)
        //   attr[1] = RO  : SET -> Relaxed Ordering    (may pass an older Posted;
        //                         does NOT help a Read Request)
        //   attr[0] = NS  : SET -> No Snoop            (no effect on ordering)
        //--------------------------------------------------------------
        `uvm_info("ATTR_BITS", $sformatf("MemWr tag=0x%0h reqid=0x%04h attr=%03b : IDO=%0b (%s)  RO=%0b (%s)  NS=%0b (%s)",
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
                    "MemRd", t1_item.attr[2], t1_item.attr[1], t1_item.requester_id,
                    "MemWr", t2_item.attr[2], t2_item.attr[1], t2_item.requester_id,
                    exp_rule, PCIe_ordering_rules::result_name(exp_res), exp_why), UVM_LOW)
        end

        `uvm_info("TL_MEMWR",$sformatf("Sending_3DW_Flit_MemWr (Memory Write, POSTED) - 2nd TLP of MemRd followed by MemWr"), UVM_LOW)
        t2_item.print();

        finish_item(t2_item);
        sent_no++;
        `uvm_info("FORK_SEQ_MEMWR", $sformatf("MEMWR_SENT : WRITE (MemWr) tag=0x%0h attr=%03b finished as #%0d %s @%0t",
                  t2_item.tag, t2_item.attr, sent_no, (sent_no == 1) ? "-> MemWr WENT FIRST" : "-> MemWr WENT SECOND", $time), UVM_LOW)
      end : MEMWR_BRANCH
    join

    `uvm_info("FORK_SEQ", "FORK_JOINED : both MemRd and MemWr are sent. See ORD_CHK ORDERING_DECISION for Table 2-42 rule A3", UVM_LOW)

    `uvm_info("3DW_FLIT_MEMRD_FOLLOWED_MEMWR","EXIT_FROM_3DW_FLIT_MEMRD_FOLLOWED_MEMWR_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

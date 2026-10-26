//=========================================================================================
// File         : PCIe_ordering_checker.sv
// Project      : PCIE_Gen6
// Description  : PCIe_environment\PCIe_ordering_checker.sv
//                Checks that TLPs leave the RC Transaction Layer in an order allowed by
//                PCIe Base Spec 6.1 Table 2-42 (Section 2.4.1, pages 247 - 250).
// Author       :
// Date         : 2026-10-22
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

//=========================================================================================
//  WHAT DOES THIS CHECKER DO ?
//-----------------------------------------------------------------------------------------
//  It listens to two EXISTING analysis ports. No driver / TL model code is changed.
//
//     issued : RC controller driver  tx_tl_ap   -> TLP GIVEN to the RC TL model
//     sent   : RC TL model           tlp_dl_ap  -> TLP that LEFT the RC TL model to the DL
//
//  It keeps a list of TLPs that are issued but not yet sent (oldest first). When a TLP
//  (T2) is sent, every TLP still in that list (T1) is OLDER than T2, so T2 has just
//  passed T1. For each such pair it asks PCIe_ordering_rules::check_pass(T2, T1):
//
//      NO   -> UVM_ERROR  "ORDERING_VIOLATION"   (spec : T2 must not pass T1)
//      YES  -> info       (legal; the spec even requires it when T1 is blocked)
//      Y/N  -> info       (legal; no requirement)
//
//  It is a pure checker. It does not change any TLP and does not block anything.
//  At the end it prints which Table 2-42 rules (A2a, B2b, D5b ...) were exercised.
//
//  INFO PRINTS FOR EVERY TLP  (grep "ORD_CHK" in the log)
//  -----------------------------------------------------------------------------------
//    TLP_LEFT_TL                  : this TLP left the RC TL now
//    ENTERED_ORDERING_TABLE_CHECK : T1 = TLP sent before it (older), T2 = this TLP (newer)
//    ORDERING_RULE_CHECKED        : Table 2-42 row / column / rule used (A2a, B2a, D3 ...)
//    ORDERING_DECISION            : which TLP the rule says goes first, which really went
//                                   first, PASS / FAIL
//  Example (MemWr then MemRd, same Requester ID, no RO / IDO help for the Read) :
//    ORDERING_RULE_CHECKED : Table 2-42 row=READ_REQ col=POSTED -> rule B2a = NO(must not pass)
//    ORDERING_DECISION     : rule B2a says T1 MemWr MUST go first ... | actual : T1 MemWr went first -> PASS
//
//-----------------------------------------------------------------------------------------
//  THINGS THE CHECKER SKIPS (on purpose)
//-----------------------------------------------------------------------------------------
//    * IDLE / NOP flits : they carry no real TLP and the TL model never puts them on
//      tlp_dl_ap (see build_idle_or_nop_flit). Same filter as rc_tl_model.fc_applies().
//    * DL replay : handle_replay_request() writes "replayed_item" on tx_tl_ap. A replay
//      re-sends TLPs that already left the TL, it is a Data Link Layer action, not a
//      new transaction, so Table 2-42 does not apply to it.
//
//-----------------------------------------------------------------------------------------
//  NOTE ABOUT THE CALL ORDER
//-----------------------------------------------------------------------------------------
//  tx_tl_ap has two subscribers : the RC TL model and this checker. The TL model sends the
//  TLP to the DL inside its write() call. Depending on which subscriber UVM calls first,
//  this checker may see "sent" BEFORE "issued" for the same TLP. Both orders are handled:
//  a "sent" with no matching "issued" waits in sent_early[] until its "issued" arrives.
//
//-----------------------------------------------------------------------------------------
//  HOW IT IS CONNECTED  (PCIe_environment.sv, connect_phase)
//-----------------------------------------------------------------------------------------
//    rc_top_agent.rc_controller_agent.rc_controller_driver.tx_tl_ap.connect(pcie_ordering_checker.issued_imp);
//    rc_top_agent.rc_controller_agent.rc_tl_model.tlp_dl_ap.connect       (pcie_ordering_checker.sent_imp);
//=========================================================================================

`uvm_analysis_imp_decl(_ord_issued)
`uvm_analysis_imp_decl(_ord_sent)

class PCIe_ordering_checker extends uvm_component;

  `uvm_component_utils(PCIe_ordering_checker)

  uvm_analysis_imp_ord_issued #(PCIe_sequence_item, PCIe_ordering_checker) issued_imp;
  uvm_analysis_imp_ord_sent   #(PCIe_sequence_item, PCIe_ordering_checker) sent_imp;

  //---------------------------------------------------------------------------------------
  // waiting[]    : issued but not yet sent, oldest first (the same handles the driver gave)
  // waiting_no[] : issue number of each waiting TLP, only for readable log messages
  // sent_early[] : sent before we saw its "issued" (see NOTE ABOUT THE CALL ORDER)
  //---------------------------------------------------------------------------------------
  protected PCIe_sequence_item waiting    [$];
  protected int unsigned       waiting_no [$];
  protected PCIe_sequence_item sent_early [$];
  protected int unsigned       next_no = 0;

  // {Requester ID, Tag} of I/O Write / Config Write requests (for rule D2b)
  protected bit io_cfg_wr_req [bit [31:0]];

  // statistics
  int unsigned n_issued;
  int unsigned n_sent;
  int unsigned n_in_order;              // sent while nothing older was waiting
  int unsigned n_violations;
  int unsigned n_rule_hit [string];     // pairs checked, per rule id

  function new(string name = "PCIe_ordering_checker", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    issued_imp = new("issued_imp", this);
    sent_imp   = new("sent_imp",   this);
  endfunction

  //---------------------------------------------------------------------------------------
  // is_real_tlp : 0 for IDLE / NOP flits and for DL replays (see "THINGS THE CHECKER SKIPS")
  //---------------------------------------------------------------------------------------
  protected function bit is_real_tlp(PCIe_sequence_item t);
    if ((t.pkt_mode == FLIT) && (t.flit_type != PCIe_PAYLOAD_flit)) return 1'b0;
    if (t.get_name() == "replayed_item")                          return 1'b0;
    return 1'b1;
  endfunction

  protected function bit is_io_cfg_wr_cpl(PCIe_sequence_item t);
    if (t.txn_type != PCIe_TL_CPL) return 1'b0;
    return io_cfg_wr_req.exists({t.requester_id, 16'(t.tag)});
  endfunction

  //---------------------------------------------------------------------------------------
  // find : position of handle t in list q, or -1
  //---------------------------------------------------------------------------------------
  protected function int find(ref PCIe_sequence_item q[$], input PCIe_sequence_item t);
    foreach (q[i]) if (q[i] == t) return i;
    return -1;
  endfunction

  //---------------------------------------------------------------------------------------
  // last TLP that left the TL (to compare every new TLP with the one before it)
  //---------------------------------------------------------------------------------------
  protected PCIe_sequence_item last_sent;
  protected int unsigned       last_sent_no;

  //---------------------------------------------------------------------------------------
  // tlp_name : short readable name, e.g. "MemWr", "MemRd", "CfgWr", "Cpl"
  //---------------------------------------------------------------------------------------
  protected function string tlp_name(PCIe_sequence_item t);
    case (t.txn_type)
      PCIe_TL_MEM : begin
        if (t.dir == PCIe_TL_WRITE) return t.mem_deferrable ? "DMWr" : "MemWr";
        return t.mem_locked ? "MemRdLk" : "MemRd";
      end
      PCIe_TL_IO  : return (t.dir == PCIe_TL_WRITE) ? "IOWr"  : "IORd";
      PCIe_TL_CFG : return (t.dir == PCIe_TL_WRITE) ? "CfgWr" : "CfgRd";
      PCIe_TL_MSG : return t.msg_has_data ? "MsgD" : "Msg";
      PCIe_TL_CPL : return "Cpl";
    endcase
    return "TLP";
  endfunction

  // one line description of a TLP for the ordering prints
  protected function string tlp_desc(PCIe_sequence_item t, int unsigned no);
    return $sformatf("#%0d %s (%s, tag=0x%0h, reqid=0x%04h, IDO=%0b RO=%0b NS=%0b)",
                     no, tlp_name(t),
                     PCIe_ordering_rules::class_name(PCIe_ordering_rules::get_ord_class(t)),
                     t.tag, t.requester_id, t.attr[2], t.attr[1], t.attr[0]);
  endfunction

  //---------------------------------------------------------------------------------------
  // [FIX] same_request : 1 when t2 is the next piece of the SAME split request as t1
  //                      (same type, same direction, same requester, same tag, and the
  //                      address continues from where t1 ended). Two pieces of one
  //                      request are one transaction, so Table 2-42 does not apply.
  //---------------------------------------------------------------------------------------
  protected function bit same_request(PCIe_sequence_item t2, PCIe_sequence_item t1);
    int unsigned t1_dw;
    t1_dw = (t1.length == 0) ? 1024 : t1.length;     // Length = 0 means 1024 DW
    return (t2.txn_type     == t1.txn_type)     &&
           (t2.dir          == t1.dir)          &&
           (t2.requester_id == t1.requester_id) &&
           (t2.tag          == t1.tag)          &&
           (t2.address      == t1.address + (t1_dw * 4));
  endfunction

  //=======================================================================================
  // print_table_decision : the 3 info prints asked for
  //   1) ENTERED_ORDERING_TABLE_CHECK : which two TLPs are compared (T1 older, T2 newer)
  //   2) ORDERING_RULE_CHECKED        : which Table 2-42 box / rule was used and why
  //   3) ORDERING_DECISION            : which TLP must / may go first by that rule,
  //                                     which TLP really went first, PASS or FAIL
  //   t2_went_first = 1 when the newer TLP (T2) left the TL before the older one (T1)
  //=======================================================================================
  protected function void print_table_decision(PCIe_sequence_item t2, int unsigned n2,
                                               PCIe_sequence_item t1, int unsigned n1,
                                               bit t2_went_first);
    string            rid, why, rule_says, actual, verdict;
    pcie_ord_result_e r;

    r = PCIe_ordering_rules::check_pass(t2, t1, rid, why, is_io_cfg_wr_cpl(t2));

    // what the table says, in plain words
    case (r)
      ORD_NO  : rule_says = $sformatf("T1 %s MUST go first (T2 %s must NOT pass T1)", tlp_name(t1), tlp_name(t2));
      ORD_YES : rule_says = $sformatf("T2 %s MUST be ABLE to pass T1 %s (if T1 is blocked, T2 goes first; else any order)", tlp_name(t2), tlp_name(t1));
      ORD_YN  : rule_says = $sformatf("no rule : T1 %s or T2 %s may go first", tlp_name(t1), tlp_name(t2));
    endcase

    // what really happened
    actual  = t2_went_first ? $sformatf("T2 %s went first", tlp_name(t2))
                            : $sformatf("T1 %s went first", tlp_name(t1));
    verdict = (r == ORD_NO && t2_went_first) ? "FAIL" : "PASS";

    `uvm_info("ORD_CHK", $sformatf("ENTERED_ORDERING_TABLE_CHECK : T1(older)=%s  T2(newer)=%s",
              tlp_desc(t1, n1), tlp_desc(t2, n2)), UVM_LOW)
    `uvm_info("ORD_CHK", $sformatf("ORDERING_RULE_CHECKED : Table 2-42 row=%s col=%s -> rule %s = %s : %s",
              PCIe_ordering_rules::class_name(PCIe_ordering_rules::get_ord_class(t2)),
              PCIe_ordering_rules::class_name(PCIe_ordering_rules::get_ord_class(t1)),
              rid, PCIe_ordering_rules::result_name(r), why), UVM_LOW)
    `uvm_info("ORD_CHK", $sformatf("ORDERING_DECISION : rule %s says %s | actual : %s -> %s",
              rid, rule_says, actual, verdict), UVM_LOW)
  endfunction

  //=======================================================================================
  // check_sent : T2 = waiting[pos] has just left the TL. Every waiting[j] with j < pos is
  //              older and was passed -> check each pair against Table 2-42.
  //=======================================================================================
  protected function void check_sent(int pos);

    `uvm_info("ORD_CHK", $sformatf("TLP_LEFT_TL : %s", tlp_desc(waiting[pos], waiting_no[pos])), UVM_LOW)

    //-------------------------------------------------------------------------------------
    // compare with the TLP that left just before this one, and print the table decision
    //-------------------------------------------------------------------------------------
    if (last_sent == null) begin
      `uvm_info("ORD_CHK", $sformatf("ENTERED_ORDERING_TABLE_CHECK : %s is the FIRST TLP, nothing older to compare",
                tlp_desc(waiting[pos], waiting_no[pos])), UVM_LOW)
    end
    else if (same_request(waiting[pos], last_sent)) begin
      // [FIX] next piece of the same split request -> not a new transaction, no table check
      `uvm_info("ORD_CHK", $sformatf("SAME_REQUEST_PIECE : %s is the next piece of %s, no ordering check",
                tlp_desc(waiting[pos], waiting_no[pos]), tlp_desc(last_sent, last_sent_no)), UVM_LOW)
    end
    else if (last_sent_no < waiting_no[pos]) begin
      // normal case : the older TLP (T1 = last_sent) went first, now the newer one (T2)
      print_table_decision(waiting[pos], waiting_no[pos], last_sent, last_sent_no, 1'b0);
    end
    else begin
      // the TLP sent before this one was NEWER -> it passed this one
      print_table_decision(last_sent, last_sent_no, waiting[pos], waiting_no[pos], 1'b1);
    end
    last_sent    = waiting[pos];
    last_sent_no = waiting_no[pos];

    if (pos == 0) begin
      n_in_order++;
      `uvm_info("ORD_CHK", $sformatf("IN_ORDER : #%0d %s class=%s attr(IDO,RO,NS)=%03b",
                waiting_no[0], waiting[0].convert2string(),
                PCIe_ordering_rules::class_name(PCIe_ordering_rules::get_ord_class(waiting[0])),
                waiting[0].attr), UVM_MEDIUM)
    end

    for (int j = 0; j < pos; j++) begin
      string            rid, why;
      pcie_ord_result_e r;
      r = PCIe_ordering_rules::check_pass(waiting[pos], waiting[j], rid, why,
                                          is_io_cfg_wr_cpl(waiting[pos]));
      if (!n_rule_hit.exists(rid)) n_rule_hit[rid] = 0;
      n_rule_hit[rid]++;

      if (r == ORD_NO) begin
        n_violations++;
        `uvm_error("ORD_CHK", $sformatf({"ORDERING_VIOLATION rule %s : #%0d was sent before older #%0d\n",
                   "    T2 (newer, sent)    : %s attr(IDO,RO,NS)=%03b\n",
                   "    T1 (older, waiting) : %s attr(IDO,RO,NS)=%03b\n",
                   "    reason : %s"},
                   rid, waiting_no[pos], waiting_no[j],
                   waiting[pos].convert2string(), waiting[pos].attr,
                   waiting[j].convert2string(),   waiting[j].attr, why))
      end
      else begin
        `uvm_info("ORD_CHK", $sformatf("LEGAL_PASS rule %s %s : #%0d before #%0d : %s",
                  rid, PCIe_ordering_rules::result_name(r), waiting_no[pos], waiting_no[j], why), UVM_LOW)
      end
    end

    // the TLP has left the TL, remove it
    if (waiting[pos].txn_type == PCIe_TL_CPL)
      io_cfg_wr_req.delete({waiting[pos].requester_id, 16'(waiting[pos].tag)});
    waiting.delete(pos);
    waiting_no.delete(pos);
    n_sent++;
  endfunction

  //=======================================================================================
  // ISSUED : RC driver -> RC TL model (tx_tl_ap)
  //=======================================================================================
  function void write_ord_issued(PCIe_sequence_item t);
    int e;
    if (!is_real_tlp(t)) return;

    waiting.push_back(t);
    waiting_no.push_back(next_no++);
    n_issued++;
    if ((t.txn_type == PCIe_TL_IO || t.txn_type == PCIe_TL_CFG) && t.dir == PCIe_TL_WRITE)
      io_cfg_wr_req[{t.requester_id, 16'(t.tag)}] = 1'b1;

    // the TL model may already have sent it (see NOTE ABOUT THE CALL ORDER)
    e = find(sent_early, t);
    if (e >= 0) begin
      sent_early.delete(e);
      check_sent(waiting.size() - 1);
    end
  endfunction

  //=======================================================================================
  // SENT : RC TL model -> RC DL model (tlp_dl_ap)
  //=======================================================================================
  function void write_ord_sent(PCIe_sequence_item t);
    int pos;
    if (!is_real_tlp(t)) return;

    pos = find(waiting, t);
    if (pos < 0) begin
      sent_early.push_back(t);      // its "issued" has not arrived yet
      return;
    end
    check_sent(pos);
  endfunction

  //---------------------------------------------------------------------------------------
  // report : result + which Table 2-42 rules were exercised by this test
  //---------------------------------------------------------------------------------------
  function void report_phase(uvm_phase phase);
    string s;
    super.report_phase(phase);
    s = $sformatf({"\n  ========== ORDERING CHECKER SUMMARY (PCIe 6.1 Table 2-42) ==========\n",
                   "  issued=%0d sent=%0d in_order=%0d violations=%0d never_sent=%0d"},
                  n_issued, n_sent, n_in_order, n_violations, waiting.size());
    if (n_rule_hit.size() == 0)
      s = {s, "\n  every TLP left the TL in issue order (no TLP passed an older TLP)"};
    foreach (n_rule_hit[rid])
      s = {s, $sformatf("\n    rule %-4s checked %0d time(s)", rid, n_rule_hit[rid])};
    `uvm_info("ORD_CHK", s, UVM_LOW)
    if (sent_early.size() != 0)
      `uvm_warning("ORD_CHK", $sformatf("%0d TLP(s) were seen leaving the TL but never seen issued by the driver", sent_early.size()))
  endfunction

endclass : PCIe_ordering_checker

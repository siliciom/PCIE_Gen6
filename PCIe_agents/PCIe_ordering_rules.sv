//=========================================================================================
// File         : PCIe_ordering_rules.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_ordering_rules.sv
//                Transaction Ordering Rules - PCIe Base Spec 6.1, Section 2.4.1,
//                Table 2-42 "Ordering Rules Summary" (spec pages 247 - 250).
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
//  WHAT IS THIS FILE ?  (read this first)
//-----------------------------------------------------------------------------------------
//  PCIe allows a TLP that was issued LATER (T2) to overtake ("pass") a TLP that was issued
//  EARLIER (T1) in some cases, and forbids it in others. Table 2-42 of the spec lists all
//  the cases. This file is that table written as code. It answers ONE question:
//
//        "T1 was issued first and is still waiting. T2 came after it.
//         Is T2 allowed to go out on the link before T1 ?"
//
//  The answer is one of three values (same words as the spec):
//
//    ORD_YES : T2 MUST be able to pass T1.   (If T1 is stuck, T2 must go, else deadlock.)
//    ORD_YN  : No rule. T2 MAY pass T1, or MAY wait. Both are legal.
//    ORD_NO  : T2 must NOT pass T1. T1 must go first. (Producer / consumer ordering.)
//
//  This class has no state and no ports. It only has static functions, so any component
//  (TX ordering queue, ordering checker, scoreboard, ...) can call it:
//
//        rule = PCIe_ordering_rules::check_pass(t2, t1, rule_id, why);
//
//-----------------------------------------------------------------------------------------
//  THE 4 TLP GROUPS USED BY THE TABLE  (spec text under Table 2-42)
//-----------------------------------------------------------------------------------------
//    Posted Request (P)   : Memory Write, Message (with or without data)
//    Read Request         : Memory Read (also MRdLk), I/O Read, Configuration Read
//    NPR with Data        : I/O Write, Configuration Write, AtomicOp, DMWr
//                           (DMWr = Deferrable Memory Write)
//    Completion (CPL)     : Cpl, CplD, CplLk, CplDLk
//    "Non-Posted Request" = Read Request OR NPR with Data
//
//-----------------------------------------------------------------------------------------
//  TABLE 2-42   Row = T2 (second / newer)   Column = T1 (first / older)
//-----------------------------------------------------------------------------------------
//
//    T2 \ T1          | Posted     | Read Req | NPR w Data | Completion
//    -----------------+------------+----------+------------+-----------------
//    Posted     (A)   | a) No      | Yes      | Yes        | a) Y/N
//                     | b) Y/N     |  (A3)    |  (A4)      | b) Yes   (A5)
//                     |   (A2)     |          |            |
//    Read Req   (B)   | a) No      | Y/N      | Y/N        | Y/N
//                     | b) Y/N(B2) |  (B3)    |  (B4)      |  (B5)
//    NPR w Data (C)   | a) No      | Y/N      | Y/N        | Y/N
//                     | b) Y/N(C2) |  (C3)    |  (C4)      |  (C5)
//    Completion (D)   | a) No      | Yes      | Yes        | a) Y/N
//                     | b) Y/N(D2) |  (D3)    |  (D4)      | b) No    (D5)
//
//  The "b)" line of a box applies only when its special condition is true
//  (RO / IDO bit set, bridge mode, same Transaction ID ...). See check_pass().
//
//-----------------------------------------------------------------------------------------
//  HEADER BITS USED  (Attr field, same mapping as print_attr_table_check() in RC TL model)
//-----------------------------------------------------------------------------------------
//    attr[2] = IDO  (ID-Based Ordering)   : "I am from a different requester, I am not
//                                            related to your traffic, let me pass."
//    attr[1] = RO   (Relaxed Ordering)    : "I do not need to wait for older writes."
//    attr[0] = NS   (No Snoop)            : does NOT change ordering (spec "Additional Rules")
//
//-----------------------------------------------------------------------------------------
//  LIMITS OF THIS ENVIRONMENT  (so a reader knows what is NOT modelled)
//-----------------------------------------------------------------------------------------
//    * PASID : PCIe_sequence_item has no PASID field yet. has_pasid() returns 0, so the
//      "same Requester ID but different PASID" part of A2b / B2b / C2b is never used.
//      When a PASID field is added, only has_pasid() / get_pasid() need to change.
//    * Requester Segment (Flit Mode) is not modelled -> only the 16 bit Requester ID is used.
//    * AtomicOp is not in pcie_tl_txn_type_e yet. When it is added, put it in the
//      ORD_NPR_DATA group inside get_ord_class().
//    * Different Traffic Class (TC) : the spec says the table applies only inside ONE TC.
//      Two TLPs with different TC have no ordering rule -> check_pass() returns ORD_YN.
//=========================================================================================

import typedef_enums :: *;

//-----------------------------------------------------------------------------------------
// ordering group of a TLP (the rows / columns of Table 2-42)
//-----------------------------------------------------------------------------------------
typedef enum bit [1:0] {
  ORD_POSTED   = 2'd0,   // Row A / Col 2 : MWr, Msg, MsgD
  ORD_READ     = 2'd1,   // Row B / Col 3 : MRd, MRdLk, IORd, CfgRd
  ORD_NPR_DATA = 2'd2,   // Row C / Col 4 : IOWr, CfgWr, DMWr, (AtomicOp)
  ORD_CPL      = 2'd3    // Row D / Col 5 : Cpl, CplD, CplLk, CplDLk
} pcie_ord_class_e;

//-----------------------------------------------------------------------------------------
// answer of the table for one (T2, T1) pair
//-----------------------------------------------------------------------------------------
typedef enum bit [1:0] {
  ORD_YES = 2'd0,        // T2 MUST be able to pass T1 (deadlock avoidance)
  ORD_YN  = 2'd1,        // no requirement : T2 may pass T1 or may wait
  ORD_NO  = 2'd2         // T2 must NOT pass T1
} pcie_ord_result_e;


class PCIe_ordering_rules extends uvm_object;

  `uvm_object_utils(PCIe_ordering_rules)

  //---------------------------------------------------------------------------------------
  // KNOB : rule A5b
  //   Set to 1 ONLY when this component is a PCI Express to PCI/PCI-X bridge working in
  //   conventional PCI mode, for traffic going in the PCIe -> PCI direction.
  //   Then "Posted passing Completion" changes from Y/N (A5a) to Yes (A5b).
  //   Our RC / EP models are not bridges, so it stays 0.
  //---------------------------------------------------------------------------------------
  static bit is_pcie_to_pci_bridge = 1'b0;

  function new(string name = "PCIe_ordering_rules");
    super.new(name);
  endfunction

  //=======================================================================================
  // SMALL HELPERS : read the bits we need from the sequence item
  //=======================================================================================

  // Relaxed Ordering bit = Attr[1]
  static function bit get_ro(PCIe_sequence_item t);
    return t.attr[1];
  endfunction

  // ID-Based Ordering bit = Attr[2]
  static function bit get_ido(PCIe_sequence_item t);
    return t.attr[2];
  endfunction

  // PASID is not modelled yet (see "LIMITS" above). Change these two functions when the
  // sequence item gets a PASID prefix / OHC field.
  static function bit has_pasid(PCIe_sequence_item t);
    return 1'b0;
  endfunction

  static function bit [19:0] get_pasid(PCIe_sequence_item t);
    return 20'h0;
  endfunction

  // Transaction ID = Requester ID + Tag. It is the same for a request and for every
  // completion that answers that request. Used by rule D5.
  static function bit same_transaction_id(PCIe_sequence_item a, PCIe_sequence_item b);
    return (a.requester_id == b.requester_id) && (a.tag == b.tag);
  endfunction

  //---------------------------------------------------------------------------------------
  // get_ord_class : which row / column of Table 2-42 does this TLP belong to ?
  //---------------------------------------------------------------------------------------
  static function pcie_ord_class_e get_ord_class(PCIe_sequence_item t);
    case (t.txn_type)
      // Memory : normal write is Posted, DMWr is NPR with Data, any read is a Read Request
      PCIe_TL_MEM : begin
        if (t.dir == PCIe_TL_WRITE)
          return t.mem_deferrable ? ORD_NPR_DATA : ORD_POSTED;
        else
          return ORD_READ;                       // MRd and MRdLk
      end
      // I/O and Config : read = Read Request, write = NPR with Data
      PCIe_TL_IO,
      PCIe_TL_CFG : return (t.dir == PCIe_TL_WRITE) ? ORD_NPR_DATA : ORD_READ;
      // Every Message (with or without data) is Posted
      PCIe_TL_MSG : return ORD_POSTED;
      // Every kind of completion
      PCIe_TL_CPL : return ORD_CPL;
      default     : return ORD_POSTED;           // unknown type -> treat as Posted (strictest column)
    endcase
  endfunction

  static function string class_name(pcie_ord_class_e c);
    case (c)
      ORD_POSTED   : return "POSTED";
      ORD_READ     : return "READ_REQ";
      ORD_NPR_DATA : return "NPR_WITH_DATA";
      ORD_CPL      : return "COMPLETION";
    endcase
    return "UNKNOWN";
  endfunction

  static function string result_name(pcie_ord_result_e r);
    case (r)
      ORD_YES : return "YES(must be able to pass)";
      ORD_YN  : return "Y/N(may pass)";
      ORD_NO  : return "NO(must not pass)";
    endcase
    return "UNKNOWN";
  endfunction

  //---------------------------------------------------------------------------------------
  // ido_ids_allow_pass : the ID part of the IDO rules A2b / B2b / C2b
  //   "permitted to pass if the two Requester IDs are different. Additionally, permitted
  //    with the same Requester ID if both Requests contain a PASID and the two PASID
  //    values are different."
  //---------------------------------------------------------------------------------------
  static function bit ido_ids_allow_pass(PCIe_sequence_item t2, PCIe_sequence_item t1);
    if (t2.requester_id != t1.requester_id)
      return 1'b1;
    if (has_pasid(t2) && has_pasid(t1) && (get_pasid(t2) != get_pasid(t1)))
      return 1'b1;
    return 1'b0;
  endfunction

  //=======================================================================================
  // check_pass : THE TABLE
  //
  //   t2                  : the NEWER TLP (row)    - the one that wants to go first
  //   t1                  : the OLDER TLP (column) - the one that is waiting
  //   t2_is_io_cfg_wr_cpl : 1 only if the caller KNOWS t2 is the completion of an I/O Write
  //                         or a Configuration Write (rule D2b). The completion header alone
  //                         does not say this, so the caller must track the request.
  //                         Spec footnote 40: if you are not sure, do not use this rule -> 0.
  //   rule_id (output)    : spec rule name, e.g. "A2a", "D3", "TC"
  //   why     (output)    : one line reason in plain English, for log messages
  //
  //   return              : ORD_YES / ORD_YN / ORD_NO
  //=======================================================================================
  static function pcie_ord_result_e check_pass(input  PCIe_sequence_item t2,
                                               input  PCIe_sequence_item t1,
                                               output string             rule_id,
                                               output string             why,
                                               input  bit                t2_is_io_cfg_wr_cpl = 1'b0);

    pcie_ord_class_e row, col;
    row = get_ord_class(t2);
    col = get_ord_class(t1);

    //-------------------------------------------------------------------------------------
    // Section 2.4.1 : the table is applied only inside one Traffic Class.
    //-------------------------------------------------------------------------------------
    if (t2.tc != t1.tc) begin
      rule_id = "TC";
      why     = $sformatf("different Traffic Class (T2 TC%0d, T1 TC%0d) : no ordering rule", t2.tc, t1.tc);
      return ORD_YN;
    end

    case (col)

      //===================================================================================
      // COLUMN 2 : T1 is a POSTED request.  Default answer "No" for every row,
      //            the "b)" exceptions use RO / IDO.
      //===================================================================================
      ORD_POSTED : begin
        case (row)

          // ---- A2 : Posted passing Posted --------------------------------------------
          ORD_POSTED : begin
            if (get_ro(t2)) begin
              rule_id = "A2b"; why = "Posted with RO=1 may pass an older Posted";
              return ORD_YN;
            end
            if (get_ido(t2) && ido_ids_allow_pass(t2, t1)) begin
              rule_id = "A2b"; why = "Posted with IDO=1 and different Requester ID (or PASID) may pass an older Posted";
              return ORD_YN;
            end
            rule_id = "A2a"; why = "Posted must not pass an older Posted (keep write order)";
            return ORD_NO;
          end

          // ---- B2 : Read Request passing Posted  (NOTE : RO does NOT help a Read) -----
          ORD_READ : begin
            if (get_ido(t2) && ido_ids_allow_pass(t2, t1)) begin
              rule_id = "B2b"; why = "Read with IDO=1 and different Requester ID (or PASID) may pass an older Posted";
              return ORD_YN;
            end
            rule_id = "B2a"; why = "Read must not pass an older Posted (read must see the written data); RO does not apply to Reads";
            return ORD_NO;
          end

          // ---- C2 : NPR with Data passing Posted ---------------------------------------
          ORD_NPR_DATA : begin
            if (get_ro(t2)) begin
              rule_id = "C2b"; why = "NPR with Data and RO=1 may pass an older Posted";
              return ORD_YN;
            end
            if (get_ido(t2) && ido_ids_allow_pass(t2, t1)) begin
              rule_id = "C2b"; why = "NPR with Data and IDO=1 and different Requester ID (or PASID) may pass an older Posted";
              return ORD_YN;
            end
            rule_id = "C2a"; why = "NPR with Data must not pass an older Posted";
            return ORD_NO;
          end

          // ---- D2 : Completion passing Posted ------------------------------------------
          ORD_CPL : begin
            if (t2_is_io_cfg_wr_cpl) begin
              rule_id = "D2b"; why = "I/O Write or Config Write Completion may pass an older Posted";
              return ORD_YN;
            end
            if (get_ro(t2)) begin
              rule_id = "D2b"; why = "Completion with RO=1 may pass an older Posted";
              return ORD_YN;
            end
            // IDO for a completion compares the COMPLETER ID of the completion with the
            // REQUESTER ID of the posted request.
            if (get_ido(t2) && (t2.completer_id != t1.requester_id)) begin
              rule_id = "D2b"; why = "Completion with IDO=1 and Completer ID != Posted Requester ID may pass an older Posted";
              return ORD_YN;
            end
            rule_id = "D2a"; why = "Completion must not pass an older Posted (data written before must be visible first)";
            return ORD_NO;
          end
        endcase
      end

      //===================================================================================
      // COLUMN 3 and 4 : T1 is a NON-POSTED request (Read Request or NPR with Data).
      //   Posted and Completion MUST be able to go around it (deadlock rule).
      //   Non-Posted vs Non-Posted has no rule.
      //   RO / IDO are not used here : these boxes are already open.
      //===================================================================================
      ORD_READ,
      ORD_NPR_DATA : begin
        case (row)
          ORD_POSTED : begin
            rule_id = (col == ORD_READ) ? "A3" : "A4";
            why     = "Posted must be able to pass an older Non-Posted (deadlock avoidance)";
            return ORD_YES;
          end
          ORD_CPL : begin
            rule_id = (col == ORD_READ) ? "D3" : "D4";
            why     = "Completion must be able to pass an older Non-Posted (deadlock avoidance)";
            return ORD_YES;
          end
          default : begin   // ORD_READ or ORD_NPR_DATA
            if (row == ORD_READ) rule_id = (col == ORD_READ) ? "B3" : "B4";
            else                 rule_id = (col == ORD_READ) ? "C3" : "C4";
            why = "Non-Posted may pass an older Non-Posted (no requirement)";
            return ORD_YN;
          end
        endcase
      end

      //===================================================================================
      // COLUMN 5 : T1 is a COMPLETION.
      //===================================================================================
      ORD_CPL : begin
        case (row)
          // ---- A5 : Posted passing Completion -------------------------------------------
          ORD_POSTED : begin
            if (is_pcie_to_pci_bridge) begin
              rule_id = "A5b"; why = "PCIe->PCI bridge : Posted must be able to pass an older Completion";
              return ORD_YES;
            end
            rule_id = "A5a"; why = "Posted may pass an older Completion (no requirement)";
            return ORD_YN;
          end

          // ---- B5 / C5 : Non-Posted passing Completion ----------------------------------
          ORD_READ : begin
            rule_id = "B5"; why = "Read may pass an older Completion (no requirement)";
            return ORD_YN;
          end
          ORD_NPR_DATA : begin
            rule_id = "C5"; why = "NPR with Data may pass an older Completion (no requirement)";
            return ORD_YN;
          end

          // ---- D5 : Completion passing Completion ---------------------------------------
          ORD_CPL : begin
            if (same_transaction_id(t2, t1)) begin
              rule_id = "D5b";
              why     = "Completions of the SAME request (same Requester ID + Tag) must not pass each other (keep ascending address order)";
              return ORD_NO;
            end
            rule_id = "D5a"; why = "Completions of different requests may pass each other";
            return ORD_YN;
          end
        endcase
      end

    endcase

    // not reachable - every (row, col) pair is covered above
    rule_id = "??";
    why     = "unknown combination";
    return ORD_NO;
  endfunction

  //---------------------------------------------------------------------------------------
  // describe_pair : one line for logs, e.g.
  //   "T2=POSTED(tag=0x3) vs T1=READ_REQ(tag=0x1) -> A3 YES(must be able to pass) : ..."
  //---------------------------------------------------------------------------------------
  static function string describe_pair(PCIe_sequence_item t2, PCIe_sequence_item t1,
                                       bit t2_is_io_cfg_wr_cpl = 1'b0);
    string            rid, why;
    pcie_ord_result_e r;
    r = check_pass(t2, t1, rid, why, t2_is_io_cfg_wr_cpl);
    return $sformatf("T2=%s(tag=0x%0h attr=%03b) vs T1=%s(tag=0x%0h) -> %s %s : %s",
                     class_name(get_ord_class(t2)), t2.tag, t2.attr,
                     class_name(get_ord_class(t1)), t1.tag,
                     rid, result_name(r), why);
  endfunction

endclass : PCIe_ordering_rules

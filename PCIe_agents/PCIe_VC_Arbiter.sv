//=========================================================================================
// File         : PCIe_VC_Arbiter.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_VC_Arbiter.sv
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

class PCIe_VC_Arbiter extends uvm_component;

  `uvm_component_utils(PCIe_VC_Arbiter)

  PCIe_sequence_item vc_q [`PCIe_NUM_VC_MAX][$];   // one TX queue per VC
  PCIe_RC_TL_model   rc_tl_model;                  // FC gate per VC (set by PCIe_environment)

  // Starvation visibility : consecutive rounds a non-empty VC was passed over
  int unsigned starve_count     [`PCIe_NUM_VC_MAX];
  int unsigned starve_count_max [`PCIe_NUM_VC_MAX];

  // statistics
  int unsigned n_round;
  int unsigned n_push        [`PCIe_NUM_VC_MAX];
  int unsigned n_won         [`PCIe_NUM_VC_MAX];
  int unsigned n_skip_credit [`PCIe_NUM_VC_MAX];   // rounds the head TLP had no FC credits
  string       won_order;                          // VC of every winner, in order

  function new(string name = "PCIe_VC_Arbiter", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    n_round   = 0;
    won_order = "";
    for (int v = 0; v < `PCIe_NUM_VC_MAX; v++) begin
      starve_count[v] = 0; starve_count_max[v] = 0;
      n_push[v] = 0; n_won[v] = 0; n_skip_credit[v] = 0;
    end
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    if (rc_tl_model == null)
      `uvm_fatal("VC_ARB", "rc_tl_model handle not set (PCIe_environment::connect_phase)")
  endfunction

  //--------------------------------------------------------------------------
  // push : called by the RC controller driver for every request
  //--------------------------------------------------------------------------
  function void push(PCIe_sequence_item item);
    vc_id_e v;
    v = item.map_tc_to_vc();
    if (!PCIe_sequence_item::tc_enabled(item.tc)) begin
      `uvm_error("VC_ARB", $sformatf("TC%0d_NOT_MAPPED_TO_ENABLED_VC : %s queued on VC0 (Sec 2.5.3 : Malformed at the receiver) | %s",
                 item.tc, item.convert2string(), PCIe_sequence_item::tc_vc_map_str()))
      v = VC0;
    end
    for (int w = 0; w < `PCIe_NUM_VC_MAX; w++)
      for (int i = 0; i < vc_q[w].size(); i++)
        if (vc_q[w][i] == item)
          `uvm_error("VC_ARB", "SAME_ITEM_OBJECT_QUEUED_TWICE : a sequence used with the VC arbiter must create a new item for every request")
    vc_q[v].push_back(item);
    n_push[v]++;
    `uvm_info("VC_ARB", $sformatf("Enqueued TC%0d -> %s : %s | queue depth%s",
              item.tc, v.name(), item.convert2string(), depths_str()), UVM_LOW)
  endfunction

  function bit any_pending();
    foreach (vc_q[v]) if (vc_q[v].size() != 0) return 1'b1;
    return 1'b0;
  endfunction

  function string depths_str();
    string s;
    s = "";
    for (int v = `PCIe_NUM_VC_MAX - 1; v >= 0; v--)
      if (PCIe_sequence_item::vc_enabled(v)) s = {s, $sformatf(" VC%0d=%0d", v, vc_q[v].size())};
    return s;
  endfunction

  //--------------------------------------------------------------------------
  // Strict-priority selection, non-blocking.
  //   returns 1 + the winning item and its VC, or 0 when no VC can send now.
  //--------------------------------------------------------------------------
  function bit try_get_next(output PCIe_sequence_item item, output vc_id_e vc_won);
    string skipped;
    skipped = "";
    item    = null;
    vc_won  = VC0;
    for (int v = `PCIe_NUM_VC_MAX - 1; v >= 0; v--) begin
      if (vc_q[v].size() == 0) continue;
      if (rc_tl_model.fc_tlp_can_send_now(vc_q[v][0])) begin
        n_round++;
        `uvm_info("VC_ARB", $sformatf("ROUND %0d : queues%s -> Arbitration winner: VC%0d (strict priority, VC7 highest / VC0 lowest)%s",
                  n_round, depths_str(), v, (skipped == "") ? "" : {" | skipped :", skipped}), UVM_LOW)
        item   = vc_q[v].pop_front();
        vc_won = vc_id_e'(v);
        n_won[v]++;
        won_order = {won_order, (won_order == "") ? "" : " ", $sformatf("VC%0d", v)};
        // reset starvation tracking for the VC that won, bump it for every
        // non-empty VC below it that lost out
        starve_count[v] = 0;
        for (int lower = v - 1; lower >= 0; lower--) begin
          if (vc_q[lower].size() == 0) continue;
          starve_count[lower]++;
          if (starve_count[lower] > starve_count_max[lower]) starve_count_max[lower] = starve_count[lower];
          if (starve_count[lower] == `PCIe_VC_ARB_STARVE_WARN)
            `uvm_warning("VC_ARB", $sformatf("VC%0d_STARVING : lost %0d strict-priority rounds in a row (Sec 6.3.3.2.1)",
                         lower, starve_count[lower]))
        end
        return 1'b1;
      end
      else begin
        skipped = {skipped, $sformatf(" VC%0d(head-of-line blocked on credit)", v)};
        `uvm_info("VC_ARB", $sformatf("VC%0d head-of-line blocked on credit, checking lower VCs", v), UVM_HIGH)
      end
    end
    for (int v = 0; v < `PCIe_NUM_VC_MAX; v++) if (vc_q[v].size() != 0) n_skip_credit[v]++;
    return 1'b0;
  endfunction

  // Blocking version ( VC_Arbiter::get_next) : waits until some VC has
  // both an item AND sufficient credit for it.
  task get_next(output PCIe_sequence_item item, output vc_id_e vc_won);
    while (!try_get_next(item, vc_won)) #1ns;
  endtask

  // Optional : call periodically from a checker for a testbench-side
  // starvation check ( is_starving()).
  function bit is_starving(vc_id_e vc, int threshold = 1000);
    return (starve_count[vc] > threshold);
  endfunction

  function void report_phase(uvm_phase phase);
    string s;
    super.report_phase(phase);
    if (PCIe_sequence_item::num_vc < 2 && n_round == 0) return;
    s = $sformatf("\n  ========== VC ARBITER SUMMARY (Strict Priority, VC7 highest / VC0 lowest) ==========\n  %s\n  rounds=%0d",
                  PCIe_sequence_item::tc_vc_map_str(), n_round);
    for (int v = `PCIe_NUM_VC_MAX - 1; v >= 0; v--)
      if (PCIe_sequence_item::vc_enabled(v))
        s = {s, $sformatf("\n  VC%0d : queued=%0d sent=%0d left=%0d  max rounds lost in a row=%0d  rounds head blocked on credit=%0d",
                          v, n_push[v], n_won[v], vc_q[v].size(), starve_count_max[v], n_skip_credit[v])};
    s = {s, "\n  send order : ", won_order};
    `uvm_info("VC_ARB", s, UVM_LOW)
    foreach (vc_q[v])
      if (vc_q[v].size() != 0)
        `uvm_error("VC_ARB", $sformatf("VC%0d : %0d TLP(s) never sent", v, vc_q[v].size()))
  endfunction

endclass : PCIe_VC_Arbiter

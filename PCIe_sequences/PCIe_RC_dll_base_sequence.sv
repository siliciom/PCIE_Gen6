//=========================================================================================
// File         : PCIe_RC_dll_base_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_dll_base_sequence.sv
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

// Common traffic for all DLL tests : num_txn 3DW Flit MemWr, one flit each.
//   1. trigger "dll_traffic_start"  -> the test saves its counters
//   2. wait    "dll_traffic_go"     -> the test has armed its error injection
//   3. send num_txn MemWr
//   4. trigger "dll_traffic_done"

class PCIe_RC_dll_base_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_dll_base_sequence)

  int unsigned num_txn = 6;     // number of MemWr (one flit each)

  function new(string name = "PCIe_RC_dll_base_sequence");
    super.new(name);
  endfunction

  task body();
    uvm_event start_ev = uvm_event_pool::get_global("dll_traffic_start");
    uvm_event go_ev    = uvm_event_pool::get_global("dll_traffic_go");
    uvm_event done_ev  = uvm_event_pool::get_global("dll_traffic_done");

    `uvm_info(get_type_name(), $sformatf("ENTERED_SEQUENCE_BODY : %0d MemWr", num_txn), UVM_LOW)
    done_ev.reset();
    start_ev.trigger();
    go_ev.wait_on();

    for (int i = 0; i < num_txn; i++) begin
      pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
      start_item(pcie_seq_item);
      if (!pcie_seq_item.randomize() with {
           // LTSSM information
           electrical_idle_test == 1'b0;
           no_receiver_test     == 1'b0;
           tx_elec_idle         == 1'b1;
           pkt_mode             == FLIT;

           // 3DW Memory Write, one flit
           txn_type       == PCIe_TL_MEM;
           dir            == PCIe_TL_WRITE;
           mem_locked     == 1'b0;
           mem_deferrable == 1'b0;
           address        == 32'h0000_2000;
           length inside {[2:8]};
           first_dw_be    == 4'hF;
           last_dw_be     == 4'hF;
           requester_id   == 16'h0100;
           ts             == 3'b000;
           at             == 2'b00;

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
        `uvm_error(get_type_name(), "randomize failed for mwr")

      `uvm_info(get_type_name(), $sformatf("Sending MemWr %0d/%0d len=%0d", i+1, num_txn, pcie_seq_item.length), UVM_LOW)
      finish_item(pcie_seq_item);
    end

    done_ev.trigger();
    `uvm_info(get_type_name(), "EXIT_FROM_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

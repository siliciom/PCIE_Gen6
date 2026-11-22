//=========================================================================================
// File         : PCIe_RC_dll_retry_request_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_dll_retry_request_sequence.sv
// Author       : Rani
// Date         : 2026-11-21
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

// Sequence for PCIe_gen6_dll_retry_request_test
//
//   4 MemWr A B C D. The test corrupts 2 flits in a row -> retry request (STANDARD NAK).
//   Traffic : 4 x 3DW Flit MemWr (posted, one flit each).
//   The test can change the count : run_dll_seq(seq, <count>).
//   Warm-up : the test uses this same sequence with num_txn = 2 after enumeration.
//   At the end it triggers the global event "dll_seq_done".

class PCIe_RC_dll_retry_request_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_dll_retry_request_sequence)

  int unsigned num_txn = 4;               // number of MemWr (A B C D : B and the next flit are corrupted)
  bit [31:0]   address = 32'h0000_2000;  // MemWr address

  function new(string name = "PCIe_RC_dll_retry_request_sequence");
    super.new(name);
  endfunction

  task body();
    uvm_event done_ev = uvm_event_pool::get_global("dll_seq_done");

    `uvm_info("DLL_SEQ", $sformatf("%s START : %0d MemWr", get_type_name(), num_txn), UVM_LOW)

    repeat (num_txn) begin
      pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
      start_item(pcie_seq_item);
      if (!pcie_seq_item.randomize() with {
           // LTSSM information
           electrical_idle_test == 1'b0;
           no_receiver_test     == 1'b0;
           tx_elec_idle         == 1'b1;
           pkt_mode             == FLIT;

           txn_type == PCIe_TL_MEM;
           dir      == PCIe_TL_WRITE;

           mem_locked     == 1'b0;
           mem_deferrable == 1'b0;

           address == local::address;

           length inside {[2:8]};      // one flit per MemWr

           first_dw_be == 4'hF;
           last_dw_be  == 4'hF;

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
        `uvm_error("DLL_SEQ", "randomize failed for MemWr")

      `uvm_info("DLL_SEQ", $sformatf("Sending 3DW Flit MemWr len=%0d", pcie_seq_item.length), UVM_LOW)
      finish_item(pcie_seq_item);
    end

    `uvm_info("DLL_SEQ", $sformatf("%s DONE : %0d MemWr", get_type_name(), num_txn), UVM_LOW)
    done_ev.trigger();   // the test waits for this event (warm-up done)
  endtask

endclass

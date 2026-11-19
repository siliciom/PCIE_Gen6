//=========================================================================================
// File         : PCIe_RC_dll_ack_nak_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences/PCIe_RC_dll_ack_nak_sequence.sv
// Author       : Rani
// Date         : 2026-11-18
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

// num_txn 3DW Flit MemWr (one flit each) for PCIe_gen6_dll_ack_nak_test

class PCIe_RC_dll_ack_nak_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_dll_ack_nak_sequence)

  int unsigned num_txn = 8;     // number of MemWr

  function new(string name = "PCIe_RC_dll_ack_nak_sequence");
    super.new(name);
  endfunction

  task body();
    uvm_event start_ev = uvm_event_pool::get_global("dll_traffic_start");
    uvm_event done_ev  = uvm_event_pool::get_global("dll_traffic_done");

    `uvm_info("DLL_ACK_NAK_SEQ", $sformatf("ENTERED_INTO_DLL_ACK_NAK_SEQUENCE_BODY : %0d MemWr", num_txn), UVM_LOW)
    start_ev.trigger();

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

           address == 32'h0000_2000;

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
        `uvm_error("DLL_ACK_NAK_SEQ", "randomize failed for mwr")

      `uvm_info("DLL_ACK_NAK_SEQ", $sformatf("Sending 3DW Flit MemWr len=%0d", pcie_seq_item.length), UVM_LOW)
      finish_item(pcie_seq_item);
    end

    done_ev.trigger();
    `uvm_info("DLL_ACK_NAK_SEQ", "EXIT_FROM_DLL_ACK_NAK_SEQUENCE_BODY", UVM_LOW)
  endtask

endclass

`ifndef PCIE_RC_3DW_FLIT_IOWR_SEQUENCE_SV
`define PCIE_RC_3DW_FLIT_IOWR_SEQUENCE_SV

class PCIe_RC_3DW_Flit_IOWr_sequence extends PCIe_RC_controller_base_sequence;
  `uvm_object_utils(PCIe_RC_3DW_Flit_IOWr_sequence)

  function new(string name="PCIe_RC_3DW_Flit_IOWr_sequence");
    super.new(name);
  endfunction

  virtual task body();
    pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");

    start_item(pcie_seq_item);
    assert(pcie_seq_item.randomize() with {
      // LTSSM information
      electrical_idle_test == 1'b0;
      no_receiver_test     == 1'b0;
      tx_elec_idle         == 1'b1;
      pkt_mode             == FLIT;

      txn_type == PCIe_TL_IO;
      dir      == PCIe_TL_WRITE;
      length   == `PCIe_TL_LEN_MIN;
      first_dw_be == 4'hF;
      last_dw_be  == 4'h0;

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
    }) else `uvm_fatal("SEQ_RAND", "Failed to randomize I/O request")
    finish_item(pcie_seq_item);
  endtask
endclass

`endif

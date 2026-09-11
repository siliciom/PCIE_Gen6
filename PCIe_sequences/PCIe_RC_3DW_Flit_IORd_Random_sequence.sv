`ifndef PCIE_RC_3DW_FLIT_IORD_RANDOM_SEQUENCE_SV
`define PCIE_RC_3DW_FLIT_IORD_RANDOM_SEQUENCE_SV

class PCIe_RC_3DW_Flit_IORd_Random_sequence extends uvm_sequence #(PCIe_sequence_item);
  `uvm_object_utils(PCIe_RC_3DW_Flit_IORd_Random_sequence)

  function new(string name="PCIe_RC_3DW_Flit_IORd_Random_sequence");
    super.new(name);
  endfunction

  virtual task body();
    PCIe_sequence_item req;
    req = PCIe_sequence_item::type_id::create("req");

    start_item(req);
    assert(req.randomize() with {
      txn_type == PCIe_TL_IO;
      dir      == PCIe_TL_READ;
      length   == `PCIe_TL_LEN_MIN;
      first_dw_be == 4'hF;
      last_dw_be  == 4'h0;
    }) else `uvm_fatal("SEQ_RAND", "Failed to randomize I/O request")
    finish_item(req);
  endtask
endclass

`endif

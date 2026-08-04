class PCIE_EP_controller_sequencer extends uvm_sequencer #(PCIE_sequence_item);
  
  `uvm_component_utils(PCIE_EP_controller_sequencer)
  
  function new(string name="PCIE_EP_controller_sequencer",uvm_component parent);
    super.new(name,parent);
  endfunction
  
endclass






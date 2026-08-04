class PCIE_subscriber extends uvm_subscriber#(PCIE_sequence_item);
  `uvm_component_utils(PCIE_subscriber)

     PCIE_sequence_item     pcie_seq_item;

  function new(string name="PCIE_subscriber",uvm_component parent);
    super.new(name,parent); 
  endfunction


  function void build_phase(uvm_phase phase);
   `uvm_info("PCIE_SUBSCRIBER","ENTERED_INTO_SUB_BUILD_PHASE",UVM_LOW)
    super.build_phase(phase);
   `uvm_info("PCIE_SUBSCRIBER","EXIT_FROM_SUB_BUILD_PHASE",UVM_LOW)
  endfunction
 
 
  virtual function void write(PCIE_sequence_item t);
      pcie_seq_item = t;
 endfunction
   
endclass


    

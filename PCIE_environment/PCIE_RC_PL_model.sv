class PCIE_RC_PL_model extends uvm_component;
   
  `uvm_component_utils(PCIE_RC_PL_model)

   function new(string name="PCIE_RC_PL_model",uvm_component parent);
      super.new(name,parent);
   endfunction


   function void build_phase(uvm_phase phase);
      `uvm_info("PCIE_PL_MODEL","ENTERED_INTO_PL_MODEL_BUILD_PHASE",UVM_LOW)
     super.build_phase(phase);
      `uvm_info("PCIE_PL_MODEL","EXIT_FROM_PL_MODEL_BUILD_PHASE",UVM_LOW)
   endfunction

endclass









class PCIE_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(PCIE_scoreboard)

  function new(string name="PCIE_scoreboard",uvm_component parent);
    super.new(name,parent);
  endfunction

  function void build_phase(uvm_phase phase);
   `uvm_info("PCIE_SCOREBOARD","ENTERED_INTO_SB_BUILD_PHASE",UVM_LOW)
    super.build_phase(phase);
   `uvm_info("PCIE_SCOREBOARD","EXIT_FROM_SB_BUILD_PHASE",UVM_LOW)
  endfunction


endclass




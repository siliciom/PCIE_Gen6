`include "uvm_macros.svh"

module PCIE_top;

`include "PCIE_PHY_interface.sv"
`include "PCIE_PIPE_interface.sv"

 import PCIE_pkg::*;
 import uvm_pkg::*;

 //interfaces
   PCIE_RC_interface    rc_pipe_intf();
   PCIE_EP_interface    ep_pipe_intf();
   PCIE_PHY_interface   pcie_phy_intf();
  
  bit pclk;
  always #0.5 pclk = ~pclk;


  initial begin
    uvm_config_db#(virtual interface PCIE_RC_interface)::set(null,"*","PCIE_RC_INTERFACE", rc_pipe_intf);
    uvm_config_db#(virtual interface PCIE_EP_interface)::set(null,"*","PCIE_EP_INTERFACE", ep_pipe_intf);
    uvm_config_db#(virtual interface PCIE_PHY_interface)::set(null,"*","PCIE_PHY_INTERFACE",pcie_phy_intf);
  end

  initial begin
    run_test();
  end
    
endmodule

`include "uvm_macros.svh"

module PCIE_top;

//`include "PCIE_PHY_interface.sv"
//`include "PCIE_PIPE_interface.sv"

 import PCIE_pkg::*;
 import uvm_pkg::*;

   bit pclk;
   always #0.5 pclk = ~pclk;

 //interfaces
   PCIE_RC_interface    rc_pipe_intf(pclk);
   PCIE_EP_interface    ep_pipe_intf(pclk);
   PCIE_PHY_interface   pcie_phy_intf();
  

  initial begin
    uvm_config_db#(virtual  PCIE_RC_interface)::set(null,"*","PCIE_RC_INTERFACE", rc_pipe_intf);
    uvm_config_db#(virtual  PCIE_EP_interface)::set(null,"*","PCIE_EP_INTERFACE", ep_pipe_intf);
    uvm_config_db#(virtual  PCIE_PHY_interface)::set(null,"*","PCIE_PHY_INTERFACE",pcie_phy_intf);
  end

  initial begin
    run_test();
  end
    
endmodule

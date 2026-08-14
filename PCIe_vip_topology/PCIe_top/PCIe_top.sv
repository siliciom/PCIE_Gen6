//=========================================================================================
// File         : PCIe_top.sv
// Project      : PCIE_Gen6
// Description  : PCIe_top\PCIe_top.sv
// Author       : 
// Date         : 2026-08-14
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

`include "uvm_macros.svh"

module PCIe_top;

//`include "PCIe_PHY_interface.sv"
//`include "PCIe_PIPE_interface.sv"

 import PCIe_pkg::*;
 import uvm_pkg::*;

   bit pclk;
   always #0.5 pclk = ~pclk;

 //interfaces
   PCIe_RC_interface    rc_pipe_intf(pclk);
   PCIe_EP_interface    ep_pipe_intf(pclk);
   PCIe_PHY_interface   pcie_phy_intf();
  

  initial begin
    uvm_config_db#(virtual  PCIe_RC_interface)::set(null,"*","PCIe_RC_INTERFACE", rc_pipe_intf);
    uvm_config_db#(virtual  PCIe_EP_interface)::set(null,"*","PCIe_EP_INTERFACE", ep_pipe_intf);
    uvm_config_db#(virtual  PCIe_PHY_interface)::set(null,"*","PCIe_PHY_INTERFACE",pcie_phy_intf);
  end

  initial begin
    run_test();
  end
    
endmodule

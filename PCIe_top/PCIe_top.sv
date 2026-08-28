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
`timescale 1ns/1ps

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
   PCIe_RC_PHY_interface   pcie_rc_phy_intf();
   PCIe_EP_PHY_interface   pcie_ep_phy_intf();
    // RC TX--->EP RX
    assign pcie_ep_phy_intf.rx_plus  = pcie_rc_phy_intf.tx_plus;
    assign pcie_ep_phy_intf.rx_minus = pcie_rc_phy_intf.tx_minus;
    // EP TX--->RC RX
    assign pcie_rc_phy_intf.rx_plus  = pcie_ep_phy_intf.tx_plus;
    assign pcie_rc_phy_intf.rx_minus = pcie_ep_phy_intf.tx_minus;
  

  initial begin
    uvm_config_db#(virtual  PCIe_RC_interface)::set(null,"*","PCIe_RC_INTERFACE", rc_pipe_intf);
    uvm_config_db#(virtual  PCIe_EP_interface)::set(null,"*","PCIe_EP_INTERFACE", ep_pipe_intf);
    uvm_config_db#(virtual  PCIe_RC_PHY_interface)::set(null,"*","PCIe_RC_PHY_INTERFACE",pcie_rc_phy_intf);
    uvm_config_db#(virtual  PCIe_EP_PHY_interface)::set(null,"*","PCIe_EP_PHY_INTERFACE",pcie_ep_phy_intf);
  end

  initial begin
    run_test();
  end
    
endmodule

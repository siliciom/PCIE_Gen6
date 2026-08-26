//=========================================================================================
// File         : PCIe_PHY_interface.sv
// Project      : PCIE_Gen6
// Description  : PCIe_top\PCIe_PHY_interface.sv
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

`timescale 1ns/1ps

interface PCIe_RC_PHY_interface();

    // TX Signals 
    logic tx_plus;
    logic tx_minus;
    // RX Signals
    logic rx_plus;
    logic rx_minus;

    // Driver Clocking Block
   /* clocking cb_phy_drv@(posedge clk);
        default input #1step output #1step;
        output tx_plus;
        output tx_minus;
        output rx_plus;
        output rx_minus;
    endclocking

    // Monitor Clocking Block
    clocking cb_phy_mon@(negedge clk);
        default input #1step;
        input tx_plus;
        input tx_minus;
        input rx_plus;
        input rx_minus;
    endclocking

    // Driver Modport
    modport mp_phy_driver(clocking cb_phy_drv);
    // Monitor Modport
    modport mp_phy_monitor(clocking cb_phy_mon);*/

endinterface

interface PCIe_EP_PHY_interface();
   
    // TX Signals 
    logic tx_plus;
    logic tx_minus;
    // RX Signals
    logic rx_plus;
    logic rx_minus;

    // Driver Clocking Block
   /* clocking cb_phy_drv@(posedge clk);
        default input #1step output #1step;
        output tx_plus;
        output tx_minus;
        output rx_plus;
        output rx_minus;
    endclocking
    // Monitor Clocking Block
    clocking cb_phy_mon@(negedge clk);
        default input #1step;
        input tx_plus;
        input tx_minus;
        input rx_plus;
        input rx_minus;
    endclocking

    // Driver Modport
    modport mp_phy_driver(clocking cb_phy_drv);
    // Monitor Modport
    modport mp_phy_monitor(clocking cb_phy_mon);*/

endinterface


interface PCIE_PHY_interface();

    //----------------------------------------
    // TX Signals 
    //----------------------------------------
    logic tx_plus;
    logic tx_minus;
    //----------------------------------------
    // RX Signals
    //----------------------------------------
    logic rx_plus;
    logic rx_minus;
    //----------------------------------------
    // Driver Clocking Block
    //----------------------------------------
   /* clocking cb_phy_drv@(posedge clk);
        default input #1step output #1step;
        output tx_plus;
        output tx_minus;
        output rx_plus;
        output rx_minus;
    endclocking

    //----------------------------------------
    // Monitor Clocking Block
    //----------------------------------------
    clocking cb_phy_mon@(negedge clk);
        default input #1step;
        input tx_plus;
        input tx_minus;
        input rx_plus;
        input rx_minus;
    endclocking

    //----------------------------------------
    // Driver Modport
    //----------------------------------------
    modport mp_phy_driver(clocking cb_phy_drv);
    //----------------------------------------
    // Monitor Modport
    //----------------------------------------
    modport mp_phy_monitor(clocking cb_phy_mon);*/

endinterface

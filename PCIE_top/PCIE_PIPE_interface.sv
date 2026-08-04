interface PCIE_RC_interface();

   //----------------------------------------
   // Clock & Reset
   //----------------------------------------
   logic               pclk;
   logic               rst_n;
   //----------------------------------------
   // MAC -> PHY (Transmit)
   //----------------------------------------
   logic [31:0] tx_data;
   logic [31:0] tx_datak;
   logic        tx_elec_idle;
   logic        tx_detect_rx;
   logic [1:0]  powerdown;
   logic [2:0]  rate;
   //----------------------------------------
   // PHY -> MAC (Receive)
   //----------------------------------------
   logic [31:0] rx_data;
   logic [31:0] rx_datak;
   logic        rx_valid;
   logic        phy_status;
   logic        rx_elec_idle;
   logic [2:0]  rx_status;
   //----------------------------------------
   // Driver Clocking Block
   //----------------------------------------
   clocking cb_rc_drv @(posedge pclk);
      default input #1step output #1step;
      output tx_data;
      output tx_datak;
      output tx_elec_idle;
      output tx_detect_rx;
      output powerdown;
      output rate;

      input  rx_data;
      input  rx_datak;
      input  rx_valid;
      input  phy_status;
      input  rx_elec_idle;
      input  rx_status;
   endclocking
   //----------------------------------------
   // Monitor Clocking Block
   //----------------------------------------
   clocking cb_rc_mon @(negedge pclk);
      default input #1step;
      input tx_data;
      input tx_datak;
      input tx_elec_idle;
      input tx_detect_rx;
      input powerdown;
      input rate;
      input rx_data;
      input rx_datak;
      input rx_valid;
      input phy_status;
      input rx_elec_idle;
      input rx_status;
   endclocking

   //----------------------------------------
   // Driver Modport
   //----------------------------------------
   modport mp_rc_driver (clocking cb_rc_drv);
   //----------------------------------------
   // Monitor Modport
   //----------------------------------------
   modport mp_rc_monitor (clocking cb_rc_mon);

endinterface

interface PCIE_EP_interface();

   //----------------------------------------
   // Clock & Reset
   //----------------------------------------
   logic               pclk;
   logic               rst_n;

   //----------------------------------------
   // MAC -> PHY (Transmit)
   //----------------------------------------
   logic [31:0] tx_data;
   logic [31:0] tx_datak;
   logic        tx_elec_idle;
   logic        tx_detect_rx;
   logic [1:0]  powerdown;
   logic [2:0]  rate;

   //----------------------------------------
   // PHY -> MAC (Receive)
   //----------------------------------------
   logic [31:0] rx_data;
   logic [31:0] rx_datak;
   logic        rx_valid;
   logic        phy_status;
   logic        rx_elec_idle;
   logic [2:0]  rx_status;

   //----------------------------------------
   // Driver Clocking Block
   //----------------------------------------
   clocking cb_ep_drv @(posedge pclk);
      default input #1step output #1step;
      output tx_data;
      output tx_datak;
      output tx_elec_idle;
      output tx_detect_rx;
      output powerdown;
      output rate;

      input  rx_data;
      input  rx_datak;
      input  rx_valid;
      input  phy_status;
      input  rx_elec_idle;
      input  rx_status;
   endclocking
   //----------------------------------------
   // Monitor Clocking Block
   //----------------------------------------
   clocking cb_ep_mon @(negedge pclk);
      default input #1step;
      input tx_data;
      input tx_datak;
      input tx_elec_idle;
      input tx_detect_rx;
      input powerdown;
      input rate;
      input rx_data;
      input rx_datak;
      input rx_valid;
      input phy_status;
      input rx_elec_idle;
      input rx_status;
   endclocking
   //----------------------------------------
   // Driver Modport
   //----------------------------------------
   modport mp_ep_driver (clocking cb_ep_drv);
   //----------------------------------------
   // Monitor Modport
   //----------------------------------------
   modport mp_ep_monitor (clocking cb_ep_mon);

endinterface

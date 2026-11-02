//=========================================================================================
// File         : PCIe_PIPE_interface.sv
// Project      : PCIE_Gen6
// Description  : PCIe_top\PCIe_PIPE_interface.sv
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

`ifndef PCIE_NUM_LANES
  `define PCIE_NUM_LANES 4
`endif

interface PCIe_RC_interface(input logic pclk);

   //----------------------------------------
   // Clock & Reset
   //----------------------------------------
   logic               rst_n;
   //----------------------------------------
   // MAC -> PHY (Transmit)
   //----------------------------------------
   logic [31:0] tx_data;
   logic [`PCIE_NUM_LANES-1:0][31:0] tx_data_lane;
   logic [`PCIE_NUM_LANES-1:0][31:0] tx_data_striped = '0;
   logic        tx_striped = 1'b0;
   logic        tx_valid;
   logic        tx_elec_idle;
   logic        tx_detect_rx;
   logic [1:0]  powerdown;
   logic [2:0]  rate;
   //----------------------------------------
   // PHY -> MAC (Receive)
   //----------------------------------------
   logic [31:0] rx_data;
   logic [`PCIE_NUM_LANES-1:0][31:0] rx_data_lane;
   logic        rx_valid;
   logic        phy_status;
   logic        rx_elec_idle;
   logic [2:0]  rx_status;

   // Ordered Sets / LTSSM traffic : scalar tx_data is broadcast on every lane.
   // FLIT data : the PL/controller drives tx_data_striped and raises tx_striped.
   always_comb begin
      for (int l = 0; l < `PCIE_NUM_LANES; l++)
         tx_data_lane[l] = tx_striped ? tx_data_striped[l] : tx_data;
   end

   // The scalar receive bus is lane 0. Ordered Sets are broadcast, so this is
   // also the logical word while the link is in training.
   assign rx_data = rx_data_lane[0];
   //----------------------------------------
   // Driver Clocking Block
   //----------------------------------------
   clocking cb_rc_drv @(posedge pclk);
      default input #1step output #1step;
      output tx_data;
      output tx_valid;
      output tx_elec_idle;
      output tx_detect_rx;
      output powerdown;
      output rate;

      input  rx_data;
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
      input tx_valid;
      input tx_elec_idle;
      input tx_detect_rx;
      input powerdown;
      input rate;
      input rx_data;
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

interface PCIe_EP_interface(input logic pclk);

   //----------------------------------------
   // Clock & Reset
   //----------------------------------------
   logic               rst_n;

   //----------------------------------------
   // MAC -> PHY (Transmit)
   //----------------------------------------
   logic [31:0] tx_data;
   logic [`PCIE_NUM_LANES-1:0][31:0] tx_data_lane;
   logic [`PCIE_NUM_LANES-1:0][31:0] tx_data_striped = '0;
   logic        tx_striped = 1'b0;
   logic        tx_valid;
   logic        tx_elec_idle;
   logic        tx_detect_rx;
   logic [1:0]  powerdown;
   logic [2:0]  rate;

   //----------------------------------------
   // PHY -> MAC (Receive)
   //----------------------------------------
   logic [31:0] rx_data;
   logic [`PCIE_NUM_LANES-1:0][31:0] rx_data_lane;
   logic        rx_valid;
   logic        phy_status;
   logic        rx_elec_idle;
   logic [2:0]  rx_status;

   // Ordered Sets / LTSSM traffic : scalar tx_data is broadcast on every lane.
   // FLIT data : the PL/controller drives tx_data_striped and raises tx_striped.
   always_comb begin
      for (int l = 0; l < `PCIE_NUM_LANES; l++)
         tx_data_lane[l] = tx_striped ? tx_data_striped[l] : tx_data;
   end

   // The scalar receive bus is lane 0. Ordered Sets are broadcast, so this is
   // also the logical word while the link is in training.
   assign rx_data = rx_data_lane[0];

   //----------------------------------------
   // Driver Clocking Block
   //----------------------------------------
   clocking cb_ep_drv @(posedge pclk);
      default input #1step output #1step;
      output tx_data;
      output tx_valid;
      output tx_elec_idle;
      output tx_detect_rx;
      output powerdown;
      output rate;

      input  rx_data;
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
      input tx_valid;
      input tx_elec_idle;
      input tx_detect_rx;
      input powerdown;
      input rate;
      input rx_data;
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

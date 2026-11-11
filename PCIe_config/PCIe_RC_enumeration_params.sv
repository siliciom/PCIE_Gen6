//=========================================================================================
// File         : PCIe_RC_enumeration_params.sv
// Project      : PCIE_Gen6
// Description  : PCIe_config\PCIe_RC_enumeration_params.sv
//                Constants used by PCIe_RC_enumeration_sequence :
//                Configuration Space offsets, CAM I/O ports and ECAM window.
//                Included in PCIe_pkg before the enumeration sequence.
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

//------------------------------------------------------------------------
// Configuration Space offsets (Type 0 header, PCIe Base 6.2 Section 7.5.1)
//------------------------------------------------------------------------
localparam bit [11:0] CFG_ID       = 12'h000;   // Device ID | Vendor ID
localparam bit [11:0] CFG_CMD_STS  = 12'h004;   // Status | Command
localparam bit [11:0] CFG_CLASS    = 12'h008;   // Class Code | Revision ID
localparam bit [11:0] CFG_HDR      = 12'h00C;   // BIST | Header Type | Latency Timer | Cache Line Size
localparam bit [11:0] CFG_BAR0     = 12'h010;   // BAR0 .. BAR5 = 010h .. 024h
localparam bit [11:0] CFG_SUBSYS   = 12'h02C;   // Subsystem ID | Subsystem Vendor ID
localparam bit [11:0] CFG_INT      = 12'h03C;   // Max_Lat | Min_Gnt | Interrupt Pin | Interrupt Line

//------------------------------------------------------------------------
// Configuration access mechanism selection
//------------------------------------------------------------------------
localparam bit CFG_MECH_CAM  = 1'b0;            // Section 7.2.1 : I/O 0CF8h / 0CFCh, offsets 000h-0FFh
localparam bit CFG_MECH_ECAM = 1'b1;            // Section 7.2.2 : memory mapped,     offsets 000h-FFFh

//------------------------------------------------------------------------
// CAM : host bridge I/O ports (Section 7.2.1)
//------------------------------------------------------------------------
localparam bit [15:0] PORT_CONFIG_ADDRESS = 16'h0CF8;
localparam bit [15:0] PORT_CONFIG_DATA    = 16'h0CFC;

//------------------------------------------------------------------------
// ECAM : memory window of the host bridge (Section 7.2.2, Table 7-1)
//   n = number of address bits mapped to the Bus Number (1 <= n <= 8)
//   window size = 2^(n+20) bytes, base aligned to the same boundary.
//   Default : n = 8 -> 256 buses -> 256 MB window at E000_0000h, which is
//   clear of the enumeration BAR pools (mem32 8000_0000h, mem64 10_0000_0000h).
//------------------------------------------------------------------------
localparam int        ECAM_BUS_BITS     = 8;
localparam bit [63:0] ECAM_BASE_ADDRESS = 64'h0000_0000_E000_0000;


//=========================================================================================
// File         : PCIe_RC_config_access.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_RC_controller_agent\PCIe_RC_config_access.sv
//                Root Complex HOST BRIDGE configuration access registers
//                (CAM : CONFIG_ADDRESS 0CF8h + CONFIG_DATA 0CFCh).
//                Turns a CPU access into "which Bus/Device/Function/Register"
//                so the RC can send a CfgRd0/CfgWr0 (or CfgRd1/CfgWr1) TLP.
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

//////////////////////////////////////////////////////////////////////////////////////////
// PCIe Base Spec 6.2, Section 7.2.1 : PCI-compatible Configuration Access
// Mechanism (CAM). Two 32-bit I/O registers in the host bridge :
//
//   CONFIG_ADDRESS  (I/O port 0CF8h)  "WHICH register do you want?"
//     [31]    Enable (1 = the next CFC access becomes a Configuration Request)
//     [30:24] Reserved
//     [23:16] Bus Number       (256 buses)
//     [15:11] Device Number    (32 devices)
//     [10:8]  Function Number  (8 functions)
//     [7:2]   Register (DW) Number  -> byte offset 000h..0FCh only
//     [1:0]   00
//
//   CONFIG_DATA     (I/O port 0CFCh)  "HERE is the data" / "GIVE me the data"
//     CPU read  of CFC -> host bridge sends CfgRd  -> completion data lands here
//     CPU write of CFC -> host bridge sends CfgWr with this data
//
// Two steps per access (write CF8, then read/write CFC).
// Only the first 256 bytes (offset 000h-0FFh) can be reached.
//
// Type 0 or Type 1 ? (Section 7.3, routing through the Root Port bridge)
//    target bus == Root Port Secondary Bus           -> Type 0 (CfgRd0/CfgWr0)
//    Secondary Bus < target bus <= Subordinate Bus   -> Type 1 (CfgRd1/CfgWr1)
//    anything else                                   -> not forwarded (reads FFFFFFFFh)
//////////////////////////////////////////////////////////////////////////////////////////

class PCIe_RC_config_access extends uvm_object;

  `uvm_object_utils(PCIe_RC_config_access)

  //------------------------------------------------------------------------
  // CAM registers (I/O ports)
  //------------------------------------------------------------------------
  localparam bit [15:0] PORT_CONFIG_ADDRESS = 16'h0CF8;
  localparam bit [15:0] PORT_CONFIG_DATA    = 16'h0CFC;

  bit [31:0] config_address_reg;   // 0CF8h : CONFIG_ADDRESS
  bit [31:0] config_data_reg;      // 0CFCh : CONFIG_DATA

  //------------------------------------------------------------------------
  // Root Port bridge bus numbers (who is below the link)
  //------------------------------------------------------------------------
  bit [7:0] secondary_bus   = `PCIe_EP_BUS_NUMBER;   // bus right below the Root Port
  bit [7:0] subordinate_bus = `PCIe_EP_BUS_NUMBER;   // highest bus below the Root Port

  function new(string name = "PCIe_RC_config_access");
    super.new(name);
  endfunction

  //========================================================================
  // CAM : build / split the CONFIG_ADDRESS (CF8) value
  //========================================================================
  function bit [31:0] make_config_address(bit [7:0] bus, bit [4:0] dev, bit [2:0] fn, bit [11:0] off);
    bit [31:0] v;
    v        = '0;
    v[31]    = 1'b1;          // Enable
    v[23:16] = bus;
    v[15:11] = dev;
    v[10:8]  = fn;
    v[7:2]   = off[7:2];      // only 000h..0FCh fit here
    v[1:0]   = 2'b00;
    return v;
  endfunction

  function void split_config_address(bit [31:0] v,
                                     output bit enable, output bit [7:0] bus,
                                     output bit [4:0] dev, output bit [2:0] fn,
                                     output bit [11:0] off);
    enable = v[31];
    bus    = v[23:16];
    dev    = v[15:11];
    fn     = v[10:8];
    off    = {4'h0, v[7:2], 2'b00};
  endfunction

  //========================================================================
  // Routing : Type 0 / Type 1 / not forwarded
  //   0 = Type 0, 1 = Type 1, 2 = not below this Root Port
  //========================================================================
  function int route(bit [7:0] bus);
    if (bus == secondary_bus)                                return 0;
    if ((bus > secondary_bus) && (bus <= subordinate_bus))   return 1;
    return 2;
  endfunction

  function string route_name(int r);
    case (r)
      0:       return "Type0 (CfgRd0/CfgWr0)";
      1:       return "Type1 (CfgRd1/CfgWr1)";
      default: return "NOT FORWARDED";
    endcase
  endfunction

endclass


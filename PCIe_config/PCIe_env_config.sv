//=========================================================================================
// File         : PCIe_env_config.sv
// Project      : PCIE_Gen6
// Description  : PCIe_config\PCIe_env_config.sv
// Author       : 
// Date         : 2026-09-09
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

import typedef_enums :: *;
class PCIe_env_config extends uvm_object;

   `uvm_object_utils(PCIe_env_config)
   //----------------------------------------
   // Top Agents
   //----------------------------------------
   bit has_rc_top_agent           = 1;
   bit has_ep_top_agent           = 1;
   //----------------------------------------
   // Protocol Models
   //----------------------------------------
   bit has_rc_tl_model            = 1;
   bit has_rc_dl_model            = 1;
   bit has_rc_pl_model            = 1;

   bit has_ep_tl_model            = 1;
   bit has_ep_dl_model            = 1;
   bit has_ep_pl_model            = 1;
   //----------------------------------------
   // LTSSM Manager
   //----------------------------------------
   bit has_ltssm                  = 1;
   //----------------------------------------
   // Scoreboard
   //----------------------------------------
   bit has_sb                     = 1;
   //----------------------------------------
   // Subscriber
   //----------------------------------------
   bit has_subscriber             = 1;
   //----------------------------------------
   // [TC_VC] TC -> VC mapping table (models the TC/VC Map field of the VC
   // Resource Control Register, PCIe Base 6.0 Sec 7.9.1.7).
   //tc2vc_table is the mapping. The index is the TC and the value is the VC:
   //  tc2vc_table[0] = VC0   -> TC0 uses VC0
  // tc2vc_table[1] = VC1   -> TC1 uses VC1
  //...
  //tc2vc_table[7] = VC7   -> TC7 uses VC7
   int unsigned num_vc            = `PCIe_NUM_VC_DEFAULT;
   vc_id_e      tc2vc_table [8]   = '{VC0, VC1, VC2, VC3, VC4, VC5, VC6, VC7};
   //----------------------------------------
   // [MPS_4KB] Max_Payload_Size of the Link in bytes (Device Control[7:5]).
   //   128 / 256 / 512 / 1024 / 2048 / 4096. Plusarg : +PCIe_MPS=<bytes>
   //----------------------------------------
   int unsigned mps_bytes         = `PCIe_TL_MPS_BYTES_DEFAULT;

   function new(string name="PCIe_env_config");
     super.new(name);
   endfunction

   // [TC_VC] pushes this cfg's table into PCIe_sequence_item's static table so
   // every item maps tc -> vc the same way, on the RC and on the EP side.
   // Called by PCIe_environment::build_phase() (before the FC models are built,
   // they size their per-VC credits from it).
   function void apply_tc2vc_map();
     int unsigned n;
     if ($value$plusargs("PCIe_NUM_VC=%d", n)) num_vc = n;
     if (num_vc < 1 || num_vc > `PCIe_NUM_VC_MAX) begin
       `uvm_error("TC_VC_CFG", $sformatf("num_vc=%0d not valid (1..%0d) - using 1", num_vc, `PCIe_NUM_VC_MAX))
       num_vc = 1;
     end
     PCIe_sequence_item::set_tc2vc_table(num_vc, tc2vc_table);
     `uvm_info("TC_VC_CFG", $sformatf("TC/VC CONFIGURATION : %s", PCIe_sequence_item::tc_vc_map_str()), UVM_HIGH)
   endfunction

   // [MPS_4KB] pushes the MPS into PCIe_sequence_item's static field, used by
   // the RC and EP TL models for the MPS check. Called by
   // PCIe_environment::build_phase() next to apply_tc2vc_map().
   function void apply_mps();
     int unsigned b;
     if ($value$plusargs("PCIe_MPS=%d", b)) mps_bytes = b;
     if (!PCIe_sequence_item::set_mps_bytes(mps_bytes)) begin
       `uvm_error("MPS_CFG", $sformatf("mps_bytes=%0d not valid (128/256/512/1024/2048/4096) - using %0d",
                  mps_bytes, `PCIe_TL_MPS_BYTES_DEFAULT))
       mps_bytes = `PCIe_TL_MPS_BYTES_DEFAULT;
       void'(PCIe_sequence_item::set_mps_bytes(mps_bytes));
     end
     `uvm_info("MPS_CFG", $sformatf("MAX PAYLOAD SIZE CONFIGURATION : %s", PCIe_sequence_item::mps_str()), UVM_LOW)
   endfunction
   
endclass





//=========================================================================================
// File         : PCIe_env_config.sv
// Project      : PCIE_Gen6
// Description  : PCIe_config\PCIe_env_config.sv
// Author       : 
// Date         : 2026-08-17
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

import typedef_enums::*;

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

   pcie_mode_e mode;

   function new(string name="PCIe_env_config");
     super.new(name);
     mode = FLIT_MODE; //by_default_nothing_is_config
   endfunction
   
endclass




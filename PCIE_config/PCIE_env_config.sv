import typedef_enums::*;

class PCIE_env_config extends uvm_object;

   `uvm_object_utils(PCIE_env_config)
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

   function new(string name="PCIE_env_config");
     super.new(name);
     mode = FLIT_MODE; //by_default_nothing_is_config
   endfunction
   
endclass




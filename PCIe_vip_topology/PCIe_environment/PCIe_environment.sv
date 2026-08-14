//=========================================================================================
// File         : PCIe_environment.sv
// Project      : PCIE_Gen6
// Description  : PCIe_environment\PCIe_environment.sv
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

class PCIe_environment extends uvm_env;

   `uvm_component_utils(PCIe_environment)
   
   PCIe_RC_top_agent                rc_top_agent;
   PCIe_EP_top_agent                ep_top_agent;
   PCIe_scoreboard                  pcie_scoreboard;
   PCIe_subscriber                  pcie_subscriber;

   PCIe_env_config                  pcie_ecfg;
   //--------------------------------------------
   // RC MODELS
   //--------------------------------------------
   PCIe_RC_TL_model                 rc_tl_model;
   PCIe_RC_DL_model                 rc_dl_model;
   PCIe_RC_PL_model                 rc_pl_model;

   //--------------------------------------------
   // EP MODELS
   //--------------------------------------------
   PCIe_EP_TL_model                 ep_tl_model;
   PCIe_EP_DL_model                 ep_dl_model;
   PCIe_EP_PL_model                 ep_pl_model;

   //--------------------------------------------
   // LTSSM
   //--------------------------------------------
   PCIe_ltssm_manager               ltssm;

   function new(string name="PCIe_environment", uvm_component parent);
      super.new(name,parent);
   endfunction

   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      `uvm_info(get_type_name(),"ENTER_BUILD_PHASE", UVM_LOW)
      if(!uvm_config_db #(PCIe_env_config)::get(this, "", "PCIe_env_config", pcie_ecfg))
      begin
         `uvm_fatal("PCIe_ENV","Cannot_get_ENV_CONFIG")
      end

      if(pcie_ecfg.has_rc_top_agent)
      begin
         rc_top_agent = PCIe_RC_top_agent::type_id::create("rc_top_agent", this);
      end


      if(pcie_ecfg.has_ep_top_agent)
      begin
         ep_top_agent =  PCIe_EP_top_agent::type_id::create("ep_top_agent", this);
      end

     
      if(pcie_ecfg.has_sb)
      begin
         pcie_scoreboard = PCIe_scoreboard::type_id::create("pcie_scoreboard", this);
      end

     
      if(pcie_ecfg.has_subscriber)
      begin
         pcie_subscriber = PCIe_subscriber::type_id::create("pcie_subscriber", this);
      end

       //----------------------------------------
      // RC MODELS
      //----------------------------------------

      if(pcie_ecfg.has_rc_tl_model)
         rc_tl_model = PCIe_RC_TL_model::type_id::create("rc_tl_model",this);

      if(pcie_ecfg.has_rc_dl_model)
         rc_dl_model = PCIe_RC_DL_model::type_id::create("rc_dl_model",this);

      if(pcie_ecfg.has_rc_pl_model)
         rc_pl_model = PCIe_RC_PL_model::type_id::create("rc_pl_model",this);

      //----------------------------------------
      // EP MODELS
      //----------------------------------------

      if(pcie_ecfg.has_ep_tl_model)
         ep_tl_model = PCIe_EP_TL_model::type_id::create("ep_tl_model",this);

      if(pcie_ecfg.has_ep_dl_model)
         ep_dl_model = PCIe_EP_DL_model::type_id::create("ep_dl_model",this);

      if(pcie_ecfg.has_ep_pl_model)
         ep_pl_model = PCIe_EP_PL_model::type_id::create("ep_pl_model",this);

      //----------------------------------------
      // LTSSM
      //----------------------------------------

      if(pcie_ecfg.has_ltssm)
      begin
         ltssm = PCIe_ltssm_manager::type_id::create("ltssm",this);
      end
      `uvm_info(get_type_name(),"EXIT_BUILD_PHASE",  UVM_LOW)
   endfunction

     function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      `uvm_info(get_type_name(),"ENTER_CONNECT_PHASE", UVM_LOW)
     
      if(pcie_ecfg.has_rc_top_agent)
      begin
         rc_top_agent.rc_controller_agent.rc_controller_driver.rc_tl_model = rc_tl_model;
         rc_top_agent.rc_controller_agent.rc_controller_driver.rc_dl_model = rc_dl_model;
         rc_top_agent.rc_controller_agent.rc_controller_driver.rc_pl_model = rc_pl_model;
         rc_top_agent.rc_controller_agent.rc_controller_driver.ltssm_dri = ltssm;
      end

      if(pcie_ecfg.has_ep_top_agent)
      begin
         ep_top_agent.ep_controller_agent.ep_controller_driver.ep_tl_model = ep_tl_model;
         ep_top_agent.ep_controller_agent.ep_controller_driver.ep_dl_model = ep_dl_model;
         ep_top_agent.ep_controller_agent.ep_controller_driver.ep_pl_model = ep_pl_model;
         ep_top_agent.ep_controller_agent.ep_controller_driver.ltssm_dri = ltssm;
      end

      //----------------------------------------
      // Scoreboard Connections
      //----------------------------------------
      if(pcie_ecfg.has_sb)
      begin

         // Example:
         //
         // rc_top_agent.rc_controller_agent.rc_controller_monitor.tx_ap.connect(
         // pcie_scoreboard.rc_tx_imp);
         //
         // ep_top_agent.ep_controller_agent.ep_controller_monitor.rx_ap.connect(
         // pcie_scoreboard.ep_rx_imp);
      end

      //----------------------------------------
      // Subscriber Connections
      //----------------------------------------
      if(pcie_ecfg.has_subscriber)
      begin
         // Example:
         //
         // rc_top_agent.rc_controller_agent.rc_controller_monitor.tx_cov_ap.connect(
         // pcie_subscriber.analysis_export);
      end
      `uvm_info(get_type_name(),"EXIT_CONNECT_PHASE", UVM_LOW)

   endfunction

endclass



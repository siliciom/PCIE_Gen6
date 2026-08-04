class PCIE_environment extends uvm_env;

  `uvm_component_utils(PCIE_environment)
     PCIE_RC_top_agent             rc_top_agent;
     PCIE_EP_top_agent             ep_top_agent;

     PCIE_scoreboard               pcie_scoreboard;
     PCIE_subscriber               pcie_subscriber;

     PCIE_RC_TL_model              rc_tl_model;
     PCIE_EP_TL_model              ep_tl_model;
     
     PCIE_RC_DL_model              rc_dl_model;
     PCIE_EP_DL_model              ep_dl_model;

     PCIE_RC_PL_model              rc_pl_model;
     PCIE_EP_PL_model              ep_pl_model;
     
     PCIE_ltssm_manager            ltssm;
    
    function new(string name="PCIE_environment",uvm_component parent);
      super.new(name,parent);
    endfunction

    function void build_phase(uvm_phase phase);
      `uvm_info("PCIE_ENV","ENTERED_INTO_ENV_BUILD_PHASE",UVM_LOW)
       super.build_phase(phase);
    	rc_top_agent = PCIE_RC_top_agent::type_id::create("rc_top_agent",this);
    	ep_top_agent = PCIE_EP_top_agent::type_id::create("ep_top_agent",this);
        pcie_scoreboard = PCIE_scoreboard::type_id::create("pcie_scoreboard",this);
        pcie_subscriber = PCIE_subscriber::type_id::create("pcie_subscriber",this);
        rc_tl_model = PCIE_RC_TL_model::type_id::create("rc_tl_model");
        rc_dl_model = PCIE_RC_DL_model::type_id::create("rc_dl_model");
        rc_pl_model = PCIE_RC_PL_model::type_id::create("rc_pl_model");
        ep_tl_model = PCIE_EP_TL_model::type_id::create("ep_tl_model");
        ep_dl_model = PCIE_EP_DL_model::type_id::create("ep_dl_model");
        ep_pl_model = PCIE_EP_PL_model::type_id::create("ep_dl_model");
        ltssm = PCIE_ltssm_manager::type_id::create("ltssm");
      `uvm_info("PCIE_ENV","EXIT_FROM_ENV_BUILD_PHASE",UVM_LOW)
    endfunction

    function void connect_phase(uvm_phase phase);
      `uvm_info("PCIE_ENV","ENTERED_INTO_ENV_CONNECT_PHASE",UVM_LOW)
       super.connect_phase(phase);
          ep_top_agent.ep_controller_agent.ep_controller_driver.ep_tl_model      = ep_tl_model;
          ep_top_agent.ep_controller_agent.ep_controller_driver.ep_dl_model      = ep_dl_model;
          ep_top_agent.ep_controller_agent.ep_controller_driver.ep_pl_model      = ep_pl_model;
          ep_top_agent.ep_controller_agent.ep_controller_driver.ltssm_dri        = ltssm;
          rc_top_agent.rc_controller_agent.rc_controller_driver.rc_tl_model      = rc_tl_model;
          rc_top_agent.rc_controller_agent.rc_controller_driver.rc_dl_model      = rc_dl_model;
          rc_top_agent.rc_controller_agent.rc_controller_driver.rc_pl_model      = rc_pl_model;
          rc_top_agent.rc_controller_agent.rc_controller_driver.ltssm_dri        = ltssm;
      `uvm_info("PCIE_ENV","EXIT_FROM_ENV_CONNECT_PHASE",UVM_LOW)
    endfunction
endclass
  
  


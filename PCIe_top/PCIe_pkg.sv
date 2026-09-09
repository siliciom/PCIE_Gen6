//=========================================================================================
// File         : PCIe_pkg.sv
// Project      : PCIE_Gen6
// Description  : PCIe_top\PCIe_pkg.sv
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
`timescale 1ns/1ps

package PCIe_pkg;

    `include "uvm_macros.svh"
     import uvm_pkg::*;
       
	`include "../PCIe_config/PCIe_defines.sv"
	`include "../PCIe_agents/PCIe_sequence_item.sv"
	`include "../PCIe_config/PCIe_env_config.sv"
	//`include "../PCIe_config/enum_defs.sv"
`include "../PCIe_agents/PCIe_RC_controller_agent/PCIe_RC_TL_model.sv"
	`include "../PCIe_agents/PCIe_RC_controller_agent/PCIe_RC_DL_model.sv"
	`include "../PCIe_agents/PCIe_RC_controller_agent/PCIe_RC_PL_model.sv"
	`include "../PCIe_agents/PCIe_EP_controller_agent/PCIe_EP_TL_model.sv"
	`include "../PCIe_agents/PCIe_EP_controller_agent/PCIe_EP_DL_model.sv"
`include "../PCIe_agents/PCIe_EP_controller_agent/PCIe_EP_PL_model.sv"
        
	`include "../PCIe_agents/PCIe_RC_controller_agent/PCIe_RC_controller_sequencer.sv"
	`include "../PCIe_agents/PCIe_EP_controller_agent/PCIe_EP_controller_sequencer.sv"
	`include "../PCIe_agents/PCIe_RC_phy_agent/PCIe_RC_phy_sequencer.sv"
	`include "../PCIe_agents/PCIe_EP_phy_agent/PCIe_EP_phy_sequencer.sv"

	`include "../PCIe_agents/PCIe_RC_controller_agent/PCIe_RC_controller_driver.sv"
	`include "../PCIe_agents/PCIe_EP_controller_agent/PCIe_EP_controller_driver.sv"
	`include "../PCIe_agents/PCIe_RC_phy_agent/PCIe_RC_phy_driver.sv"
	`include "../PCIe_agents/PCIe_EP_phy_agent/PCIe_EP_phy_driver.sv"

	`include "../PCIe_agents/PCIe_RC_controller_agent/PCIe_RC_controller_monitor.sv"
	`include "../PCIe_agents/PCIe_EP_controller_agent/PCIe_EP_controller_monitor.sv"
	`include "../PCIe_agents/PCIe_RC_phy_agent/PCIe_RC_phy_monitor.sv"
	`include "../PCIe_agents/PCIe_EP_phy_agent/PCIe_EP_phy_monitor.sv"

	
        `include "../PCIe_agents/PCIe_RC_controller_agent/PCIe_RC_controller_agent.sv"
	`include "../PCIe_agents/PCIe_EP_controller_agent/PCIe_EP_controller_agent.sv"
	`include "../PCIe_agents/PCIe_RC_phy_agent/PCIe_RC_phy_agent.sv"
	`include "../PCIe_agents/PCIe_EP_phy_agent/PCIe_EP_phy_agent.sv"
	`include "../PCIe_agents/PCIe_EP_top_agent.sv"
	`include "../PCIe_agents/PCIe_RC_top_agent.sv"

	`include "../PCIe_sequences/PCIe_RC_controller_base_sequence.sv"
	`include "../PCIe_sequences/PCIe_EP_controller_base_sequence.sv"
	`include "../PCIe_sequences/PCIe_RC_phy_base_sequence.sv"
	`include "../PCIe_sequences/PCIe_EP_phy_base_sequence.sv"
	`include "../PCIe_sequences/PCIe_RC_3DW_flit_sequence.sv"
	`include "../PCIe_sequences/PCIe_IO_3DW_FLIT_sequence.sv"

     `include "../PCIe_environment/PCIe_scoreboard.sv"
     `include "../PCIe_environment/PCIe_subscriber.sv"
     `include "../PCIe_environment/PCIe_environment.sv"

     `include "../PCIe_tests/PCIe_base_test.sv"
     `include "../PCIe_tests/PCIe_3DW_flit_test.sv"
     `include "../PCIe_tests/PCIe_IO_3DW_FLIT_test.sv"


endpackage


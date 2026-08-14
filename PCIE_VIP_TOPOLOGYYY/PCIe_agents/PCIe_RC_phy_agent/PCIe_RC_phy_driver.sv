//=========================================================================================
// File         : PCIe_RC_phy_driver.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_RC_phy_agent\PCIe_RC_phy_driver.sv
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

class PCIe_RC_phy_driver extends uvm_driver #(PCIe_sequence_item);
  
       `uvm_component_utils(PCIe_RC_phy_driver)
  
 	PCIe_sequence_item     pcie_seq_item;
 
        
        virtual PCIe_RC_interface     rc_pipe_intf_tx, rc_pipe_intf_rx;	
        virtual PCIe_PHY_interface    rc_phy_intf_tx, rc_phy_intf_rx;	
	
        function new(string name="PCIe_RC_phy_driver", uvm_component parent);
           super.new(name,parent);
	endfunction

	function void build_phase(uvm_phase phase);
          `uvm_info("RC_PHY","ENTERED_INTO_RC_PHY_DRIVER_BUILD_PHASE",UVM_LOW)
	   super.build_phase(phase);
             pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
           
           if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_tx))
            `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")

           if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_rx))
            `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")
          
           if (!uvm_config_db#(virtual PCIe_PHY_interface)::get(this, "", "PCIe_PHY_INTERFACE", rc_phy_intf_tx))
            `uvm_fatal("NO_VIF", "RC_PHY_INTERFACE_not_found")

           if (!uvm_config_db#(virtual PCIe_PHY_interface)::get(this, "", "PCIe_PHY_INTERFACE", rc_phy_intf_rx))
            `uvm_fatal("NO_VIF", "RC_PHY_INTERFACE_not_found")

          `uvm_info("RC_PHY","EXIT_FROM_RC_PHY_DRIVER_BUILD_PHASE",UVM_LOW)
  	endfunction

 	task run_phase(uvm_phase phase);
           `uvm_info("RC_PHY","ENTERED_INTO_RC_PHY_DRIVER_RUN_PHASE",UVM_LOW)
          forever begin
	    seq_item_port.get_next_item(pcie_seq_item);
            seq_item_port.item_done(pcie_seq_item);
          end
           `uvm_info("RC_PHY","EXIT_FROM_RC_PHY_DRIVER_RUN_PHASE",UVM_LOW)
        endtask

endclass






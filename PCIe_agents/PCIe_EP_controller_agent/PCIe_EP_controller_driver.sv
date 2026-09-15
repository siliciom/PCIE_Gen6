//=========================================================================================
// File         : PCIe_EP_controller_driver.sv
// Project      : PCIe_Gen6
// Description  : PCIe_agents\PCIe_EP_controller_agent\PCIe_EP_controller_driver.sv
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

class PCIe_EP_controller_driver extends uvm_driver #(PCIe_sequence_item);
  
  `uvm_component_utils(PCIe_EP_controller_driver)
   uvm_analysis_port #(PCIe_sequence_item) tx_ap;
  
   PCIe_sequence_item            pcie_seq_item;
   PCIe_sequence_item            replayed_item;
   PCIe_sequence_item            nak_item;
   PCIe_sequence_item ack_item;
   
   PCIe_EP_TL_model              ep_tl_model;
   PCIe_EP_DL_model              ep_dl_model;
   PCIe_EP_PL_model              ep_pl_model;
   
   bit[`PCIe_PL_PIPE_WORD_W-1:0] scr_data;
   bit[0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_data;
   bit[0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dl_flit_out;

   
   virtual PCIe_EP_interface     ep_pipe_intf_tx, ep_pipe_intf_rx;	
    
   function new(string name="PCIe_EP_controller_driver", uvm_component parent);
     super.new(name,parent);
	   tx_ap=new("tx_ap",this);
   endfunction

   function void build_phase(uvm_phase phase);
    `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
     super.build_phase(phase);
      pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
      replayed_item = PCIe_sequence_item::type_id::create("replayed_item");
      nak_item = PCIe_sequence_item::type_id::create("nak_item");
      ack_item=PCIe_sequence_item::type_id::create("ack_item");
  
    if (!uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_pipe_intf_tx))
        `uvm_fatal("NO_VIF", "EP_PIPE_INTERFACE_not_found")

    if (!uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_pipe_intf_rx))
        `uvm_fatal("NO_VIF", "EP_PIPE_INTERFACE_not_found")
             
        `uvm_info("EP_CONTROLLER","EXIT_FROM_EP_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
  endfunction

 task run_phase(uvm_phase phase);
  `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_DRIVER_RUN_PHASE",UVM_LOW)
      `uvm_info("EP_CONTROLLER",$sformatf("DLCMSM_STATE_IS %s",ep_dl_model.DL_STATE.name()),UVM_LOW)
  forever begin
      seq_item_port.try_next_item(pcie_seq_item);
      if (pcie_seq_item != null) begin
        ep_pl_model.ep_ltssm(pcie_seq_item);
        `uvm_info("EP_CONTROLLER","ENTERED_INTO_EP_CONTROLLER_DRIVER_NORMAL_TRANSFER_SECTION",UVM_LOW)
        seq_item_port.item_done();
      end
      else begin
        #1ns;
      end
    end
  endtask

  // Drive the flit task
  task drive_flit();
   wait(ep_pl_model.pl_sent);
  `uvm_info("EP_CONTROLLER",$sformatf("dl_flit_out is %p",ep_pl_model.dl_flit_out),UVM_LOW)
   // FLIT is 242 bytes = 60.5 dwords, send 61 dwords (last dword partial)
        for(int i=0 ; i<`PCIe_FLIT_DWORDS; i++) begin
            bit [`PCIe_MON_DATA_W-1:0] flit_dword;
            flit_dword = {ep_pl_model.dl_flit_out[i*`PCIe_PL_BYTES_PER_WORD+3], ep_pl_model.dl_flit_out[i*`PCIe_PL_BYTES_PER_WORD+2], ep_pl_model.dl_flit_out[i*`PCIe_PL_BYTES_PER_WORD+1], ep_pl_model.dl_flit_out[i*`PCIe_PL_BYTES_PER_WORD+0]};
 	    ep_pl_model.tx_process_executed = 1'b0;
 	    ep_pl_model.tx_process(flit_dword, scr_data,pcie_seq_item);
                  if (ep_pl_model.tx_process_executed) begin
                     @(posedge ep_pipe_intf_tx.pclk);
                     ep_pipe_intf_tx.tx_data <= scr_data;
                     ep_pipe_intf_tx.tx_valid <= 1'b1;
                  end
              end
                 @(posedge ep_pipe_intf_tx.pclk);
                   ep_pl_model.pl_sent=0;
                   ep_pipe_intf_tx.tx_valid <= 1'b0;
            endtask

  // Handles the replay things
  task handle_replay_request(bit[`PCIe_SEQ_NUM_W-1:0] N);
    foreach(ep_dl_model.tx_retry_buffer[i]) begin
      replayed_item.seq_num=ep_dl_model.tx_retry_buffer[i].seq_num;
      replayed_item.tlp_data=ep_dl_model.tx_retry_buffer[i].tlp_data;
      // Handle Replay Types
      if(ep_dl_model.REPLAY_SCHEDULED_TYPE==STANDARD_REPLAY) begin
        if(replayed_item.seq_num>=N) begin
          tx_ap.write(replayed_item);
          `uvm_info("EP_CONTROLLER","writing on the port now....",UVM_LOW)
        end
      end
      else if(ep_dl_model.REPLAY_SCHEDULED_TYPE==SELECTIVE_REPLAY) begin
        tx_ap.write(replayed_item);
        break;
      end
    end
    ep_dl_model.EP_REPLAY_IN_PROGRESS=1'b0;
  endtask


endclass





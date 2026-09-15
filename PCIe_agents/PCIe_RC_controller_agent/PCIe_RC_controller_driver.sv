//=========================================================================================
// File         : PCIe_RC_controller_driver.sv
// Project      : PCIe_Gen6
// Description  : PCIe_agents\PCIe_RC_controller_agent\PCIe_RC_controller_driver.sv
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

class PCIe_RC_controller_driver extends uvm_driver #(PCIe_sequence_item);
  
  `uvm_component_utils(PCIe_RC_controller_driver)
   uvm_analysis_port #(PCIe_sequence_item) tx_ap;
   uvm_analysis_port #(PCIe_sequence_item) ltssm_ap;
  
   PCIe_sequence_item            pcie_seq_item;
   PCIe_sequence_item            replayed_item;
   PCIe_sequence_item            nak_item;
   PCIe_sequence_item            ack_item;

   PCIe_RC_TL_model              rc_tl_model;
   PCIe_RC_DL_model              rc_dl_model;
   PCIe_RC_PL_model              rc_pl_model;

  bit[`PCIe_MON_DATA_W-1:0] scr_data;
  bit[0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dl_flit_out;
  bit[0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_data;



   virtual PCIe_RC_interface     rc_pipe_intf_tx, rc_pipe_intf_rx;	
	
   function new(string name="PCIe_RC_controller_driver", uvm_component parent);
     super.new(name,parent);
     tx_ap=new("tx_ap",this);
   endfunction

   function void build_phase(uvm_phase phase);
    `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
     super.build_phase(phase);
      pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
      replayed_item = PCIe_sequence_item::type_id::create("replayed_item");
      nak_item = PCIe_sequence_item::type_id::create("nak_item");
      ack_item=PCIe_sequence_item::type_id::create("ack_item");
	
      if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_tx))
       `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")

      if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_rx))
       `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")
       `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
  	endfunction

task run_phase(uvm_phase phase);
      `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_DRIVER_RUN_PHASE",UVM_LOW)
      `uvm_info("RC_CONTROLLER",$sformatf("DLCMSM_STATE_IS %s",rc_dl_model.DL_STATE.name()),UVM_LOW)
  forever begin
     if (!rc_pl_model.link_up) begin
        seq_item_port.try_next_item(pcie_seq_item);
        if (pcie_seq_item != null) begin
          `uvm_info("RC_CONTROLLER","LTSSM_INITIATED",UVM_LOW)
          rc_pl_model.rc_ltssm(pcie_seq_item);
          // ACK/NAK/REPLAY processing threads can start when L0 is reached.
          rc_dl_model.phy_linkup = rc_pl_model.link_up;
          drive_flit(pcie_seq_item);
          `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_DRIVER_NORMAL_TRANSFER_SECTION",UVM_LOW)
          tx_ap.write(pcie_seq_item);
        end
        seq_item_port.item_done();
     end
        else begin
          // No sequence item currently available.
          // Give DL model a chance to schedule ACK/NAK/REPLAY.
          #1ns;
        end
     end
     /*else begin
        // Link is up: route normal TLPs through TL -> DL -> PL and push the
        // resulting flit onto the PIPE interface.
        rc_dl_model.phy_linkup = rc_pl_model.link_up;
        seq_item_port.try_next_item(pcie_seq_item);
        if (pcie_seq_item != null) begin
          if (rc_pl_model.pl_sent && !pcie_seq_item.electrical_idle_test) begin
             `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_DRIVER_NORMAL_TRANSFER_SECTION",UVM_LOW)
            drive_flit(pcie_seq_item);
            `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_DRIVER_NORMAL_TRANSFER_SECTION",UVM_LOW)
            tx_ap.write(pcie_seq_item);
          end
          seq_item_port.item_done();
        end
        else begin
          if (rc_pl_model.pl_sent) begin
            drive_flit(pcie_seq_item);
          end
          else begin
            #1ns;
          end
        end*/
    // end
  //end
  endtask

  

  // Drive the flit task
  task drive_flit(PCIe_sequence_item pcie_seq_item);
   bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] flit_local;
   `uvm_info("RC_CONTROLLER","ENTERED_INTO_DRIVE_FLIT",UVM_LOW)
   wait(rc_pl_model.pl_sent);
   `uvm_info("RC_CONTROLLER","WAIT_INTO_DRIVE_FLIT",UVM_LOW)
   // Snapshot the flit so a mid-drive PL/DL update cannot corrupt it.
   flit_local = rc_pl_model.dl_flit_out;
  `uvm_info("RC_CONTROLLER",$sformatf("dl_flit_out is %p",rc_pl_model.dl_flit_out),UVM_LOW)
   // FLIT is 242 bytes = 60.5 dwords, send 61 dwords (last dword partial)
        for(int i=0 ; i<`PCIe_FLIT_DWORDS; i++) begin
            bit [`PCIe_MON_DATA_W-1:0] flit_dword;
            flit_dword = {flit_local[i*`PCIe_PL_BYTES_PER_WORD+3], flit_local[i*`PCIe_PL_BYTES_PER_WORD+2], flit_local[i*`PCIe_PL_BYTES_PER_WORD+1], flit_local[i*`PCIe_PL_BYTES_PER_WORD+0]};
  `uvm_info("DRIVE_FLIT",$sformatf("flit_dword is %h :: %d",flit_dword,flit_dword),UVM_LOW)
rc_pl_model.tx_process_executed = 1'b0;
            pcie_seq_item.print();
 	    rc_pl_model.tx_process(flit_dword, scr_data, pcie_seq_item);
  `uvm_info("SCR_DATA",$sformatf("scr_data is %h :: %d",scr_data,scr_data),UVM_LOW)
                  if (rc_pl_model.tx_process_executed) begin
                     @(posedge rc_pipe_intf_tx.pclk);
                     rc_pipe_intf_tx.tx_data <= scr_data;
                     rc_pipe_intf_tx.tx_valid <= 1'b1;
                     `uvm_info("RC_CONTROLLER",$sformatf("RC_CTRLR_DRV_INTF_PIPE_TX_DATA === %h",rc_pipe_intf_tx.tx_data),UVM_LOW)
                  end
              end
                 @(posedge rc_pipe_intf_tx.pclk);
                   rc_pl_model.pl_sent=0;
                   rc_pipe_intf_tx.tx_valid <= 1'b0;
      endtask

  // Handles the replay things
  task handle_replay_request(bit[`PCIe_SEQ_NUM_W-1:0] N);
    foreach(rc_dl_model.tx_retry_buffer[i]) begin
      replayed_item.seq_num=rc_dl_model.tx_retry_buffer[i].seq_num;
      replayed_item.tlp_data=rc_dl_model.tx_retry_buffer[i].tlp_data;
      // Handle Replay Types
      if(rc_dl_model.REPLAY_SCHEDULED_TYPE==STANDARD_REPLAY) begin
        if(replayed_item.seq_num>=N) begin
          tx_ap.write(replayed_item);
          `uvm_info("RC_CONTROLLER","writing on the port now....",UVM_LOW)
        end
      end
      else if(rc_dl_model.REPLAY_SCHEDULED_TYPE==SELECTIVE_REPLAY) begin
        tx_ap.write(replayed_item);
        break;
      end
    end
    rc_dl_model.RC_REPLAY_IN_PROGRESS=1'b0;
  endtask
    

endclass





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
    // Retained for compatibility. DL_ACTIVE is now detected via the level flag
    // ep_dl_model.dl_link_active (see drive_dlcmsm_packets).
    uvm_event ep_dl_active_event;                  // fires once, the instant DL_ACTIVE is entered
    // Watchdog: consecutive 1ns polls with no DLLP flit to drive before the
    // DLCMSM is declared stalled (only reached if DLCMSM stops producing flits).
    localparam int unsigned DLCMSM_IDLE_TIMEOUT_POLLS = 100000;
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
    ep_dl_active_event = uvm_event_pool::get_global("ep_dl_active_event");
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
      if(!ep_pl_model.link_up)begin
      seq_item_port.try_next_item(pcie_seq_item);
      if (pcie_seq_item != null) begin
          `uvm_info("EP_CONTROLLER","LTSSM_INITIATED",UVM_LOW)
        ep_pl_model.ep_ltssm(pcie_seq_item);
        ep_dl_model.phy_linkup = ep_pl_model.link_up;
        if (ep_pl_model.link_up) begin
          // ---------------------------------------------------------------
          // LINK_UP = 1  (LTSSM reached L0)
          //   STEP 1 : DLCMSM is now running in the EP DL model. Drive every
          //            DLLP packet it generates (FEATURE, FC_INIT1, FC_INIT2)
          //            on the PIPE until the DLCMSM reaches DL_ACTIVE.
          //   STEP 2 : DL_ACTIVE reached -> only now send the TLP packet
          //            (TL -> DL -> PL -> PIPE).
          // ---------------------------------------------------------------
          `uvm_info("EP_LTSSM","LINK_UP=1 :: STARTING_DLCMSM_PACKET_DRIVE",UVM_LOW)

          // STEP 1 : DLCMSM packets
          drive_dlcmsm_packets(pcie_seq_item);

          // STEP 2 : TLP packets, only once DL is active
          if (ep_dl_model.dl_link_active) begin
            `uvm_info("EP_DLCMSM","DL_ACTIVE=1 :: SENDING_TLP_PACKET",UVM_LOW)
            tx_ap.write(pcie_seq_item);
            drive_flit(pcie_seq_item);
          end
          else begin
            `uvm_error("EP_DLCMSM",$sformatf("DL_ACTIVE_NOT_REACHED :: TLP_PACKET_NOT_SENT :: DL_STATE=%s link_up=%0b",
                       ep_dl_model.DL_STATE.name(), ep_pl_model.link_up))
          end
        end
        seq_item_port.item_done();
      end
      else begin
        #1ns;
      end
    end
    else begin
      #1ns;
    end
    end
  endtask

  // Drives the DLCMSM (Data Link Control and Management State Machine) packets.
  //
  // Called right after link_up=1. The EP DL model walks
  //     DL_INACTIVE -> DL_FEATURE -> DL_INIT.FC_INIT1 -> DL_INIT.FC_INIT2 -> DL_ACTIVE
  // and, for every DLLP flit it creates (FEATURE, InitFC1 x N, InitFC2 x N),
  // hands it to the PL model and raises ep_dl_model.dllp_tx_pending, then waits.
  // This task puts each of those flits on the PIPE (drive_flit) and clears
  // dllp_tx_pending so the DLCMSM can move on. It returns as soon as the DLCMSM
  // reaches DL_ACTIVE (ep_dl_model.dl_link_active == 1).
  //
  // DL_ACTIVE is detected through the level flag dl_link_active, not through a
  // one-shot uvm_event, so a trigger that fires before the driver is waiting
  // can never be missed.
  task drive_dlcmsm_packets(PCIe_sequence_item pcie_seq_item);
    int unsigned dllp_flits_driven = 0;
    int unsigned idle_polls        = 0;
    `uvm_info("EP_DLCMSM_DRV","DRIVING_DLCMSM_PACKETS_UNTIL_DL_ACTIVE",UVM_LOW)
    while (!ep_dl_model.dl_link_active && ep_pl_model.link_up) begin
      if (ep_dl_model.dllp_tx_pending && ep_pl_model.pl_sent) begin
        idle_polls = 0;
        dllp_flits_driven++;
        `uvm_info("EP_DLCMSM_DRV",$sformatf("DL_STATE=%s :: DRIVING_DLLP_FLIT_NO=%0d",ep_dl_model.DL_STATE.name(),dllp_flits_driven),UVM_LOW)
        drive_flit(pcie_seq_item);             // DLLP flit is now on the PIPE
        ep_dl_model.dllp_tx_pending = 1'b0;    // release the DLCMSM (next state / next DLLP)
      end
      else begin
        // DLCMSM has nothing for us right now - let it run.
        #1ns;
        idle_polls++;
        if (idle_polls > DLCMSM_IDLE_TIMEOUT_POLLS) begin
          // [FIX] print every handshake signal so the stall cause is obvious:
          //   phy_linkup=0            -> DL model never saw link-up
          //   DL_STATE=DL_INACTIVE    -> DLCMSM never started
          //   dllp_tx_pending=1 pl_sent=0 -> PL model did not accept the DLLP flit
          `uvm_error("EP_DLCMSM_DRV",$sformatf("DLCMSM_STALLED :: DL_STATE=%s phy_linkup=%0b dllp_tx_pending=%0b pl_sent=%0b dllp_flits_driven=%0d :: NO_DLLP_FLIT_FOR_%0d_POLLS",
                     ep_dl_model.DL_STATE.name(), ep_dl_model.phy_linkup, ep_dl_model.dllp_tx_pending,
                     ep_pl_model.pl_sent, dllp_flits_driven, idle_polls))
          break;
        end
      end
    end
    `uvm_info("EP_DLCMSM_DRV",$sformatf("DLCMSM_PACKET_DRIVE_DONE :: DL_STATE=%s dl_link_active=%0d dllp_flits_driven=%0d",ep_dl_model.DL_STATE.name(),ep_dl_model.dl_link_active,dllp_flits_driven),UVM_LOW)
  endtask
 
  // Drive the flit task
  task drive_flit(PCIe_sequence_item pcie_seq_item);
   bit [`PCIe_BYTE_W-1:0] flit_full_q[$];
   wait(ep_pl_model.pl_sent);
  `uvm_info("EP_CONTROLLER",$sformatf("dl_flit_out is %p",ep_pl_model.dl_flit_out),UVM_LOW)
   // FEC/CRC : snapshot the full 256B flit (242B DL + 8B CRC + 6B FEC) so a
   // mid-drive PL/DL update cannot corrupt it, then drive all 64 dwords.
   flit_full_q = ep_pl_model.ep_flit_with_crc_fec_body;
   // FULL FLIT is 256 bytes = 242 DL + 8 CRC + 6 FEC, send 64 dwords
        for(int i=0 ; i<`PCIe_FLIT_DWORDS+3; i++) begin
            bit [`PCIe_MON_DATA_W-1:0] flit_dword;
            flit_dword = {flit_full_q[i*`PCIe_PL_BYTES_PER_WORD+3], flit_full_q[i*`PCIe_PL_BYTES_PER_WORD+2], flit_full_q[i*`PCIe_PL_BYTES_PER_WORD+1], flit_full_q[i*`PCIe_PL_BYTES_PER_WORD+0]};
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

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
   uvm_analysis_port #(PCIe_sequence_item) tx_tl_ap;
   uvm_analysis_port #(PCIe_sequence_item) ltssm_ap;
   PCIe_sequence_item            pcie_seq_item;
   PCIe_sequence_item            dllp_item;   // [FIX] fallback item for DL-initiated flits
   PCIe_sequence_item            replayed_item;
   PCIe_sequence_item            nak_item;
   PCIe_sequence_item            ack_item;
 
   PCIe_RC_TL_model              rc_tl_model;
   PCIe_RC_DL_model              rc_dl_model;
   PCIe_RC_PL_model              rc_pl_model;
 
  bit[`PCIe_MON_DATA_W-1:0] scr_data;
  bit[0:`PCIe_DLP_BYTE_W-1][`PCIe_BYTE_W-1:0] dl_flit_out;
  bit[0:`PCIe_TLP_DATA_BYTE_W-1][`PCIe_BYTE_W-1:0] tlp_data;
  bit tl_link_active;
 
   virtual PCIe_RC_interface     rc_pipe_intf_tx, rc_pipe_intf_rx;	
    // Retained for compatibility. DL_ACTIVE is now detected via the level flag
    // rc_dl_model.dl_link_active (see drive_dlcmsm_packets).
    uvm_event dl_active_event;                  // fires once, the instant DL_ACTIVE is entered
    // Watchdog: consecutive 1ns polls with no DLLP flit to drive before the
    // DLCMSM is declared stalled (only reached if DLCMSM stops producing flits).
    localparam int unsigned DLCMSM_IDLE_TIMEOUT_POLLS = 100000;

    // [LINK_FIRST] Bring the link up BEFORE taking any item from the sequence.
    //   link_up_first = 1 : run_phase first runs LTSSM (-> L0) and the DLCMSM
    //                       (-> DL_ACTIVE) with the driver's own ltssm_item,
    //                       then triggers "rc_link_ready". Only after that the
    //                       sequence items (e.g. the enumeration requests) are
    //                       taken, all through the normal "link is up" path.
    //   link_up_first = 0 : old behaviour - the FIRST sequence item starts the
    //                       LTSSM and is then sent as the first TLP (default, so
    //                       the LTSSM tests that use the first item still work).
    //   Set from a test : uvm_config_db#(bit)::set(this, "*", "link_up_before_traffic", 1'b1);
    bit                link_up_first = 1'b0;
    PCIe_sequence_item ltssm_item;               // driver-owned item used only for link training
    uvm_event          link_ready_event;         // global "rc_link_ready" : L0 + DL_ACTIVE reached
   function new(string name="PCIe_RC_controller_driver", uvm_component parent);
     super.new(name,parent);
     tx_tl_ap=new("tx_tl_ap",this);
   endfunction
 
   function void build_phase(uvm_phase phase);
    `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
     super.build_phase(phase);
      pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
      replayed_item = PCIe_sequence_item::type_id::create("replayed_item");
      nak_item = PCIe_sequence_item::type_id::create("nak_item");
      ack_item=PCIe_sequence_item::type_id::create("ack_item");
    dl_active_event = uvm_event_pool::get_global("dl_active_event");
    // [LINK_FIRST] option + "link ready" event (the enumeration sequence waits on it)
    void'(uvm_config_db#(bit)::get(this, "", "link_up_before_traffic", link_up_first));
    link_ready_event = uvm_event_pool::get_global("rc_link_ready");
    `uvm_info("RC_CONTROLLER", $sformatf("LINK_UP_BEFORE_TRAFFIC = %0b (%s)", link_up_first,
              link_up_first ? "driver brings the link up first, then takes sequence items"
                            : "first sequence item starts the LTSSM"), UVM_LOW)
      if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_tx))
       `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")
 
      if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_rx))
       `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")
       `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
  	endfunction
 
task run_phase(uvm_phase phase);
      `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_DRIVER_RUN_PHASE",UVM_LOW)
      `uvm_info("RC_CONTROLLER",$sformatf("DLCMSM_STATE_IS %s",rc_dl_model.DL_STATE.name()),UVM_LOW)

      // [LINK_FIRST] LTSSM (L0) + DLCMSM (DL_ACTIVE) first, no sequence item used.
      // After this, rc_pl_model.link_up = 1, so the loop below goes straight to the
      // "link is up" branch and sends EVERY sequence item (the 1st one included)
      // as a normal TLP.
      if (link_up_first) bring_link_up();

      forever begin
      if (!rc_pl_model.link_up) begin
         seq_item_port.try_next_item(pcie_seq_item);
        if (pcie_seq_item != null) begin
          `uvm_info("RC_CONTROLLER","LTSSM_INITIATED",UVM_LOW)
          rc_pl_model.rc_ltssm(pcie_seq_item);
          rc_dl_model.phy_linkup = rc_pl_model.link_up;
          if (rc_pl_model.link_up) begin
            // ---------------------------------------------------------------
            // LINK_UP = 1  (LTSSM reached L0)
            //   STEP 1 : DLCMSM is now running in the RC DL model. Drive every
            //            DLLP packet it generates (FEATURE, FC_INIT1, FC_INIT2)
            //            on the PIPE until the DLCMSM reaches DL_ACTIVE.
            //   STEP 2 : DL_ACTIVE reached -> only now send the TLP packet
            //            (TL -> DL -> PL -> PIPE).
            // ---------------------------------------------------------------
            `uvm_info("RC_LTSSM","LINK_UP=1 :: STARTING_DLCMSM_PACKET_DRIVE",UVM_LOW)

            // STEP 1 : DLCMSM packets
            drive_dlcmsm_packets(pcie_seq_item);

            // STEP 2 : TLP packets, only once DL is active
            tl_link_active = rc_dl_model.dl_link_active;
            if (rc_dl_model.dl_link_active) begin
              `uvm_info("RC_DLCMSM",$sformatf("DL_ACTIVE=1 :: SENDING_TLP_PACKET tl_link_active=%0d",tl_link_active),UVM_LOW)
              // FLOW CONTROL : transmitter gate (Eq 2-11). Blocks until the peer's
              // CREDIT_LIMIT covers this TLP (InitFC1 / UpdateFC received by the DL).
              // [FLIT_SEG] send_request() splits a TLP that does not fit one
              // 236 B FLIT TLP region and sends every segment in its own FLIT.
              send_request(pcie_seq_item);
            end
            else begin
              `uvm_error("RC_DLCMSM","DL_ACTIVE_NOT_REACHED :: TLP_PACKET_NOT_SENT")
            end
          end
          // FLOW CONTROL : from here on DL-initiated DLLP flits (UpdateFC) may use the PL model
          if (rc_dl_model.dl_link_active) rc_dl_model.fc_tx_allowed = 1'b1;
          seq_item_port.item_done();
      end
        else begin
          // No sequence item currently available.
          // Give DL model a chance to schedule ACK/NAK/REPLAY.
          #1ns;
end
     end
      else begin
        // FLOW CONTROL : link is up. DLLP-only flits created by the DL model after
        // DL_ACTIVE (UpdateFC) are put on the PIPE here and released afterwards.
        if (rc_dl_model.dl_link_active && rc_dl_model.dllp_tx_pending && rc_pl_model.pl_sent) begin
          `uvm_info("RC_FC_DRV","DRIVING_DL_INITIATED_DLLP_FLIT (UpdateFC)",UVM_LOW)
          drive_flit(pcie_seq_item);
          rc_dl_model.dllp_tx_pending = 1'b0;
        end
        else begin
          // [ENUM] LINK IS UP : send every further item from the sequence
          // (the 2nd, 3rd ... configuration request of the enumeration).
          seq_item_port.try_next_item(pcie_seq_item);
          if (pcie_seq_item != null) begin
            if (rc_dl_model.dl_link_active) begin
              // The RC PL model holds ONE flit. Pause new DL UpdateFC flits and
              // drive the ones already queued, so they cannot overwrite this TLP.
              rc_dl_model.fc_tx_allowed = 1'b0;
              drain_dl_dllp_flits();
              `uvm_info("RC_CONTROLLER","LINK_UP=1 :: DL_ACTIVE=1 :: SENDING_NEXT_TLP_PACKET",UVM_LOW)
              send_request(pcie_seq_item);                      // FLOW CONTROL gate + [FLIT_SEG]
              rc_dl_model.fc_tx_allowed = 1'b1;                  // UpdateFC allowed again
            end
            else begin
              `uvm_error("RC_CONTROLLER","LINK_UP=1 BUT DL_ACTIVE=0 :: TLP_PACKET_NOT_SENT")
            end
            seq_item_port.item_done();
          end
          else begin
            #1ns;
          end
        end
      end
     end
   endtask

  //--------------------------------------------------------------------------
  // [LINK_FIRST] bring_link_up : link training BEFORE any sequence item.
  //   STEP 1 : build the driver's own LTSSM item (Flit mode, normal link-up :
  //            no electrical-idle / no-receiver test, TxElecIdle = 1)
  //   STEP 2 : LTSSM  -> rc_pl_model.rc_ltssm()        until L0  (link_up = 1)
  //   STEP 3 : DLCMSM -> drive_dlcmsm_packets()          until DL_ACTIVE
  //            (FEATURE, InitFC1, InitFC2 DLLP flits)
  //   STEP 4 : allow UpdateFC flits and trigger "rc_link_ready"
  //            -> the enumeration sequence starts sending requests only now.
  //--------------------------------------------------------------------------
  task bring_link_up();
    `uvm_info("RC_LINK_FIRST","==================== LINK UP BEFORE TRAFFIC : START ====================",UVM_LOW)

    // STEP 1 : link-training item (not from the sequence)
    ltssm_item = PCIe_sequence_item::type_id::create("rc_ltssm_item");
    if (!ltssm_item.randomize() with {
          pkt_mode             == FLIT;
          electrical_idle_test == 1'b0;
          no_receiver_test     == 1'b0;
          tx_elec_idle         == 1'b1;
          txn_type             == PCIe_TL_CFG;
          dir                  == PCIe_TL_READ;
          cfg_type1            == 1'b0;
        })
      `uvm_fatal("RC_LINK_FIRST","randomize failed for the driver LTSSM item")

    // STEP 2 : LTSSM -> L0
    `uvm_info("RC_LINK_FIRST","STEP 1 : LTSSM_INITIATED (driver-owned item, no sequence item consumed)",UVM_LOW)
    rc_pl_model.rc_ltssm(ltssm_item);
    rc_dl_model.phy_linkup = rc_pl_model.link_up;
    if (!rc_pl_model.link_up) begin
      `uvm_error("RC_LINK_FIRST","LTSSM_DID_NOT_REACH_L0 :: link_up=0 - sequence items will start the LTSSM again")
      return;
    end
    `uvm_info("RC_LINK_FIRST","STEP 2 : LTSSM_REACHED_L0 :: LINK_UP=1 :: STARTING_DLCMSM_PACKET_DRIVE",UVM_LOW)

    // STEP 3 : DLCMSM -> DL_ACTIVE
    drive_dlcmsm_packets(ltssm_item);
    tl_link_active = rc_dl_model.dl_link_active;
    if (!rc_dl_model.dl_link_active) begin
      `uvm_error("RC_LINK_FIRST","DL_ACTIVE_NOT_REACHED :: link is up but the Data Link Layer is not active")
      return;
    end

    // STEP 4 : traffic may start
    rc_dl_model.fc_tx_allowed = 1'b1;          // UpdateFC flits allowed from now on
    `uvm_info("RC_LINK_FIRST","STEP 3 : DL_ACTIVE=1 :: LINK READY (LTSSM L0 + DL_ACTIVE) -> sequence items (enumeration) can start",UVM_LOW)
    link_ready_event.trigger();
    `uvm_info("RC_LINK_FIRST","==================== LINK UP BEFORE TRAFFIC : DONE =====================",UVM_LOW)
  endtask

  //--------------------------------------------------------------------------
  // [FLIT_SEG] send_request : TL -> DL -> PL -> PIPE for one sequence item.
  //   FLIT mode and the TLP does not fit the 236 B TLP region (e.g. a 1024 DW
  //   MWr / DMWr) : the RC TL model splits it into N complete TLPs and each
  //   one is sent in its own FLIT, one after the other :
  //       FC gate -> TL (header + payload + NOP pad) -> DL -> PL -> drive FLIT
  //   Otherwise the item is sent exactly as before (one TLP, one FLIT).
  //   The RC PL model holds one FLIT, so DL UpdateFC flits already queued are
  //   drained between two segments and new ones stay paused (fc_tx_allowed is
  //   restored to the caller's value at the end).
  //--------------------------------------------------------------------------
  task send_request(PCIe_sequence_item req);
    PCIe_sequence_item segs[$];
    bit                fc_allowed_saved;

    if (!rc_tl_model.flit_needs_segmentation(req)) begin
      rc_tl_model.wait_for_fc_credits(req);
      tx_tl_ap.write(req);
      drive_flit(req);
      return;
    end

    rc_tl_model.split_flit_tlp(req, segs);

    fc_allowed_saved          = rc_dl_model.fc_tx_allowed;
    rc_dl_model.fc_tx_allowed = 1'b0;

    foreach (segs[i]) begin
      if (rc_dl_model.dllp_tx_pending) drain_dl_dllp_flits();
      rc_tl_model.wait_for_fc_credits(segs[i]);
      `uvm_info("RC_FLIT_SEG_DRV",
        $sformatf("SENDING_SEGMENT %0d/%0d : addr=0x%0h len=%0d DW tag=0x%0h -> own FLIT",
                  i + 1, segs.size(), segs[i].address, segs[i].data.size(), segs[i].tag), UVM_LOW)
      tx_tl_ap.write(segs[i]);
      drive_flit(segs[i]);
    end

    `uvm_info("RC_FLIT_SEG_DRV",
      $sformatf("ALL_SEGMENTS_SENT : %0d TLPs in %0d FLITs for the %0d DW request",
                segs.size(), segs.size(), req.data.size()), UVM_LOW)

    rc_dl_model.fc_tx_allowed = fc_allowed_saved;
  endtask

  // [ENUM] Drive every DLLP flit (UpdateFC) the DL model has already queued,
  // until nothing is pending. Called with fc_tx_allowed = 0, so the DL model
  // only finishes the UpdateFC batch it had started and does not start a new one.
  task drain_dl_dllp_flits();
    int unsigned polls = 0;
    do begin
      #1ns;
      polls++;
      if (rc_dl_model.dllp_tx_pending && rc_pl_model.pl_sent) begin
        `uvm_info("RC_FC_DRV","DRIVING_DL_INITIATED_DLLP_FLIT (UpdateFC) BEFORE NEXT TLP",UVM_LOW)
        drive_flit(pcie_seq_item);
        rc_dl_model.dllp_tx_pending = 1'b0;
        polls = 0;
      end
      if (polls > 1000) begin
        `uvm_error("RC_FC_DRV","DLLP_FLIT_PENDING_BUT_PL_NOT_READY :: giving up the drain")
        break;
      end
    end while (rc_dl_model.dllp_tx_pending);
  endtask

  // Drives the DLCMSM (Data Link Control and Management State Machine) packets.
  //
  // Called right after link_up=1. The RC DL model walks
  //     DL_INACTIVE -> DL_FEATURE -> DL_INIT.FC_INIT1 -> DL_INIT.FC_INIT2 -> DL_ACTIVE
  // and, for every DLLP flit it creates (FEATURE, InitFC1 x N, InitFC2 x N),
  // hands it to the PL model and raises rc_dl_model.dllp_tx_pending, then waits.
  // This task puts each of those flits on the PIPE (drive_flit) and clears
  // dllp_tx_pending so the DLCMSM can move on. It returns as soon as the DLCMSM
  // reaches DL_ACTIVE (rc_dl_model.dl_link_active == 1).
  //
  // DL_ACTIVE is detected through the level flag dl_link_active, not through a
  // one-shot uvm_event, so a trigger that fires before the driver is waiting
  // can never be missed.
  task drive_dlcmsm_packets(PCIe_sequence_item pcie_seq_item);
    int unsigned dllp_flits_driven = 0;
    int unsigned idle_polls        = 0;
    `uvm_info("RC_DLCMSM_DRV","DRIVING_DLCMSM_PACKETS_UNTIL_DL_ACTIVE",UVM_LOW)
    while (!rc_dl_model.dl_link_active && rc_pl_model.link_up) begin
      if (rc_dl_model.dllp_tx_pending && rc_pl_model.pl_sent) begin
        idle_polls = 0;
        dllp_flits_driven++;
        `uvm_info("RC_DLCMSM_DRV",$sformatf("DL_STATE=%s :: DRIVING_DLLP_FLIT_NO=%0d",rc_dl_model.DL_STATE.name(),dllp_flits_driven),UVM_LOW)
        drive_flit(pcie_seq_item);             // DLLP flit is now on the PIPE
        rc_dl_model.dllp_tx_pending = 1'b0;    // release the DLCMSM (next state / next DLLP)
      end
      else begin
        // DLCMSM has nothing for us right now - let it run.
        #1ns;
        idle_polls++;
        if (idle_polls > DLCMSM_IDLE_TIMEOUT_POLLS) begin
          `uvm_error("RC_DLCMSM_DRV",$sformatf("DLCMSM_STALLED :: DL_STATE=%s dllp_flits_driven=%0d :: NO_DLLP_FLIT_FOR_%0d_POLLS",rc_dl_model.DL_STATE.name(),dllp_flits_driven,idle_polls))
          break;
        end
      end
    end
    `uvm_info("RC_DLCMSM_DRV",$sformatf("DLCMSM_PACKET_DRIVE_DONE :: DL_STATE=%s dl_link_active=%0d dllp_flits_driven=%0d",rc_dl_model.DL_STATE.name(),rc_dl_model.dl_link_active,dllp_flits_driven),UVM_LOW)
  endtask
 
  // Drive the flit task
  task drive_flit(PCIe_sequence_item pcie_seq_item);
   bit [0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] flit_local;
   bit [`PCIe_BYTE_W-1:0] flit_full_q[$];
   // [FIX] try_next_item() leaves pcie_seq_item == null when no sequence item is
   // pending (DL-initiated DLLP / UpdateFC / Completion flits). drive_flit() then
   // called pcie_seq_item.print() / tx_process(..,item) on a null handle ->
   // SIGSEGV in uvm_object::sprint. Use a valid FLIT-mode item instead.
   if (pcie_seq_item == null) begin
      if (dllp_item == null) begin
         dllp_item = PCIe_sequence_item::type_id::create("dllp_item");
         dllp_item.pkt_mode = FLIT;
      end
      pcie_seq_item = dllp_item;
   end
   `uvm_info("RC_CONTROLLER","ENTERED_INTO_DRIVE_FLIT",UVM_LOW)
   wait(rc_pl_model.pl_sent);
   `uvm_info("RC_CONTROLLER","WAIT_INTO_DRIVE_FLIT",UVM_LOW)
   // FEC/CRC : snapshot the full 256B flit (242B DL + 8B CRC + 6B FEC) so a
   // mid-drive PL/DL update cannot corrupt it, then drive all 64 dwords.
   flit_local = rc_pl_model.dl_flit_out;
   flit_full_q = rc_pl_model.flit_with_crc_fec_body;
   `uvm_info("RC_CONTROLLER",$sformatf("dl_flit_out is %p",rc_pl_model.dl_flit_out),UVM_LOW)
     // FULL FLIT is 256 bytes = 64 dwords. Encode every logical dword, then
     // let the RC PL model byte-stripe the flit across the lanes. The driver
     // only clocks the resulting per-lane words onto the PIPE.
     begin
       int unsigned nlanes;
       int unsigned rounds;
       bit [31:0] enc_flit[$];
       bit [`PCIE_LANE_BUS_W-1:0] lane_buses[$];

       nlanes = `PCIE_NUM_LANES;
       enc_flit.delete();
       for (int unsigned i = 0; i < `PCIe_FLIT_TOTAL_DW; i++) begin
          bit [`PCIe_MON_DATA_W-1:0] flit_dword;
          flit_dword = {flit_full_q[i*`PCIe_PL_BYTES_PER_WORD+3], flit_full_q[i*`PCIe_PL_BYTES_PER_WORD+2], flit_full_q[i*`PCIe_PL_BYTES_PER_WORD+1], flit_full_q[i*`PCIe_PL_BYTES_PER_WORD+0]};
          `uvm_info("DRIVE_FLIT",$sformatf("flit_dword is %h :: %d",flit_dword,flit_dword),UVM_LOW)
          rc_pl_model.tx_process_executed = 1'b0;
          if (pcie_seq_item != null) pcie_seq_item.print();
          rc_pl_model.tx_process(flit_dword, scr_data, pcie_seq_item);
          `uvm_info("SCR_DATA",$sformatf("scr_data is %h :: %d",scr_data,scr_data),UVM_LOW)
          enc_flit.push_back(scr_data);
       end

       // Byte striping is owned by the RC PL model (logs BYTE_STRIPE).
       PCIe_RC_PL_model::stripe_flit("RC", this, enc_flit, lane_buses);
       rounds = lane_buses.size();

       for (int unsigned r = 0; r < rounds; r++) begin
          @(posedge rc_pipe_intf_tx.pclk);
          for (int unsigned l = 0; l < nlanes; l++)
             rc_pipe_intf_tx.tx_data_striped[l] <= lane_buses[r][l*`PCIe_LANE_W +: `PCIe_LANE_W];
          rc_pipe_intf_tx.tx_striped <= 1'b1;
          rc_pipe_intf_tx.tx_valid   <= 1'b1;
       end
       @(posedge rc_pipe_intf_tx.pclk);
       rc_pl_model.pl_sent = 0;
       rc_pipe_intf_tx.tx_valid   <= 1'b0;
       rc_pipe_intf_tx.tx_striped <= 1'b0;
     end
       endtask
 
  // Handles the replay things
  task handle_replay_request(bit[`PCIe_SEQ_NUM_W-1:0] N);
    foreach(rc_dl_model.tx_retry_buffer[i]) begin
      replayed_item.seq_num=rc_dl_model.tx_retry_buffer[i].seq_num;
      replayed_item.tlp_data=rc_dl_model.tx_retry_buffer[i].tlp_data;
      // Handle Replay Types
      if(rc_dl_model.REPLAY_SCHEDULED_TYPE==STANDARD_REPLAY) begin
        if(replayed_item.seq_num>=N) begin
          tx_tl_ap.write(replayed_item);
          `uvm_info("RC_CONTROLLER","writing on the port now....",UVM_LOW)
        end
      end
      else if(rc_dl_model.REPLAY_SCHEDULED_TYPE==SELECTIVE_REPLAY) begin
        tx_tl_ap.write(replayed_item);
        break;
      end
    end
    rc_dl_model.RC_REPLAY_IN_PROGRESS=1'b0;
  endtask

 
endclass
   




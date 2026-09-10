//=========================================================================================
// File         : PCIe_subscriber.sv
// Project      : PCIE_Gen6
// Description  : PCIe_environment\PCIe_subscriber.sv
// Author       : 
// Date         : 2026-09-09
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

import typedef_enums :: *;
import uvm_pkg :: *;

class PCIe_subscriber extends uvm_subscriber#(PCIe_sequence_item);

  `uvm_component_utils(PCIe_subscriber)
   PCIe_sequence_item     pcie_seq_item;

   PCIe_RC_PL_model  rc_pl;
   PCIe_EP_PL_model  ep_pl;

   virtual PCIe_RC_interface rc_pipe_intf;
   virtual PCIe_EP_interface ep_pipe_intf;

PCIe_env_config   pcie_ecfg;
    // Per-transaction mode coverage from pcie_seq_item.pkt_mode in write()

   int rc_l0_flit_dword_count;
   int ep_l0_flit_dword_count;

   event rc_pl_sample_ev;
   event ep_pl_sample_ev;

   covergroup rc_pl_cg @(rc_pl_sample_ev);

      cp_rc_main_state : coverpoint rc_pl.rc_main_state {
                                                         bins b_detect       = { DETECT       };
                                                         bins b_polling      = { POLLING      };
                                                         bins b_configuration= { CONFIGURATION};
                                                         bins b_l0           = { L0           };
                                                         // RECOVERY enum value exists but is never entered (no recovery logic).
                                                         ignore_bins b_recovery_unimpl = { RECOVERY }; // FUTURE COVERAGE
                                                        }



      cp_rc_rx_status_detect : coverpoint rc_pl.rc_pipe_intf_tx.rx_status {
                              						    bins b_found  = { 3'b011 };
        								    bins b_notfound= { 3'b000 };
        								   }

      cp_rc_poll_state : coverpoint rc_pl.rc_poll_state {
      							 bins b_active         = { POLLING_ACTIVE         };
              					         bins b_configuration  = { POLLING_CONFIGURATION  };
      					                 ignore_bins b_compliance_unimpl = { POLLING_COMPLIANCE }; // FUTURE COVERAGE
      					                 }
 


      // CONFIGURATION substates (enum : LINKWIDTH_START, LINKWIDTH_ACCEPT,
      //                            LANENUM_WAIT, LANENUM_ACCEPT,
      //                            CONFIG_COMPLETE, CONFIG_IDLE)
      cp_rc_cfg_state : coverpoint rc_pl.rc_cfg_state {
                                                       bins b_lwstart     = { LINKWIDTH_START };
                                                       bins b_lwaccept    = { LINKWIDTH_ACCEPT };
                                                       bins b_lnwait      = { LANENUM_WAIT     };
                                                       bins b_lnaccept    = { LANENUM_ACCEPT   };
                                                       bins b_complete    = { CONFIG_COMPLETE  };
                                                       bins b_idle        = { CONFIG_IDLE      };
                                                       }

      cp_rc_cfg_to_l0 : coverpoint rc_pl.rc_main_state
                        iff (rc_pl.rc_cfg_state == CONFIG_IDLE) {
                                                                 bins b_cfg_idle_to_l0 = { L0 };
                                                                 }

      // L0 entry reached (link up).
      cp_rc_link_up : coverpoint rc_pl.link_up {
                                                 bins b_down = { 1'b0 };
                                                 bins b_up   = { 1'b1 };
                                                 }

      cp_rc_tx_valid : coverpoint rc_pl.rc_pipe_intf_tx.tx_valid {
                                                                  bins b_inactive = { 1'b0 };
                                                                  bins b_active   = { 1'b1 };
                                                                  }

      cp_rc_tx_elec_idle : coverpoint rc_pl.rc_pipe_intf_tx.tx_elec_idle {
                                                                          bins b_idle   = { 1'b0 };
                                                                          bins b_noidle = { 1'b1 };
                                                                         }

      cp_rc_tx_detect_rx : coverpoint rc_pl.rc_pipe_intf_tx.tx_detect_rx {
                                                                           bins b_inactive = { 1'b0 };
                                                                           bins b_active   = { 1'b1 };
                                                                          }

     cp_rc_rate : coverpoint pcie_seq_item.rate {
   						 bins        b_rate0 = {3'b101};
    					         ignore_bins b_rate1 = {[3'b000:3'b100], [3'b110:3'b111]};
                                                }

      cp_rc_phy_status : coverpoint rc_pl.rc_pipe_intf_tx.phy_status {
                                                                       bins b_deasserted = { 1'b0 };
                                                                       bins b_asserted   = { 1'b1 };
                                                                     }

      cp_rc_powerdown : coverpoint pcie_seq_item.powerdown {
                                                             bins b_p0 = { 1'b0 };
                                                             ignore_bins b_p1 = { 1'b1 };
                                                           }

      cp_rc_rx_valid : coverpoint rc_pl.rc_pipe_intf_rx.rx_valid {
                                                                  bins b_inactive = { 1'b0 };
                                                                  bins b_active   = { 1'b1 };
                                                                  }


      cp_rc_rx_status : coverpoint rc_pl.rc_pipe_intf_rx.rx_status {
                                                                     bins b_rcv_detect_done = { 3'b011 };
                                                                     bins b_other           = { 3'b000, 3'b001, 3'b010, 3'b100, 3'b101,3'b110, 3'b111 };
                                                                   }

      // Ordered-set build fields (TS1).
      cp_rc_ts1_os_com : coverpoint rc_pl.rc_ts1_os[0] {
                                                         bins b_com = { 8'hBC };
                                                       }
      cp_rc_ts1_link_num : coverpoint rc_pl.rc_ts1_os[1] {
                                                           bins b_selected = { 8'h00 };
                                                           bins b_pad      = { 8'hFF };
                                                         }
      cp_rc_ts1_lane_num : coverpoint rc_pl.rc_ts1_os[2] {
                                                           bins b_assigned = { 8'h00 };
                                                           bins b_pad      = { 8'hFF };
                                                          }
      cp_rc_ts1_nfts : coverpoint rc_pl.rc_ts1_os[3] {
                                                      bins b_nfts = { 8'h10 };
                                                     }

      // Ordered-set build fields (TS2).
      cp_rc_ts2_os_s0 : coverpoint rc_pl.rc_ts2_os[0] {
                                                       bins b_ts2_com = { 8'h39 };
                                                      }
      cp_rc_ts2_link_num : coverpoint rc_pl.rc_ts2_os[1] {
                                                          bins b_selected = { 8'h00 };
                                                          bins b_pad      = { 8'hFF };
                                                          }
      cp_rc_ts2_lane_num : coverpoint rc_pl.rc_ts2_os[2] {
                                                          bins b_assigned = { 8'h00 };
                                                          bins b_pad      = { 8'hFF };
                                                         }

      cp_rc_ts2_training_ctl : coverpoint rc_pl.rc_ts2_os[6] {
                                                              bins b_normal          = { 8'h00 };  // Training.Control = 0
                                                             }

cp_rc_mode : coverpoint pcie_seq_item.pkt_mode {
                                           ignore_bins b_non_flit = { NON_FLIT };
                                           bins b_flit     = { FLIT     };
                                          }

   endgroup : rc_pl_cg

   covergroup ep_pl_cg @(ep_pl_sample_ev);

      cp_ep_main_state : coverpoint ep_pl.ep_main_state {
                                                         bins b_detect       = { DETECT       };
                                                         bins b_polling      = { POLLING      };
                                                         bins b_configuration= { CONFIGURATION};
                                                         bins b_l0           = { L0           };
                                                         ignore_bins b_recovery_unimpl = { RECOVERY }; // FUTURE COVERAGE
                                                         }



      cp_ep_rx_status_detect : coverpoint ep_pl.ep_pipe_intf_tx.rx_status {
                                                                           bins b_found   = { 3'b011 };
                                                                           bins b_notfound= { 3'b000 };
                                                                           }

      cp_ep_poll_state : coverpoint ep_pl.ep_poll_state {
                                                         bins b_active         = { POLLING_ACTIVE        };
                                                         bins b_configuration  = { POLLING_CONFIGURATION };
                                                         ignore_bins b_compliance_unimpl = { POLLING_COMPLIANCE }; // FUTURE COVERAGE
                                                        }

      cp_ep_cfg_state : coverpoint ep_pl.ep_cfg_state {
                                                       bins b_lwstart     = { LINKWIDTH_START };
                                                       bins b_lwaccept    = { LINKWIDTH_ACCEPT };
                                                       bins b_lnwait      = { LANENUM_WAIT     };
                                                       bins b_lnaccept    = { LANENUM_ACCEPT   };
                                                       bins b_complete    = { CONFIG_COMPLETE  };
                                                       bins b_idle        = { CONFIG_IDLE      };
                                                       }

      cp_ep_cfg_to_l0 : coverpoint ep_pl.ep_main_state
                        iff (ep_pl.ep_cfg_state == CONFIG_IDLE) {
                                                                 bins b_cfg_idle_to_l0 = { L0 };
                                                                }

      cp_ep_link_up : coverpoint ep_pl.link_up {
                                                 bins b_down = { 1'b0 };
                                                 bins b_up   = { 1'b1 };
                                               }

      cp_ep_tx_valid : coverpoint ep_pl.ep_pipe_intf_tx.tx_valid {
                                                                   bins b_inactive = { 1'b0 }; 
	                                                           bins b_active = { 1'b1 };
                                                                 }


      cp_ep_tx_elec_idle : coverpoint ep_pl.ep_pipe_intf_tx.tx_elec_idle {
                                                                           bins b_inactive = { 1'b0 }; 
	                                                                   bins b_active = { 1'b1 };
                                                                          }


      cp_ep_tx_detect_rx : coverpoint ep_pl.ep_pipe_intf_tx.tx_detect_rx {
                                                                           bins b_inactive = { 1'b0 };
	                                                                   bins b_active = { 1'b1 };
                                                                          }


      cp_ep_rate : coverpoint ep_pl.ep_pipe_intf_tx.rate {
                                                           bins b_r0={2'b00}; 
	                                                   ignore_bins b_r1={2'b01}; 
	                                                   ignore_bins b_r2={2'b10}; 
	                                                   ignore_bins b_r3={2'b11};
                                                         }


      cp_ep_phy_status : coverpoint ep_pl.ep_pipe_intf_tx.phy_status {
                                                                      bins b_deasserted={1'b0}; 
	                                                              bins b_asserted={1'b1};
                                                                      }

      cp_ep_rx_valid : coverpoint ep_pl.ep_pipe_intf_rx.rx_valid {
                                                                  bins b_inactive = {1'b0}; 
	                                                          bins b_active = {1'b1};
                                                                  }


      cp_ep_rx_first_symbol : coverpoint ep_pl.ep_pipe_intf_rx.rx_data[1:0] {
                                                                              bins b_ts1 = {2'b11}; 
	                                                                      bins b_ts2 = {2'b10}; 
	                                                                      bins b_idle = {2'b00};
                                                                             }


      cp_ep_ts1_os_com     : coverpoint ep_pl.ep_ts1_os[0]   { bins b_com = {8'hBC}; }


      cp_ep_ts1_link_num   : coverpoint ep_pl.ep_ts1_os[1]   {
                                                              bins b_selected={8'h00}; 
	                                                      bins b_pad={8'hFF}; 
                                                              }


      cp_ep_ts1_lane_num   : coverpoint ep_pl.ep_ts1_os[2]   {
                                                                bins b_assigned={8'h00}; 
	                                                        bins b_pad={8'hFF}; 
                                                             }


      cp_ep_ts2_os_s0      : coverpoint ep_pl.ep_ts2_os[0]   { bins b_ts2_com = {8'h39}; }


      cp_ep_ts2_training_ctl: coverpoint ep_pl.ep_ts2_os[6]   {
                                                                bins b_goto_compliance = {8'h01}; 
	                                                        bins b_normal = {8'h00};
      }

cp_ep_mode : coverpoint pcie_seq_item.pkt_mode {
                                           ignore_bins b_non_flit = { NON_FLIT };
                                           bins b_flit     = { FLIT     };
                                          }


      cp_ep_pl_sent : coverpoint ep_pl.pl_sent {
                                                bins b_not_sent = {1'b0}; 
	                                        bins b_sent = {1'b1};
                                               }

   endgroup : ep_pl_cg

   function new(string name="PCIe_subscriber",uvm_component parent);
     super.new(name,parent);
      rc_pl_cg       = new();
      //rc_pl_cross_cg = new();
      ep_pl_cg       = new();
      //ep_pl_cross_cg = new();
   endfunction

function void build_phase(uvm_phase phase);
     `uvm_info("PCIe_SUBSCRIBER","ENTERED_INTO_SUB_BUILD_PHASE",UVM_LOW)
      super.build_phase(phase);
         pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item") ;
      if (!uvm_config_db#(PCIe_env_config)::get(this, "", "PCIe_env_config", pcie_ecfg))
         `uvm_fatal("PCIe_SUBSCRIBER","Cannot_get_PCIe_env_config")
      uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf);
      uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_pipe_intf);
     `uvm_info("PCIe_SUBSCRIBER","EXIT_FROM_SUB_BUILD_PHASE",UVM_LOW)
    endfunction

   function void start_of_simulation_phase(uvm_phase phase);
     super.start_of_simulation_phase(phase);
     if (!uvm_config_db#(PCIe_RC_PL_model)::get(this, "", "RC_PL_MODEL", rc_pl))
        `uvm_fatal("PCIe_SUBSCRIBER", "RC_PL_MODEL handle not found in config DB")
     if (!uvm_config_db#(PCIe_EP_PL_model)::get(this, "", "EP_PL_MODEL", ep_pl))
        `uvm_fatal("PCIe_SUBSCRIBER", "EP_PL_MODEL handle not found in config DB")
   endfunction

   task run_phase(uvm_phase phase);
      main_state_e    r_prev_main = DETECT;
      detect_state_e  r_prev_det  = DETECT_QUIET;
      polling_state_e r_prev_pol  = POLLING_ACTIVE;
      config_state_e  r_prev_cfg  = LINKWIDTH_START;
      main_state_e    e_prev_main = DETECT;
      detect_state_e  e_prev_det  = DETECT_QUIET;
      polling_state_e e_prev_pol  = POLLING_ACTIVE;
      config_state_e  e_prev_cfg  = LINKWIDTH_START;

      fork
         // RC sampler
         forever begin
            @(negedge rc_pipe_intf.pclk);
            if ((rc_pl.rc_main_state != r_prev_main)||(rc_pl.rc_detect_state != r_prev_det)||(rc_pl.rc_poll_state   != r_prev_pol) ||(rc_pl.rc_cfg_state != r_prev_cfg) || (rc_pl.rc_pipe_intf_tx.tx_valid) || (rc_pl.rc_pipe_intf_rx.rx_valid)) begin
               -> rc_pl_sample_ev;
               r_prev_main = rc_pl.rc_main_state;
               r_prev_det  = rc_pl.rc_detect_state;
               r_prev_pol  = rc_pl.rc_poll_state;
               r_prev_cfg  = rc_pl.rc_cfg_state;
            end
         end
         // EP sampler
         forever begin
            @(negedge ep_pipe_intf.pclk);
            if ((ep_pl.ep_main_state != e_prev_main) || (ep_pl.ep_detect_state != e_prev_det) ||  (ep_pl.ep_poll_state   != e_prev_pol) ||
                (ep_pl.ep_cfg_state    != e_prev_cfg) || (ep_pl.ep_pipe_intf_tx.tx_valid) || (ep_pl.ep_pipe_intf_rx.rx_valid)) begin
               -> ep_pl_sample_ev;
               e_prev_main = ep_pl.ep_main_state;
               e_prev_det  = ep_pl.ep_detect_state;
               e_prev_pol  = ep_pl.ep_poll_state;
               e_prev_cfg  = ep_pl.ep_cfg_state;
            end
         end
      join_none
   endtask

  virtual function void write(PCIe_sequence_item t);
     pcie_seq_item = t;
  endfunction

endclass

    

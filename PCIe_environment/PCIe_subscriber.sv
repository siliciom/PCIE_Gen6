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

//==============================================================================
// [TL_COV] analysis imp declarations : RECEIVED TLPs (FLIT mode coverage)
//   rc_rx_tl : PCIe_RC_TL_model rx_decoded_ap (Completions received by the RC)
//   ep_rx_tl : PCIe_EP_TL_model rx_decoded_ap (Requests received by the EP)
//==============================================================================
`uvm_analysis_imp_decl(_rc_rx_tl)
`uvm_analysis_imp_decl(_ep_rx_tl)

//==============================================================================
// [DL_COV] analysis imp declarations : RECEIVED flits, DLP already decoded
//   rc_rx_dl : PCIe_RC_DL_model rc_dl_cov_ap (EP -> RC flits)
//   ep_rx_dl : PCIe_EP_DL_model ep_dl_cov_ap (RC -> EP flits)
//==============================================================================
`uvm_analysis_imp_decl(_rc_rx_dl)
`uvm_analysis_imp_decl(_ep_rx_dl)

//==============================================================================
// [PL_COV] analysis imp declarations : PIPE control / status pins
//   rc : RC controller monitor rc_cov_ap -> rc_export -> write_rc()
//   ep : EP controller monitor ep_cov_ap -> ep_export -> write_ep()
//   item.cov_dir = PCIE_COV_TX (TX pins) or PCIE_COV_RX (RX pins)
//==============================================================================
`uvm_analysis_imp_decl(_rc)
`uvm_analysis_imp_decl(_ep)

class PCIe_subscriber extends uvm_subscriber#(PCIe_sequence_item);

  `uvm_component_utils(PCIe_subscriber)
   PCIe_sequence_item     pcie_seq_item;

   //===========================================================================
   // [PL_COV] ports and sampled items (connected in PCIe_environment.sv)
   //===========================================================================
   uvm_analysis_imp_rc #(PCIe_sequence_item, PCIe_subscriber) rc_export;
   uvm_analysis_imp_ep #(PCIe_sequence_item, PCIe_subscriber) ep_export;

   PCIe_sequence_item  rc_tx_item;   // RC PIPE TX pins (cov_dir = TX)
   PCIe_sequence_item  rc_rx_item;   // RC PIPE RX pins (cov_dir = RX)
   PCIe_sequence_item  ep_tx_item;   // EP PIPE TX pins (cov_dir = TX)
   PCIe_sequence_item  ep_rx_item;   // EP PIPE RX pins (cov_dir = RX)

   //===========================================================================
   // [TL_COV] ports and sampled items (connected in PCIe_environment.sv)
   //   The TL models send the received TLP AFTER they decode it, so all
   //   fields used below (txn_type, length, tag, cpl_status ...) are filled.
   //===========================================================================
   uvm_analysis_imp_rc_rx_tl #(PCIe_sequence_item, PCIe_subscriber) rc_rx_tl_imp;
   uvm_analysis_imp_ep_rx_tl #(PCIe_sequence_item, PCIe_subscriber) ep_rx_tl_imp;

   PCIe_sequence_item  rc_rx_tl_item;   // Completion received by the RC (decoded)
   PCIe_sequence_item  ep_rx_tl_item;   // Request    received by the EP (decoded)

   //===========================================================================
   // [DL_COV] ports, DL model handles and decoded DLP fields
   //   (connected / set in PCIe_environment.sv)
   //===========================================================================
   uvm_analysis_imp_rc_rx_dl #(PCIe_sequence_item, PCIe_subscriber) rc_rx_dl_imp;
   uvm_analysis_imp_ep_rx_dl #(PCIe_sequence_item, PCIe_subscriber) ep_rx_dl_imp;

   PCIe_RC_DL_model  rc_dl;
   PCIe_EP_DL_model  ep_dl;

   // Received flit with DLP fields already decoded by the DL model
   //   (same style as rc_rx_tl_item / ep_rx_tl_item)
   PCIe_sequence_item  rc_rx_dl_item;   // EP -> RC flit (decoded by RC DL model)
   PCIe_sequence_item  ep_rx_dl_item;   // RC -> EP flit (decoded by EP DL model)

   virtual PCIe_RC_interface rc_pipe_intf;
   virtual PCIe_EP_interface ep_pipe_intf;

PCIe_env_config   pcie_ecfg;
    // Per-transaction mode coverage from pcie_seq_item.pkt_mode in write()

   int rc_l0_flit_dword_count;
   int ep_l0_flit_dword_count;

   //===========================================================================
   // [COV_2CG] Only 2 covergroups : rc_cg and ep_cg
   //   Each covergroup has 5 sections : TL RX, DL RX, PL TX, PL RX, DL STATE.
   //   sample(src) tells the covergroup which section the new data is for, and
   //   every coverpoint has  iff (src == <its section>)  so a coverpoint only
   //   counts when its own data is new.
   //
   //   TL / DL : RX only. Each packet is counted ONCE, by the side that
   //             received it (no TL / DL TX sections : with no change in the
   //             TL / DL models, TX data would be the same item as the other
   //             side's RX, so the same packet would be counted twice).
   //               rc_cg.tl_rx_* : Completions the RC received
   //               ep_cg.tl_rx_* : Requests    the EP received
   //               rc_cg.dl_rx_* / ep_cg.dl_rx_* : flits each side received
   //   PL      : PIPE control / status pins sent by the RC / EP controller
   //             monitors on rc_export / ep_export, routed by item.cov_dir
   //             (PCIE_COV_TX -> PL TX section, PCIE_COV_RX -> PL RX section)
   //===========================================================================
   typedef enum {TL_RX, DL_RX, PL_TX, PL_RX, DL_STATE} cov_src_e;

   covergroup rc_cg with function sample(cov_src_e src);
      option.per_instance = 1;

      //======================================================================
      // PL TX : PIPE TX control pins of the RC   (data = rc_tx_item from the RC controller monitor, cov_dir = TX)
      //======================================================================
      pl_tx_valid : coverpoint rc_tx_item.tx_valid iff (src == PL_TX) {
        bins b_inactive = { 1'b0 };
        bins b_active   = { 1'b1 };
      }
      pl_tx_elec_idle : coverpoint rc_tx_item.tx_elec_idle iff (src == PL_TX) {
        bins b_inactive = { 1'b0 };
        bins b_active   = { 1'b1 };
      }
      pl_tx_detect_rx : coverpoint rc_tx_item.tx_detect_rx iff (src == PL_TX) {
        bins b_inactive = { 1'b0 };
        bins b_active   = { 1'b1 };
      }
      // PL models only ever drive P0 today (powerdown is never assigned in the
      // RC/EP PL models). P1..P3 are waived until the PL model drives them;
      // compile with +define+PCIE_COV_POWERDOWN_FULL to bring them back as targets.
      pl_tx_powerdown : coverpoint rc_tx_item.powerdown iff (src == PL_TX) {
        bins b_p0 = { 2'b00 };
`ifdef PCIE_COV_POWERDOWN_FULL
        bins b_p1 = { 2'b01 };
        bins b_p2 = { 2'b10 };
        bins b_p3 = { 2'b11 };
`else
        ignore_bins b_p1_p3_not_driven = { [2'b01 : 2'b11] };
`endif
      }
      pl_tx_rate : coverpoint rc_tx_item.rate iff (src == PL_TX) {
        bins b_not_negotiated = { `PCIe_RATE_NOT_NEGOTIATED };
        bins b_gen1           = { `PCIe_RATE_GEN1 };
        bins b_gen2           = { `PCIe_RATE_GEN2 };
        bins b_gen3           = { `PCIe_RATE_GEN3 };
        bins b_gen4           = { `PCIe_RATE_GEN4 };
        bins b_gen5           = { `PCIe_RATE_GEN5 };
        bins b_gen6           = { `PCIe_RATE_GEN6 };
        ignore_bins b_rsvd    = { 3'b111 };
      }

      //======================================================================
      // TL RX : Completions the RC receives   (data = rc_rx_tl_item)
      //======================================================================
      // Cpl (0Ah, no data : writes, UR) / CplD (4Ah, with data : reads)
      tl_rx_cpl_type : coverpoint rc_rx_tl_item.cpl_has_data iff (src == TL_RX) {
                                     bins b_cpl  = { 1'b0 };
                                     bins b_cpld = { 1'b1 };
                                    }
      // Completion Status (OHC-A5 [2:0], SC when no OHC-A5)
      //   SC : normal, UR : config access to a register / function that does not exist
      tl_rx_status : coverpoint rc_rx_tl_item.cpl_status iff (src == TL_RX) {
                                     bins b_sc = { 3'b000 };   // `PCIe_CPL_STATUS_SC : Successful Completion
                                     bins b_ur = { 3'b001 };   // `PCIe_CPL_STATUS_UR : Unsupported Request
                                     ignore_bins b_crs_ca = { 3'b010, 3'b100 };   // `PCIe_CPL_STATUS_CRS / `PCIe_CPL_STATUS_CA : EP never returns them
                                     ignore_bins b_rsvd   = { 3'b011, 3'b101, 3'b110, 3'b111 };              // reserved encodings
                                    }
      // OHC (DW0[20:16]) : a Completion can only carry OHC-A5
      //   OHC-A5 is added when status != SC or Lower Address[1:0] != 00
      tl_rx_ohc : coverpoint rc_rx_tl_item.ohc iff (src == TL_RX) {
                                     bins ohc_none = { 5'b00000 };   // SC and DW aligned : no OHC
                                     bins ohcA5    = { 5'b00001 };   // OHC-A5 (status + Lower Address[1:0])
                                     ignore_bins b_ohc_bce = { [5'b00010 : 5'b11111] };   // OHC-B/C/E not supported
                                    }
      // Length (DW0[9:0]) of a CplD : read of 1 DW, random 2..32 DW, and the
      // parts of a 1024 DW read split over several FLITs (max 56 DW each)
      tl_rx_length : coverpoint rc_rx_tl_item.length iff (src == TL_RX && rc_rx_tl_item.cpl_has_data) {
                                     bins b_len_1     = { 1 };
                                     bins b_len_2_32  = { [2:32] };
                                     bins b_len_33_56 = { [33:56] };
                                     ignore_bins b_len_other = { 0, [57:1023] };   // a CplD never carries more than one FLIT
                                    }
      // Byte Count (DW2[11:0]) : bytes still to be returned (0 encodes 4096)
      tl_rx_byte_count : coverpoint rc_rx_tl_item.byte_count iff (src == TL_RX) {
                                     bins b_bc_1_4      = { [1:4]      };   // 1 DW access, IO / CFG
                                     bins b_bc_5_128    = { [5:128]    };   // random 2..32 DW reads
                                     bins b_bc_129_4095 = { [129:4095] };   // later parts of a 1024 DW read
                                     bins b_bc_4096     = { 0 };            // first part of a 1024 DW read
                                    }
      // Lower Address = {DW1[14], DW2[15:12], OHC-A5 [4:3]}
      tl_rx_lower_addr : coverpoint rc_rx_tl_item.lower_address iff (src == TL_RX) {
                                     bins b_la_0     = { 0 };         // DW aligned start
                                     bins b_la_1_3   = { [1:3] };     // first_dw_be != 1111 (needs OHC-A5)
                                     bins b_la_4_127 = { [4:127] };   // parts of a split read
                                    }
      // TC / Attr / TS / EP : copied by the EP from the request
      tl_rx_tc : coverpoint rc_rx_tl_item.tc iff (src == TL_RX) {
                                     bins b_tc0 = { 0 };
                                     ignore_bins b_tc_1_7 = { [1:7] };
                                    }
      tl_rx_attr : coverpoint rc_rx_tl_item.attr iff (src == TL_RX) {
                                     bins b_attr_000 = { 3'b000 };
                                     bins b_attr_110 = { 3'b110 };
                                     ignore_bins b_attr_other = { 3'b001, 3'b010, 3'b011, 3'b100, 3'b101, 3'b111 };
                                    }
      tl_rx_ts : coverpoint rc_rx_tl_item.ts iff (src == TL_RX) {
                                     bins b_no_trailer = { 3'b000 };   // `PCIe_TL_TS_NO_TRAILER : no trailer
                                     ignore_bins b_ts_other = { [3'b001 : 3'b111] };   // EP never adds ECRC to a Completion
                                    }
      tl_rx_ep : coverpoint rc_rx_tl_item.ep iff (src == TL_RX) {
                                     bins b_ep0 = { 1'b0 };
                                     ignore_bins b_ep1 = { 1'b1 };
                                    }
      // Tag (DW1[13:0]) : copied from the request
      tl_rx_tag : coverpoint rc_rx_tl_item.tag iff (src == TL_RX) {
                                     bins b_tag_0_255    = { [0:255]    };
                                     bins b_tag_256_1023 = { [256:1023] };
                                    }
      // Requester ID (DW2[31:16], Destination BDF) : copied from the request
      tl_rx_requester_id : coverpoint rc_rx_tl_item.requester_id iff (src == TL_RX) {
                                     bins b_rid_0000 = { 16'h0000 };
                                     bins b_rid_0100 = { 16'h0100 };
                                     bins b_rid_0200 = { 16'h0200 };
                                     ignore_bins b_rid_other = { [16'h0001 : 16'h00FF], [16'h0101 : 16'h01FF],
                                                                 [16'h0201 : 16'hFFFF] };
                                    }
      // Completer ID (DW1[31:16]) : the EP model always uses `PCIe_TL_CPL_COMPLETER_ID = 16'h0100
      tl_rx_completer_id : coverpoint rc_rx_tl_item.completer_id iff (src == TL_RX) {
                                     bins b_cplr_ep = { 16'b0000_0001_0000_0000 };   // `PCIe_TL_CPL_COMPLETER_ID (0100h)
                                     ignore_bins b_cplr_other = { [16'b0000_0000_0000_0000 : 16'b0000_0000_1111_1111],
                                                                  [16'b0000_0001_0000_0001 : 16'b1111_1111_1111_1111] };
                                    }
      //-------------------------------------------------------------------
      // Crosses
      //-------------------------------------------------------------------
      // Cpl / CplD with every status (a UR Completion never carries data)
      tl_rx_cx_type_status : cross tl_rx_cpl_type, tl_rx_status iff (src == TL_RX) {
                               ignore_bins b_cpld_ur = binsof(tl_rx_cpl_type.b_cpld) && binsof(tl_rx_status.b_ur);
                             }
      // Cpl / CplD with and without OHC-A5
      tl_rx_cx_type_ohc : cross tl_rx_cpl_type, tl_rx_ohc iff (src == TL_RX) ;

      //======================================================================
      // DL RX : DLP of the flits the RC receives   (data = rc_rx_dl_item)
      //======================================================================
      // DLP0[7:6] Flit Usage
      dl_rx_usage : coverpoint rc_rx_dl_item.dl_flit_usage iff (src == DL_RX && rc_rx_dl_item.is_valid) {
                          bins b_nop_idle = { 2'b00 };   // NOP / IDLE flit
                          bins b_payload  = { 2'b01 };   // TLP flit
                          ignore_bins b_rsvd = { 2'b10, 2'b11 };
                        }
      // DLP0[5] Prior Flit was Payload
      dl_rx_prior_pay : coverpoint rc_rx_dl_item.dl_prior_pay iff (src == DL_RX && rc_rx_dl_item.is_valid) {
                          bins b_no  = { 1'b0 };
                          bins b_yes = { 1'b1 };
                        }
      // DLP0[4] Type of DLLP Payload
      dl_rx_dllp_pay_type : coverpoint rc_rx_dl_item.dl_dllp_pay_type iff (src == DL_RX && rc_rx_dl_item.is_valid) {
                          bins        b_dllp       = { 1'b0 };   // normal DLLP in DLP2..5
                          ignore_bins b_ouf_marker = { 1'b1 };   // Optimized_Update_FC / Flit_Marker : not generated
                        }
      // DLP0[3:2] Replay Command
      dl_rx_replay_cmd : coverpoint rc_rx_dl_item.dl_replay_cmd iff (src == DL_RX && rc_rx_dl_item.is_valid) {
                          bins b_explicit_seq = { 2'b00 };   // flit carries its own sequence number
                          bins b_ack          = { 2'b01 };   // Ack
                          // NAKs only come after a bad flit : change to bins when an error-injection test exists
                          ignore_bins b_std_nak = { 2'b10 };
                          ignore_bins b_sel_nak = { 2'b11 };
                        }
      // DLP0[1:0] + DLP1 Flit Sequence Number
      dl_rx_seq : coverpoint rc_rx_dl_item.dl_seq_num iff (src == DL_RX && rc_rx_dl_item.is_valid) {
                          bins b_seq_0     = { 10'b00_0000_0000 };                          // IDLE flit
                          bins b_seq_1_15  = { [10'b00_0000_0001 : 10'b00_0000_1111] };
                          bins b_seq_16_up = { [10'b00_0001_0000 : 10'b11_1111_1111] };
                        }
      // DLP2 DLLP Type byte (spec Table 3-5)
      dl_rx_dllp_type : coverpoint rc_rx_dl_item.dl_dllp_type iff (src == DL_RX && rc_rx_dl_item.is_valid) {
                          bins b_nop2       = { 8'b0000_0000 };   // NOP2
                          bins b_feature    = { 8'b0000_0001 };   // model FEATURE_DLLP (spec : 8'b0000_0010)
                          bins b_initfc1[]  = { 8'b0100_0000,      // P   shared
                                                8'b0100_1000,      // P   dedicated
                                                8'b0101_0000,      // NP  shared
                                                8'b0101_1000,      // NP  dedicated
                                                8'b0110_0000,      // Cpl shared
                                                8'b0110_1000 };    // Cpl dedicated
                          bins b_initfc2[]  = { 8'b1100_0000,      // P   shared
                                                8'b1100_1000,      // P   dedicated
                                                8'b1101_0000,      // NP  shared
                                                8'b1101_1000,      // NP  dedicated
                                                8'b1110_0000,      // Cpl shared
                                                8'b1110_1000 };    // Cpl dedicated
                          // UpdateFC : one bin for any class (sent only after many TLPs or every 30 us)
                          bins b_updatefc   = { 8'b1000_0000, 8'b1000_1000, 8'b1001_0000,
                                                8'b1001_1000, 8'b1010_0000, 8'b1010_1000 };
                        }
      // DLP2..DLP5 FC DLLP fields
      dl_rx_fc_type : coverpoint rc_rx_dl_item.dl_fc_type iff (src == DL_RX && rc_rx_dl_item.is_valid && rc_rx_dl_item.dl_is_fc) {
                          bins b_initfc1  = { 2'b01 };
                          bins b_initfc2  = { 2'b11 };
                          bins b_updatefc = { 2'b10 };
                        }
      dl_rx_fc_cls : coverpoint rc_rx_dl_item.dl_fc_cls iff (src == DL_RX && rc_rx_dl_item.is_valid && rc_rx_dl_item.dl_is_fc) {
                          bins b_p   = { 2'b00 };
                          bins b_np  = { 2'b01 };
                          bins b_cpl = { 2'b10 };
                        }
      dl_rx_fc_shared : coverpoint rc_rx_dl_item.dl_fc_shared iff (src == DL_RX && rc_rx_dl_item.is_valid && rc_rx_dl_item.dl_is_fc) {
                          bins b_dedicated = { 1'b0 };
                          bins b_shared    = { 1'b1 };
                        }
      dl_rx_fc_vc : coverpoint rc_rx_dl_item.dl_fc_vc iff (src == DL_RX && rc_rx_dl_item.is_valid && rc_rx_dl_item.dl_is_fc) {
                          bins        b_vc0    = { 3'b000 };
                          ignore_bins b_vc_1_7 = { [3'b001 : 3'b111] };   // only VC0 enabled
                        }
      dl_rx_fc_scale : coverpoint { rc_rx_dl_item.dl_fc_hscale, rc_rx_dl_item.dl_fc_dscale } iff (src == DL_RX && rc_rx_dl_item.is_valid && rc_rx_dl_item.dl_is_fc) {
                          bins        b_1x_1x = { 4'b0101 };   // HdrScale = DataScale = 01b (model always)
                          ignore_bins b_other = { [4'b0000 : 4'b0100], [4'b0110 : 4'b1111] };
                        }
      // every InitFC round = 6 DLLPs : P / NP / Cpl x dedicated / shared
      dl_rx_fc_init_round : cross dl_rx_fc_type, dl_rx_fc_cls, dl_rx_fc_shared iff (src == DL_RX) {
                          ignore_bins b_updatefc = binsof(dl_rx_fc_type.b_updatefc);   // UpdateFC is covered in dl_rx_dllp_type
                        }

      //======================================================================
      // PL RX : PIPE RX status pins of the RC   (data = rc_rx_item from the RC controller monitor, cov_dir = RX)
      //======================================================================
      pl_rx_valid : coverpoint rc_rx_item.rx_valid iff (src == PL_RX) {
        bins b_inactive = { 1'b0 };
        bins b_active   = { 1'b1 };
      }
      pl_rx_elec_idle : coverpoint rc_rx_item.rx_elec_idle iff (src == PL_RX) {
        bins b_inactive = { 1'b0 };
        bins b_active   = { 1'b1 };
      }
      // The PHY BFM only produces RxStatus 000 (OK) and 011 (receiver detected).
      // 001/010/101/110 are elastic-buffer SKP/overflow/underflow and 100/111 are
      // 8b/10b decode/disparity errors - none exist on a Gen6 (128b/130b + FLIT)
      // link or in this BFM, so they are waived rather than counted as holes.
      pl_rx_status : coverpoint rc_rx_item.rx_status iff (src == PL_RX) {
        bins b_ok           = { 3'b000 };
        bins b_rx_detected  = { 3'b011 };
        ignore_bins b_not_modelled = { 3'b001, 3'b010, [3'b100 : 3'b111] };
      }
      pl_rx_phy_status : coverpoint rc_rx_item.phy_status iff (src == PL_RX) {
        bins b_deasserted = { 1'b0 };
        bins b_asserted   = { 1'b1 };
      }
  

      //======================================================================
      // DL STATE : RC DLCMSM states (sampled when the state changes)
      //======================================================================
      dl_st_state : coverpoint rc_dl.DL_STATE iff (src == DL_STATE) {
                          bins b_inactive = { DL_INACTIVE };
                          bins b_feature  = { DL_FEATURE  };
                          bins b_init     = { DL_INIT     };
                          bins b_active   = { DL_ACTIVE   };
                        }
      dl_st_init_sub : coverpoint rc_dl.dl_init_substate iff (src == DL_STATE && rc_dl.DL_STATE == DL_INIT) {
                          bins b_fc1 = { INIT_FC1 };
                          bins b_fc2 = { INIT_FC2 };
                        }
      dl_st_link_active : coverpoint rc_dl.dl_link_active iff (src == DL_STATE) {
                          bins b_down = { 1'b0 };
                          bins b_up   = { 1'b1 };
                        }
      // state order : INACTIVE -> FEATURE -> INIT -> ACTIVE
      dl_st_trans : coverpoint rc_dl.DL_STATE iff (src == DL_STATE) {
                          bins b_inact_feat = ( DL_INACTIVE => DL_FEATURE );
                          bins b_feat_init  = ( DL_FEATURE  => DL_INIT    );
                          bins b_init_act   = ( DL_INIT     => DL_ACTIVE  );
                        }

   endgroup : rc_cg

   covergroup ep_cg with function sample(cov_src_e src);
      option.per_instance = 1;

      //======================================================================
      // PL TX : PIPE TX control pins of the EP   (data = ep_tx_item from the EP controller monitor, cov_dir = TX)
      //======================================================================
      pl_tx_valid : coverpoint ep_tx_item.tx_valid iff (src == PL_TX) {
        bins b_inactive = { 1'b0 };
        bins b_active   = { 1'b1 };
      }
      pl_tx_elec_idle : coverpoint ep_tx_item.tx_elec_idle iff (src == PL_TX) {
        bins b_inactive = { 1'b0 };
        bins b_active   = { 1'b1 };
      }
      pl_tx_detect_rx : coverpoint ep_tx_item.tx_detect_rx iff (src == PL_TX) {
        bins b_inactive = { 1'b0 };
        bins b_active   = { 1'b1 };
      }
      // PL models only ever drive P0 today (powerdown is never assigned in the
      // RC/EP PL models). P1..P3 are waived until the PL model drives them;
      // compile with +define+PCIE_COV_POWERDOWN_FULL to bring them back as targets.
      pl_tx_powerdown : coverpoint ep_tx_item.powerdown iff (src == PL_TX) {
        bins b_p0 = { 2'b00 };
`ifdef PCIE_COV_POWERDOWN_FULL
        bins b_p1 = { 2'b01 };
        bins b_p2 = { 2'b10 };
        bins b_p3 = { 2'b11 };
`else
        ignore_bins b_p1_p3_not_driven = { [2'b01 : 2'b11] };
`endif
      }
      pl_tx_rate : coverpoint ep_tx_item.rate iff (src == PL_TX) {
        bins b_not_negotiated = { `PCIe_RATE_NOT_NEGOTIATED };
        bins b_gen1           = { `PCIe_RATE_GEN1 };
        bins b_gen2           = { `PCIe_RATE_GEN2 };
        bins b_gen3           = { `PCIe_RATE_GEN3 };
        bins b_gen4           = { `PCIe_RATE_GEN4 };
        bins b_gen5           = { `PCIe_RATE_GEN5 };
        bins b_gen6           = { `PCIe_RATE_GEN6 };
        ignore_bins b_rsvd    = { 3'b111 };
      }

      //======================================================================
      // TL RX : Requests the EP receives   (data = ep_rx_tl_item)
      //======================================================================
      // Transaction type : decoded from the Flit Type byte (DW0[31:24])
      tl_rx_txn_type : coverpoint ep_rx_tl_item.txn_type iff (src == TL_RX) {
                                     bins b_mem = { PCIe_TL_MEM };
                                     bins b_io  = { PCIe_TL_IO  };
                                     bins b_cfg = { PCIe_TL_CFG };
                                     bins b_msg = { PCIe_TL_MSG };
                                     ignore_bins b_cpl = { PCIe_TL_CPL };   // the RC never sends a Completion
                                    }
      // Read / Write : decoded from the Flit Type byte
      tl_rx_dir : coverpoint ep_rx_tl_item.dir iff (src == TL_RX) {
                                     bins b_read  = { PCIe_TL_READ  };
                                     bins b_write = { PCIe_TL_WRITE };
                                    }
      // Flit Type (DW0[31:24]) : every request type used by the FLIT sequences
      // 32-bit types : 3DW tests (default compile), 64-bit types : 4DW tests (+FORCE_4DW)
      tl_rx_flit_type : coverpoint ep_rx_tl_item.get_flit_type() iff (src == TL_RX) {
                                     bins b_mrd_32   = { PCIe_FLITTYPE_MRD_32   };
                                     bins b_mrd_64   = { PCIe_FLITTYPE_MRD_64   };
                                     bins b_mrdlk_32 = { PCIe_FLITTYPE_MRDLK_32 };
                                     bins b_mrdlk_64 = { PCIe_FLITTYPE_MRDLK_64 };
                                     bins b_mwr_32   = { PCIe_FLITTYPE_MWR_32   };
                                     bins b_mwr_64   = { PCIe_FLITTYPE_MWR_64   };
                                     bins b_dmwr_32  = { PCIe_FLITTYPE_DMWR_32  };
                                     bins b_dmwr_64  = { PCIe_FLITTYPE_DMWR_64  };
                                     bins b_iord     = { PCIe_FLITTYPE_IORD     };
                                     bins b_iowr     = { PCIe_FLITTYPE_IOWR     };
                                     bins b_cfgrd0   = { PCIe_FLITTYPE_CFGRD0   };
                                     bins b_cfgwr0   = { PCIe_FLITTYPE_CFGWR0   };
                                     bins b_cfgrd1   = { PCIe_FLITTYPE_CFGRD1   };
                                     bins b_cfgwr1   = { PCIe_FLITTYPE_CFGWR1   };
                                     bins b_msg      = { PCIe_FLITTYPE_MSG      };
                                     bins b_msgd     = { PCIe_FLITTYPE_MSGD     };
                                     // Atomics are not generated by any sequence
                                     ignore_bins b_atomic = { PCIe_FLITTYPE_FETCHADD_32, PCIe_FLITTYPE_FETCHADD_64,
                                                              PCIe_FLITTYPE_SWAP_32,     PCIe_FLITTYPE_SWAP_64,
                                                              PCIe_FLITTYPE_CAS_32,      PCIe_FLITTYPE_CAS_64 };
                                    }
      // Length (DW0[9:0]) of MEM requests. 0 encodes 1024 DW.
      //   MinPayload = 1, fixed = 2, Random = 2..32, MaxPayload write = 1024 DW
      //   split into FLIT segments of max 56 DW, MaxPayload read = 1024 (one TLP)
      tl_rx_mem_length : coverpoint ep_rx_tl_item.length iff (src == TL_RX && ep_rx_tl_item.txn_type == PCIe_TL_MEM) {
                                     bins b_len_1     = { 1 };
                                     bins b_len_2     = { 2 };
                                     bins b_len_3_32  = { [3:32] };
                                     bins b_len_33_56 = { [33:56] };   // MaxPayload write segments
                                     bins b_len_1024  = { 0 };         // MaxPayload read
                                     ignore_bins b_len_57_1023 = { [57:1023] };   // not generated
                                    }
      // Length of IO / CFG requests : always 1 DW
      tl_rx_io_cfg_length : coverpoint ep_rx_tl_item.length
                               iff (src == TL_RX && ep_rx_tl_item.txn_type inside {PCIe_TL_IO, PCIe_TL_CFG}) {
                                     bins b_len_1 = { 1 };
                                     ignore_bins b_len_other = { 0, [2:1023] };   // illegal for IO / CFG
                                    }
      // TC (DW0[23:21]) : sequences constrain tc == 0
      tl_rx_tc : coverpoint ep_rx_tl_item.tc iff (src == TL_RX) {
                                     bins b_tc0 = { 0 };
                                     ignore_bins b_tc_1_7 = { [1:7] };   // not generated
                                    }
      // Attr (DW0[12:10]) = {IDO, RO, NS} : sequences use 000 and 110
      tl_rx_attr : coverpoint ep_rx_tl_item.attr iff (src == TL_RX) {
                                     bins b_attr_000 = { 3'b000 };
                                     bins b_attr_110 = { 3'b110 };   // IDO + RO
                                     ignore_bins b_attr_other = { 3'b001, 3'b010, 3'b011, 3'b100, 3'b101, 3'b111 };
                                    }
      // TS (DW0[15:13]) : 000 = no trailer, 001 = 1 DW ECRC (PCIe_RC_3DW_flit_sequence)
      tl_rx_ts : coverpoint ep_rx_tl_item.ts iff (src == TL_RX) {
                                     bins b_no_trailer = { 3'b000 };   // `PCIe_TL_TS_NO_TRAILER : no trailer
                                     bins b_ecrc_1dw   = { 3'b001 };   // `PCIe_TL_TS_1DW_ECRC   : 1 DW ECRC trailer
                                     ignore_bins b_ts_other = { [3'b010 : 3'b111] };   // not generated
                                    }
      // OHC kind = { OHC-A bit (DW0[16]) , txn_type (4 bits) }
      //   first bit  : 1 = OHC-A present, 0 = no OHC
      //   next 4 bits: txn_type  0000 = MEM, 0001 = IO, 0010 = CFG, 0011 = MSG, 0100 = CPL
      //   OHC-A + MEM -> OHC-A1, + IO -> OHC-A2, + CFG -> OHC-A3, + MSG -> OHC-A4
      //   (OHC-B / C / E are never sent : constraint ohc[4:1] == 0)
      tl_rx_ohc : coverpoint { ep_rx_tl_item.ohc[0], ep_rx_tl_item.txn_type } iff (src == TL_RX) {
                                     bins ohc_none = { 5'b0_0000 };   // MEM, all BEs 1111 : no OHC
                                     bins ohcA1    = { 5'b1_0000 };   // MEM + OHC-A1 (BEs not all 1111)
                                     bins ohcA2    = { 5'b1_0001 };   // IO  + OHC-A2
                                     bins ohcA3    = { 5'b1_0010 };   // CFG + OHC-A3
                                     bins ohcA4    = { 5'b1_0011 };   // MSG + OHC-A4
                                     ignore_bins b_not_possible = { 5'b0_0001, 5'b0_0010, 5'b0_0011 };   // IO / CFG / MSG always carry OHC-A
                                     ignore_bins b_cpl          = { 5'b0_0100, 5'b1_0100 };              // the EP never receives a Completion
                                     ignore_bins b_rsvd_type    = { [5'b0_0101 : 5'b0_1111], [5'b1_0101 : 5'b1_1111] };   // unused txn_type codes
                                    }
      // EP / poisoned (DW1[15]) : sequences constrain ep == 0
      tl_rx_ep : coverpoint ep_rx_tl_item.ep iff (src == TL_RX) {
                                     bins b_ep0 = { 1'b0 };
                                     ignore_bins b_ep1 = { 1'b1 };   // poisoned TLP not generated
                                    }
      // AT (MEM address bits [1:0]) : sequences constrain at == 0
      tl_rx_at : coverpoint ep_rx_tl_item.at iff (src == TL_RX && ep_rx_tl_item.txn_type == PCIe_TL_MEM) {
                                     bins b_at_00 = { 2'b00 };
                                     ignore_bins b_at_other = { 2'b01, 2'b10, 2'b11 };   // ATS not used
                                    }
      // First DW Byte Enable (First DW BE) : which bytes of the first DW are valid
      // MEM : no OHC when BE = 1111, OHC-A1 when BE != 1111
      //   1110 : PCIe_RC_3DW_flit_sequence
      tl_rx_mem_first_be : coverpoint ep_rx_tl_item.first_dw_be iff (src == TL_RX && ep_rx_tl_item.txn_type == PCIe_TL_MEM) {
                                     bins ohc_none = { 4'b1111 };   // no OHC  : all 4 bytes (implied)
                                     bins ohcA1    = { 4'b1110 };   // OHC-A1  : bytes 1,2,3
                                     ignore_bins b_be_other = { [4'b0000 : 4'b1101] };   // not generated
                                    }
      // IO : always OHC-A2, sequences use BE = 1111
      tl_rx_io_first_be : coverpoint ep_rx_tl_item.first_dw_be iff (src == TL_RX && ep_rx_tl_item.txn_type == PCIe_TL_IO) {
                                     bins ohcA2 = { 4'b1111 };   // OHC-A2 : all 4 bytes
                                     ignore_bins b_be_other = { [4'b0000 : 4'b1110] };   // not generated
                                    }
      // CFG : always OHC-A3
      //   1111 : CFG sequences, BAR sizing
      //   0011 : enumeration Command register write (do not touch Status)
      //   0001 : enumeration Interrupt Line write
      tl_rx_cfg_first_be : coverpoint ep_rx_tl_item.first_dw_be iff (src == TL_RX && ep_rx_tl_item.txn_type == PCIe_TL_CFG) {
                                     bins ohcA3_4bytes = { 4'b1111 };   // OHC-A3 : all 4 bytes
                                     bins ohcA3_2bytes = { 4'b0011 };   // OHC-A3 : bytes 0,1
                                     bins ohcA3_1byte  = { 4'b0001 };   // OHC-A3 : byte 0
                                     ignore_bins b_be_other = { 4'b0000, 4'b0010, [4'b0100 : 4'b1110] };   // not generated
                                    }
      // Last DW BE (OHC-A [7:4]) : F for multi-DW, 0 for 1 DW
      tl_rx_last_be : coverpoint ep_rx_tl_item.last_dw_be iff (src == TL_RX && ep_rx_tl_item.txn_type != PCIe_TL_MSG) {
                                     bins multi_dw = { 4'b1111 };
                                     bins one_dw = { 4'b0000 };
                                     ignore_bins b_be_other = { [4'b0001 : 4'b1110] };   // not generated
                                    }
      // Requester ID (DW1[31:16]) : 0100h (sequences), 0200h (random), 0000h (enumeration)
      tl_rx_requester_id : coverpoint ep_rx_tl_item.requester_id iff (src == TL_RX) {
                                     bins b_rid_0000 = { 16'h0000 };
                                     bins b_rid_0100 = { 16'h0100 };
                                     bins b_rid_0200 = { 16'h0200 };
                                     ignore_bins b_rid_other = { [16'h0001 : 16'h00FF], [16'h0101 : 16'h01FF],
                                                                 [16'h0201 : 16'hFFFF] };
                                    }
      // Tag (DW1[13:0]) : fixed 8-bit tags and random 10-bit tags
      tl_rx_tag : coverpoint ep_rx_tl_item.tag iff (src == TL_RX) {
                                     bins b_tag_0_255    = { [0:255]    };
                                     bins b_tag_256_1023 = { [256:1023] };
                                    }
      // Memory read lock / deferrable write (from the Flit Type)
      tl_rx_mem_locked     : coverpoint ep_rx_tl_item.mem_locked  
      				iff (src == TL_RX && ep_rx_tl_item.txn_type == PCIe_TL_MEM)
			       	{ bins b_vals[] = { 0, 1 }; }
      tl_rx_mem_deferrable : coverpoint ep_rx_tl_item.mem_deferrable
     				 iff (src == TL_RX && ep_rx_tl_item.txn_type == PCIe_TL_MEM) 
				 { bins b_vals[] = { 0, 1 }; }
      // CFG Type 0 / Type 1 (from the Flit Type)
      tl_rx_cfg_type : coverpoint ep_rx_tl_item.cfg_type1 iff (src == TL_RX && ep_rx_tl_item.txn_type == PCIe_TL_CFG) {
                                     bins b_type0 = { 1'b0 };
                                     bins b_type1 = { 1'b1 };
                                    }
      // CFG Bus / Device / Function (DW2[31:16]) : EP is Bus 1, Dev 0, Fn 0
      tl_rx_cfg_bus : coverpoint ep_rx_tl_item.cfg_bus_num iff (src == TL_RX && ep_rx_tl_item.txn_type == PCIe_TL_CFG) {
                                     bins b_bus_ep = { 8'b0000_0001 };   // `PCIe_EP_BUS_NUMBER = bus 1
                                     ignore_bins b_bus_other = { 8'b0000_0000, [8'b0000_0010 : 8'b1111_1111] };
                                    }
      tl_rx_cfg_dev : coverpoint ep_rx_tl_item.cfg_dev_num iff (src == TL_RX && ep_rx_tl_item.txn_type == PCIe_TL_CFG) {
                                     bins b_dev0 = { 0 };
                                     ignore_bins b_dev_1_31 = { [1:31] };   // single device on the link
                                    }
      tl_rx_cfg_fn : coverpoint ep_rx_tl_item.cfg_fn_num iff (src == TL_RX && ep_rx_tl_item.txn_type == PCIe_TL_CFG) {
                                     bins b_fn0 = { 0 };
                                     ignore_bins b_fn_1_7 = { [1:7] };   // only scanned when the EP is multi-function
                                    }
      // CFG Register (DW2[11:2], byte offset) : header 00h-3Ch, capabilities 40h-FCh
      tl_rx_cfg_reg : coverpoint ep_rx_tl_item.cfg_reg_num iff (src == TL_RX && ep_rx_tl_item.txn_type == PCIe_TL_CFG) {
                                     bins b_reg_header = { [12'h000 : 12'h03C] };
                                     bins b_reg_cap    = { [12'h040 : 12'h0FC] };
                                     ignore_bins b_reg_ext = { [12'h100 : 12'hFFC] };   // not reachable with CF8/CFC
                                    }
      // Message Code (DW1[7:0]) : 00h and 7Eh (Vendor Defined Type 0)
      tl_rx_msg_code : coverpoint ep_rx_tl_item.msg_code iff (src == TL_RX && ep_rx_tl_item.txn_type == PCIe_TL_MSG) {
                                     bins b_code_00 = { 8'h00 };
                                     bins b_code_7e = { 8'h7E };
                                     ignore_bins b_code_other = { [8'h01 : 8'h7D], [8'h7F : 8'hFF] };
                                    }
      tl_rx_msg_has_data : coverpoint ep_rx_tl_item.msg_has_data iff (src == TL_RX && ep_rx_tl_item.txn_type == PCIe_TL_MSG) {
                                     bins b_msg  = { 1'b0 };
                                     bins b_msgd = { 1'b1 };
                                    }
      //-------------------------------------------------------------------
      // Crosses
      //-------------------------------------------------------------------
      // every transaction type with read and write (a Message is always a write)
      tl_rx_cx_type_dir : cross tl_rx_txn_type, tl_rx_dir iff (src == TL_RX) {
                            ignore_bins b_msg_read = binsof(tl_rx_txn_type.b_msg) && binsof(tl_rx_dir.b_read);
                          }
      // MEM read / write with every length
      tl_rx_cx_mem_dir_len : cross tl_rx_dir, tl_rx_mem_length iff (src == TL_RX) {
                               ignore_bins b_write_1024 = binsof(tl_rx_dir.b_write) && binsof(tl_rx_mem_length.b_len_1024);   // writes are split
                               ignore_bins b_read_33_56 = binsof(tl_rx_dir.b_read)  && binsof(tl_rx_mem_length.b_len_33_56); // reads are 1..32 or 1024
                             }
      // CFG Type 0 / Type 1 with read and write
      tl_rx_cx_cfg_type_dir : cross tl_rx_cfg_type, tl_rx_dir iff (src == TL_RX) ;

      //======================================================================
      // DL RX : DLP of the flits the EP receives   (data = ep_rx_dl_item)
      //======================================================================
      // DLP0[7:6] Flit Usage
      dl_rx_usage : coverpoint ep_rx_dl_item.dl_flit_usage iff (src == DL_RX && ep_rx_dl_item.is_valid) {
                          bins b_nop_idle = { 2'b00 };   // NOP / IDLE flit
                          bins b_payload  = { 2'b01 };   // TLP flit
                          ignore_bins b_rsvd = { 2'b10, 2'b11 };
                        }
      // DLP0[5] Prior Flit was Payload
      dl_rx_prior_pay : coverpoint ep_rx_dl_item.dl_prior_pay iff (src == DL_RX && ep_rx_dl_item.is_valid) {
                          bins b_no  = { 1'b0 };
                          bins b_yes = { 1'b1 };
                        }
      // DLP0[4] Type of DLLP Payload
      dl_rx_dllp_pay_type : coverpoint ep_rx_dl_item.dl_dllp_pay_type iff (src == DL_RX && ep_rx_dl_item.is_valid) {
                          bins        b_dllp       = { 1'b0 };   // normal DLLP in DLP2..5
                          ignore_bins b_ouf_marker = { 1'b1 };   // Optimized_Update_FC / Flit_Marker : not generated
                        }
      // DLP0[3:2] Replay Command
      dl_rx_replay_cmd : coverpoint ep_rx_dl_item.dl_replay_cmd iff (src == DL_RX && ep_rx_dl_item.is_valid) {
                          bins b_explicit_seq = { 2'b00 };   // flit carries its own sequence number
                          bins b_ack          = { 2'b01 };   // Ack
                          // NAKs only come after a bad flit : change to bins when an error-injection test exists
                          ignore_bins b_std_nak = { 2'b10 };
                          ignore_bins b_sel_nak = { 2'b11 };
                        }
      // DLP0[1:0] + DLP1 Flit Sequence Number
      dl_rx_seq : coverpoint ep_rx_dl_item.dl_seq_num iff (src == DL_RX && ep_rx_dl_item.is_valid) {
                          bins b_seq_0     = { 10'b00_0000_0000 };                          // IDLE flit
                          bins b_seq_1_15  = { [10'b00_0000_0001 : 10'b00_0000_1111] };
                          bins b_seq_16_up = { [10'b00_0001_0000 : 10'b11_1111_1111] };
                        }
      // DLP2 DLLP Type byte (spec Table 3-5)
      dl_rx_dllp_type : coverpoint ep_rx_dl_item.dl_dllp_type iff (src == DL_RX && ep_rx_dl_item.is_valid) {
                          bins b_nop2       = { 8'b0000_0000 };   // NOP2
                          bins b_feature    = { 8'b0000_0001 };   // model FEATURE_DLLP (spec : 8'b0000_0010)
                          bins b_initfc1[]  = { 8'b0100_0000,      // P   shared
                                                8'b0100_1000,      // P   dedicated
                                                8'b0101_0000,      // NP  shared
                                                8'b0101_1000,      // NP  dedicated
                                                8'b0110_0000,      // Cpl shared
                                                8'b0110_1000 };    // Cpl dedicated
                          bins b_initfc2[]  = { 8'b1100_0000,      // P   shared
                                                8'b1100_1000,      // P   dedicated
                                                8'b1101_0000,      // NP  shared
                                                8'b1101_1000,      // NP  dedicated
                                                8'b1110_0000,      // Cpl shared
                                                8'b1110_1000 };    // Cpl dedicated
                          // UpdateFC : one bin for any class (sent only after many TLPs or every 30 us)
                          bins b_updatefc   = { 8'b1000_0000, 8'b1000_1000, 8'b1001_0000,
                                                8'b1001_1000, 8'b1010_0000, 8'b1010_1000 };
                        }
      // DLP2..DLP5 FC DLLP fields
      dl_rx_fc_type : coverpoint ep_rx_dl_item.dl_fc_type iff (src == DL_RX && ep_rx_dl_item.is_valid && ep_rx_dl_item.dl_is_fc) {
                          bins b_initfc1  = { 2'b01 };
                          bins b_initfc2  = { 2'b11 };
                          bins b_updatefc = { 2'b10 };
                        }
      dl_rx_fc_cls : coverpoint ep_rx_dl_item.dl_fc_cls iff (src == DL_RX && ep_rx_dl_item.is_valid && ep_rx_dl_item.dl_is_fc) {
                          bins b_p   = { 2'b00 };
                          bins b_np  = { 2'b01 };
                          bins b_cpl = { 2'b10 };
                        }
      dl_rx_fc_shared : coverpoint ep_rx_dl_item.dl_fc_shared iff (src == DL_RX && ep_rx_dl_item.is_valid && ep_rx_dl_item.dl_is_fc) {
                          bins b_dedicated = { 1'b0 };
                          bins b_shared    = { 1'b1 };
                        }
      dl_rx_fc_vc : coverpoint ep_rx_dl_item.dl_fc_vc iff (src == DL_RX && ep_rx_dl_item.is_valid && ep_rx_dl_item.dl_is_fc) {
                          bins        b_vc0    = { 3'b000 };
                          ignore_bins b_vc_1_7 = { [3'b001 : 3'b111] };   // only VC0 enabled
                        }
      dl_rx_fc_scale : coverpoint { ep_rx_dl_item.dl_fc_hscale, ep_rx_dl_item.dl_fc_dscale } iff (src == DL_RX && ep_rx_dl_item.is_valid && ep_rx_dl_item.dl_is_fc) {
                          bins        b_1x_1x = { 4'b0101 };   // HdrScale = DataScale = 01b (model always)
                          ignore_bins b_other = { [4'b0000 : 4'b0100], [4'b0110 : 4'b1111] };
                        }
      // every InitFC round = 6 DLLPs : P / NP / Cpl x dedicated / shared
      dl_rx_fc_init_round : cross dl_rx_fc_type, dl_rx_fc_cls, dl_rx_fc_shared iff (src == DL_RX) {
                          ignore_bins b_updatefc = binsof(dl_rx_fc_type.b_updatefc);   // UpdateFC is covered in dl_rx_dllp_type
                        }

      //======================================================================
      // PL RX : PIPE RX status pins of the EP   (data = ep_rx_item from the EP controller monitor, cov_dir = RX)
      //======================================================================
      pl_rx_valid : coverpoint ep_rx_item.rx_valid iff (src == PL_RX) {
        bins b_inactive = { 1'b0 };
        bins b_active   = { 1'b1 };
      }
      pl_rx_elec_idle : coverpoint ep_rx_item.rx_elec_idle iff (src == PL_RX) {
        bins b_inactive = { 1'b0 };
        bins b_active   = { 1'b1 };
      }
      // The PHY BFM only produces RxStatus 000 (OK) and 011 (receiver detected).
      // 001/010/101/110 are elastic-buffer SKP/overflow/underflow and 100/111 are
      // 8b/10b decode/disparity errors - none exist on a Gen6 (128b/130b + FLIT)
      // link or in this BFM, so they are waived rather than counted as holes.
      pl_rx_status : coverpoint ep_rx_item.rx_status iff (src == PL_RX) {
        bins b_ok           = { 3'b000 };
        bins b_rx_detected  = { 3'b011 };
        ignore_bins b_not_modelled = { 3'b001, 3'b010, [3'b100 : 3'b111] };
      }
      pl_rx_phy_status : coverpoint ep_rx_item.phy_status iff (src == PL_RX) {
        bins b_deasserted = { 1'b0 };
        bins b_asserted   = { 1'b1 };
      }
  

      //======================================================================
      // DL STATE : EP DLCMSM states (sampled when the state changes)
      //======================================================================
      dl_st_state : coverpoint ep_dl.DL_STATE iff (src == DL_STATE) {
                          bins b_inactive = { DL_INACTIVE };
                          bins b_feature  = { DL_FEATURE  };
                          bins b_init     = { DL_INIT     };
                          bins b_active   = { DL_ACTIVE   };
                        }
      dl_st_init_sub : coverpoint ep_dl.dl_init_substate iff (src == DL_STATE && ep_dl.DL_STATE == DL_INIT) {
                          bins b_fc1 = { INIT_FC1 };
                          bins b_fc2 = { INIT_FC2 };
                        }
      dl_st_link_active : coverpoint ep_dl.dl_link_active iff (src == DL_STATE) {
                          bins b_down = { 1'b0 };
                          bins b_up   = { 1'b1 };
                        }
      dl_st_trans : coverpoint ep_dl.DL_STATE iff (src == DL_STATE) {
                          bins b_inact_feat = ( DL_INACTIVE => DL_FEATURE );
                          bins b_feat_init  = ( DL_FEATURE  => DL_INIT    );
                          bins b_init_act   = ( DL_INIT     => DL_ACTIVE  );
                        }

   endgroup : ep_cg


   function new(string name="PCIe_subscriber",uvm_component parent);
     super.new(name,parent);
      rc_export = new("rc_export", this);   // [PL_COV]
      ep_export = new("ep_export", this);   // [PL_COV]
      rc_cg = new();   // [COV_2CG] RC : TL / DL / PL  TX + RX
      ep_cg = new();   // [COV_2CG] EP : TL / DL / PL  TX + RX
   endfunction

function void build_phase(uvm_phase phase);
     `uvm_info("PCIe_SUBSCRIBER","ENTERED_INTO_SUB_BUILD_PHASE",UVM_LOW)
      super.build_phase(phase);
         pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item") ;
      // [COV_2CG] empty items so no handle is null before the first packet arrives
      rc_rx_tl_item = PCIe_sequence_item::type_id::create("rc_rx_tl_item");
      ep_rx_tl_item = PCIe_sequence_item::type_id::create("ep_rx_tl_item");
      rc_rx_dl_item = PCIe_sequence_item::type_id::create("rc_rx_dl_item");
      ep_rx_dl_item = PCIe_sequence_item::type_id::create("ep_rx_dl_item");
      rc_tx_item    = PCIe_sequence_item::type_id::create("rc_tx_item");   // [PL_COV]
      rc_rx_item    = PCIe_sequence_item::type_id::create("rc_rx_item");
      ep_tx_item    = PCIe_sequence_item::type_id::create("ep_tx_item");
      ep_rx_item    = PCIe_sequence_item::type_id::create("ep_rx_item");
      rc_rx_tl_imp = new("rc_rx_tl_imp", this);   // [TL_COV]
      ep_rx_tl_imp = new("ep_rx_tl_imp", this);   // [TL_COV]
      rc_rx_dl_imp = new("rc_rx_dl_imp", this);   // [DL_COV]
      ep_rx_dl_imp = new("ep_rx_dl_imp", this);   // [DL_COV]
      if (!uvm_config_db#(PCIe_env_config)::get(this, "", "PCIe_env_config", pcie_ecfg))
         `uvm_fatal("PCIe_SUBSCRIBER","Cannot_get_PCIe_env_config")
      void'(uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf));
      void'(uvm_config_db#(virtual PCIe_EP_interface)::get(this, "", "PCIe_EP_INTERFACE", ep_pipe_intf));
     `uvm_info("PCIe_SUBSCRIBER","EXIT_FROM_SUB_BUILD_PHASE",UVM_LOW)
    endfunction

   function void start_of_simulation_phase(uvm_phase phase);
     super.start_of_simulation_phase(phase);
     // [DL_COV] DL model handles (set in PCIe_environment.sv)
     if (!uvm_config_db#(PCIe_RC_DL_model)::get(this, "", "RC_DL_MODEL", rc_dl))
        `uvm_fatal("PCIe_SUBSCRIBER", "RC_DL_MODEL handle not found in config DB")
     if (!uvm_config_db#(PCIe_EP_DL_model)::get(this, "", "EP_DL_MODEL", ep_dl))
        `uvm_fatal("PCIe_SUBSCRIBER", "EP_DL_MODEL handle not found in config DB")
   endfunction

   task run_phase(uvm_phase phase);
      // [DL_COV] previous DLCMSM state / substate
      dl_state_e          r_prev_dl  = DL_INACTIVE;
      dl_state_e          e_prev_dl  = DL_INACTIVE;
      dl_init_substate_e  r_prev_sub = INIT_FC1;
      dl_init_substate_e  e_prev_sub = INIT_FC1;

      fork
         // [DL_COV] RC DLCMSM sampler
         forever begin
            @(negedge rc_pipe_intf.pclk);
            if ((rc_dl.DL_STATE != r_prev_dl) || (rc_dl.dl_init_substate != r_prev_sub)) begin
               rc_cg.sample(DL_STATE);   // [COV_2CG]
               r_prev_dl  = rc_dl.DL_STATE;
               r_prev_sub = rc_dl.dl_init_substate;
            end
         end
         // [DL_COV] EP DLCMSM sampler
         forever begin
            @(negedge ep_pipe_intf.pclk);
            if ((ep_dl.DL_STATE != e_prev_dl) || (ep_dl.dl_init_substate != e_prev_sub)) begin
               ep_cg.sample(DL_STATE);   // [COV_2CG]
               e_prev_dl  = ep_dl.DL_STATE;
               e_prev_sub = ep_dl.dl_init_substate;
            end
         end
      join_none
   endtask

  virtual function void write(PCIe_sequence_item t);
     pcie_seq_item = t;
  endfunction

   //===========================================================================
   // [TL_COV] write functions : FLIT mode only
   //===========================================================================
   // From PCIe_RC_TL_model.sv write_dl_rx() : rx_decoded_ap.write(cpl_it)
   function void write_rc_rx_tl(PCIe_sequence_item t);
      rc_rx_tl_item = t;
      if (rc_rx_tl_item.pkt_mode != FLIT) return;          // FLIT mode coverage only
      `uvm_info("PCIe_SUBSCRIBER", $sformatf("RC_RX_TL : %s status=%0d len=%0d bc=%0d tag=%0h",
                rc_rx_tl_item.cpl_has_data ? "CplD" : "Cpl", rc_rx_tl_item.cpl_status,
                rc_rx_tl_item.length, rc_rx_tl_item.byte_count, rc_rx_tl_item.tag), UVM_MEDIUM)
      rc_cg.sample(TL_RX);   // [COV_2CG] Completion the RC received
   endfunction

   // From PCIe_EP_TL_model.sv write_mon() : rx_decoded_ap.write(item)
   function void write_ep_rx_tl(PCIe_sequence_item t);
      ep_rx_tl_item = t;
      if (ep_rx_tl_item.pkt_mode != FLIT) return;          // FLIT mode coverage only
      `uvm_info("PCIe_SUBSCRIBER", $sformatf("EP_RX_TL : %s %s len=%0d tag=%0h",
                ep_rx_tl_item.txn_type.name(), ep_rx_tl_item.dir.name(),
                ep_rx_tl_item.length, ep_rx_tl_item.tag), UVM_MEDIUM)
      ep_cg.sample(TL_RX);   // [COV_2CG] Request the EP received
   endfunction

   //===========================================================================
   // [DL_COV] write functions : FLIT mode only, fields decoded by the DL models
   //===========================================================================
   // From PCIe_RC_DL_model.sv write_rc_mon_242b() : rc_dl_cov_ap.write(cov_item)
   function void write_rc_rx_dl(PCIe_sequence_item t);
      rc_rx_dl_item = t;
      if (rc_rx_dl_item.pkt_mode != FLIT) return;          // FLIT mode coverage only
      `uvm_info("PCIe_SUBSCRIBER", $sformatf("RC_RX_DL : good=%0b usage=%0b replay_cmd=%0b seq=%0d dllp=%0h",
                rc_rx_dl_item.is_valid, rc_rx_dl_item.dl_flit_usage, rc_rx_dl_item.dl_replay_cmd,
                rc_rx_dl_item.dl_seq_num, rc_rx_dl_item.dl_dllp_type), UVM_HIGH)
      rc_cg.sample(DL_RX);   // [COV_2CG] flit the RC received
   endfunction

   // From PCIe_EP_DL_model.sv write_ep_mon_242b() : ep_dl_cov_ap.write(cov_item)
   function void write_ep_rx_dl(PCIe_sequence_item t);
      ep_rx_dl_item = t;
      if (ep_rx_dl_item.pkt_mode != FLIT) return;          // FLIT mode coverage only
      `uvm_info("PCIe_SUBSCRIBER", $sformatf("EP_RX_DL : good=%0b usage=%0b replay_cmd=%0b seq=%0d dllp=%0h",
                ep_rx_dl_item.is_valid, ep_rx_dl_item.dl_flit_usage, ep_rx_dl_item.dl_replay_cmd,
                ep_rx_dl_item.dl_seq_num, ep_rx_dl_item.dl_dllp_type), UVM_HIGH)
      ep_cg.sample(DL_RX);   // [COV_2CG] flit the EP received
   endfunction

   //===========================================================================
   // [PL_COV] write functions : PIPE pins from the controller monitors
   //   cov_dir decides the section : TX pins -> PL TX , RX pins -> PL RX
   //===========================================================================
   // From RC controller monitor : rc_cov_ap.write(item)
   function void write_rc(PCIe_sequence_item t);
      if (t.cov_dir == PCIE_COV_TX) begin
         rc_tx_item = t;
         rc_cg.sample(PL_TX);
      end
      else begin
         rc_rx_item = t;
         rc_cg.sample(PL_RX);
      end
   endfunction

   // From EP controller monitor : ep_cov_ap.write(item)
   function void write_ep(PCIe_sequence_item t);
      if (t.cov_dir == PCIE_COV_TX) begin
         ep_tx_item = t;
         ep_cg.sample(PL_TX);
      end
      else begin
         ep_rx_item = t;
         ep_cg.sample(PL_RX);
      end
   endfunction

   //===========================================================================
   // [COV_REPORT] Print coverage % in the log at the end of the test
   //   search the log for : COVERAGE_REPORT
   //===========================================================================
   function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("COVERAGE_REPORT", "==================== COVERAGE SUMMARY ====================", UVM_NONE)
      `uvm_info("COVERAGE_REPORT", $sformatf("RC  rc_cg  = %0.2f %%", rc_cg.get_inst_coverage()), UVM_NONE)
      `uvm_info("COVERAGE_REPORT", $sformatf("EP  ep_cg  = %0.2f %%", ep_cg.get_inst_coverage()), UVM_NONE)
      `uvm_info("COVERAGE_REPORT", "==========================================================", UVM_NONE)
   endfunction

endclass

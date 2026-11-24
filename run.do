#set testname "PCIe_base_test"
set testname "PCIe_3DW_flit_test"
#set testname "PCIe_IO_3DW_FLIT_test"
#set testname "PCIe_gen6_ltssm_electrical_idle_during_training_test"
#set testname "PCIe_gen6_ltssm_detect_no_receiver_test"
#set testname "PCIe_gen6_ltssm_basic_linkup_L0_test"
#set testname "PCIe_gen6_ltssm_l0p_test"
#set testname "PCIe_gen6_ltssm_l1_test"
#set testname "PCIe_gen6_ltssm_l2_test"
#set testname "PCIe_gen6_ltssm_disabled_test"
#set testname "PCIe_gen6_ltssm_loopback_test"
#set testname "PCIe_gen6_ltssm_hot_reset_test"
#set testname "PCIe_gen6_ltssm_recovery_test"
# --- LTSSM directed timeout tests ---
#set testname "PCIe_gen6_ltssm_timeout_detect_quiet_test"
#set testname "PCIe_gen6_ltssm_timeout_detect_active_test"
#set testname "PCIe_gen6_ltssm_timeout_polling_active_test"
#set testname "PCIe_gen6_ltssm_timeout_polling_configuration_test"
#set testname "PCIe_gen6_ltssm_timeout_config_linkwidth_start_test"
#set testname "PCIe_gen6_ltssm_timeout_config_linkwidth_accept_test"
#set testname "PCIe_gen6_ltssm_timeout_config_lanenum_wait_test"
#set testname "PCIe_gen6_ltssm_timeout_config_lanenum_accept_test"
#set testname "PCIe_gen6_ltssm_timeout_config_complete_test"
#set testname "PCIe_gen6_ltssm_timeout_config_idle_test"
#set testname "PCIe_gen6_ltssm_timeout_recovery_rcvrlock_test"
#set testname "PCIe_gen6_ltssm_timeout_recovery_equalization_test"
#set testname "PCIe_gen6_ltssm_timeout_recovery_rcvrcfg_test"
#set testname "PCIe_gen6_ltssm_timeout_recovery_idle_test"
#set testname "PCIe_gen6_ltssm_timeout_loopback_entry_test"
#set testname "PCIe_gen6_ltssm_timeout_loopback_active_test"
#set testname "PCIe_gen6_ltssm_timeout_loopback_exit_test"
#set testname "PCIe_gen6_ltssm_timeout_hot_reset_test"
#set testname "PCIe_gen6_ltssm_timeout_disabled_test"
#set testname "PCIe_gen6_3DW_Flit_MemWr_MinPayload_test"
#set testname "PCIe_gen6_3DW_Flit_MemWr_MaxPayload_test"
#set testname "PCIe_gen6_3DW_Flit_DefMemWr_MaxPayload_test"
#set testname "PCIe_gen6_3DW_Flit_MemWr_followed_MemRd_MaxPayload_test"
# [FLIT_SEG] 4DW tests : compile with +define+FORCE_4DW+CONFIG_4DW (see the commented vlog block below)
#set testname "PCIe_gen6_3DW_Flit_IOWr_test"
#set testname "PCIe_gen6_3DW_Flit_IORd_test"
#set testname "PCIe_gen6_3DW_Flit_IOWr_Random_test"
#set testname "PCIe_gen6_3DW_Flit_IOWr_followed_IORd_Random_test"
#set testname "PCIe_gen6_3DW_Flit_IOWr_followed_IORd_test"
#set testname "PCIe_gen6_3DW_Flit_CFGWr0_test"
#set testname "PCIe_gen6_3DW_Flit_CFGWr1_test"
#set testname "PCIe_gen6_3DW_Flit_CFGRd0_test"
#set testname "PCIe_gen6_enumeration_test"
#set testname "PCIe_gen6_3DW_Flit_CFGRd1_test"
#set testname "PCIe_gen6_3DW_Flit_MemWr_followed_MemRd_Random_test"
#set testname "PCIe_gen6_3DW_Flit_CFGRd0_Random_test"
#set testname "PCIe_gen6_3DW_Flit_CFGWr0_Random_test"
#set testname "PCIe_gen6_3DW_Flit_CFGWr0_followed_CFGRd0_test"
#set testname "PCIe_gen6_3DW_Flit_CFGWr0_followed_CFGRd0_Random_test"
#set testname "PCIe_gen6_3DW_Flit_CFGRd1_test"
#set testname "PCIe_gen6_3DW_Flit_CFGRd1_Random_test"
#set testname "PCIe_gen6_3DW_Flit_CFGWr1_Random_test"
#set testname "PCIe_gen6_3DW_Flit_CFGWr1_followed_CFGRd1_test"
#set testname "PCIe_gen6_3DW_Flit_CFGWr1_followed_CFGRd1_Random_test"
#set testname "PCIe_gen6_3DW_Flit_MemWr_Random_test"
#set testname "PCIe_gen6_3DW_Flit_DefMemWr_MinPayload_test"
#set testname "PCIe_gen6_3DW_Flit_DefMemWr_Random_test"
#set testname "PCIe_gen6_3DW_Flit_MemRd_MinPayload_test"
#set testname "PCIe_gen6_3DW_Flit_MemRd_MaxPayload_test"
#set testname "PCIe_gen6_3DW_Flit_MemRd_Random_test"
#set testname "PCIe_gen6_3DW_Flit_MemRdlock_MinPayload_test"
#set testname "PCIe_gen6_3DW_Flit_MemRdlock_MaxPayload_test"
#set testname "PCIe_gen6_3DW_Flit_MemRdlock_Random_test"
#set testname "PCIe_gen6_3DW_Flit_MemWr_followed_MemRd_MinPayload_test"
#set testname "PCIe_gen6_4DW_Flit_MemWr_MinPayload_test"
#set testname "PCIe_gen6_4DW_Flit_MemWr_MaxPayload_test"
#set testname "PCIe_gen6_4DW_Flit_MemWr_Random_test"
#set testname "PCIe_gen6_4DW_Flit_DefMemWr_MinPayload_test"
#set testname "PCIe_gen6_4DW_Flit_DefMemWr_MaxPayload_test"
#set testname "PCIe_gen6_4DW_Flit_MsgWr_withdata_test"
#set testname "PCIe_gen6_4DW_Flit_MsgWr_withoutdata_test"
#set testname "PCIe_gen6_3DW_Flit_MsgWr_withdata_test"
#set testname  "PCIe_gen6_3DW_Flit_MsgWr_withoutdata_test"
#set testname  "PCIe_gen6_ltssm_recovery_test"
#set testname "PCIe_gen6_4DW_Flit_DefMemWr_Random_test"
#set testname "PCIe_gen6_4DW_Flit_MemRd_MinPayload_test"
#set testname "PCIe_gen6_4DW_Flit_MemRd_MaxPayload_test"
#set testname "PCIe_gen6_4DW_Flit_MemRd_Random_test"
#set testname "PCIe_gen6_4DW_Flit_MemRdlock_MinPayload_test"
#set testname "PCIe_gen6_4DW_Flit_MemRdlock_MaxPayload_test"
#set testname "PCIe_gen6_4DW_Flit_MemRdlock_Random_test"
#set testname "PCIe_gen6_4DW_Flit_MemWr_followed_MemRd_MinPayload_test"
#set testname "PCIe_gen6_4DW_Flit_MemWr_followed_MemRd_MaxPayload_test"
#set testname "PCIe_gen6_4DW_Flit_MemWr_followed_MemRd_Random_test"
#set testname "PCIe_gen6_3DW_Flit_MemWr_MemRd_tc_vc_test"  
#set testname "PCIe_gen6_3DW_Flit_MemRd_followed_MemWr_test"
#set testname "PCIe_gen6_3DW_Flit_IOWr_ECRC_Error_test"
#set testname "PCIe_gen6_3DW_Flit_MemWr_Malformed_TLP_test"
#set testname "PCIe_gen6_3DW_Flit_DefMemWr_Poisoned_TLP_test" 
#set testname "PCIe_gen6_3DW_LPRFX_Flit_MemWR_Random_test"
#set testname "PCIe_gen6_3DW_E2E_PRFX_Flit__MemWr_Random_test"
#set testname "PCIe_gen6_3DW_OHC_B_Flit__MemWr_Random_test"
#set testname "PCIe_RC_3DW_OHC_C_Flit_MemWr_MinPayload_test"
#set testname "PCIe_RC_3DW_OHC_E1_Flit_MemWr_MinPayload_test"
#set testname "PCIe_RC_3DW_OHC_E4_Flit_MemWr_MinPayload_test"
#set testname "PCIe_RC_3DW_OHC_Order_A_B_C_E4_Flit_MemWr_MinPayload_test"
# [DLL] Data Link Layer tests (all DLL tests in one place)
#set testname "PCIe_gen6_dll_inactive_state_test"
#set testname "PCIe_gen6_dll_initfc1_test"
#set testname "PCIe_gen6_dll_initfc2_test"
#set testname "PCIe_gen6_dll_feature_negotiation_test"
#set testname "PCIe_gen6_dll_active_state_test"
#set testname "PCIe_gen6_dll_ack_nak_test"
#set testname "PCIe_gen6_dll_crc_error_replay_test"
#set testname "PCIe_gen6_dll_retry_request_test"
#set testname "PCIe_gen6_dll_duplicate_flit_discard_test"
#set testname "PCIe_gen6_dll_replay_timer_expiry_test"
#set testname "PCIe_gen6_dll_replay_buffer_limit_test"
#set testname "PCIe_gen6_dll_sequence_wraparound_test"
#set testname "PCIe_gen6_dll_fec_error_correction_test"
#set testname "PCIe_gen6_dll_invalid_dllp_test"
#set testname "PCIe_gen6_dll_nop_dllp_test"
#set testname "PCIe_gen6_dll_link_management_dllp_test"
#set testname "PCIe_gen6_dll_flow_control_credit_exhaustion_test"
#set testname "PCIe_gen6_dll_credit_recovery_test"
#set testname "PCIe_gen6_dll_updatefc_optimized_test"
#set testname "PCIe_gen6_dll_link_recovery_reinitialization_test"
#set testname "PCIe_gen6_dll_reset_replay_buffer_clear_test"
#set testname "PCIe_gen6_dll_lost_nak_test"
#set testname "PCIe_gen6_dll_multi_flit_replay_test"
#set testname "PCIe_gen6_dll_sequence_gap_detection_test"
set RUN_DO_TESTNAME_FROM_CLI [info exists testname]
if {!$RUN_DO_TESTNAME_FROM_CLI} {
#  set testname "PCIe_gen6_dll_out_of_order_flit_test"
}
#set testname "PCIe_gen6_dll_maximum_replay_buffer_test"
#set testname "PCIe_gen6_dll_retry_buffer_overflow_test"
#set testname "PCIe_gen6_dll_flit_crc_generation_test"
#set testname "PCIe_gen6_dll_flit_crc_error__test"
#set testname "PCIe_gen6_dll_uncorrectable_fec_error_test"
#set testname "PCIe_gen6_dll_crc_and_fec_combined_test"
 
vlib work
vmap work work
vlog -work work -sv +define+PCIE_GEN6_FEC_CRC PCIe_top/PCIe_PHY_interface.sv
vlog -work work -sv +define+PCIE_GEN6_FEC_CRC PCIe_config/enum_defs.sv
vlog -work work -sv +define+PCIE_GEN6_FEC_CRC PCIe_top/PCIe_PIPE_interface.sv
vlog -work work -sv +define+PCIE_GEN6_FEC_CRC PCIe_top/PCIe_pkg.sv
vlog -work work -sv +define+PCIE_GEN6_FEC_CRC PCIe_top/PCIe_top.sv
 
# [FLIT_SEG] for the 4DW tests use these five lines instead of the five above
# (64-bit address field + 4DW header base) :
#vlog -work work -sv +define+PCIE_GEN6_FEC_CRC+FORCE_4DW+CONFIG_4DW PCIe_top/PCIe_PHY_interface.sv
#vlog -work work -sv +define+PCIE_GEN6_FEC_CRC+FORCE_4DW+CONFIG_4DW PCIe_config/enum_defs.sv
#vlog -work work -sv +define+PCIE_GEN6_FEC_CRC+FORCE_4DW+CONFIG_4DW PCIe_top/PCIe_PIPE_interface.sv
#vlog -work work -sv +define+PCIE_GEN6_FEC_CRC+FORCE_4DW+CONFIG_4DW PCIe_top/PCIe_pkg.sv
#vlog -work work -sv +define+PCIE_GEN6_FEC_CRC+FORCE_4DW+CONFIG_4DW PCIe_top/PCIe_top.sv
 
if {![info exists testname] || $testname eq ""} {
  set testname "PCIe_gen6_ltssm_basic_linkup_L0_test"
}

file mkdir sim
set logfile "sim/${testname}_log.log"

if {[catch {vsim work.PCIe_top +UVM_TESTNAME=${testname} -l $logfile} err]} {
  echo "SINGLE RUN : vsim failed : $err"
  if {[batch_mode]} { quit -f -code 1 }
  return -code error $err
}

if {![batch_mode]} {
  view wave
  add wave -r /PCIe_top/*
  add log -r /*
}

if {[catch {run 200ms} rerr]} {
  echo "SINGLE RUN : run failed : $rerr"
  catch {quit -sim}
  if {[batch_mode]} { quit -f -code 1 }
  return -code error $rerr
}

if {[batch_mode]} { quit -f -code 0 }

#set testname "PCIe_base_test"
#set testname "PCIe_3DW_flit_test"
#set testname "PCIe_IO_3DW_FLIT_test"
#set testname "PCIe_gen6_ltssm_electrical_idle_during_training_test"
#set testname "PCIe_gen6_ltssm_detect_no_receiver_test"
#set testname "PCIe_gen6_ltssm_basic_linkup_L0_test"
#set testname "PCIe_gen6_ltssm_disabled_test"
#set testname "PCIe_gen6_ltssm_loopback_test"
#set testname "PCIe_gen6_ltssm_hot_reset_test"
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
# [ATOMIC] AtomicOp tests (4DW ones : use the FORCE_4DW+CONFIG_4DW vlog block below)
set testname "PCIe_gen6_3DW_Flit_FetchAdd_1dwPayload_test"
#set testname "PCIe_gen6_3DW_Flit_FetchAdd_2dwPayload_test"
#set testname "PCIe_gen6_3DW_Flit_swap_1dwPayload_test"
#set testname "PCIe_gen6_3DW_Flit_swap_2dwPayload_test"
#set testname "PCIe_gen6_3DW_Flit_CAS_1dwPayload_test"
#set testname "PCIe_gen6_3DW_Flit_CAS_2dwPayload_test"
#set testname "PCIe_gen6_4DW_Flit_FetchAdd_1dwPayload_test"
#set testname "PCIe_gen6_4DW_Flit_FetchAdd_2dwPayload_test"
#set testname "PCIe_gen6_4DW_Flit_swap_1dwPayload_test"
#set testname "PCIe_gen6_4DW_Flit_swap_2dwPayload_test"
#set testname "PCIe_gen6_4DW_Flit_CAS_1dwPayload_test"
#set testname "PCIe_gen6_4DW_Flit_CAS_2dwPayload_test"
 
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
 
#set infile [open "logs/${testname}_log.log" w+]
set infile [open "sim/${testname}_log.log" w+]
 
vsim PCIe_top +UVM_TESTNAME=${testname} -l $infile
#vsim work.PCIe_top +UVM_TESTNAME=${testname} -l ${testname}.log
 
view wave
add wave -r /PCIe_top/*
 
add log -r /*
run -all

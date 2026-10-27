#set testname "PCIe_base_test"
#set testname "PCIe_3DW_flit_test"
#set testname "PCIe_IO_3DW_FLIT_test"
#set testname "PCIe_gen6_ltssm_electrical_idle_during_training_test"
#set testname "PCIe_gen6_ltssm_detect_no_receiver_test"
#set testname "PCIe_gen6_ltssm_basic_linkup_L0_test"
#set testname "PCIe_gen6_3DW_Flit_MemWr_MinPayload_test"
#set testname "PCIe_gen6_3DW_Flit_MemWr_MaxPayload_test"
#set testname "PCIe_gen6_3DW_Flit_DefMemWr_MaxPayload_test"
#set testname "PCIe_gen6_3DW_Flit_MemWr_followed_MemRd_MaxPayload_test"
# [FLIT_SEG] 4DW tests : compile with +define+FORCE_4DW+CONFIG_4DW (see the commented vlog block below)
#set testname "PCIe_gen6_4DW_Flit_MemWr_MaxPayload_test"
#set testname "PCIe_gen6_4DW_Flit_DefMemWr_MaxPayload_test"
#set testname "PCIe_gen6_3DW_Flit_IOWr_test"
#set testname "PCIe_gen6_3DW_Flit_IORd_test"
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
set testname "PCIe_gen6_3DW_Flit_CFGWr1_followed_CFGRd1_Random_test"

vlib work
vmap work work
vlog -work work -sv +define+PCIE_GEN6_FEC_CRC PCIe_top/PCIe_PHY_interface.sv
vlog -work work -sv +define+PCIE_GEN6_FEC_CRC PCIe_top/PCIe_PIPE_interface.sv
vlog -work work -sv +define+PCIE_GEN6_FEC_CRC PCIe_config/enum_defs.sv
vlog -work work -sv +define+PCIE_GEN6_FEC_CRC PCIe_top/PCIe_pkg.sv
vlog -work work -sv +define+PCIE_GEN6_FEC_CRC PCIe_top/PCIe_top.sv

# [FLIT_SEG] for the 4DW tests use these five lines instead of the five above
# (64-bit address field + 4DW header base) :
#vlog -work work -sv +define+PCIE_GEN6_FEC_CRC+FORCE_4DW+CONFIG_4DW PCIe_top/PCIe_PHY_interface.sv
#vlog -work work -sv +define+PCIE_GEN6_FEC_CRC+FORCE_4DW+CONFIG_4DW PCIe_top/PCIe_PIPE_interface.sv
#vlog -work work -sv +define+PCIE_GEN6_FEC_CRC+FORCE_4DW+CONFIG_4DW PCIe_config/enum_defs.sv
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






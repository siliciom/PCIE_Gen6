#set testname "PCIe_base_test"
#set testname "PCIe_3DW_flit_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
# [FLIT_SEG] 4DW tests : compile with +define+FORCE_4DW+CONFIG_4DW (see the commented vlog block below)
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
#set testname "PCIe_base_test"
set testname "PCIe_base_test"



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






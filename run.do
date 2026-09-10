#set testname "PCIe_base_test"
#set testname "PCIe_3DW_flit_test"
#set testname "PCIe_IO_3DW_FLIT_test"
#set testname "PCIe_gen6_ltssm_electrical_idle_during_training_test"
#set testname "PCIe_gen6_ltssm_detect_no_receiver_test"
set testname "PCIe_gen6_ltssm_basic_linkup_L0_test"

vlib work
vmap work work
vlog -work work -sv PCIe_top/PCIe_PHY_interface.sv
vlog -work work -sv PCIe_top/PCIe_PIPE_interface.sv
vlog -work work -sv PCIe_config/enum_defs.sv
vlog -work work -sv PCIe_top/PCIe_pkg.sv
vlog -work work -sv PCIe_top/PCIe_top.sv

#set infile [open "logs/${testname}_log.log" w+]
set infile [open "sim/${testname}_log.log" w+]

vsim PCIe_top +UVM_TESTNAME=${testname} -l $infile
#vsim work.PCIe_top +UVM_TESTNAME=${testname} -l ${testname}.log

view wave
add wave -r /PCIe_top/*

add log -r /*
run -all




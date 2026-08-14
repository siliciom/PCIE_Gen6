set testname "PCIe_base_test"

vlib work
vmap work work
vlog -work work -sv PCIe_top/PCIe_PHY_interface.sv
vlog -work work -sv PCIe_top/PCIe_PIPE_interface.sv
vlog -work work -sv PCIe_top/PCIe_pkg.sv
vlog -work work -sv PCIe_top/PCIe_top.sv

#set infile [open "logs/${testname}_log.log" w+]
set infile [open "sim/${testname}_log.log" w+]

vsim PCIe_top +UVM_TESTNAME=${testname} -l $infile
#vsim work.PCIe_top +UVM_TESTNAME=${testname} -l ${testname}.log

add log -r /*
run -all




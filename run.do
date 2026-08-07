set testname "PCIE_base_test"

vlib work
vmap work work
vlog -work work -sv PCIE_top/PCIE_PHY_interface.sv
vlog -work work -sv PCIE_top/PCIE_PIPE_interface.sv
vlog -work work -sv PCIE_config/enum_defs.sv
vlog -work work -sv PCIE_top/PCIE_pkg.sv
vlog -work work -sv PCIE_top/PCIE_top.sv

#set infile [open "logs/${testname}_log.log" w+]
set infile [open "sim/${testname}_log.log" w+]

vsim PCIE_top +UVM_TESTNAME=${testname} -l $infile
#vsim work.PCIE_top +UVM_TESTNAME=${testname} -l ${testname}.log

add log -r /*
run -all




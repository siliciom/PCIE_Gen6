set testname "PCIe_base_test"

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

#add wave -r /PCIe_top/rc_pipe_intf/pclk 
#add wave -r /PCIe_top/rc_pipe_intf/tx_data 
#add wave -r /PCIe_top/rc_pipe_intf/tx_valid 
#add wave -r /PCIe_top/rc_pipe_intf/tx_elec_idle 
#add wave -r /PCIe_top/rc_pipe_intf/tx_detect_rx 
#add wave -r /PCIe_top/rc_pipe_intf/powerdown
#add wave -r /PCIe_top/rc_pipe_intf/rate
#add wave -r /PCIe_top/rc_pipe_intf/rx_data
#add wave -r /PCIe_top/rc_pipe_intf/rx_valid 
#add wave -r /PCIe_top/rc_pipe_intf/phy_status 
#add wave -r /PCIe_top/rc_pipe_intf/rx_elec_idle 
#add wave -r /PCIe_top/rc_pipe_intf/rx_status 
#add wave -r /PCIe_top/ep_pipe_intf/pclk 
#add wave -r /PCIe_top/ep_pipe_intf/tx_data 
#add wave -r /PCIe_top/ep_pipe_intf/tx_valid 
#add wave -r /PCIe_top/ep_pipe_intf/tx_elec_idle 
#add wave -r /PCIe_top/ep_pipe_intf/tx_detect_rx 
#add wave -r /PCIe_top/ep_pipe_intf/powerdown 
#add wave -r /PCIe_top/ep_pipe_intf/rate 
#add wave -r /PCIe_top/ep_pipe_intf/rx_data 
#add wave -r /PCIe_top/ep_pipe_intf/rx_valid 
#add wave -r /PCIe_top/ep_pipe_intf/phy_status 
#add wave -r /PCIe_top/ep_pipe_intf/rx_elec_idle 
#add wave -r /PCIe_top/ep_pipe_intf/rx_status 
#add wave -r /PCIe_top/pcie_rc_phy_intf/tx_plus 
#add wave -r /PCIe_top/pcie_rc_phy_intf/tx_minus 
#add wave -r /PCIe_top/pcie_rc_phy_intf/rx_plus 
#add wave -r /PCIe_top/pcie_rc_phy_intf/rx_minus 
#add wave -r /PCIe_top/pcie_ep_phy_intf/tx_plus 
#add wave -r /PCIe_top/pcie_ep_phy_intf/tx_minus 
#add wave -r /PCIe_top/pcie_ep_phy_intf/rx_plus 
#add wave -r /PCIe_top/pcie_ep_phy_intf/rx_minus 
run -all




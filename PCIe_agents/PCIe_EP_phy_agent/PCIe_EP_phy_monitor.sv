//=========================================================================================
// File         : PCIe_EP_phy_monitor.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_EP_phy_agent\PCIe_EP_phy_monitor.sv
// Author       :
// Date         : 2026-08-17
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document, including by copying, saving,
* distributing, displaying or preparing derivatives of, you agree to be and are bound to the terms of the
* SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
**********************************************************************************************************************/

class PCIe_EP_phy_monitor extends uvm_monitor;

  `uvm_component_utils(PCIe_EP_phy_monitor)

  PCIe_sequence_item pcie_seq_item;
  virtual PCIe_EP_PHY_interface ep_phy_intf_tx,ep_phy_intf_rx;

  uvm_analysis_port #(PCIe_sequence_item) ep_phy_rx_mon_ap;
  uvm_analysis_port #(PCIe_sequence_item) ep_phy_tx_mon_ap;

  event rc_to_ep_bit_event;
  event ep_to_rc_bit_event;

  function new(string name="PCIe_EP_phy_monitor",uvm_component parent);
    super.new(name,parent);
  endfunction

  function void build_phase(uvm_phase phase);
    `uvm_info("EP_PHY_MONITOR","ENTERED_INTO_EP_PHY_MONITOR_BUILD_PHASE",UVM_LOW)
    super.build_phase(phase);

    ep_phy_rx_mon_ap=new("ep_phy_rx_mon_ap",this);
    ep_phy_tx_mon_ap=new("ep_phy_tx_mon_ap",this);
    pcie_seq_item=PCIe_sequence_item::type_id::create("pcie_seq_item");

    if(!uvm_config_db#(virtual PCIe_EP_PHY_interface)::get(this,"","PCIe_EP_PHY_INTERFACE",ep_phy_intf_tx))
      `uvm_fatal("NO_VIF","EP_PHY_INTERFACE_not_found")

    if(!uvm_config_db#(virtual PCIe_EP_PHY_interface)::get(this,"","PCIe_EP_PHY_INTERFACE",ep_phy_intf_rx))
      `uvm_fatal("NO_VIF","EP_PHY_INTERFACE_not_found")

    if(!uvm_config_db#(event)::get(this,"","RC_TO_EP_BIT_EVENT",rc_to_ep_bit_event))
      `uvm_fatal("NO_EVENT","RC_TO_EP_BIT_EVENT_not_found")

    if(!uvm_config_db#(event)::get(this,"","EP_TO_RC_BIT_EVENT",ep_to_rc_bit_event))
      `uvm_fatal("NO_EVENT","EP_TO_RC_BIT_EVENT_not_found")

    `uvm_info("EP_PHY_MONITOR","EXIT_FROM_EP_PHY_MONITOR_BUILD_PHASE",UVM_LOW)
  endfunction

  task run_phase(uvm_phase phase);
    `uvm_info("EP_PHY_MONITOR","ENTERED_INTO_EP_PHY_MONITOR_RUN_PHASE",UVM_LOW)
    fork
      forever begin
        rx_sipo(ep_phy_intf_rx);
      end
      forever begin
        tx_sipo(ep_phy_intf_tx);
      end
    join
    `uvm_info("EP_PHY_MONITOR","EXIT_FROM_EP_PHY_MONITOR_RUN_PHASE",UVM_LOW)
  endtask

  task rx_sipo(virtual PCIe_EP_PHY_interface ep_phy_intf_rx);
    bit [`PCIe_PL_PIPE_WORD_W-1:0] rx_data;
    bit rx_bit;

    `uvm_info("EP_PHY_MONITOR","ENTERED_INTO_RX_SIPO_EP_MONITOR",UVM_LOW)
    rx_data='0;

    for(int i=0;i<`PCIe_PL_PIPE_WORD_W;i++) begin
      @rc_to_ep_bit_event;
      #15.625ps;
      rx_bit=ep_phy_intf_rx.rx_plus;
      rx_data[i]=rx_bit;
      `uvm_info("EP_PHY_MONITOR",$sformatf("RX_BIT_IN_EP_MONITOR[%0d] = %0b TIME = %0.5f",i,rx_bit,$realtime),UVM_LOW)
    end

    pcie_seq_item.data_q_ep_mon_rx.push_back(rx_data);
    `uvm_info("EP_PHY_MONITOR",$sformatf("RX_32_BIT_PARALLEL_EP_MONITOR_DATA = %08h EP_MONITOR_QUEUE_SIZE = %0d",rx_data,pcie_seq_item.data_q_ep_mon_rx.size()),UVM_LOW)
    `uvm_info("EP_PHY_MONITOR","EXIT_FROM_RX_SIPO_EP_MONITOR",UVM_LOW)
    ep_phy_rx_mon_ap.write(pcie_seq_item);
  endtask

  task tx_sipo(virtual PCIe_EP_PHY_interface ep_phy_intf_tx);
    bit [`PCIe_PL_PIPE_WORD_W-1:0] tx_data;
    bit tx_bit;

    `uvm_info("EP_PHY_MONITOR","ENTERED_INTO_TX_SIPO_EP_MONITOR",UVM_LOW)

    for(int i=0;i<`PCIe_PL_PIPE_WORD_W;i++) begin
      @ep_to_rc_bit_event;
      #15.625ps;
      tx_bit=ep_phy_intf_tx.tx_plus;
      tx_data[i]=tx_bit;
      `uvm_info("EP_PHY_MONITOR",$sformatf("TX_BIT_IN_EP_MONITOR[%0d] = %0b TIME = %0.5f",i,tx_bit,$realtime),UVM_LOW)
    end

    pcie_seq_item.data_q_ep_mon_tx.push_back(tx_data);
    `uvm_info("EP_PHY_MONITOR",$sformatf("EP_TX_32_BIT_PARALLEL_MONITOR_DATA = %08h EP_MONITOR_QUEUE_SIZE = %0d",tx_data,pcie_seq_item.data_q_ep_mon_tx.size()),UVM_LOW)
    `uvm_info("EP_PHY_MONITOR","EXIT_FROM_TX_SIPO_EP_MONITOR",UVM_LOW)
    ep_phy_tx_mon_ap.write(pcie_seq_item);
  endtask

endclass

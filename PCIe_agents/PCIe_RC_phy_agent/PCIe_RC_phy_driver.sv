//=========================================================================================
// File         : PCIe_RC_phy_driver.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_RC_phy_agent\PCIe_RC_phy_driver.sv
// Author       :
// Date         : 2026-08-17
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document, including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

class PCIe_RC_phy_driver extends uvm_driver #(PCIe_sequence_item);

  `uvm_component_utils(PCIe_RC_phy_driver)

  PCIe_sequence_item pcie_seq_item;

  virtual PCIe_RC_interface rc_pipe_intf_tx, rc_pipe_intf_rx;
  virtual PCIe_RC_PHY_interface rc_phy_intf_tx, rc_phy_intf_rx;

  bit [`PCIe_PL_PIPE_WORD_W-1:0] rc_data_q[$];
  bit [`PCIe_PL_PIPE_WORD_W-1:0] ep_data_q[$];

  event rc_to_ep_bit_event;
  event ep_to_rc_bit_event;

  function new(string name="PCIe_RC_phy_driver",uvm_component parent);
    super.new(name,parent);
  endfunction

  function void build_phase(uvm_phase phase);
    `uvm_info("RC_PHY","ENTERED_INTO_RC_PHY_DRIVER_BUILD_PHASE",UVM_LOW)

    super.build_phase(phase);

    pcie_seq_item=PCIe_sequence_item::type_id::create("pcie_seq_item");

    if(!uvm_config_db#(virtual PCIe_RC_interface)::get(this,"","PCIe_RC_INTERFACE",rc_pipe_intf_tx))
      `uvm_fatal("NO_VIF","RC_PIPE_INTERFACE_not_found")

    if(!uvm_config_db#(virtual PCIe_RC_interface)::get(this,"","PCIe_RC_INTERFACE",rc_pipe_intf_rx))
      `uvm_fatal("NO_VIF","RC_PIPE_INTERFACE_not_found")

    if(!uvm_config_db#(virtual PCIe_RC_PHY_interface)::get(this,"","PCIe_RC_PHY_INTERFACE",rc_phy_intf_tx))
      `uvm_fatal("NO_VIF","RC_PHY_INTERFACE_not_found")

    if(!uvm_config_db#(virtual PCIe_RC_PHY_interface)::get(this,"","PCIe_RC_PHY_INTERFACE",rc_phy_intf_rx))
      `uvm_fatal("NO_VIF","RC_PHY_INTERFACE_not_found")

    if(!uvm_config_db#(event)::get(this,"","RC_TO_EP_BIT_EVENT",rc_to_ep_bit_event))
      `uvm_fatal("NO_EVENT","RC_TO_EP_BIT_EVENT_not_found")

    if(!uvm_config_db#(event)::get(this,"","EP_TO_RC_BIT_EVENT",ep_to_rc_bit_event))
      `uvm_fatal("NO_EVENT","EP_TO_RC_BIT_EVENT_not_found")

    `uvm_info("RC_PHY","EXIT_FROM_RC_PHY_DRIVER_BUILD_PHASE",UVM_LOW)
  endfunction

  task run_phase(uvm_phase phase);
    `uvm_info("RC_PHY","ENTERED_INTO_RC_PHY_DRIVER_RUN_PHASE",UVM_LOW)

    fork
      rx_sipo(rc_phy_intf_rx);
      sending_pipe_rx(rc_pipe_intf_rx);
      receiving_data_rc(rc_pipe_intf_tx);
    join_none

    forever begin
      seq_item_port.get_next_item(pcie_seq_item);
      seq_item_port.item_done(pcie_seq_item);
    end

    `uvm_info("RC_PHY","EXIT_FROM_RC_PHY_DRIVER_RUN_PHASE",UVM_LOW)
  endtask

  task receiving_data_rc(virtual PCIe_RC_interface rc_pipe_intf_tx);
    bit [`PCIe_PL_PIPE_WORD_W-1:0]   tx_data;
    bit [`PCIe_TX_VALID_W-1:0]       tx_valid;
    bit [`PCIe_TX_ELEC_IDLE_W-1:0]   tx_elec_idle;
    bit [`PCIe_TX_DETECT_RX_W-1:0]   tx_detect_rx;
    bit [`PCIe_POWERDOWN_W-1:0]      powerdown;
    bit [`PCIe_RATE_W-1:0]           rate;
    bit [`PCIe_PL_PIPE_WORD_W-1:0]   serial_word;

    `uvm_info("RC_PHY_DRIVER","ENTERED_INTO_RECEIVING_PIPE_DATA_TASK",UVM_LOW)

    wait(rc_pipe_intf_tx.tx_valid);

    `uvm_info("RC_PHY_DRIVER","STARTED_RECEIVING_PIPE_DATA",UVM_LOW)

    while(rc_pipe_intf_tx.tx_valid) begin
      @(negedge rc_pipe_intf_tx.pclk);

      tx_valid=rc_pipe_intf_tx.tx_valid;
      tx_elec_idle=rc_pipe_intf_tx.tx_elec_idle;
      tx_detect_rx=rc_pipe_intf_tx.tx_detect_rx;
      powerdown=rc_pipe_intf_tx.powerdown;
      rate=rc_pipe_intf_tx.rate;

      if(tx_valid) begin
        tx_data=rc_pipe_intf_tx.tx_data;

        rc_data_q.push_back(tx_data);

        `uvm_info("RC_PHY_DRIVER",
                  $sformatf("RECEIVED_DATA=%08h QUEUE_SIZE=%0d",
                            tx_data,rc_data_q.size()),
                  UVM_LOW)

        serial_word=rc_data_q.pop_front();

        tx_piso(serial_word);
      end
    end
  endtask

  task tx_piso(input bit [`PCIe_PL_PIPE_WORD_W-1:0] data_in);
    bit piso_data_out;

    `uvm_info("RC_PHY_DRIVER","ENTERED_INTO_PISO_TASK",UVM_LOW)

    // Serialize each 32-bit word
    for(int i=0;i<`PCIe_PL_PIPE_WORD_W;i++) begin
      piso_data_out=data_in[i];

      rc_phy_intf_tx.tx_plus<=piso_data_out;
      rc_phy_intf_tx.tx_minus<=~piso_data_out;

      `uvm_info("RC_PHY_DRIVER",
                $sformatf("PISO_DATA_IN_PHY_BIT_BY_BIT[%0d]=%0b TIME=%0t",
                          i,piso_data_out,$time),
                UVM_LOW)

      ->rc_to_ep_bit_event;

      #31.25ps;
    end

    rc_phy_intf_tx.tx_plus<=1'b0;
    rc_phy_intf_tx.tx_minus<=1'b1;

    `uvm_info("RC_PHY_DRIVER","EXIT_FROM_PISO_TASK_COMPLETED",UVM_LOW)
  endtask

  task rx_sipo(virtual PCIe_RC_PHY_interface rc_phy_intf_rx);
    bit [`PCIe_PL_PIPE_WORD_W-1:0] rx_data;
    bit rx_bit;

    `uvm_info("RC_PHY_DRIVER","ENTERED_INTO_RX_SIPO_RC_PHY_DRIVER",UVM_LOW)

    forever begin
      for(int i=0;i<`PCIe_PL_PIPE_WORD_W;i++) begin
        @ep_to_rc_bit_event;

        #15.625ps;

        rx_bit=rc_phy_intf_rx.rx_plus;
        rx_data[i]=rx_bit;

        `uvm_info("EP_PHY_DRIVER",
                  $sformatf("RC_PHY_DRIVER_RX_BIT[%0d]=%0b TIME=%0.5f",
                            i,rx_bit,$realtime),
                  UVM_LOW)
      end

      ep_data_q.push_back(rx_data);

      `uvm_info("RC_PHY_DRIVER",
                $sformatf("RC_PHY_DRIVER_RX_32_BIT_PARALLEL_DATA=%08h QUEUE_SIZE=%0d",
                          rx_data,ep_data_q.size()),
                UVM_LOW)
    end

    `uvm_info("RC_PHY_DRIVER","RC_PHY_DRIVER_EXIT_FROM_RX_SIPO",UVM_LOW)
  endtask

  task sending_pipe_rx(virtual PCIe_RC_interface rc_pipe_intf_rx);
    bit [`PCIe_PL_PIPE_WORD_W-1:0] rx_parallel_data;

    `uvm_info("RC_PHY_DRIVER",
              "ENTERED_INTO_SENDING_PARALLEL_DATA_TO_PIPE_RX_RC_PHY_DRIVER",
              UVM_LOW)

    rc_pipe_intf_rx.phy_status<=1'b0;
    rc_pipe_intf_rx.rx_elec_idle<=1'b0;
    rc_pipe_intf_rx.rx_status<='0;

    forever begin
      @(posedge rc_pipe_intf_rx.pclk);

      if(ep_data_q.size()>0) begin
        rx_parallel_data=ep_data_q.pop_front();

        rc_pipe_intf_rx.rx_data<=rx_parallel_data;
        rc_pipe_intf_rx.rx_valid<=1'b1;

        `uvm_info("RC_PHY_DRIVER",
                  $sformatf("DRIVING_RC_PIPE_RX_DATA=%08h",
                            rx_parallel_data),
                  UVM_LOW)
      end
      else begin
        rc_pipe_intf_rx.rx_valid<=1'b0;
      end

      `uvm_info("RC_PHY_DRIVER",
                "EXIT_FROM_SENDING_PARALLEL_DATA_TO_PIPE_RX_RC",
                UVM_LOW)
    end
  endtask

endclass

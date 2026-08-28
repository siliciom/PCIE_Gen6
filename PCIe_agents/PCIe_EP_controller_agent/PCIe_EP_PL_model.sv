//=========================================================================================
// File         : PCIe_EP_PL_model.sv
// Project      : PCIe_Gen6
// Description  : PCIe_environment\PCIe_EP_PL_model.sv
// Author       :
// Date         : 2026-08-14
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document, including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

import typedef_enums::*;

class PCIe_EP_PL_model extends uvm_component;

  `uvm_component_utils(PCIe_EP_PL_model)

  // Input from RC DL model.
  uvm_analysis_imp#(PCIe_sequence_item,PCIe_EP_PL_model) pl_imp;

  pcie_mode_e mode;
  PCIe_env_config pcie_ecfg;

  bit[0:`PCIe_DLP_FLIT_BYTE_W-1][`PCIe_BYTE_W-1:0] dl_flit_out;
  bit[`PCIe_BYTE_W-1:0] pl_qu[$];
  bit[`PCIe_PL_SCRAMBLER_LFSR_W-1:0] lfsr;
  bit[`PCIe_PL_SCRAMBLER_LFSR_W-1:0] polynomial;
  bit[`PCIe_PL_SYMBOL_W-1:0] previous_symbol;
  bit tx_parity_q[$];
  bit pl_sent;

  function new(string name="PCIe_EP_PL_model",uvm_component parent);
    super.new(name,parent);
    pl_imp=new("pl_imp",this);
  endfunction

  function void build_phase(uvm_phase phase);
    `uvm_info("PCIe_PL_MODEL","ENTERED_INTO_PL_MODEL_BUILD_PHASE",UVM_LOW)
    super.build_phase(phase);

    if(!uvm_config_db#(PCIe_env_config)::get(this,"","PCIe_env_config",pcie_ecfg))
    begin
      `uvm_fatal("PL_MODEL","Cannot_get_PCIe_env_config");
    end

    mode=pcie_ecfg.mode;

    if(mode==FLIT_MODE)
      `uvm_info("EP_PL_MODEL","Configured_in_FLIT_MODE",UVM_LOW)
    else
      `uvm_info("EP_PL_MODEL","Configured_in_NON_FLIT_MODE",UVM_LOW)

    polynomial=`PCIe_PL_SCRAMBLER_POLYNOMIAL;
    reset_scrambler();
    previous_symbol=2'b11;

    `uvm_info("PCIe_PL_MODEL","EXIT_FROM_PL_MODEL_BUILD_PHASE",UVM_LOW)
  endfunction

  task reset_scrambler();
    lfsr=`PCIe_PL_SCRAMBLER_SEED;
  endtask

  task scramble(
    input bit[`PCIe_BYTE_W-1:0] data_in,
    output bit[`PCIe_BYTE_W-1:0] data_out
  );

    bit scramble_bit;

    data_out=data_in;

    `uvm_info("PCIe_PL_MODEL","ENTERED_INTO_SCRAMBLER_TASK",UVM_LOW)

    for(int i=0;i<`PCIe_BYTE_W;i++)
    begin
      scramble_bit=lfsr[`PCIe_PL_SCRAMBLER_LFSR_W-1];
      data_out[i]=data_in[i]^scramble_bit;

      if(scramble_bit)
      begin
        lfsr=(lfsr<<1)^polynomial;
      end
      else
      begin
        lfsr=(lfsr<<1);
      end
    end

    `uvm_info("PCIe_PL_MODEL","EXIT_FROM_SCRAMBLER_TASK",UVM_LOW)
  endtask

  // One PIPE word = 32 bits
  task scramble_32(
    input bit[`PCIe_PL_PIPE_WORD_W-1:0] data_in,
    output bit[`PCIe_PL_PIPE_WORD_W-1:0] data_out
  );

    bit[`PCIe_BYTE_W-1:0] temp;

    `uvm_info("PCIe_PL_MODEL",$sformatf("SCRAMBLE_32_INPUT=%08h",data_in),UVM_LOW)

    scramble(data_in[`PCIe_BYTE_W-1:0],temp);
    data_out[`PCIe_BYTE_W-1:0]=temp;

    scramble(data_in[2*`PCIe_BYTE_W-1:`PCIe_BYTE_W],temp);
    data_out[2*`PCIe_BYTE_W-1:`PCIe_BYTE_W]=temp;

    scramble(data_in[3*`PCIe_BYTE_W-1:2*`PCIe_BYTE_W],temp);
    data_out[3*`PCIe_BYTE_W-1:2*`PCIe_BYTE_W]=temp;

    scramble(data_in[`PCIe_PL_PIPE_WORD_W-1:3*`PCIe_BYTE_W],temp);
    data_out[`PCIe_PL_PIPE_WORD_W-1:3*`PCIe_BYTE_W]=temp;

    `uvm_info("PCIe_PL_MODEL",$sformatf("SCRAMBLE_32_OUTPUT=%08h",data_out),UVM_LOW)
  endtask

  task tx_gray_encode(
    input bit[`PCIe_PL_PIPE_WORD_W-1:0] data_in,
    output bit[`PCIe_PL_PIPE_WORD_W-1:0] gray_out
  );

    bit[`PCIe_PL_SYMBOL_W-1:0] symbol;

    gray_out='0;

    `uvm_info("PCIe_PL_MODEL",$sformatf("ENTERED_INTO_GRAY_ENCODE_TASK"),UVM_LOW)
    `uvm_info("PCIe_PL_MODEL",$sformatf("GRAY_ENCODE_INPUT=%0b",data_in),UVM_LOW)

    for(int i=0;i<`PCIe_PL_PIPE_WORD_W;i=i+`PCIe_PL_SYMBOL_W)
    begin
      symbol=data_in[i+:`PCIe_PL_SYMBOL_W];

      case(symbol)
        2'b00:
          gray_out[i+:`PCIe_PL_SYMBOL_W]=2'b00;

        2'b01:
          gray_out[i+:`PCIe_PL_SYMBOL_W]=2'b01;

        2'b10:
          gray_out[i+:`PCIe_PL_SYMBOL_W]=2'b11;

        2'b11:
          gray_out[i+:`PCIe_PL_SYMBOL_W]=2'b10;

        default:
          gray_out[i+:`PCIe_PL_SYMBOL_W]=2'b00;
      endcase
    end

    `uvm_info("PCIe_PL_MODEL",$sformatf("GRAY_ENCODE_OUTPUT=%0b",gray_out),UVM_LOW)
    `uvm_info("PCIe_PL_MODEL",$sformatf("EXIT_FROM_GRAY_ENCODE_TASK"),UVM_LOW)
  endtask

  task tx_parity_generate(
    input bit[`PCIe_PL_PIPE_WORD_W-1:0] data_in,
    output bit parity_bit
  );

    `uvm_info("PCIe_PL_MODEL",$sformatf("ENTERED_INTO_PARITY_GENERATE_TASK"),UVM_LOW)

    parity_bit=^data_in;

    `uvm_info("PCIe_PL_MODEL",$sformatf("PARITY_INPUT=%08h PARITY=%0b",data_in,parity_bit),UVM_LOW)
    `uvm_info("PCIe_PL_MODEL",$sformatf("PARITY_GENERATE_OUTPUT=%b",parity_bit),UVM_LOW)
  endtask

  task tx_precoder(
    input bit[`PCIe_PL_PIPE_WORD_W-1:0] gray_data,
    output bit[`PCIe_PL_PIPE_WORD_W-1:0] precoded_data
  );

    bit[`PCIe_PL_SYMBOL_W-1:0] current_symbol;

    precoded_data='0;

    `uvm_info("PCIe_PL_MODEL",$sformatf("ENTERED_INTO_PRE_ENCODE_TASK"),UVM_LOW)
    `uvm_info("PCIe_PL_MODEL",$sformatf("PRECODE_INPUT=%0b",gray_data),UVM_LOW)

    for(int i=0;i<`PCIe_PL_PIPE_WORD_W;i=i+`PCIe_PL_SYMBOL_W)
    begin
      current_symbol=gray_data[i+:`PCIe_PL_SYMBOL_W];
      precoded_data[i+:`PCIe_PL_SYMBOL_W]=current_symbol^previous_symbol;
      previous_symbol=precoded_data[i+:`PCIe_PL_SYMBOL_W];
    end

    `uvm_info("PCIe_PL_MODEL",$sformatf("PRECODE_OUTPUT=%0b",precoded_data),UVM_LOW)
    `uvm_info("PCIe_PL_MODEL",$sformatf("EXIT_FROM_PRE_ENCODE_TASK"),UVM_LOW)
  endtask

  task tx_process(
    input bit[`PCIe_PL_PIPE_WORD_W-1:0] data_in,
    output bit[`PCIe_PL_PIPE_WORD_W-1:0] data_out
  );

    bit[`PCIe_PL_PIPE_WORD_W-1:0] scramble_data;
    bit[`PCIe_PL_PIPE_WORD_W-1:0] gray_data;
    bit[`PCIe_PL_PIPE_WORD_W-1:0] pre_data;
    bit parity;

    `uvm_info("PCIe_PL_MODEL","ENTERED_INTO_TX_PROCESS_TASK",UVM_LOW)
    `uvm_info("PCIe_PL_MODEL",$sformatf("The data_in_from PL inside tx_process is %d",data_in),UVM_LOW)

    case(mode)

      // NON-FLIT MODE
      NON_FLIT_MODE:
      begin
        `uvm_info("PCIe_PL_MODEL","TX_PROCESS:NON_FLIT_MODE",UVM_LOW)

        scramble_32(data_in,scramble_data);
        tx_gray_encode(scramble_data,gray_data);
        tx_parity_generate(gray_data,parity);

        tx_parity_q.push_back(parity);

        `uvm_info("PCIe_PL_MODEL",$sformatf("TX_PARITY=%0b PARITY_QUEUE_SIZE=%0d",parity,tx_parity_q.size()),UVM_LOW)

        tx_precoder(gray_data,pre_data);
        data_out=pre_data;
      end

      // FLIT MODE
      FLIT_MODE:
      begin
        `uvm_info("PCIe_PL_MODEL","TX_PROCESS:FLIT_MODE",UVM_LOW)

        scramble_32(data_in,scramble_data);
        tx_gray_encode(scramble_data,gray_data);
        tx_parity_generate(gray_data,parity);

        tx_parity_q.push_back(parity);

        `uvm_info("PCIe_PL_MODEL",$sformatf("TX_PARITY=%0b PARITY_QUEUE_SIZE=%0d",parity,tx_parity_q.size()),UVM_LOW)

        tx_precoder(gray_data,pre_data);
        data_out=pre_data;
      end

      default:
      begin
        `uvm_error("PCIe_PL_MODEL","INVALID_PCIe_MODE")
        data_out=data_in;
      end

    endcase

    `uvm_info("PCIe_PL_MODEL",$sformatf("TX_PROCESS_INPUT=%08h OUTPUT=%08h",data_in,data_out),UVM_LOW)
    `uvm_info("PCIe_PL_MODEL","EXIT_FROM_TX_PROCESS_TASK",UVM_LOW)
  endtask

  // PL model receives the 242-byte DL result.
  function void write(PCIe_sequence_item item);

    bit[`PCIe_PL_PIPE_WORD_W-1:0] temp;

    `uvm_info("EP_PL_MODEL",$sformatf("PL -> INTERFACE received 242-byte packet, payload=%p",item.dlp_flit_out),UVM_MEDIUM)

    dl_flit_out=item.dlp_flit_out;
    pl_qu.delete();

    for(int i=0;i<`PCIe_DLP_FLIT_BYTE_W;i+=`PCIe_PL_BYTES_PER_WORD)
    begin
      temp='0;

      for(int j=0;j<`PCIe_PL_BYTES_PER_WORD;j++)
      begin
        if((i+j)<`PCIe_DLP_FLIT_BYTE_W)
          temp[j*`PCIe_BYTE_W+:`PCIe_BYTE_W]=dl_flit_out[i+j];
      end

      pl_qu.push_back(temp);
    end

    `uvm_info("EP_PL_MODEL",$sformatf("PL -> INTERFACE received 242-byte packet, payload=%p",pl_qu),UVM_MEDIUM)

    pl_sent=1;
  endfunction

endclass

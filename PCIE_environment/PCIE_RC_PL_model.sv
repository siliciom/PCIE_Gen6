import typedef_enums::*;

class PCIE_RC_PL_model extends uvm_component;
   
  `uvm_component_utils(PCIE_RC_PL_model)
   pcie_mode_e mode;
   PCIE_env_config   pcie_ecfg;

   bit [22:0] lfsr;
   bit [22:0] polynomial;

   function new(string name="PCIE_RC_PL_model",uvm_component parent);
      super.new(name,parent);
   endfunction


   function void build_phase(uvm_phase phase);
      `uvm_info("PCIE_PL_MODEL","ENTERED_INTO_PL_MODEL_BUILD_PHASE",UVM_LOW)
     super.build_phase(phase);
       if(!uvm_config_db#(PCIE_env_config)::get(this,"","PCIE_env_config",pcie_ecfg))
     begin
      `uvm_fatal("PL_MODEL","Cannot_get_PCIE_env_config");
     end
     mode = pcie_ecfg.mode;
     polynomial = 23'b101000010000000100100101;
     reset_scrambler();
      `uvm_info("PCIE_PL_MODEL","EXIT_FROM_PL_MODEL_BUILD_PHASE",UVM_LOW)
   endfunction

   task reset_scrambler();
      lfsr = 23'h7FFFFF;
   endtask

   task scramble(input  bit [7:0] data_in,output bit [7:0] data_out);
      bit scramble_bit;
      data_out = data_in;
      `uvm_info("PCIE_PL_MODEL","ENTERED_INTO_SCRAMBLER_TASK",UVM_LOW)
      case(mode)
         //-------------------------------------
         // NON FLIT MODE
         //-------------------------------------
         NON_FLIT_MODE:
         begin
            for(int i=0;i<8;i++) begin
               scramble_bit = lfsr[22];
               data_out[i] = data_in[i] ^ scramble_bit;
               if(scramble_bit)
                  lfsr = (lfsr << 1) ^ polynomial;
               else
                  lfsr = (lfsr << 1);
            end
         end
         //-------------------------------------
         // FLIT MODE
         //-------------------------------------
         FLIT_MODE:
         begin
            for(int i=0;i<8;i++) begin
               scramble_bit = lfsr[22];
               data_out[i] = data_in[i] ^ scramble_bit;
               if(scramble_bit)
                  lfsr = (lfsr << 1) ^ polynomial;
               else
                  lfsr = (lfsr << 1);
            end
         end
      endcase
      `uvm_info("PCIE_PL_MODEL","EXIT_FROM_SCRAMBLER_TASK",UVM_LOW)
   endtask

endclass




/*class PCIE_RC_PL_model extends uvm_component;

  `uvm_component_utils(PCIE_RC_PL_model)

    function new(string name="PCIE_RC_PL_model" uvm_component parent);
      super.new(name,parent);
    endfunction
   
   pcie_mode_e mode;
   bit [22:0] lfsr;
   bit [22:0] polynomial;

   task configure(input pcie_mode_e cfg_mode);
      mode = cfg_mode;
      polynomial = 23'b101000010000000100100101;
      reset_scrambler();
   endtask

   task reset_scrambler();
      lfsr = 23'h7FFFFF;
   endtask

   task scramble(input  bit [7:0] data_in,output bit [7:0] data_out);
      bit scramble_bit;
      data_out = data_in;

      for(int i=0;i<8;i++)begin
         scramble_bit = lfsr[22];
         data_out[i] = data_in[i] ^ scramble_bit;
         if(scramble_bit)
            lfsr = (lfsr << 1) ^ polynomial;
         else
            lfsr = (lfsr << 1);
      end
   endtask

endclass*/
  


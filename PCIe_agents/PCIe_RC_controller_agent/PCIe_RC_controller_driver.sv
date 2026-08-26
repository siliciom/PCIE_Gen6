//=========================================================================================
// File         : PCIe_RC_controller_driver.sv
// Project      : PCIe_Gen6
// Description  : PCIe_agents\PCIe_RC_controller_agent\PCIe_RC_controller_driver.sv
// Author       : 
// Date         : 2026-08-14
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

class PCIe_RC_controller_driver extends uvm_driver #(PCIe_sequence_item);
  
  `uvm_component_utils(PCIe_RC_controller_driver)
   uvm_analysis_port #(PCIe_sequence_item) tx_ap;
  
   PCIe_sequence_item            pcie_seq_item;
   PCIe_sequence_item            replayed_item;
   PCIe_sequence_item            nak_item;

   PCIe_RC_TL_model              rc_tl_model;
   PCIe_RC_DL_model              rc_dl_model;
   PCIe_RC_PL_model              rc_pl_model;

   int count=1; // only for debug remove later
   bit[31:0] scr_data;

   virtual PCIe_RC_interface     rc_pipe_intf_tx, rc_pipe_intf_rx;	
	
   function new(string name="PCIe_RC_controller_driver", uvm_component parent);
     super.new(name,parent);
     tx_ap=new("tx_ap",this);
   endfunction

   function void build_phase(uvm_phase phase);
    `uvm_info("RC_CONTROLLER","ENTERED_INTO_RC_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
     super.build_phase(phase);
      pcie_seq_item = PCIe_sequence_item::type_id::create("pcie_seq_item");
      replayed_item = PCIe_sequence_item::type_id::create("replayed_item");
      nak_item = PCIe_sequence_item::type_id::create("nak_item");
	
      if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_tx))
       `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")

      if (!uvm_config_db#(virtual PCIe_RC_interface)::get(this, "", "PCIe_RC_INTERFACE", rc_pipe_intf_rx))
       `uvm_fatal("NO_VIF", "RC_PIPE_INTERFACE_not_found")
       `uvm_info("RC_CONTROLLER","EXIT_FROM_RC_CONTROLLER_DRIVER_BUILD_PHASE",UVM_LOW)
  	endfunction

    task run_phase(uvm_phase phase);
      `uvm_info("RC_CONTROLLER", "ENTERED_INTO_RC_CONTROLLER_DRIVER_RUN_PHASE", UVM_LOW)
     forever begin
       seq_item_port.get_next_item(pcie_seq_item);
	    if(!rc_dl_model.RC_REPLAY_IN_PROGRESS)
	    begin
          tx_ap.write(pcie_seq_item);//sending to the rc tl model
	    
          wait(rc_pl_model.pl_sent);
         `uvm_info("RC_CONTROLLER",$sformatf("dl_flit_out is %p",rc_pl_model.dl_flit_out),UVM_LOW)
	      for(int i=0 ; i<242; i++)
	      begin
	        rc_pl_model.tx_process(rc_pl_model.dl_flit_out[i],scr_data);
	        @(posedge rc_pipe_intf_tx.pclk);
              rc_pipe_intf_tx.tx_data <= scr_data;
              rc_pipe_intf_tx.tx_valid         <= 1'b1;
	      end
	         @(posedge rc_pipe_intf_tx.pclk);
	           rc_pl_model.pl_sent=0;
               rc_pipe_intf_tx.tx_valid <= 1'b0;
	    end
        seq_item_port.item_done();
      end
     endtask

endclass


	/*// dummy task for the debug
	task drive_256_bytes();
		 bit[7:0]data[256];
		 foreach(data[i]) begin
                   data[i]=$urandom_range(1,100);
		   if(i==236)
	             begin
		     data[236]=8'b00000000;
		     data[237]=count;
		     count=count+1;
		     end
		 end
		 $display("dummy data formed is %p",data);
		for (int i = 0; i < 256; i += 4) begin
		 @(posedge rc_pipe_intf_tx.pclk);
		 rc_pipe_intf_tx.rx_valid<=1;
		 rc_pipe_intf_tx.rx_data[31:0] <= {data[i+3],data[i+2],data[i+1],data[i]};
		 if(i==240)
	            begin
		    rc_pipe_intf_tx.rx_valid<=0;
	            end
		 //$display("driver driving on the interface data is %h",rc_pipe_intf_tx.rx_data);
	        end
         endtask


	 task handle_replay_request(bit [9:0] N);
		//rc_dl_model.RC_REPLAY_IN_PROGRESS=1'b1; 
    	       foreach(rc_dl_model.tx_retry_buffer[i]) 
	       begin
	       replayed_item.seq_num = rc_dl_model.tx_retry_buffer[i].seq_num;	
               replayed_item.tlp_data = rc_dl_model.tx_retry_buffer[i].tlp_data;
	       // Handle Replay Types
               if(rc_dl_model.REPLAY_SCHEDULED_TYPE == STANDARD_REPLAY) begin
		       if(replayed_item.seq_num >=N)
		       begin
            	       tx_ap.write(replayed_item); // Send everything in the buffer
           `uvm_info("RC_CONTROLLER", "writing on the port now....", UVM_LOW)
		        end
        	end 
      	       else if (rc_dl_model.REPLAY_SCHEDULED_TYPE == SELECTIVE_REPLAY) begin
                tx_ap.write(replayed_item); 
                break; // Stop after replaying ONLY the first unacknowledged flit (N+1)
                end
                end
                rc_dl_model.RC_REPLAY_IN_PROGRESS = 1'b0;
	 endtask 
	*/






	 /*else if(rc_dl_model.RC_REPLAY_IN_PROGRESS)
         begin
         `uvm_info("RC_CONTROLLER", "ENTERED_INTO_RC_CONTROLLER_DRIVER_REPLAY_SECTION", UVM_LOW)
	 handle_replay_request(rc_dl_model.TX_REPLAY_FLIT_SEQ_NUM); 
         end
	 else if(rc_dl_model.NAK_SCHEDULED)
	 begin
	     nak_item.tlp_data=0;
	 nak_item.is_payload=1;
	 tx_ap.write(nak_item);
	 end
	 else 
	 begin
	// form and replay the ack packet by default
	 end */

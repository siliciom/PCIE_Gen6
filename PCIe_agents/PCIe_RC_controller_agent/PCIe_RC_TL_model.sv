//=========================================================================================
// File         : PCIe_RC_TL_model.sv
// Project      : PCIE_Gen6
// Description  : PCIe_agents\PCIe_RC_controller_agent\PCIe_RC_TL_model.sv
// Author       : 
// Date         : 2026-09-09
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

import typedef_enums :: *;

class PCIe_RC_TL_model extends uvm_component;

  `uvm_component_utils(PCIe_RC_TL_model)

  //--------------------------------------------------------------------------
  // TLM ports  (names kept identical to the integration environment)
  //--------------------------------------------------------------------------
  // Input from RC controller driver.
  uvm_analysis_imp #(PCIe_sequence_item, PCIe_RC_TL_model) tl_imp;
  // Output toward RC DL model.
  uvm_analysis_port #(PCIe_sequence_item) tl_ap;

  PCIe_sequence_item item;

  //--------------------------------------------------------------------------
  // Configuration knobs
  //--------------------------------------------------------------------------
  // There is no EP->RC upstream path in this environment yet, so completion
  // tracking is recorded but never blocked on. Flip to 1 once the DL model
  // exposes a dl2tl path back into cpl_write().
  bit          wait_for_completion = 1'b0;

  // Outstanding non-posted requests, keyed by tag.
  protected PCIe_sequence_item outstanding [bit [`PCIe_TL_TAG_W-1:0]];

  //--------------------------------------------------------------------------
  function new(string name="PCIe_RC_TL_model", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info("RC_TL_MODEL","ENTERED_INTO_RC_TL_MODEL_BUILD_PHASE",UVM_LOW)
     tl_imp = new("tl_imp", this);
     tl_ap  = new("tl_ap",  this);
    `uvm_info("RC_TL_MODEL","EXIT_FROM_RC_TL_MODEL_BUILD_PHASE",UVM_LOW)
  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: write (tl_imp) - entry point from the RC controller driver.
  //--------------------------------------------------------------------------
  virtual function void write(PCIe_sequence_item tr);
    `uvm_info("RC_TL_MODEL", $sformatf("RECEIVED_TL_PAYLOAD_FROM_RC_CONTROLLER_DRIVER %s", tr.pkt_mode.name()), UVM_LOW)
     send_tlp(tr);
  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: send_tlp - build the complete TLP / FLIT and push it to the DL.
  //--------------------------------------------------------------------------
  virtual function void send_tlp(PCIe_sequence_item tr);

    bit [`PCIe_TL_DATA_DW_W-1:0] hdr[];

    serialize_header(tr, hdr);       // Header Base + OHC
    tr.hdr_dw_count = hdr.size();

    build_complete_tlp(tr, hdr);     // Header + OHC + Payload -> serialized_tlp

    // FLIT MODE : pack the TLP into the 236 byte FLIT TLP region and pad the
    // remainder with NOP TLPs (Sec 2.2.1.2). Non-Flit Mode has no such region.
    if (tr.pkt_mode == FLIT)
      assemble_flit(tr);

    `uvm_info(get_type_name(),
      $sformatf("[TL->DL] RC-TL launch: %s | header_dw=%0d payload_dw=%0d total_dw=%0d",
                 tr.convert2string(), tr.tlp_header_dw_count,
                 tr.tlp_payload_dw_count, tr.tlp_total_dw_count), UVM_MEDIUM);

    //----------------------------------------------------------------------
    // Track non-posted requests (completion matching, when it is wired up)
    //----------------------------------------------------------------------
    if (is_non_posted(tr)) begin
      outstanding[tr.tag] = tr;
    end

    //----------------------------------------------------------------------
    // Hand the 236 byte TLP region to the DL in the field it consumes
    //----------------------------------------------------------------------
    pack_to_tlp_data(tr);

    `uvm_info(get_type_name(), "[TL->DL] TLP_SENT_TO_DL", UVM_MEDIUM);
     tl_ap.write(tr);

  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: pack_to_tlp_data
  //
  //   The DL model consumes item.tlp_data - a packed 236 byte array where
  //   byte 0 is the first byte on the wire - inside form_dl_packet().
  //   Flatten the TL's DW output into it, MSB-first within each DW (same byte
  //   order used by print_flit_region), and zero-fill anything beyond.
  //--------------------------------------------------------------------------
  virtual function void pack_to_tlp_data(PCIe_sequence_item tr);

    bit [`PCIe_TL_DATA_DW_W-1:0] src[];
    int nbytes;
    int b;

    // FLIT mode  : the padded 236 byte region (59 DW)
    // NON-FLIT   : the raw serialized TLP, zero padded up to 236 B
    if (tr.pkt_mode == FLIT)
      src = tr.flit_tlp_region;
    else
      src = tr.serialized_tlp;

    tr.tlp_data = '0;                                 // clear all 236 bytes

    nbytes = src.size() * 4;
    if (nbytes > `PCIe_TLP_DATA_BYTE_W)
      nbytes = `PCIe_TLP_DATA_BYTE_W;                 // longer than one flit -> truncate

    for (b = 0; b < nbytes; b++)
      tr.tlp_data[b] = src[b/4][ 8*(3-(b%4)) +: 8 ];

    // DL flags : this flit carries a real TLP payload
    tr.is_payload = 1'b1;
    tr.drive_flit = (tr.pkt_mode == FLIT);

    `uvm_info("RC_TL_MODEL",
      $sformatf("PACKED_FOR_DL : mode=%s src_dw=%0d packed_bytes=%0d",
                 tr.pkt_mode.name(), src.size(), nbytes), UVM_LOW)

    print_tlp_data(tr);

  endfunction

  //--------------------------------------------------------------------------
  // Dump the 236 bytes exactly as the DL will receive them
  //--------------------------------------------------------------------------
  virtual function void print_tlp_data(PCIe_sequence_item tr);

    string line;
    string dump;
    int    b;

    dump = "\n";
    line = "";

    for (b = 0; b < `PCIe_TLP_DATA_BYTE_W; b++) begin
      if ((b % `PCIe_FLIT_DUMP_BPL) == 0)
        line = $sformatf("  [%3d] :", b);

      line = {line, $sformatf(" %02h", tr.tlp_data[b])};

      if (((b % `PCIe_FLIT_DUMP_BPL) == `PCIe_FLIT_DUMP_BPL-1) ||
          (b == `PCIe_TLP_DATA_BYTE_W-1)) begin
        dump = {dump, line, "\n"};
      end
    end

    `uvm_info("TL_TO_DL_236B", dump, UVM_LOW)

  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: is_non_posted - reads, MRdLk, DMWr, and all cfg expect a Cpl.
  //--------------------------------------------------------------------------
  virtual function bit is_non_posted(PCIe_sequence_item tr);
    case (tr.txn_type)
      PCIe_TL_MEM : return (!tr.is_write()) || tr.mem_deferrable;
      PCIe_TL_IO  : return 1'b1;
      PCIe_TL_CFG : return 1'b1;
      PCIe_TL_MSG : return 1'b0;
      default     : return 1'b0;
    endcase
  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: cpl_write - inbound completion; match by tag, copy fields.
  //   Not connected yet (no upstream path in this environment). Call this from
  //   a future RC_DL dl2tl analysis port.
  //--------------------------------------------------------------------------
  virtual function void cpl_write(PCIe_sequence_item cpl);
    PCIe_sequence_item req_h;
    if (outstanding.exists(cpl.tag)) begin
      req_h = outstanding[cpl.tag];
      req_h.cpl_data   = cpl.cpl_data;
      req_h.cpl_status = cpl.cpl_status;
      outstanding.delete(cpl.tag);
      `uvm_info(get_type_name(),
        $sformatf("RC-TL got completion tag=0x%0h status=%0d dw=%0d",
                   cpl.tag, cpl.cpl_status, cpl.cpl_data.size()), UVM_LOW)
    end
    else begin
      `uvm_warning(get_type_name(),
        $sformatf("Unexpected/duplicate completion tag=0x%0h", cpl.tag))
    end
  endfunction

  //--------------------------------------------------------------------------
  // FUNCTION: serialize_header
  //
  //   NON_FLIT : Fmt[2:0] + Type[4:0], 3DW / 4DW headers
  //   FLIT     : Type[7:0], Header Base size determined by Type, OHC appended
  //--------------------------------------------------------------------------
  virtual function void serialize_header(PCIe_sequence_item tr,
                                         ref bit [`PCIe_TL_DATA_DW_W-1:0] hdr[]);

    `uvm_info("RC_TL_MODEL",
      $sformatf("ENTERED_INTO_SERIALIZE_HEADER_FOR_%s", tr.pkt_mode.name()), UVM_LOW)

    if (tr.pkt_mode == FLIT)
      serialize_flit_header(tr, hdr);
    else
      serialize_non_flit_header(tr, hdr);

  endfunction

  //--------------------------------------------------------------------------
  // NON-FLIT TLP HEADER
  //--------------------------------------------------------------------------
  virtual function void serialize_non_flit_header(PCIe_sequence_item tr,
                                                  ref bit [`PCIe_TL_DATA_DW_W-1:0] hdr[]);

    bit [`PCIe_TL_FMTTYPE_W-1:0] ft;
    bit [`PCIe_TL_DATA_DW_W-1:0] dw0;
    bit [`PCIe_TL_DATA_DW_W-1:0] dw1;
    bit [`PCIe_TL_DATA_DW_W-1:0] dw2;
    bit [`PCIe_TL_DATA_DW_W-1:0] dw3;

    ft = tr.get_fmttype();

    dw0 = '0;
    dw1 = '0;
    dw2 = '0;
    dw3 = '0;

    //======================================================================
    // DW0 - PCIe Base 6.0 Fig 2-5 / Fig 2-31 (Non-Flit Mode)
    //
    //   byte0  [31:24] = Fmt[2:0] , Type[4:0]
    //   byte1  [23]    = T9   (Tag[9])
    //          [22:20] = TC[2:0]
    //          [19]    = T8   (Tag[8])
    //          [18]    = A2   (Attr[2] - IDO)
    //          [17]    = R    (Reserved - was LN, deprecated)
    //          [16]    = TH
    //   byte2  [15]    = TD
    //          [14]    = EP
    //          [13:12] = Attr[1:0]
    //          [11:10] = AT[1:0]
    //          [9:8]   = Length[9:8]
    //   byte3  [7:0]   = Length[7:0]
    //======================================================================

    dw0[31:24] = ft;

    // Tag[9] / Tag[8] - non-contiguous with Tag[7:0] in Non-Flit Mode
    dw0[23]    = tr.tag[9];
    dw0[22:20] = tr.tc;
    dw0[19]    = tr.tag[8];

    // Attr[2] (IDO)
    dw0[18]    = tr.attr[2];

    // dw0[17] Reserved (deprecated LN bit) ; dw0[16] TH - not modelled

    dw0[15]    = tr.td;
    dw0[14]    = tr.ep;
    dw0[13:12] = tr.attr[1:0];
    dw0[11:10] = tr.at;
    dw0[9:0]   = tr.length;

    //======================================================================
    // DW1
    //   [31:16] Requester ID
    //   [15:8]  Tag[7:0]
    //   [7:4]   Last DW BE
    //   [3:0]   First DW BE
    //======================================================================

    dw1[31:16] = tr.requester_id;
    dw1[15:8]  = tr.tag[7:0];
    dw1[7:4]   = tr.last_dw_be;
    dw1[3:0]   = tr.first_dw_be;

    //======================================================================
    // Address / Request-specific header
    //======================================================================
    case (tr.txn_type)

      PCIe_TL_MEM: begin
        if (tr.is_4dw()) begin
          // 4DW Memory Request
          dw2 = tr.address[63:32];
          dw3 = {tr.address[31:2], 2'b00};
          hdr = new[4];
          hdr[0] = dw0;
          hdr[1] = dw1;
          hdr[2] = dw2;
          hdr[3] = dw3;
        end
        else begin
          // 3DW Memory Request
          dw2 = {tr.address[31:2], 2'b00};
          hdr = new[3];
          hdr[0] = dw0;
          hdr[1] = dw1;
          hdr[2] = dw2;
        end
      end

      PCIe_TL_IO: begin
        dw2 = {tr.address[31:2], 2'b00};
        hdr = new[3];
        hdr[0] = dw0;
        hdr[1] = dw1;
        hdr[2] = dw2;
      end

      PCIe_TL_CFG: begin
        dw2 = '0;
        dw2[31:24] = tr.cfg_bus_num;
        dw2[23:19] = tr.cfg_dev_num;
        dw2[18:16] = tr.cfg_fn_num;
        dw2[11:2]  = tr.cfg_reg_num[11:2];
        hdr = new[3];
        hdr[0] = dw0;
        hdr[1] = dw1;
        hdr[2] = dw2;
      end

      PCIe_TL_MSG: begin
        dw0[26:24] = tr.msg_route;
        dw1[7:0]   = tr.msg_code;
        dw2 = '0;
        hdr = new[3];
        hdr[0] = dw0;
        hdr[1] = dw1;
        hdr[2] = dw2;
      end

      default: begin
        hdr = new[1];
        hdr[0] = dw0;
      end
    endcase

  endfunction

  //==========================================================================
  // Serialize OHC
  //==========================================================================
  virtual function void serialize_ohc(PCIe_sequence_item tr,
                                      ref bit [`PCIe_TL_DATA_DW_W-1:0] ohc_data[]);

    bit [`PCIe_TL_DATA_DW_W-1:0] dw;

    dw = '0;

    //----------------------------------------------------------------------
    // No OHC
    //----------------------------------------------------------------------
    if (tr.ohc[0] == 1'b0) begin
      ohc_data = new[0];
      return;
    end

    case (tr.ohc_a_type)

      OHC_A1: begin   // OHC-A1 - explicit Byte Enables
                dw = '0;
                dw[7:4] = tr.last_dw_be;   // [7:4] = Last DW BE
                dw[3:0] = tr.first_dw_be;  // [3:0] = First DW BE
                ohc_data = new[1];
                ohc_data[0] = dw;
      end
      OHC_A2: begin   // OHC-A2 - IO Requests (Fig 2-8)
                dw = '0;
                // [31:8] Reserved
                dw[7:4] = tr.last_dw_be;   // must be 0000b for IO
                dw[3:0] = tr.first_dw_be;
                ohc_data = new[1];
                ohc_data[0] = dw;
      end
      OHC_A3: begin  // OHC-A3 - Configuration
                dw = '0;
                ohc_data = new[1];
                ohc_data[0] = dw;
      end
      OHC_A4: begin   // OHC-A4 - Message
                dw = '0;
                ohc_data = new[1];
                ohc_data[0] = dw;
      end
      OHC_A5: begin  // OHC-A5 - Completion
                dw = '0;
                ohc_data = new[1];
                ohc_data[0] = dw;
      end
      default: begin
                ohc_data = new[0];
      end
    endcase

  endfunction

  //==========================================================================
  // FLIT HEADER SERIALIZER
  //
  //   32-bit Address : Header Base = 3 DW
  //   64-bit Address : Header Base = 4 DW
  //   OHC is appended after the Header Base.
  //==========================================================================
  virtual function void serialize_flit_header(PCIe_sequence_item tr,
                                              ref bit [`PCIe_TL_DATA_DW_W-1:0] hdr[]);

    bit [`PCIe_TL_DATA_DW_W-1:0] dw0;
    bit [`PCIe_TL_DATA_DW_W-1:0] dw1;
    bit [`PCIe_TL_DATA_DW_W-1:0] dw2;
    bit [`PCIe_TL_DATA_DW_W-1:0] dw3;

    bit [`PCIe_TL_DATA_DW_W-1:0] ohc_data[];

    pcie_flit_type_e flit_type;

    bit [`PCIe_TL_DATA_DW_W-1:0] tmp[];

    int header_base_dw;
    int ohc_dw;
    int total_header_dw;
    int i;

    tr.determine_ohc();               // Determine OHC
    flit_type = tr.get_flit_type();   // FLIT Type

    //======================================================================
    // Header Base size
    //======================================================================
    if (tr.is_64bit_addr())
      header_base_dw = 4;
    else
      header_base_dw = 3;

    dw0 = '0;
    dw1 = '0;
    dw2 = '0;
    dw3 = '0;

    //======================================================================
    // DW0
    //   [31:24] Type   [23:21] TC   [20:16] OHC
    //   [15:13] TS     [12:10] Attr [9:0]   Length
    //======================================================================
    dw0[31:24] = flit_type;
    dw0[23:21] = tr.tc;
    dw0[20:16] = tr.ohc;
    dw0[15:13] = tr.ts;
    dw0[12:10] = tr.attr;
    dw0[9:0]   = tr.length;

    //======================================================================
    // DW1
    //   [31:16] Requester ID   [15] EP   [14] Reserved   [13:0] Tag
    //======================================================================
    dw1[31:16] = tr.requester_id;
    dw1[15]    = tr.ep;
    dw1[14]    = 1'b0;
    dw1[13:0]  = tr.tag;

    //======================================================================
    // MEMORY REQUEST
    //======================================================================
    if (tr.txn_type == PCIe_TL_MEM) begin

      if (tr.is_64bit_addr()) begin
        // 64-bit address
        dw2 = tr.address[63:32];

        dw3 = '0;
        dw3[31:2] = tr.address[31:2];
        dw3[1:0]  = tr.at;

        hdr = new[header_base_dw];
        hdr[0] = dw0;
        hdr[1] = dw1;
        hdr[2] = dw2;
        hdr[3] = dw3;
      end

      else begin
        // 32-bit address
        dw2 = '0;
        dw2[31:2] = tr.address[31:2];
        dw2[1:0]  = tr.at;

        hdr = new[header_base_dw];
        hdr[0] = dw0;
        hdr[1] = dw1;
        hdr[2] = dw2;
      end

    end

    //======================================================================
    // IO REQUEST - Flit Mode (Fig 2-41)
    //   Header Base is always 3 DW (IO is 32-bit addressed only).
    //   DW2 = Address[31:2], bits [1:0] Reserved (AT is Memory-only in Flit).
    //   OHC-A2 is mandatory for all IO Requests (Sec 2.2.5.2).
    //======================================================================
    else if (tr.txn_type == PCIe_TL_IO) begin

      dw2 = '0;
      dw2[31:2] = tr.address[31:2];
      dw2[1:0]  = 2'b00;          // Reserved

      hdr = new[3];
      hdr[0] = dw0;
      hdr[1] = dw1;
      hdr[2] = dw2;

    end

    else begin
      hdr = new[1];
      hdr[0] = dw0;
    end

    //======================================================================
    // Serialize OHC and append it to the Header Base
    //======================================================================
    serialize_ohc(tr, ohc_data);

    ohc_dw = ohc_data.size();

    if (ohc_dw != 0) begin

      tmp = new[hdr.size() + ohc_dw];

      // Header Base
      for (i = 0; i < hdr.size(); i++)
        tmp[i] = hdr[i];

      // OHC
      for (i = 0; i < ohc_dw; i++)
        tmp[hdr.size() + i] = ohc_data[i];

      hdr = tmp;

    end

    total_header_dw = hdr.size();

    //======================================================================
    // PRINT HEADER INFORMATION
    //======================================================================
    `uvm_info("FLIT_HEADER",
      $sformatf({"\n",
        "         ---------------------------------------------\n",
        "                   PCIe Gen6 FLIT TLP HEADER\n",
        "         ---------------------------------------------\n",
        "         Packet Mode       : FLIT\n",
        "         Transaction Type  : %s\n",
        "         Direction         : %s\n",
        "         FLIT Type         : 0x%02h\n",
        "         Address           : 0x%016h\n",
        "         Address Mode      : %s\n",
        "         Payload Length    : %0d DW (%0d bytes)\n",
        "         Header Base       : %0d DW (%0d bytes)\n",
        "         OHC DWs           : %0d DW (%0d bytes)\n",
        "         TOTAL TLP HEADER  : %0d DW (%0d bytes)\n",
        "         ---------------------------------------------"},
        tr.txn_type.name(),
        tr.dir.name(),
        flit_type,
        tr.address,
        tr.is_64bit_addr() ? "64-bit" : "32-bit",
        tr.length,
        tr.length * 4,
        header_base_dw,
        header_base_dw * 4,
        ohc_dw,
        ohc_dw * 4,
        total_header_dw,
        total_header_dw * 4), UVM_LOW);

    foreach (hdr[i]) begin
      `uvm_info("FLIT_HEADER_DW", $sformatf("HEADER DW[%0d] = %08h", i, hdr[i]), UVM_LOW);
    end

  endfunction

  //==========================================================================
  // FLIT ASSEMBLY
  //
  //   A Gen6 FLIT is 256 bytes:
  //       236 B TLP region + 6 B DLP + 8 B CRC + 6 B FEC
  //
  //   The 236 B (59 DW) TLP region is a CONTAINER, not a single TLP. It holds
  //   one or more TLPs; whatever is left over must be filled with NOP TLPs.
  //
  //   PCIe Base 6.0 Sec 2.2.1.2:
  //     "It is required to transmit NOP TLPs while TLP transmission is active
  //      if there are no other TLPs to transmit..."
  //
  //   NOP = Type 8'h00, 1 DW Header Base, no payload -> the DW is all zeros.
  //==========================================================================
  virtual function void assemble_flit(PCIe_sequence_item tr);

    int tlp_dw;
    int nop_dw;
    int i;

    tlp_dw = tr.serialized_tlp.size();

    //----------------------------------------------------------------------
    // A TLP larger than the region has to be spread over several FLITs.
    // Multi-FLIT segmentation is not modelled yet - flag it rather than
    // silently truncating.
    //----------------------------------------------------------------------
    if (tlp_dw > `PCIe_FLIT_TLP_DW) begin
      `uvm_warning("FLIT_ASSEMBLY",
         $sformatf("TLP is %0d DW (%0d B) which exceeds the %0d DW (%0d B) FLIT TLP region - multi-FLIT segmentation is not implemented, region left unpadded",
                    tlp_dw, tlp_dw*4, `PCIe_FLIT_TLP_DW, `PCIe_FLIT_TLP_BYTES))
      tr.flit_tlp_region = new[tlp_dw];
      foreach (tr.serialized_tlp[i])
        tr.flit_tlp_region[i] = tr.serialized_tlp[i];
      tr.flit_tlp_dw_count = tlp_dw;
      tr.flit_nop_dw_count = 0;
      return;
    end

    nop_dw = `PCIe_FLIT_TLP_DW - tlp_dw;

    tr.flit_tlp_region   = new[`PCIe_FLIT_TLP_DW];
    tr.flit_tlp_dw_count = tlp_dw;
    tr.flit_nop_dw_count = nop_dw;

    // The TLP
    for (i = 0; i < tlp_dw; i++)
      tr.flit_tlp_region[i] = tr.serialized_tlp[i];

    // NOP TLP padding - one 1 DW NOP TLP per remaining DW
    for (i = tlp_dw; i < `PCIe_FLIT_TLP_DW; i++)
      tr.flit_tlp_region[i] = `PCIe_FLIT_NOP_DW;

    print_flit_region(tr);

  endfunction

  //==========================================================================
  // Dump the assembled 236 byte FLIT TLP region
  //==========================================================================
  virtual function void print_flit_region(PCIe_sequence_item tr);

    string line;
    string dump;
    int    b;
    int    total_bytes;
    bit [7:0] byte_val;
    bit    mark_line;

    total_bytes = tr.flit_tlp_region.size() * 4;

    `uvm_info("FLIT_REGION",
       $sformatf({"\n",
         "         ============================================================\n",
         "                    ASSEMBLED FLIT TLP REGION\n",
         "         ============================================================\n",
         "         TLP DWs           : %0d  (%0d bytes)\n",
         "         NOP padding DWs   : %0d  (%0d bytes)\n",
         "         TOTAL REGION DWs  : %0d  (%0d bytes)\n",
         "         FLIT on the wire  : %0d B TLP + %0d B DLP + %0d B CRC + %0d B FEC = %0d B\n",
         "         ============================================================"},
         tr.flit_tlp_dw_count, tr.flit_tlp_dw_count*4,
         tr.flit_nop_dw_count, tr.flit_nop_dw_count*4,
         tr.flit_tlp_region.size(), total_bytes,
         `PCIe_FLIT_TLP_BYTES, `PCIe_FLIT_DLP_BYTES, `PCIe_FLIT_CRC_BYTES,
         `PCIe_FLIT_FEC_BYTES, `PCIe_FLIT_TOTAL_BYTES), UVM_LOW)

    //----------------------------------------------------------------------
    // Byte dump, 16 bytes per line (byte 0 = first byte on the wire)
    //----------------------------------------------------------------------
    dump      = "\n";
    line      = "";
    mark_line = 1'b0;

    for (b = 0; b < total_bytes; b++) begin

      byte_val = tr.flit_tlp_region[b/4][ 8*(3-(b%4)) +: 8 ];

      if ((b % `PCIe_FLIT_DUMP_BPL) == 0) begin
        line      = $sformatf("  [%3d] :", b);
        mark_line = 1'b0;
      end

      line = {line, $sformatf(" %02h", byte_val)};

      if (b == (tr.flit_tlp_dw_count*4 - 1))
        mark_line = 1'b1;

      if (((b % `PCIe_FLIT_DUMP_BPL) == `PCIe_FLIT_DUMP_BPL-1) ||
          (b == total_bytes-1)) begin
        if (mark_line)
          line = {line, $sformatf("   <- TLP ends at byte %0d, NOP padding follows",
                                   tr.flit_tlp_dw_count*4 - 1)};
        dump = {dump, line, "\n"};
      end
    end

    `uvm_info("FLIT_REGION_BYTES", dump, UVM_LOW)

  endfunction

  //==========================================================================
  // Build complete serialized TLP :  Header + OHC + Payload
  //==========================================================================
  virtual function void build_complete_tlp(PCIe_sequence_item tr,
                                           input bit [`PCIe_TL_DATA_DW_W-1:0] hdr[]);

    int header_dw;
    int payload_dw;
    int total_dw;
    int i;

    header_dw  = hdr.size();
    payload_dw = tr.data.size();

    total_dw = header_dw + payload_dw;

    tr.serialized_tlp = new[total_dw];

    // Header + OHC
    for (i = 0; i < header_dw; i++)
      tr.serialized_tlp[i] = hdr[i];

    // Payload
    for (i = 0; i < payload_dw; i++)
      tr.serialized_tlp[header_dw + i] = tr.data[i];

    // Save counts
    tr.tlp_header_dw_count  = header_dw;
    tr.tlp_payload_dw_count = payload_dw;
    tr.tlp_total_dw_count   = total_dw;

    `uvm_info("FULL_TLP",
      $sformatf({"\n",
        "         ============================================================\n",
        "                       COMPLETE PCIe TLP\n",
        "         ============================================================\n",
        "         Packet Mode       : %s\n",
        "         Header DWs        : %0d\n",
        "         Header Bytes      : %0d\n",
        "         Payload DWs       : %0d\n",
        "         Payload Bytes     : %0d\n",
        "         TOTAL TLP DWs     : %0d\n",
        "         TOTAL TLP Bytes   : %0d\n",
        "         ============================================================"},
        (tr.pkt_mode == FLIT) ? "FLIT" : "NON-FLIT",
        header_dw,
        header_dw * 4,
        payload_dw,
        payload_dw * 4,
        total_dw,
        total_dw * 4), UVM_LOW);

    for (i = 0; i < total_dw; i++) begin
      if (i < header_dw) begin
        `uvm_info("FULL_TLP_DW",$sformatf("TLP DW[%0d] = %08h  <-- HEADER", i, tr.serialized_tlp[i]),UVM_LOW)
      end
      else begin
        `uvm_info("FULL_TLP_DW",$sformatf("TLP DW[%0d] = %08h  <-- PAYLOAD",i, tr.serialized_tlp[i]),UVM_LOW)
      end
    end

  endfunction

endclass

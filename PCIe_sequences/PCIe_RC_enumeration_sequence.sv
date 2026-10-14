//=========================================================================================
// File         : PCIe_RC_enumeration_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences\PCIe_RC_enumeration_sequence.sv
//                RC (Root Complex) side enumeration of the device below the
//                Root Port, Flit mode, Configuration Type 0 requests only.
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/

//////////////////////////////////////////////////////////////////////////////////////////
// WHAT THIS SEQUENCE DOES (in order)
//
//   STEP 1  Find the device   : CfgRd 000h -> Vendor ID / Device ID
//                               FFFFh or UR  -> no device, stop.
//   STEP 2  Identify it       : CfgRd 008h (Class Code / Revision)
//                               CfgRd 00Ch (Header Type, multi-function bit)
//                               CfgRd 02Ch (Subsystem IDs)
//   STEP 3  Size the BARs     : for BAR0..BAR5 : save -> write FFFFFFFFh ->
//                               read back -> size = ~(read & mask) + 1
//   STEP 4  Assign addresses  : give each implemented BAR an aligned address
//                               from the RC memory / IO pools, write it, read it back
//   STEP 5  Capabilities      : if Status[4] = 1, walk the list from 034h,
//                               find the PCI Express Capability (ID 10h),
//                               read Device/Link Cap + Link Status, program MPS/MRRS.
//                               Then walk the Extended Capabilities from 100h.
//   STEP 6  Interrupt line    : CfgRd 03Ch, write Interrupt Line if Int Pin != 0
//   STEP 7  Enable the device : Command register = Memory Space / IO Space /
//                               Bus Master Enable, read back and check
//   STEP 8  Print a summary
//
// HOW A CONFIG REQUEST IS SENT AND HOW ITS COMPLETION COMES BACK
//
//   sequence --start_item/finish_item--> RC driver -> RC TL -> RC DL -> RC PL -> PIPE
//   EP ... builds Cpl / CplD ... -> PIPE -> RC monitor -> RC DL -> RC TL.write_rc_dl_rx()
//   sequence --rc_tl.wait_completion(tag)--> gets the completion with the same tag
//
//   Every request uses a NEW tag, so each completion is matched to its request.
//
// WHICH DEVICE : Bus / Device / Function come from PCIe_defines.sv
//   `PCIe_EP_BUS_NUMBER, `PCIe_EP_DEVICE_NUMBER, `PCIe_EP_FUNCTION_NUMBER
// The other functions (0..7) of the same device are scanned only when the
// Header Type multi-function bit is 1.
//////////////////////////////////////////////////////////////////////////////////////////

class PCIe_RC_enumeration_sequence extends PCIe_RC_controller_base_sequence;

  `uvm_object_utils(PCIe_RC_enumeration_sequence)

  //------------------------------------------------------------------------
  // Knobs (can be changed from the test before start())
  //------------------------------------------------------------------------
  // EP Bus / Device / Function : taken from PCIe_defines.sv
  bit [7:0]    bus_num         = `PCIe_EP_BUS_NUMBER;
  bit [4:0]    dev_num         = `PCIe_EP_DEVICE_NUMBER;
  bit [2:0]    fn_num          = `PCIe_EP_FUNCTION_NUMBER;
  bit [15:0]   rc_requester_id = 16'h0000;             // Bus 0 / Dev 0 / Fn 0 = Root Port
  int unsigned cpl_timeout_ns  = 20000;                // wait for each completion

  // Address pools handed out to the BARs
  bit [31:0]   mem32_base      = 32'h8000_0000;        // non-prefetchable / 32-bit memory
  bit [63:0]   mem64_base      = 64'h0000_0010_0000_0000; // 64-bit prefetchable memory
  bit [31:0]   io_base         = 32'h0000_1000;        // I/O space

  // What the RC supports (used to program the device)
  bit [2:0]    rc_mps          = 3'b001;               // Max Payload Size  : 001b = 256 B
  bit [2:0]    rc_mrrs         = 3'b010;               // Max Read Request  : 010b = 512 B
  bit [7:0]    int_line_value  = 8'h0B;                // Interrupt Line given to the device

  //------------------------------------------------------------------------
  // Internal
  //------------------------------------------------------------------------
  PCIe_RC_TL_model          rc_tl;
  bit [`PCIe_TL_TAG_W-1:0]  next_tag = 'h40;
  bit                       first_request = 1'b1;   // first item also brings the link up

  int unsigned n_cfg_rd, n_cfg_wr, n_timeout, n_ur, n_func_found;
  string       summary_q[$];

  // Per-BAR result (filled for the function being enumerated)
  bit          bar_impl  [6];
  bit          bar_is_io [6];
  bit          bar_is_64 [6];
  bit          bar_pref  [6];
  bit [63:0]   bar_size  [6];
  bit [63:0]   bar_addr  [6];
  string       bar_note  [6];

  // Config space offsets used below
  localparam bit [11:0] CFG_ID        = 12'h000;
  localparam bit [11:0] CFG_CMD_STS   = 12'h004;
  localparam bit [11:0] CFG_CLASS     = 12'h008;
  localparam bit [11:0] CFG_HDR       = 12'h00C;
  localparam bit [11:0] CFG_BAR0      = 12'h010;
  localparam bit [11:0] CFG_SUBSYS    = 12'h02C;
  localparam bit [11:0] CFG_CAP_PTR   = 12'h034;
  localparam bit [11:0] CFG_INT       = 12'h03C;
  localparam bit [11:0] CFG_EXT_START = 12'h100;

  function new(string name="PCIe_RC_enumeration_sequence");
    super.new(name);
  endfunction

  //========================================================================
  // body
  //========================================================================
  task body();
    bit [31:0] id_dw, hdr_dw;
    bit [2:0]  st;
    bit        ok;
    bit        multi_fn;

    `uvm_info("RC_ENUM","==================== PCIe GEN6 ENUMERATION : START ====================",UVM_LOW)

    // Handle to the RC TL model : the place where completions arrive.
    if (!uvm_config_db#(PCIe_RC_TL_model)::get(m_sequencer, "", "rc_tl_model", rc_tl))
      `uvm_fatal("RC_ENUM","rc_tl_model handle not found in uvm_config_db (set in PCIe_RC_controller_agent::connect_phase)")

    `uvm_info("RC_ENUM", $sformatf("TARGET EP (from PCIe_defines.sv) : Bus=%0d Device=%0d Function=%0d",
              bus_num, dev_num, fn_num), UVM_LOW)

    // ---- The EP function from the define file must exist ----
    cfg_read(dev_num, fn_num, CFG_ID, id_dw, st, ok);
    if (!ok || id_dw[15:0] == 16'hFFFF || id_dw[15:0] == 16'h0000) begin
      `uvm_error("RC_ENUM", $sformatf("NO_DEVICE_FOUND at %0d:%0d.%0d (VID/DID=%08h ok=%0b status=%s)",
                 bus_num, dev_num, fn_num, id_dw, ok, rc_tl.cpl_status_str(st)))
      print_summary();
      return;
    end

    // ---- Multi-function? (Header Type bit 7) ----
    cfg_read(dev_num, fn_num, CFG_HDR, hdr_dw, st, ok);
    multi_fn = ok && hdr_dw[23];

    enumerate_function(dev_num, fn_num, id_dw);

    // ---- other functions of the same device (only if multi-function) ----
    if (multi_fn) begin
      for (int fn = 0; fn < 8; fn++) begin
        if (fn[2:0] == fn_num) continue;          // already done above
        cfg_read(dev_num, fn[2:0], CFG_ID, id_dw, st, ok);
        if (ok && id_dw[15:0] != 16'hFFFF && id_dw[15:0] != 16'h0000)
          enumerate_function(dev_num, fn[2:0], id_dw);
        else
          `uvm_info("RC_ENUM", $sformatf("FUNCTION %0d:%0d.%0d not present", bus_num, dev_num, fn), UVM_LOW)
      end
    end

    print_summary();
    `uvm_info("RC_ENUM","==================== PCIe GEN6 ENUMERATION : DONE =====================",UVM_LOW)
  endtask

  //========================================================================
  // enumerate_function : STEP 2 .. STEP 7 for one function
  //========================================================================
  task enumerate_function(bit [4:0] dev, bit [2:0] fn, bit [31:0] id_dw);
    bit [31:0] class_dw, hdr_dw, subsys_dw, cmd_dw, int_dw, rd;
    bit [2:0]  st;
    bit        ok;
    bit [7:0]  header_type;
    bit [15:0] cmd;
    bit        any_mem, any_io;
    bit [11:0] pcie_cap;
    string     s;

    `uvm_info("RC_ENUM", $sformatf("---------- FUNCTION %0d:%0d.%0d FOUND : VID=%04h DID=%04h ----------",
              bus_num, dev, fn, id_dw[15:0], id_dw[31:16]), UVM_LOW)
    n_func_found++;

    // ---------------- STEP 2 : identify ----------------
    cfg_read(dev, fn, CFG_CLASS,  class_dw,  st, ok);
    cfg_read(dev, fn, CFG_HDR,    hdr_dw,    st, ok);
    cfg_read(dev, fn, CFG_SUBSYS, subsys_dw, st, ok);
    header_type = hdr_dw[23:16];

    `uvm_info("RC_ENUM", $sformatf("  CLASS=%06h (base=%02h sub=%02h prog_if=%02h) REV=%02h HEADER_TYPE=%02h (%s, %s) SUBSYS_VID=%04h SUBSYS_ID=%04h",
              class_dw[31:8], class_dw[31:24], class_dw[23:16], class_dw[15:8], class_dw[7:0],
              header_type, (header_type[6:0] == 7'h00) ? "Type0 / Endpoint" :
                           (header_type[6:0] == 7'h01) ? "Type1 / Bridge" : "UNKNOWN",
              header_type[7] ? "multi-function" : "single-function",
              subsys_dw[15:0], subsys_dw[31:16]), UVM_LOW)

    if (header_type[6:0] != 7'h00) begin
      `uvm_warning("RC_ENUM", $sformatf("  %0d:%0d.%0d is not a Type 0 header (%02h) - BAR / bridge programming skipped",
                   bus_num, dev, fn, header_type))
      summary_q.push_back($sformatf("%0d:%0d.%0d  VID=%04h DID=%04h  HEADER_TYPE=%02h (not enumerated)",
                          bus_num, dev, fn, id_dw[15:0], id_dw[31:16], header_type));
      return;
    end

    // Turn decoding OFF before sizing BARs (Command bits 0 and 1 = 0)
    cfg_read(dev, fn, CFG_CMD_STS, cmd_dw, st, ok);
    cmd = cmd_dw[15:0] & ~16'h0003;
    cfg_write(dev, fn, CFG_CMD_STS, {16'h0000, cmd}, 4'b0011, st, ok);   // BE=0011 : do not touch Status (RW1C)

    // ---------------- STEP 3 + 4 : BARs ----------------
    size_and_assign_bars(dev, fn);

    // ---------------- STEP 5 : capabilities ----------------
    pcie_cap = 12'h000;
    if (cmd_dw[20]) begin                     // Status[4] = Capabilities List
      walk_capabilities(dev, fn, pcie_cap);
      if (pcie_cap != 12'h000)
        walk_ext_capabilities(dev, fn);
    end
    else begin
      `uvm_info("RC_ENUM", "  STATUS[4] (Capabilities List) = 0 : device has no capability list - STEP 5 skipped", UVM_LOW)
    end

    // ---------------- STEP 6 : interrupt line ----------------
    cfg_read(dev, fn, CFG_INT, int_dw, st, ok);
    if (ok && int_dw[15:8] != 8'h00) begin
      cfg_write(dev, fn, CFG_INT, {24'h0, int_line_value}, 4'b0001, st, ok);
      `uvm_info("RC_ENUM", $sformatf("  INTERRUPT_PIN=INT%s -> INTERRUPT_LINE programmed to %0d",
                string'(8'h40 + int_dw[15:8]), int_line_value), UVM_LOW)
    end

    // ---------------- STEP 7 : enable ----------------
    any_mem = 0; any_io = 0;
    for (int i = 0; i < 6; i++) if (bar_impl[i] && bar_note[i] == "") begin
      if (bar_is_io[i]) any_io = 1; else any_mem = 1;
    end
    cmd = cmd | 16'h0004;                     // bit 2 Bus Master Enable
    if (any_mem) cmd = cmd | 16'h0002;        // bit 1 Memory Space Enable
    if (any_io)  cmd = cmd | 16'h0001;        // bit 0 IO Space Enable
    cfg_write(dev, fn, CFG_CMD_STS, {16'h0000, cmd}, 4'b0011, st, ok);
    cfg_read (dev, fn, CFG_CMD_STS, rd, st, ok);
    if (rd[15:0] !== cmd)
      `uvm_error("RC_ENUM", $sformatf("  COMMAND_READBACK_MISMATCH : wrote %04h read %04h", cmd, rd[15:0]))
    else
      `uvm_info("RC_ENUM", $sformatf("  COMMAND=%04h (IO=%0b MEM=%0b BUS_MASTER=%0b) - device ENABLED",
                cmd, cmd[0], cmd[1], cmd[2]), UVM_LOW)

    // ---------------- summary lines for this function ----------------
    summary_q.push_back($sformatf("%0d:%0d.%0d  VID=%04h DID=%04h  CLASS=%06h REV=%02h  HEADER=Type0  COMMAND=%04h",
                        bus_num, dev, fn, id_dw[15:0], id_dw[31:16], class_dw[31:8], class_dw[7:0], rd[15:0]));
    for (int i = 0; i < 6; i++) begin
      if (!bar_impl[i] && bar_note[i] == "") continue;
      if (bar_note[i] != "") s = $sformatf("    BAR%0d : %s", i, bar_note[i]);
      else s = $sformatf("    BAR%0d : %s%s%s size=0x%0h (%0d B) assigned=0x%0h", i,
                         bar_is_io[i] ? "IO" : "MEM", bar_is_64[i] ? " 64-bit" : (bar_is_io[i] ? "" : " 32-bit"),
                         bar_pref[i] ? " prefetchable" : "", bar_size[i], bar_size[i], bar_addr[i]);
      summary_q.push_back(s);
    end
  endtask

  //========================================================================
  // STEP 3 + 4 : size every BAR and give it an address
  //========================================================================
  task size_and_assign_bars(bit [4:0] dev, bit [2:0] fn);
    bit [31:0] orig_lo, orig_hi, rd_lo, rd_hi, rd;
    bit [63:0] mask, size, addr;
    bit [2:0]  st;
    bit        ok, ok2;
    bit [11:0] off;
    int        i;

    for (int k = 0; k < 6; k++) begin
      bar_impl[k] = 0; bar_is_io[k] = 0; bar_is_64[k] = 0; bar_pref[k] = 0;
      bar_size[k] = 0; bar_addr[k] = 0; bar_note[k] = "";
    end

    i = 0;
    while (i < 6) begin
      off = CFG_BAR0 + 4*i;

      // save -> write all 1s -> read back
      cfg_read (dev, fn, off, orig_lo, st, ok);
      cfg_write(dev, fn, off, 32'hFFFF_FFFF, 4'hF, st, ok2);
      cfg_read (dev, fn, off, rd_lo, st, ok);

      if (!ok || rd_lo == 32'h0) begin                       // hard-wired 0 = not implemented
        `uvm_info("RC_ENUM", $sformatf("  BAR%0d : not implemented (reads 0 after writing FFFFFFFFh)", i), UVM_LOW)
        i++;
        continue;
      end

      //---------------- I/O BAR ----------------
      if (rd_lo[0] == 1'b1) begin
        if (rd_lo[1] != 1'b0) begin                          // bit 1 is reserved = 0 for an IO BAR
          bar_note[i] = $sformatf("ILLEGAL VALUE %08h after sizing (IO BAR bit1 must be 0) - EP BAR is not hard-wired, BAR ignored", rd_lo);
          `uvm_warning("RC_ENUM", $sformatf("  BAR%0d : %s", i, bar_note[i]))
          cfg_write(dev, fn, off, orig_lo, 4'hF, st, ok);    // put the old value back
          i++;
          continue;
        end
        mask = {32'h0, rd_lo & 32'hFFFF_FFFC};
        if (mask[31:16] == 16'h0) mask[31:16] = 16'hFFFF;    // 16-bit IO decoder
        size = (~mask + 1) & 64'h0000_0000_FFFF_FFFF;
        addr = align_up({32'h0, io_base}, size);
        io_base = addr[31:0] + size[31:0];
        bar_impl[i] = 1; bar_is_io[i] = 1; bar_size[i] = size; bar_addr[i] = addr;
        cfg_write(dev, fn, off, addr[31:0] | 32'h1, 4'hF, st, ok);
        cfg_read (dev, fn, off, rd, st, ok);
        check_bar_readback(i, {32'h0, rd & 32'hFFFF_FFFC}, addr);
        i++;
        continue;
      end

      //---------------- Memory BAR ----------------
      // [2:1] type : 00 = 32-bit, 10 = 64-bit, 01/11 = reserved.  [3] prefetchable
      if (rd_lo[2:1] == 2'b01 || rd_lo[2:1] == 2'b11) begin
        bar_note[i] = $sformatf("ILLEGAL VALUE %08h after sizing (memory type %02b reserved) - BAR ignored", rd_lo, rd_lo[2:1]);
        `uvm_warning("RC_ENUM", $sformatf("  BAR%0d : %s", i, bar_note[i]))
        cfg_write(dev, fn, off, orig_lo, 4'hF, st, ok);
        i++;
        continue;
      end

      bar_pref[i] = rd_lo[3];
      if (rd_lo[2:1] == 2'b10) begin                         // 64-bit : this BAR + the next one
        if (i == 5) begin
          bar_note[i] = "64-bit BAR in BAR5 has no upper half - BAR ignored";
          `uvm_warning("RC_ENUM", $sformatf("  BAR%0d : %s", i, bar_note[i]))
          cfg_write(dev, fn, off, orig_lo, 4'hF, st, ok);
          break;
        end
        cfg_read (dev, fn, off + 12'h4, orig_hi, st, ok);
        cfg_write(dev, fn, off + 12'h4, 32'hFFFF_FFFF, 4'hF, st, ok);
        cfg_read (dev, fn, off + 12'h4, rd_hi, st, ok);
        mask = {rd_hi, rd_lo & 32'hFFFF_FFF0};
        size = ~mask + 1;
        addr = align_up(mem64_base, size);
        mem64_base = addr + size;
        bar_impl[i] = 1; bar_is_64[i] = 1; bar_size[i] = size; bar_addr[i] = addr;
        cfg_write(dev, fn, off,          addr[31:0],  4'hF, st, ok);
        cfg_write(dev, fn, off + 12'h4,  addr[63:32], 4'hF, st, ok);
        cfg_read (dev, fn, off,          rd_lo, st, ok);
        cfg_read (dev, fn, off + 12'h4,  rd_hi, st, ok);
        check_bar_readback(i, {rd_hi, rd_lo & 32'hFFFF_FFF0}, addr);
        i += 2;                                              // upper half already used
      end
      else begin                                             // 32-bit memory
        mask = {32'hFFFF_FFFF, rd_lo & 32'hFFFF_FFF0};
        size = (~mask + 1) & 64'h0000_0000_FFFF_FFFF;
        addr = align_up({32'h0, mem32_base}, size);
        mem32_base = addr[31:0] + size[31:0];
        bar_impl[i] = 1; bar_size[i] = size; bar_addr[i] = addr;
        cfg_write(dev, fn, off, addr[31:0], 4'hF, st, ok);
        cfg_read (dev, fn, off, rd, st, ok);
        check_bar_readback(i, {32'h0, rd & 32'hFFFF_FFF0}, addr);
        i++;
      end
    end
  endtask

  function void check_bar_readback(int i, bit [63:0] got, bit [63:0] exp);
    if (got !== exp)
      `uvm_error("RC_ENUM", $sformatf("  BAR%0d : ADDRESS_READBACK_MISMATCH wrote 0x%0h read 0x%0h", i, exp, got))
    else
      `uvm_info("RC_ENUM", $sformatf("  BAR%0d : %s size=0x%0h -> assigned 0x%0h (readback OK)",
                i, bar_is_io[i] ? "IO" : (bar_is_64[i] ? "MEM64" : "MEM32"), bar_size[i], exp), UVM_LOW)
  endfunction

  // Round 'a' up to a multiple of 'size' (size is a power of 2)
  function bit [63:0] align_up(bit [63:0] a, bit [63:0] size);
    if (size == 0) return a;
    return (a + size - 1) & ~(size - 1);
  endfunction

  //========================================================================
  // STEP 5a : standard capability list (starts at 034h)
  //========================================================================
  task walk_capabilities(bit [4:0] dev, bit [2:0] fn, output bit [11:0] pcie_cap);
    bit [31:0] rd, devcap, devctl, linkcap, linksts;
    bit [2:0]  st;
    bit        ok;
    bit [7:0]  ptr;
    bit [2:0]  mps;
    int        guard;

    pcie_cap = 12'h000;
    cfg_read(dev, fn, CFG_CAP_PTR, rd, st, ok);
    ptr   = rd[7:0] & 8'hFC;
    guard = 0;

    while (ok && ptr != 8'h00 && guard < 48) begin
      guard++;
      cfg_read(dev, fn, {4'h0, ptr}, rd, st, ok);
      if (!ok) break;
      `uvm_info("RC_ENUM", $sformatf("  CAPABILITY @%03h : ID=%02h (%s) NEXT=%02h",
                ptr, rd[7:0], cap_name(rd[7:0]), rd[15:8]), UVM_LOW)

      if (rd[7:0] == 8'h10) begin                // PCI Express Capability
        pcie_cap = {4'h0, ptr};
        `uvm_info("RC_ENUM", $sformatf("    PCIe CAP : version=%0d device/port type=%0h (%s)",
                  rd[19:16], rd[23:20], port_type_name(rd[23:20])), UVM_LOW)
        cfg_read(dev, fn, pcie_cap + 12'h04, devcap,  st, ok);   // Device Capabilities
        cfg_read(dev, fn, pcie_cap + 12'h08, devctl,  st, ok);   // Device Control / Status
        cfg_read(dev, fn, pcie_cap + 12'h0C, linkcap, st, ok);   // Link Capabilities
        cfg_read(dev, fn, pcie_cap + 12'h10, linksts, st, ok);   // Link Control / Status
        `uvm_info("RC_ENUM", $sformatf("    DEVICE : MPS supported=%0d B | LINK : max speed=%s max width=x%0d | now speed=%s width=x%0d",
                  128 << devcap[2:0], speed_name(linkcap[3:0]), linkcap[9:4],
                  speed_name(linksts[19:16]), linksts[25:20]), UVM_LOW)

        // Max Payload Size = smaller of (device supports, RC supports)
        mps = (devcap[2:0] < rc_mps) ? devcap[2:0] : rc_mps;
        devctl[7:5]   = mps;
        devctl[14:12] = rc_mrrs;
        cfg_write(dev, fn, pcie_cap + 12'h08, {16'h0, devctl[15:0]}, 4'b0011, st, ok);  // keep Device Status
        `uvm_info("RC_ENUM", $sformatf("    DEVICE CONTROL programmed : MPS=%0d B MRRS=%0d B",
                  128 << mps, 128 << rc_mrrs), UVM_LOW)
        summary_q.push_back($sformatf("    PCIe CAP @%03h : link %s x%0d, MPS=%0d B, MRRS=%0d B",
                            pcie_cap, speed_name(linksts[19:16]), linksts[25:20], 128 << mps, 128 << rc_mrrs));
      end
      ptr = rd[15:8] & 8'hFC;
    end
  endtask

  //========================================================================
  // STEP 5b : extended capability list (starts at 100h, PCIe devices only)
  //========================================================================
  task walk_ext_capabilities(bit [4:0] dev, bit [2:0] fn);
    bit [31:0] rd;
    bit [2:0]  st;
    bit        ok;
    bit [11:0] ptr;
    int        guard;

    ptr   = CFG_EXT_START;
    guard = 0;
    while (ptr >= CFG_EXT_START && guard < 64) begin
      guard++;
      cfg_read(dev, fn, ptr, rd, st, ok);
      if (!ok || rd == 32'h0 || rd == 32'hFFFF_FFFF) begin
        if (ptr == CFG_EXT_START)
          `uvm_info("RC_ENUM", "  EXTENDED CAPABILITIES : none (100h reads 0 / FFFFFFFFh / UR)", UVM_LOW)
        break;
      end
      `uvm_info("RC_ENUM", $sformatf("  EXT CAPABILITY @%03h : ID=%04h VER=%0d NEXT=%03h",
                ptr, rd[15:0], rd[19:16], rd[31:20]), UVM_LOW)
      summary_q.push_back($sformatf("    EXT CAP @%03h : ID=%04h", ptr, rd[15:0]));
      ptr = rd[31:20] & 12'hFFC;
    end
  endtask

  //========================================================================
  // cfg_read / cfg_write : one Configuration Request + wait for its completion
  //   ok = 1 only when the completion came back with status SC
  //========================================================================
  task cfg_read(input bit [4:0] dev, input bit [2:0] fn, input bit [11:0] off,
                output bit [31:0] rdata, output bit [2:0] status, output bit ok);
    cfg_request(1'b0, dev, fn, off, 32'h0, 4'hF, rdata, status, ok);
  endtask

  task cfg_write(input bit [4:0] dev, input bit [2:0] fn, input bit [11:0] off,
                 input bit [31:0] wdata, input bit [3:0] be,
                 output bit [2:0] status, output bit ok);
    bit [31:0] unused;
    cfg_request(1'b1, dev, fn, off, wdata, be, unused, status, ok);
  endtask

  task cfg_request(input  bit        is_write,
                   input  bit [4:0]  dev,
                   input  bit [2:0]  fn,
                   input  bit [11:0] off,
                   input  bit [31:0] wdata,
                   input  bit [3:0]  be,
                   output bit [31:0] rdata,
                   output bit [2:0]  status,
                   output bit        ok);
    PCIe_sequence_item       req, cpl;
    bit [`PCIe_TL_TAG_W-1:0] tag;
    bit                      timed_out;

    rdata  = 32'h0;
    status = `PCIe_CPL_STATUS_SC;
    ok     = 1'b0;

    tag      = next_tag;
    next_tag = next_tag + 1'b1;
    if (next_tag == '0) next_tag = 'h40;      // wrap, skip the low tags used by other tests

    req = PCIe_sequence_item::type_id::create($sformatf("enum_cfg_%s_%03h", is_write ? "wr" : "rd", off));
    start_item(req);
    if (!req.randomize() with {
         // "local::" = take the value from THIS sequence, not from the item
         // LTSSM information (the first item of the test also brings the link up)
         electrical_idle_test == 1'b0;
         no_receiver_test     == 1'b0;
         tx_elec_idle         == 1'b1;
         pkt_mode             == FLIT;

         txn_type  == PCIe_TL_CFG;
         dir       == (local::is_write ? PCIe_TL_WRITE : PCIe_TL_READ);
         length    == `PCIe_TL_LEN_MIN;
         cfg_type1 == 1'b0;

         cfg_bus_num     == local::bus_num;
         cfg_dev_num     == local::dev;
         cfg_fn_num      == local::fn;
         cfg_reg_num     == {local::off[11:2], 2'b00};   // byte offset of the DW
         cfg_ext_reg_num == local::off[11:8];

         first_dw_be == local::be;
         last_dw_be  == 4'h0;

         if (local::is_write) { data.size() == 1; data[0] == local::wdata; }

         ep           == 1'b0;
         td           == 1'b0;
         tag          == local::tag;
         requester_id == local::rc_requester_id;

         tc   == 3'h0;
         ts   == 3'b000;
         attr == 3'h0;
         at   == 2'b00;

         io_data      == '0;
         msg_code     == '0;
         msg_route    == PCIe_MSG_ROUTE_TO_RC;
         msg_has_data == 1'b0;
         address      == '0;
       })
      `uvm_fatal("RC_ENUM", "randomize failed for the configuration request")
    req.is_payload = 1'b1;
    req.flit_type  = PCIe_PAYLOAD_flit;
    finish_item(req);

    if (is_write) n_cfg_wr++; else n_cfg_rd++;
    if (first_request) begin
      first_request = 1'b0;
      `uvm_info("RC_ENUM", "  (first request : link training + DL init were done by the driver with this item)", UVM_LOW)
    end

    // ---- wait for the completion with the same tag ----
    rc_tl.wait_completion(tag, cpl_timeout_ns, cpl, timed_out);

    if (timed_out) begin
      n_timeout++;
      `uvm_error("RC_ENUM", $sformatf("COMPLETION_TIMEOUT : CfgWr0/CfgRd0 %s %0d:%0d.%0d off=%03h tag=0x%0h - no completion in %0d ns",
                 is_write ? "WRITE" : "READ", bus_num, dev, fn, off, tag, cpl_timeout_ns))
      rdata = 32'hFFFF_FFFF;                  // what software sees when nothing answers
      return;
    end

    status = cpl.cpl_status;
    if (status != `PCIe_CPL_STATUS_SC) begin
      n_ur++;
      rdata = 32'hFFFF_FFFF;
      `uvm_info("RC_ENUM", $sformatf("  %s %03h -> completion status %s",
                is_write ? "CFG_WR" : "CFG_RD", off, rc_tl.cpl_status_str(status)), UVM_LOW)
      return;
    end

    if (!is_write) begin
      if (cpl.cpl_data.size() == 0) begin
        `uvm_error("RC_ENUM", $sformatf("CFG_RD %03h tag=0x%0h : SC completion without data", off, tag))
        return;
      end
      rdata = cpl.cpl_data[0];
      `uvm_info("RC_ENUM", $sformatf("  CFG_RD %0d:%0d.%0d off=%03h tag=0x%0h -> %08h", bus_num, dev, fn, off, tag, rdata), UVM_LOW)
    end
    else begin
      `uvm_info("RC_ENUM", $sformatf("  CFG_WR %0d:%0d.%0d off=%03h tag=0x%0h data=%08h be=%04b -> SC", bus_num, dev, fn, off, tag, wdata, be), UVM_LOW)
    end
    ok = 1'b1;
  endtask

  //========================================================================
  // STEP 8 : summary
  //========================================================================
  function void print_summary();
    string s;
    s = "\n  ======================== ENUMERATION SUMMARY ========================\n";
    s = {s, $sformatf("  functions found : %0d\n", n_func_found)};
    foreach (summary_q[i]) s = {s, "  ", summary_q[i], "\n"};
    s = {s, $sformatf("  config reads=%0d writes=%0d | non-SC completions=%0d | timeouts=%0d\n",
                      n_cfg_rd, n_cfg_wr, n_ur, n_timeout)};
    s = {s, "  ======================================================================"};
    `uvm_info("RC_ENUM", s, UVM_NONE)
  endfunction

  //========================================================================
  // small name helpers (for the log only)
  //========================================================================
  function string cap_name(bit [7:0] id);
    case (id)
      8'h01: return "Power Management";
      8'h05: return "MSI";
      8'h09: return "Vendor Specific";
      8'h10: return "PCI Express";
      8'h11: return "MSI-X";
      default: return "other";
    endcase
  endfunction

  function string speed_name(bit [3:0] s);
    case (s)
      4'h1: return "2.5GT/s";
      4'h2: return "5GT/s";
      4'h3: return "8GT/s";
      4'h4: return "16GT/s";
      4'h5: return "32GT/s";
      4'h6: return "64GT/s";
      default: return $sformatf("?(%0h)", s);
    endcase
  endfunction

  function string port_type_name(bit [3:0] t);
    case (t)
      4'h0: return "PCIe Endpoint";
      4'h1: return "Legacy Endpoint";
      4'h4: return "Root Port";
      4'h5: return "Upstream Switch Port";
      4'h6: return "Downstream Switch Port";
      4'h9: return "RCiEP";
      default: return "other";
    endcase
  endfunction

endclass




//=========================================================================================
// File         : PCIe_RC_enumeration_sequence.sv
// Project      : PCIE_Gen6
// Description  : PCIe_sequences\PCIe_RC_enumeration_sequence.sv
//                RC (Root Complex) side enumeration of the device below the
//                Root Port, Flit mode. Configuration Space is reached through
//                the host bridge with ECAM (default) or CAM.
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
//   STEP 5  Interrupt line    : CfgRd 03Ch, write Interrupt Line if Int Pin != 0
//   STEP 6  Enable the device : Command register = Memory Space / IO Space /
//                               Bus Master Enable, read back and check
//   STEP 7  Print a summary
//
// HOW SOFTWARE REACHES CONFIGURATION SPACE
//   The CPU cannot send a Configuration Request by itself. It accesses the
//   host bridge, and the host bridge turns that access into a CfgRd/CfgWr TLP.
//   The registers of both mechanisms live in this sequence (cfg_mech selects) :
//
//   ECAM (PCIe Base 6.2, Section 7.2.2) - default, reaches offset 000h-FFFh
//     One memory read / write inside the ECAM window. The memory address
//     itself says which register (Table 7-1) :
//       A[(20+n-1):20] Bus Number      (1 <= n <= 8, unmapped bus bits = 0)
//       A[19:15]       Device Number
//       A[14:12]       Function Number
//       A[11:8]        Extended Register Number
//       A[7:2]         Register Number
//       A[1:0]         with the access size -> Byte Enables
//     The window is 2^(n+20) bytes, base aligned to that size. Accesses that
//     cross a DW boundary are not translated. A write does not return until
//     its CfgWr completion is back, so software knows the write has landed
//     before it carries on (Section 7.2.2 ordering requirement).
//
//   CAM (PCIe Base 6.2, Section 7.2.1) - reaches offset 000h-0FFh only
//     step 1 : I/O write 0CF8h (CONFIG_ADDRESS) = which Bus/Dev/Fn/register
//     step 2 : I/O read/write 0CFCh (CONFIG_DATA) = the data -> TLP goes out
//     Extended Register Number is always 0.
//
//   Type 0 or Type 1 ? (Section 7.3, routing through the Root Port bridge)
//     target bus == Root Port Secondary Bus           -> Type 0 (CfgRd0/CfgWr0)
//     Secondary Bus < target bus <= Subordinate Bus   -> Type 1 (CfgRd1/CfgWr1)
//     anything else                                   -> not forwarded (reads FFFFFFFFh)
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
//
// Offsets, CAM ports and the ECAM window come from PCIe_RC_enumeration_params.sv
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

  // Configuration access mechanism : CFG_MECH_ECAM or CFG_MECH_CAM
  bit          cfg_mech        = CFG_MECH_ECAM;
  bit [63:0]   ecam_base       = ECAM_BASE_ADDRESS;    // aligned to 2^(n+20)
  int          ecam_bus_bits   = ECAM_BUS_BITS;        // n, 1..8(it can tell how many buses it supports)

  // Root Port bridge bus numbers (who is below the link)
  bit [7:0]    secondary_bus   = `PCIe_EP_BUS_NUMBER;  // bus right below the Root Port
  bit [7:0]    subordinate_bus = `PCIe_EP_BUS_NUMBER;  // highest bus below the Root Port

  // Address pools handed out to the BARs
  bit [31:0]   mem32_base      = 32'h8000_0000;        // non-prefetchable / 32-bit memory
  bit [63:0]   mem64_base      = 64'h0000_0010_0000_0000; // 64-bit prefetchable memory
  bit [31:0]   io_base         = 32'h0000_1000;        // I/O space

  bit [7:0]    int_line_value  = 8'h0B;                // Interrupt Line given to the device

  //------------------------------------------------------------------------
  // Host bridge registers
  //------------------------------------------------------------------------
  // CAM (I/O ports)
  bit [31:0]   config_address_reg;   // 0CF8h : CONFIG_ADDRESS
  bit [31:0]   config_data_reg;      // 0CFCh : CONFIG_DATA
  // ECAM (last memory access decoded by the host bridge)
  bit [63:0]   ecam_address_reg;     // memory address inside the ECAM window---  Helper variables to  remember last address 
  bit [31:0]   ecam_data_reg;        // write data / read completion data

  //------------------------------------------------------------------------
  // Internal
  //------------------------------------------------------------------------
  PCIe_RC_TL_model          rc_tl;
  bit [`PCIe_TL_TAG_W-1:0]  next_tag = 'h40;
  bit                       first_request = 1'b1;   // first configuration request of the test
  bit                       link_up_first = 1'b0;   // [LINK_FIRST] 1 = driver brought the link up before enumeration

  int unsigned n_cfg_rd, n_cfg_wr, n_timeout, n_ur, n_func_found;    // counters 
  string       summary_q[$];   // Summary for printing

  // Per-BAR result (filled for the function being enumerated)
  bit          bar_impl  [6];   // is the bar exists
  bit          bar_is_io [6];   // is the bar io or memory
  bit          bar_is_64 [6];   // is it a 64 bit address or 32-bit address
  bit          bar_pref  [6];   // about prefetchability
  bit [63:0]   bar_size  [6];   // how much space the bar needs
  bit [63:0]   bar_addr  [6];   // address given to the bar
  string       bar_note  [6];  // printing purpose

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

    // [LINK_FIRST] Enumeration runs only AFTER link training : wait until the
    // RC driver reports LTSSM L0 + DL_ACTIVE (global event "rc_link_ready").
    void'(uvm_config_db#(bit)::get(m_sequencer, "", "link_up_before_traffic", link_up_first));
    if (link_up_first) begin
      uvm_event link_ready_ev;
      link_ready_ev = uvm_event_pool::get_global("rc_link_ready");
      `uvm_info("RC_ENUM","WAITING_FOR_LINK_UP : LTSSM -> L0 and DLCMSM -> DL_ACTIVE (done by the RC driver)",UVM_LOW)
      link_ready_ev.wait_on();
      `uvm_info("RC_ENUM","LINK_READY (L0 + DL_ACTIVE) :: ENUMERATION STARTS NOW",UVM_LOW)
    end

    if (cfg_mech == CFG_MECH_ECAM) begin
      check_ecam_window();
      `uvm_info("RC_ENUM", $sformatf("CONFIG ACCESS MECHANISM : ECAM base=%016h n=%0d (buses 0..%0d, window %0d MB) | Root Port secondary bus=%0d subordinate bus=%0d",
                ecam_base, ecam_bus_bits, (1 << ecam_bus_bits) - 1, 1 << ecam_bus_bits, secondary_bus, subordinate_bus), UVM_LOW)
    end
    else begin
      `uvm_info("RC_ENUM", $sformatf("CONFIG ACCESS MECHANISM : CAM (I/O 0CF8h CONFIG_ADDRESS / 0CFCh CONFIG_DATA) | Root Port secondary bus=%0d subordinate bus=%0d",
                secondary_bus, subordinate_bus), UVM_LOW)
    end

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
  // enumerate_function : STEP 2 .. STEP 6 for one function
  //========================================================================
  task enumerate_function(bit [4:0] dev, bit [2:0] fn, bit [31:0] id_dw);
    bit [31:0] class_dw, hdr_dw, subsys_dw, cmd_dw, int_dw, rd;
    bit [2:0]  st;
    bit        ok;
    bit [7:0]  header_type;
    bit [15:0] cmd;
    bit        any_mem, any_io;
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

    // ---------------- STEP 5 : interrupt line ----------------
    cfg_read(dev, fn, CFG_INT, int_dw, st, ok);
    if (ok && int_dw[15:8] != 8'h00) begin
      cfg_write(dev, fn, CFG_INT, {24'h0, int_line_value}, 4'b0001, st, ok);
      `uvm_info("RC_ENUM", $sformatf("  INTERRUPT_PIN=INT%s -> INTERRUPT_LINE programmed to %0d",
                string'(8'h40 + int_dw[15:8]), int_line_value), UVM_LOW)
    end

    // ---------------- STEP 6 : enable ----------------
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
        mask = {32'h0, rd_lo & 32'hFFFF_FFFC};   // clears the last 2 bits (bit 0 and bit 1), which are type bits, not size
        if (mask[31:16] == 16'h0) mask[31:16] = 16'hFFFF;//Some I/O BARs only use the lower 16 bits, so their upper half reads back 0 (e.g. 0000_FF01). That would make the size calculation wrong, so the code fills the upper half with F’s.
        size = (~mask + 1) & 64'h0000_0000_FFFF_FFFF;
        addr = align_up({32'h0, io_base}, size);
        io_base = addr[31:0] + size[31:0];  // next available io address starts from here
        bar_impl[i] = 1; bar_is_io[i] = 1; bar_size[i] = size; bar_addr[i] = addr;
        cfg_write(dev, fn, off, addr[31:0] | 32'h1, 4'hF, st, ok); // write the address into bar1 and ( "| 1") keeps bit0 1
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
        cfg_write(dev, fn, off + 12'h4, 32'hFFFF_FFFF, 4'hF, st, ok);  // off + 4 for next bar
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
    return (a + size - 1) & ~(size - 1);//take the next free address and round it UP to a multiple of the BAR size because in pcie BAR's address should be multiple of it's size
  endfunction

  //========================================================================
  // cfg_read / cfg_write : what every enumeration step calls.
  //   They act like software and go through the host bridge :
  //     ECAM : one memory read / write inside the ECAM window
  //     CAM  : write CONFIG_ADDRESS (0CF8h), then read / write CONFIG_DATA (0CFCh)
  //   The host bridge part then calls cfg_request(), which sends the TLP.
  //   wdata / rdata are DW lane aligned (byte k on bits [8k+7:8k]).
  //   ok = 1 only when the completion came back with status SC
  //========================================================================
  task cfg_read(input bit [4:0] dev, input bit [2:0] fn, input bit [11:0] off,
                output bit [31:0] rdata, output bit [2:0] status, output bit ok);
    if (cfg_mech == CFG_MECH_ECAM) begin
      ecam_mem_read(make_ecam_address(bus_num, dev, fn, {off[11:2], 2'b00}), 4, rdata, status, ok);
      return;
    end
    if (off >= 12'h100) begin
      // CONFIG_ADDRESS has room only for offset 000h-0FCh
      `uvm_info("RC_CAM", $sformatf("  offset %03h is above 0FFh : not reachable with CF8/CFC -> FFFFFFFFh", off), UVM_LOW)
      rdata  = 32'hFFFF_FFFF;
      status = `PCIe_CPL_STATUS_SC;
      ok     = 1'b0;
      return;
    end
    // step 1 = say WHICH register (CF8), step 2 = read the DATA (CFC)
    io_write(PORT_CONFIG_ADDRESS, make_config_address(bus_num, dev, fn, off), 4'hF, status, ok);
    io_read (PORT_CONFIG_DATA, rdata, status, ok);
  endtask

  task cfg_write(input bit [4:0] dev, input bit [2:0] fn, input bit [11:0] off,
                 input bit [31:0] wdata, input bit [3:0] be,
                 output bit [2:0] status, output bit ok);
    bit [1:0] byte_off;
    int       size;

    if (cfg_mech == CFG_MECH_ECAM) begin
      // A CPU store is (address, size) : turn the byte enables back into that
      if (!be_to_access(be, byte_off, size)) begin
        `uvm_error("RC_ECAM", $sformatf("  BE=%04b is not one CPU access (1, 2 or 4 contiguous bytes) - write dropped", be))
        status = `PCIe_CPL_STATUS_SC;
        ok     = 1'b0;
        return;
      end
      ecam_mem_write(make_ecam_address(bus_num, dev, fn, {off[11:2], byte_off}), wdata, size, status, ok);
      return;
    end
    if (off >= 12'h100) begin
      `uvm_info("RC_CAM", $sformatf("  offset %03h is above 0FFh : not reachable with CF8/CFC -> write dropped", off), UVM_LOW)
      status = `PCIe_CPL_STATUS_SC;
      ok     = 1'b0;
      return;
    end
    // step 1 = say WHICH register (CF8), step 2 = write the DATA (CFC)
    io_write(PORT_CONFIG_ADDRESS, make_config_address(bus_num, dev, fn, off), 4'hF, status, ok);
    io_write(PORT_CONFIG_DATA, wdata, be, status, ok);
  endtask

  //========================================================================
  // Routing through the Root Port : 0 = Type 0, 1 = Type 1, 2 = not below
  //========================================================================
  function int route(bit [7:0] bus);
    if (bus == secondary_bus)                                return 0;
    if ((bus > secondary_bus) && (bus <= subordinate_bus))   return 1;
    return 2;
  endfunction

  //========================================================================
  // ECAM (Section 7.2.2) : memory window -> Configuration Request
  //========================================================================
  function bit [63:0] ecam_window_size();
    return 64'h1 << (ecam_bus_bits + 20);  // it calculates the size of ECAM area: each bus needs 1 MB (2²⁰), and there are 2ⁿ buses, so the ECAM area = 2ⁿ × 2²⁰ = 1 << (n + 20)
  endfunction

  // Window rules from Section 7.2.2 : 1 <= n <= 8, base aligned to 2^(n+20),
  // every bus this sequence may target must fit in n bits.
  function void check_ecam_window();
    if (ecam_bus_bits < 1 || ecam_bus_bits > 8)   // ECAM can use 1 to 8 bits for the bus number
      `uvm_fatal("RC_ECAM", $sformatf("ecam_bus_bits=%0d : n must be 1..8", ecam_bus_bits))
    if ((ecam_base & (ecam_window_size() - 1)) != 0)  // The start address must be a multiple of the window size which is 256MB multiples means lasts 7 bits must be zero
      `uvm_fatal("RC_ECAM", $sformatf("ecam_base=%016h is not aligned to the 2^(n+20) = 0x%0h byte window",
                 ecam_base, ecam_window_size()))
    if (subordinate_bus > (1 << ecam_bus_bits) - 1 || bus_num > (1 << ecam_bus_bits) - 1) // Checks buses within the limit
      `uvm_fatal("RC_ECAM", $sformatf("bus %0d / subordinate bus %0d cannot be reached with n=%0d (buses 0..%0d)",
                 bus_num, subordinate_bus, ecam_bus_bits, (1 << ecam_bus_bits) - 1))
  endfunction

  // Table 7-1 : build the memory address software uses for one register.
  // off carries the byte address, so off[1:0] is A[1:0].
  function bit [63:0] make_ecam_address(bit [7:0] bus, bit [4:0] dev, bit [2:0] fn, bit [11:0] off);
    bit [63:0] bus_mask;
    bus_mask = (64'h1 << ecam_bus_bits) - 1;
    return ecam_base
         | ((bus & bus_mask) << 20)
         | (64'(dev) << 15)
         | (64'(fn)  << 12)
         | 64'(off);
  endfunction

  // Table 7-1 in the other direction : what the host bridge decodes.
  // hit = 0 when the address is outside the ECAM window.
  function void split_ecam_address(bit [63:0] a, output bit hit,
                                   output bit [7:0] bus, output bit [4:0] dev,
                                   output bit [2:0] fn, output bit [11:0] off);
    bit [63:0] rel;
    hit = (a >= ecam_base) && (a < ecam_base + ecam_window_size());    // It cheks address inside the ECAM area
    rel = a - ecam_base;    // It removes base address
    bus = 8'(rel >> 20) & 8'((1 << ecam_bus_bits) - 1);   // take out the bus 
    dev = rel[19:15];
    fn  = rel[14:12];
    off = rel[11:0];                                       // [11:8] Ext Reg, [7:2] Reg, [1:0] byte
  endfunction

  // A[1:0] + access size -> First DW Byte Enables. 0 = crosses a DW boundary.
  function bit [3:0] ecam_byte_enables(bit [1:0] a10, int size);
    if (!(size inside {1, 2, 4}) || (int'(a10) + size > 4)) return 4'b0000;
    return 4'(((1 << size) - 1) << a10);  // Build the byte enable
  endfunction

  // BE pattern of a single CPU access -> (A[1:0], size). 0 = not one access.
  function bit be_to_access(bit [3:0] be, output bit [1:0] a10, output int size);
    case (be)
      4'b0001: begin a10 = 2'd0; size = 1; end
      4'b0010: begin a10 = 2'd1; size = 1; end
      4'b0100: begin a10 = 2'd2; size = 1; end
      4'b1000: begin a10 = 2'd3; size = 1; end
      4'b0011: begin a10 = 2'd0; size = 2; end
      4'b0110: begin a10 = 2'd1; size = 2; end
      4'b1100: begin a10 = 2'd2; size = 2; end
      4'b1111: begin a10 = 2'd0; size = 4; end
      default: begin a10 = 2'd0; size = 0; return 1'b0; end
    endcase
    return 1'b1;
  endfunction

  // MEMORY READ inside the ECAM window -> CfgRd, completion data -> ecam_data_reg
  task ecam_mem_read(input bit [63:0] addr, input int size,
                     output bit [31:0] data, output bit [2:0] status, output bit ok);
    bit        hit;
    bit [7:0]  bus;
    bit [4:0]  dev;
    bit [2:0]  fn;
    bit [11:0] off;
    bit [3:0]  be;
    int        r;

    status = `PCIe_CPL_STATUS_SC;
    ok     = 1'b0;
    data   = 32'hFFFF_FFFF;

    ecam_address_reg = addr;
    split_ecam_address(addr, hit, bus, dev, fn, off);
    be = ecam_byte_enables(off[1:0], size);
    `uvm_info("RC_ECAM", $sformatf("  MEM_RD %016h size=%0d : Bus=%0d Dev=%0d Fn=%0d ExtReg=%0h Reg=%02h BE=%04b",
              addr, size, bus, dev, fn, off[11:8], off[7:2], be), UVM_LOW)

    if (!hit) begin
      `uvm_error("RC_ECAM", $sformatf("  MEM_RD %016h is outside the ECAM window", addr))
      return;
    end
    if (be == 4'b0000) begin
      `uvm_warning("RC_ECAM", $sformatf("  MEM_RD %016h size=%0d crosses a DW boundary - not translated", addr, size))
      return;
    end
    r = route(bus);
    if (r == 2) begin
      `uvm_info("RC_ECAM", $sformatf("  Bus %0d is not below the Root Port -> FFFFFFFFh (Master Abort)", bus), UVM_LOW)
      return;
    end
    cfg_request(1'b0, bus, dev, fn, {off[11:2], 2'b00}, (r == 1), 32'h0, be, ecam_data_reg, status, ok);
    data = ecam_data_reg;
    `uvm_info("RC_ECAM", $sformatf("  MEM_RD %016h => %08h", addr, data), UVM_LOW)
  endtask

  // MEMORY WRITE inside the ECAM window -> CfgWr. Returns only after the
  // CfgWr completion, so the write is done before software continues.
  task ecam_mem_write(input bit [63:0] addr, input bit [31:0] data, input int size,
                      output bit [2:0] status, output bit ok);
    bit        hit;
    bit [7:0]  bus;
    bit [4:0]  dev;
    bit [2:0]  fn;
    bit [11:0] off;
    bit [3:0]  be;
    bit [31:0] unused;
    int        r;

    status = `PCIe_CPL_STATUS_SC;
    ok     = 1'b0;

    ecam_address_reg = addr;
    ecam_data_reg    = data;
    split_ecam_address(addr, hit, bus, dev, fn, off);
    be = ecam_byte_enables(off[1:0], size);
    `uvm_info("RC_ECAM", $sformatf("  MEM_WR %016h size=%0d <= %08h : Bus=%0d Dev=%0d Fn=%0d ExtReg=%0h Reg=%02h BE=%04b",
              addr, size, data, bus, dev, fn, off[11:8], off[7:2], be), UVM_LOW)

    if (!hit) begin
      `uvm_error("RC_ECAM", $sformatf("  MEM_WR %016h is outside the ECAM window", addr))
      return;
    end
    if (be == 4'b0000) begin
      `uvm_warning("RC_ECAM", $sformatf("  MEM_WR %016h size=%0d crosses a DW boundary - not translated", addr, size))
      return;
    end
    r = route(bus);
    if (r == 2) begin
      `uvm_info("RC_ECAM", $sformatf("  Bus %0d is not below the Root Port : write dropped", bus), UVM_LOW)
      return;
    end
    cfg_request(1'b1, bus, dev, fn, {off[11:2], 2'b00}, (r == 1), data, be, unused, status, ok);
  endtask

  //========================================================================
  // CAM (Section 7.2.1) : CONFIG_ADDRESS (CF8) value
  //========================================================================
  function bit [31:0] make_config_address(bit [7:0] bus, bit [4:0] dev, bit [2:0] fn, bit [11:0] off);
    bit [31:0] v;
    v        = '0;
    v[31]    = 1'b1;          // Enable
    v[23:16] = bus;
    v[15:11] = dev;
    v[10:8]  = fn;
    v[7:2]   = off[7:2];      // only 000h..0FCh fit here
    v[1:0]   = 2'b00;
    return v;
  endfunction

  function void split_config_address(bit [31:0] v,
                                     output bit enable, output bit [7:0] bus,
                                     output bit [4:0] dev, output bit [2:0] fn,
                                     output bit [11:0] off);
    enable = v[31];
    bus    = v[23:16];
    dev    = v[15:11];
    fn     = v[10:8];
    off    = {4'h0, v[7:2], 2'b00};
  endfunction

  //========================================================================
  // CAM : CPU I/O access to the host bridge ports 0CF8h / 0CFCh
  //========================================================================
  // I/O WRITE
  //   0CF8h : only stores CONFIG_ADDRESS. NO packet goes out.
  //   0CFCh : stores CONFIG_DATA, then (if CF8 Enable=1) sends a CfgWr TLP
  task io_write(input bit [15:0] port, input bit [31:0] data, input bit [3:0] be,
                output bit [2:0] status, output bit ok);
    bit        en;
    bit [7:0]  bus;
    bit [4:0]  dev;
    bit [2:0]  fn;
    bit [11:0] off;
    bit [31:0] unused;
    int        r;

    status = `PCIe_CPL_STATUS_SC;
    ok     = 1'b1;

    if (port == PORT_CONFIG_ADDRESS) begin
      config_address_reg = data;
      split_config_address(data, en, bus, dev, fn, off);
      `uvm_info("RC_CAM", $sformatf("  IO_WR 0CF8h (CONFIG_ADDRESS) <= %08h : Enable=%0b Bus=%0d Dev=%0d Fn=%0d Reg=%03h",
                data, en, bus, dev, fn, off), UVM_LOW)
      return;
    end

    if (port == PORT_CONFIG_DATA) begin
      config_data_reg = data;
      split_config_address(config_address_reg, en, bus, dev, fn, off);
      `uvm_info("RC_CAM", $sformatf("  IO_WR 0CFCh (CONFIG_DATA)    <= %08h BE=%04b", data, be), UVM_LOW)
      if (!en) begin
        `uvm_info("RC_CAM", "  CONFIG_ADDRESS Enable=0 : no Configuration Request (normal I/O write)", UVM_LOW)
        return;
      end
      r = route(bus);
      if (r == 2) begin
        `uvm_info("RC_CAM", $sformatf("  Bus %0d is not below the Root Port : write dropped", bus), UVM_LOW)
        ok = 1'b0;
        return;
      end
      cfg_request(1'b1, bus, dev, fn, off, (r == 1), data, be, unused, status, ok);
      return;
    end

    `uvm_warning("RC_CAM", $sformatf("IO_WR to port %04h is not a configuration port", port))
    ok = 1'b0;
  endtask

  // I/O READ
  //   0CF8h : returns CONFIG_ADDRESS. NO packet goes out.
  //   0CFCh : (if CF8 Enable=1) sends a CfgRd TLP, completion data -> CONFIG_DATA
  task io_read(input bit [15:0] port, output bit [31:0] data,
               output bit [2:0] status, output bit ok);
    bit        en;
    bit [7:0]  bus;
    bit [4:0]  dev;
    bit [2:0]  fn;
    bit [11:0] off;
    int        r;

    status = `PCIe_CPL_STATUS_SC;
    ok     = 1'b1;

    if (port == PORT_CONFIG_ADDRESS) begin
      data = config_address_reg;
      return;
    end

    if (port == PORT_CONFIG_DATA) begin
      split_config_address(config_address_reg, en, bus, dev, fn, off);
      if (!en) begin
        `uvm_info("RC_CAM", "  IO_RD 0CFCh with Enable=0 : no Configuration Request -> FFFFFFFFh", UVM_LOW)
        data = 32'hFFFF_FFFF;
        ok   = 1'b0;
        return;
      end
      r = route(bus);
      if (r == 2) begin
        `uvm_info("RC_CAM", $sformatf("  Bus %0d is not below the Root Port -> FFFFFFFFh (Master Abort)", bus), UVM_LOW)
        data = 32'hFFFF_FFFF;
        ok   = 1'b0;
        return;
      end
      cfg_request(1'b0, bus, dev, fn, off, (r == 1), 32'h0, 4'hF, config_data_reg, status, ok);
      data = config_data_reg;
      `uvm_info("RC_CAM", $sformatf("  IO_RD 0CFCh (CONFIG_DATA)    => %08h", data), UVM_LOW)
      return;
    end

    `uvm_warning("RC_CAM", $sformatf("IO_RD from port %04h is not a configuration port", port))
    data = 32'hFFFF_FFFF;
    ok   = 1'b0;
  endtask

  //========================================================================
  // cfg_request : HOST BRIDGE -> one Configuration Request TLP + wait for
  //   its completion. tgt_bus / type1 come from the decoded ECAM address
  //   or from CONFIG_ADDRESS (CAM).
  //========================================================================
  task cfg_request(input  bit        is_write,
                   input  bit [7:0]  tgt_bus,
                   input  bit [4:0]  dev,
                   input  bit [2:0]  fn,
                   input  bit [11:0] off,
                   input  bit        type1,
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
         cfg_type1 == local::type1;        // Type 0 or Type 1 (decided by the host bridge)

         cfg_bus_num     == local::tgt_bus;
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
      if (link_up_first)
        `uvm_info("RC_ENUM", "  (first request : link was already up - LTSSM L0 + DL_ACTIVE done by the driver before enumeration)", UVM_LOW)
      else
        `uvm_info("RC_ENUM", "  (first request : link training + DL init were done by the driver with this item)", UVM_LOW)
    end

    // ---- wait for the completion with the same tag ----
    rc_tl.wait_completion(tag, cpl_timeout_ns, cpl, timed_out);

    if (timed_out) begin
      n_timeout++;
      `uvm_error("RC_ENUM", $sformatf("COMPLETION_TIMEOUT : Cfg%s%0d %0d:%0d.%0d off=%03h tag=0x%0h - no completion in %0d ns",
                 is_write ? "Wr" : "Rd", type1, tgt_bus, dev, fn, off, tag, cpl_timeout_ns))
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
      `uvm_info("RC_ENUM", $sformatf("  CFG_RD%0d %0d:%0d.%0d off=%03h tag=0x%0h -> %08h", type1, tgt_bus, dev, fn, off, tag, rdata), UVM_LOW)
    end
    else begin
      `uvm_info("RC_ENUM", $sformatf("  CFG_WR%0d %0d:%0d.%0d off=%03h tag=0x%0h data=%08h be=%04b -> SC", type1, tgt_bus, dev, fn, off, tag, wdata, be), UVM_LOW)
    end
    ok = 1'b1;
  endtask

  //========================================================================
  // STEP 7 : summary
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

endclass


`timescale 1ns/1ps

//-----------------------------------------------------------------------------
// DAP SWD / JTAG bus functional model.
//
// Drives the SoC-400 SWJ-DP chip boundary pads (nTRST, SWCLK, SWDIO, TDI) and
// samples TDO.  Implements the JTAG TAP protocol plus the legacy Arm JTAG-DP
// DPACC / APACC register accesses used by the SoC-400 SWJ-DP.
//
// The protocol details implemented here were derived from the SoC-400 RTL that
// is integrated in this project:
//
//   * The instruction register is 4 bits wide (IRLEN8 = 0).  Both the
//     instruction register and the data register are shifted LSB first: the
//     shift registers are loaded as {tdi, reg[N-1:1]}, so the first bit
//     shifted in ends up in the least significant bit of the register and
//     TDO (taken from bit 0) presents the oldest data first.
//
//   * The data register is 35 bits wide.  For the IDCODE instruction TDO is
//     taken from DR[3], so the 32 bit IDCODE appears LSB first starting at
//     the fourth shift clock.  For DPACC / APACC TDO is taken from DR[0].
//
//   * TDO is updated on the falling edge of SWCLK (IEEE 1149.1) and is
//     sampled by the target on the rising edge.  ntdoen is an active low
//     output enable.
//
//   * The JTAG-DP address register holds the AP select in bits [31:24] and the
//     AP bank select in bits [7:4].  The DAPBUS address is
//     {ap_sel, ap_banksel, ap_reg}.
//
//   * An AP register is selected by the 2 bit A field of the APACC access:
//       A = 00 -> CSW      (AP offset 0x00)
//       A = 01 -> TAR      (AP offset 0x04)
//       A = 10 -> unused   (AP offset 0x08)
//       A = 11 -> DRW      (AP offset 0x0C)
//     The bank select extends the AP register offset by 0x10 per bank, so
//     bank 0xF / A = 11 gives the AP identification register at 0xFC.
//
//   * A DP register read (DPACC) needs two scans: the first scan selects the
//     read multiplexer, the second scan captures the data.  The same applies
//     to an AP read (APACC): the first scan issues the bus transaction, the
//     second scan captures the read data buffer.
//
//   * The DP CTRL register must be written with CDBGPWRUPREQ (bit 28) set
//     before any AP access will be issued.
//
//   * nTRST must be pulsed, otherwise the TAP state and the instruction
//     register are never initialised.
//-----------------------------------------------------------------------------

module dap_swd_bfm #(
    parameter int SWCLK_PERIOD_NS = 20,
    parameter int START_DELAY_NS   = 2000,
    parameter int AP_TX_WAIT_CLKS  = 24
)(
    output wire swclk,
    inout  wire swdio,
    output wire tdi,
    output wire ntrst,
    input  wire tdo,

    output reg  test_done,
    output reg  test_pass
);

  //--------------------------------------------------------------------------
  // Parameters / constants
  //--------------------------------------------------------------------------
  localparam real HALF_PERIOD = SWCLK_PERIOD_NS / 2.0;

  // JTAG instructions (4 bit IR, MSB first)
  localparam logic [3:0] IR_ABORT  = 4'h8;
  localparam logic [3:0] IR_DPACC  = 4'hA;
  localparam logic [3:0] IR_APACC  = 4'hB;
  localparam logic [3:0] IR_IDCODE = 4'hE;
  localparam logic [3:0] IR_BYPASS = 4'hF;

  // DP register select (A field of a DPACC access)
  localparam logic [1:0] DP_REG_IDCODE = 2'b00;
  localparam logic [1:0] DP_REG_CTRL   = 2'b01;
  localparam logic [1:0] DP_REG_ADDR   = 2'b10;
  localparam logic [1:0] DP_REG_RDBUFF = 2'b11;

  // AP register select (A field of an APACC access)
  localparam logic [1:0] AP_REG_CSW = 2'b00;
  localparam logic [1:0] AP_REG_TAR = 2'b01;
  localparam logic [1:0] AP_REG_DRW = 2'b11;

  // DP CTRL/STAT bit positions (within the 32 bit register value)
  localparam int DP_STAT_CDBGPWRUPREQ = 28;
  localparam int DP_STAT_CDBGPWRUPACK = 29;
  localparam int DP_STAT_CSYSPWRUPREQ = 30;
  localparam int DP_STAT_CSYSPWRUPACK = 31;
  localparam int DP_STAT_STICKYERR    = 5;
  localparam int DP_STAT_STICKYCMP    = 4;

  // Access port numbers as decoded by the DAPBUS interconnect
  localparam logic [7:0] AP_APBIC = 8'd0;   // APB-AP  -> CoreSight APB fabric
  localparam logic [7:0] AP_AXI   = 8'd1;   // AXI-AP  -> NIC400 debug port
  localparam logic [7:0] AP_R5    = 8'd2;   // APB-AP  -> Cortex-R5 EDI
  localparam logic [7:0] AP_M85   = 8'd3;   // AHB-AP  -> Cortex-M85 EPPB

  // Expected values
  localparam logic [31:0] TAP_IDCODE_EXPECTED = 32'h6BA00477;
  localparam logic [31:0] SWD_DPIDR_EXPECTED  = 32'h6BA02477;
  localparam logic [31:0] APBAP_IDR_EXPECTED  = 32'h54770002;
  localparam logic [31:0] AHBAP_IDR_EXPECTED  = 32'h84770001;
  localparam logic [31:0] BOOTROM_FIRST_WORD  = 32'hE59F_F018;

  // CoreSight component identification registers of the Cortex-R5 external
  // debug interface (heron_dbg.v, DBG_ID_COMP0-3 and DBG_DEVTYPE).
  localparam logic [31:0] R5_COMP0_EXPECTED   = 32'h0000_000D;
  localparam logic [31:0] R5_COMP1_EXPECTED   = 32'h0000_0090;
  localparam logic [31:0] R5_COMP2_EXPECTED   = 32'h0000_0005;
  localparam logic [31:0] R5_COMP3_EXPECTED   = 32'h0000_00B1;
  localparam logic [31:0] R5_DEVTYPE_EXPECTED = 32'h0000_0015;

  // Cortex-M85 debug ROM table at 0xE00FF000 (olympus_romtable.sv).
  localparam logic [31:0] M85_ROM_BASE        = 32'hE00F_F000;
  localparam logic [31:0] M85_ROM_SCS_ENTRY   = 32'hFFF0_F003;
  localparam logic [31:0] M85_ROM_CID0        = 32'h0000_000D;
  localparam logic [31:0] M85_ROM_CID1        = 32'h0000_0010;
  localparam logic [31:0] M85_ROM_CID2        = 32'h0000_0005;
  localparam logic [31:0] M85_ROM_CID3        = 32'h0000_00B1;

  //--------------------------------------------------------------------------
  // Pad drivers
  //--------------------------------------------------------------------------
  reg swclk_r;
  reg tdi_r;
  reg ntrst_r;
  reg swdio_oe;
  reg swdio_r;

  assign swclk = swclk_r;
  assign tdi   = tdi_r;
  assign ntrst = ntrst_r;

  // In JTAG mode the host owns SWDIO (it carries TMS).  In SW-DP mode the
  // host releases the pad while the DP drives it, so both the value and the
  // output enable are driven explicitly by the clock primitives below.
  assign swdio = swdio_oe ? swdio_r : 1'bz;

  //--------------------------------------------------------------------------
  // Error accounting
  //--------------------------------------------------------------------------
  integer errors = 0;

  task automatic check(input logic condition, input string message);
    if (condition) begin
      $display("[%0t] DAP BFM: PASS - %s", $time, message);
    end
    else begin
      errors = errors + 1;
      $display("[%0t] DAP BFM: FAIL - %s", $time, message);
    end
  endtask

  task automatic check_eq32(input logic [31:0] got, input logic [31:0] exp,
                            input string message);
    if (got === exp) begin
      $display("[%0t] DAP BFM: PASS - %s (0x%08x)", $time, message, got);
    end
    else begin
      errors = errors + 1;
      $display("[%0t] DAP BFM: FAIL - %s: got 0x%08x expected 0x%08x",
               $time, message, got, exp);
    end
  endtask

  //--------------------------------------------------------------------------
  // JTAG TAP primitives
  //--------------------------------------------------------------------------

  // One SWCLK period.  TMS and TDI are presented before the rising edge, TDO
  // is updated by the target on the falling edge.
  task automatic jtag_clk(input logic tms_i, input logic tdi_i);
    swdio_r  = tms_i;
    swdio_oe = 1'b1;
    tdi_r    = tdi_i;
    #1;
    swclk_r = 1'b1;         // rising edge - target samples TMS/TDI
    #HALF_PERIOD;
    swclk_r = 1'b0;         // falling edge - target updates TDO
    #HALF_PERIOD;
  endtask

  // Clock the TAP while it is parked in Run-Test/Idle.
  task automatic jtag_idle(input integer count);
    for (int i = 0; i < count; i++) begin
      jtag_clk(1'b0, 1'b0);
    end
  endtask

  // Load the instruction register.  The instruction register is shifted
  // LSB first: the shift register is loaded as {tdi, ir[3:1]}, so the first
  // bit shifted in ends up in the least significant bit of the instruction.
  //
  // Note on the shift count: the clock that leaves the shift state also
  // performs a shift (IEEE 1149.1).  The IR is therefore loaded with exactly
  // four shift clocks, the last one carrying TMS = 1.
  task automatic jtag_set_ir(input logic [3:0] ir);
    logic [3:0] ir_in;
    jtag_clk(1'b1, 1'b0);   // Run-Test/Idle -> Select-DR-Scan
    jtag_clk(1'b1, 1'b0);   // Select-DR-Scan -> Select-IR-Scan
    jtag_clk(1'b0, 1'b0);   // Select-IR-Scan -> Capture-IR
    jtag_clk(1'b0, 1'b0);   // Capture-IR -> Shift-IR (IR is captured here)
    for (int i = 0; i < 4; i++) begin
      ir_in[i] = tdo;
      // The last shift clock exits the shift state.
      jtag_clk((i == 3), ir[i]);
    end
    jtag_clk(1'b1, 1'b0);   // Exit1-IR -> Update-IR
    jtag_clk(1'b0, 1'b0);   // Update-IR -> Run-Test/Idle (IR takes effect here)
  endtask

  // Shift the data register.  The DR is shifted LSB first: dr[0] is the first
  // bit on the wire in both directions.
  //
  // As for the IR, the clock that leaves the shift state also performs a
  // shift, so the register is shifted exactly nbits times.
  task automatic jtag_shift_dr(input logic [34:0] dr_out, input integer nbits,
                               output logic [34:0] dr_in);
    dr_in = '0;
    jtag_clk(1'b1, 1'b0);   // Run-Test/Idle -> Select-DR-Scan
    jtag_clk(1'b0, 1'b0);   // Select-DR-Scan -> Capture-DR
    jtag_clk(1'b0, 1'b0);   // Capture-DR -> Shift-DR (DR is captured here)
    for (int i = 0; i < nbits; i++) begin
      dr_in[i] = tdo;
      // The last shift clock exits the shift state.
      jtag_clk((i == (nbits-1)), dr_out[i]);
    end
    jtag_clk(1'b1, 1'b0);   // Exit1-DR -> Update-DR
    jtag_clk(1'b0, 1'b0);   // Update-DR -> Run-Test/Idle (access fires here)
  endtask

  // Pulse nTRST and then reset the TAP through the TMS sequence.
  task automatic dap_reset();
    ntrst_r = 1'b0;
    #(SWCLK_PERIOD_NS * 4);
    ntrst_r = 1'b1;
    #(SWCLK_PERIOD_NS * 2);
    for (int i = 0; i < 5; i++) begin
      jtag_clk(1'b1, 1'b0);
    end
    jtag_clk(1'b0, 1'b0);   // Test-Logic-Reset -> Run-Test/Idle
    jtag_idle(4);
  endtask

  //--------------------------------------------------------------------------
  // JTAG-DP register accesses
  //--------------------------------------------------------------------------

  // Write a DP register.  The A field selects the register, bit 0 of the DR
  // is 0 for a write.
  task automatic dp_write(input logic [31:0] data, input logic [1:0] areg);
    logic [34:0] dr;
    logic [34:0] dr_in;
    dr      = '0;
    dr[34:3] = data;
    dr[2:1]  = areg;
    dr[0]    = 1'b0;
    jtag_set_ir(IR_DPACC);
    jtag_shift_dr(dr, 35, dr_in);
  endtask

  // Read a DP register.  The first scan selects the read multiplexer, the
  // second scan captures the data.
  task automatic dp_read(input logic [1:0] areg, output logic [31:0] data);
    logic [34:0] dr;
    logic [34:0] dr_in;
    dr       = '0;
    dr[2:1]  = areg;
    dr[0]    = 1'b1;        // read
    jtag_set_ir(IR_DPACC);
    jtag_shift_dr(dr, 35, dr_in);   // select the read multiplexer
    jtag_shift_dr(dr, 35, dr_in);   // capture the data
    data = dr_in[34:3];
  endtask

  //--------------------------------------------------------------------------
  // AP accesses
  //--------------------------------------------------------------------------

  // Select the AP (and optionally the AP bank) that the following APACC
  // accesses will target.
  task automatic ap_select(input logic [7:0] ap_num, input logic [3:0] bank);
    logic [31:0] addr;
    addr        = '0;
    addr[31:24] = ap_num;
    addr[7:4]   = bank;
    dp_write(addr, DP_REG_ADDR);
  endtask

  // Write an AP register.
  task automatic ap_write(input logic [1:0] apreg, input logic [31:0] data);
    logic [34:0] dr;
    logic [34:0] dr_in;
    dr       = '0;
    dr[34:3] = data;
    dr[2:1]  = apreg;
    dr[0]    = 1'b0;        // write
    jtag_set_ir(IR_APACC);
    jtag_shift_dr(dr, 35, dr_in);
    jtag_idle(AP_TX_WAIT_CLKS);
  endtask

  // Read an AP register.
  task automatic ap_read(input logic [1:0] apreg, output logic [31:0] data);
    logic [34:0] dr;
    logic [34:0] dr_in;
    dr       = '0;
    dr[2:1]  = apreg;
    dr[0]    = 1'b1;        // read
    jtag_set_ir(IR_APACC);
    jtag_shift_dr(dr, 35, dr_in);   // issue the read
    jtag_idle(AP_TX_WAIT_CLKS);
    jtag_shift_dr(dr, 35, dr_in);   // capture the read data
    data = dr_in[34:3];
    jtag_idle(AP_TX_WAIT_CLKS);
  endtask

  // Read a 32 bit word from the target of the currently selected AP.
  //
  // The transfer address register is programmed with a byte address.  The
  // APB-AP drives {TAR[29:0], 2'b00} on its APB address bus and the AHB-AP
  // drives TAR[31:0] on its AHB address bus, so one helper serves both.
  task automatic ap_mem_read(input logic [31:0] byte_addr,
                             output logic [31:0] data);
    ap_write(AP_REG_TAR, byte_addr);
    ap_read(AP_REG_DRW, data);
  endtask

  // Write a 32 bit word to the target of the currently selected AP.
  task automatic ap_mem_write(input logic [31:0] byte_addr,
                              input logic [31:0] data);
    ap_write(AP_REG_TAR, byte_addr);
    ap_write(AP_REG_DRW, data);
  endtask

  // Read a word through the selected AP and compare it against the value
  // documented by the target's RTL.
  task automatic ap_check_read(input logic [31:0] byte_addr,
                               input logic [31:0] expected,
                               input string message);
    logic [31:0] data;
    ap_mem_read(byte_addr, data);
    check_eq32(data, expected, message);
  endtask

  //--------------------------------------------------------------------------
  // Serial Wire debug primitives
  //
  // Once the SWJ-DP has been switched out of JTAG the debug port speaks the
  // two wire Serial Wire protocol on SWCLK / SWDIO:
  //
  //   request : start(1) APnDP RnW A[2] A[3] parity stop(0) park(1)
  //   ACK     : 3 bits, OK = 0b001, WAIT = 0b010, FAULT = 0b100,
  //             protocol ERROR = 0b111
  //   payload : 32 data bits LSB first followed by one even parity bit
  //
  // The SW-DP registers all of its logic on the rising edge of SWCLK, so the
  // host presents a bit before the rising edge and samples the target half a
  // period after it.  The register in the target's output path supplies the
  // one cycle turnaround that Serial Wire requires.
  //
  // Only the DP and AP request frames used by the tests below are modelled;
  // the DP is never put into its "overrun detection" mode.
  //--------------------------------------------------------------------------
  localparam logic [2:0] SWD_ACK_OK    = 3'b001;
  localparam logic [2:0] SWD_ACK_WAIT  = 3'b010;
  localparam logic [2:0] SWD_ACK_FAULT = 3'b100;
  localparam logic [2:0] SWD_ACK_ERROR = 3'b111;

  localparam logic SWD_DP = 1'b0;
  localparam logic SWD_AP = 1'b1;

  // Number of idle clocks needed between the ACK of a write and the first
  // data bit: the SW-DP passes through SLEPARKW and SLETRNW0 first.
  localparam int SWD_WR_TURN_CLKS = 2;
  // Number of idle clocks needed after the last bit of a read (or after a
  // WAIT / FAULT response) to return the port to its idle state.
  localparam int SWD_RD_IDLE_CLKS = 4;

  // One SWCLK period.  When drive_en is low the pad is released so that the
  // target can drive it; the value on the pad is sampled half way through the
  // period and returned in q.
  task automatic swd_clk(input logic drive_en, input logic d, output logic q);
    swdio_oe = drive_en;
    swdio_r  = d;
    #1;
    swclk_r = 1'b1;             // rising edge - target samples SWDIO
    #HALF_PERIOD;
    q = swdio;                  // sample the target output
    #HALF_PERIOD;
    swclk_r = 1'b0;
  endtask

  // Drive one bit from the host and ignore the value on the pad.
  task automatic swd_out(input logic d);
    logic q;
    swd_clk(1'b1, d, q);
  endtask

  // Release the pad and sample one bit driven by the target.
  task automatic swd_in(output logic q);
    swd_clk(1'b0, 1'b0, q);
  endtask

  // Drive the pad low for the given number of clocks (host idle).
  task automatic swd_idle(input integer count);
    for (int i = 0; i < count; i++) swd_out(1'b0);
  endtask

  // Build a Serial Wire request byte.
  function automatic logic [7:0] swd_request(input logic apndp, input logic rnw,
                                             input logic [1:0] areg);
    logic [7:0] req;
    req[0] = 1'b1;                              // start
    req[1] = apndp;
    req[2] = rnw;
    req[3] = areg[0];
    req[4] = areg[1];
    req[5] = req[1] ^ req[2] ^ req[3] ^ req[4]; // even parity
    req[6] = 1'b0;                              // stop
    req[7] = 1'b1;                              // park
    return req;
  endfunction

  // Send a request and return the three ACK bits driven by the target.
  task automatic swd_ack(input logic apndp, input logic rnw,
                         input logic [1:0] areg, output logic [2:0] ack);
    logic [7:0] req;
    logic q;
    req = swd_request(apndp, rnw, areg);
    for (int i = 0; i < 8; i++) swd_out(req[i]);
    for (int i = 0; i < 3; i++) begin
      swd_in(q);
      ack[i] = q;
    end
  endtask

  // Read the 32 bit payload (and its parity bit) that follows an OK ACK.
  task automatic swd_read_payload(output logic [31:0] data);
    logic q;
    for (int i = 0; i < 32; i++) begin
      swd_in(q);
      data[i] = q;
    end
    swd_in(q);                  // parity bit, not checked here
  endtask

  // Write the 32 bit payload, its parity bit and the trailing stop bit.
  task automatic swd_write_payload(input logic [31:0] data);
    for (int i = 0; i < 32; i++) swd_out(data[i]);
    swd_out(^data);             // even parity
    swd_out(1'b0);              // stop
  endtask

  // Issue a DP write.  Returns the ACK so the caller can see WAIT / FAULT.
  task automatic swd_dp_write_ack(input logic [1:0] areg, input logic [31:0] data,
                                  output logic [2:0] ack);
    swd_ack(SWD_DP, 1'b0, areg, ack);
    if (ack == SWD_ACK_OK) begin
      for (int i = 0; i < SWD_WR_TURN_CLKS; i++) swd_out(1'b0);
      swd_write_payload(data);
    end
    else begin
      swd_idle(SWD_RD_IDLE_CLKS);
    end
  endtask

  // Issue a DP read.
  task automatic swd_dp_read_ack(input logic [1:0] areg, output logic [31:0] data,
                                 output logic [2:0] ack);
    swd_ack(SWD_DP, 1'b1, areg, ack);
    if (ack == SWD_ACK_OK) swd_read_payload(data);
    else                    data = 32'hxxxx_xxxx;
    swd_idle(SWD_RD_IDLE_CLKS);
  endtask

  // DP write with WAIT retries.
  task automatic swd_dp_write(input logic [1:0] areg, input logic [31:0] data,
                              input string message);
    logic [2:0] ack;
    int         tries;
    tries = 0;
    do begin
      swd_dp_write_ack(areg, data, ack);
      tries++;
    end while ((ack == SWD_ACK_WAIT) && (tries < 64));
    check_eq32({29'd0, ack}, SWD_ACK_OK, message);
  endtask

  // DP read with WAIT retries.
  task automatic swd_dp_read(input logic [1:0] areg, output logic [31:0] data,
                             input string message);
    logic [2:0] ack;
    int         tries;
    tries = 0;
    do begin
      swd_dp_read_ack(areg, data, ack);
      tries++;
    end while ((ack == SWD_ACK_WAIT) && (tries < 64));
    check_eq32({29'd0, ack}, SWD_ACK_OK, message);
  endtask

  // AP register read over Serial Wire.
  //
  // The SW-DP posts AP reads: the transfer that addresses the AP register
  // issues the bus transaction and returns the bus read data of the previous
  // transfer.  The actual result is collected from DP RDBUFF (A = 0b11).
  task automatic swd_ap_read(input logic [1:0] areg, output logic [31:0] data,
                             input string message);
    logic [2:0]  ack;
    logic [31:0] dummy;
    int          tries;

    tries = 0;
    do begin
      swd_ack(SWD_AP, 1'b1, areg, ack);
      if (ack == SWD_ACK_OK) swd_read_payload(dummy);
      swd_idle(SWD_RD_IDLE_CLKS);
      tries++;
    end while ((ack == SWD_ACK_WAIT) && (tries < 64));
    check_eq32({29'd0, ack}, SWD_ACK_OK, message);

    // Allow the AP bus transaction to complete, then collect its result.
    swd_idle(8);

    tries = 0;
    do begin
      swd_dp_read_ack(2'b11, data, ack);
      tries++;
    end while ((ack == SWD_ACK_WAIT) && (tries < 64));
    check_eq32({29'd0, ack}, SWD_ACK_OK, {message, " RDBUFF"});
  endtask

  // AP register write over Serial Wire.
  task automatic swd_ap_write(input logic [1:0] areg, input logic [31:0] data,
                              input string message);
    logic [2:0] ack;
    int         tries;
    tries = 0;
    do begin
      swd_ack(SWD_AP, 1'b0, areg, ack);
      if (ack == SWD_ACK_OK) begin
        for (int i = 0; i < SWD_WR_TURN_CLKS; i++) swd_out(1'b0);
        swd_write_payload(data);
      end
      else swd_idle(SWD_RD_IDLE_CLKS);
      tries++;
    end while ((ack == SWD_ACK_WAIT) && (tries < 64));
    check_eq32({29'd0, ack}, SWD_ACK_OK, message);
  endtask

  // Read a word through the selected AP over Serial Wire and compare it.
  task automatic swd_ap_check_read(input logic [31:0] byte_addr,
                                   input logic [31:0] expected,
                                   input string message);
    logic [31:0] rd;
    swd_ap_write(2'b01, byte_addr, {message, " TAR write"});
    swd_ap_read(2'b11, rd, {message, " DRW read"});
    check_eq32(rd, expected, message);
  endtask

  logic [34:0] dr_in;
  logic [31:0] idcode;
  logic [31:0] stat;
  logic [31:0] addr_rb;
  logic [31:0] csw;
  logic [31:0] idr;

  logic [31:0] swd_data;
  logic [31:0] swd_stat;
  logic [31:0] swd_addr;
  logic [2:0]  swd_ack_r;
  logic [15:0] swd_switch;

  //--------------------------------------------------------------------------
  // Test sequence
  //--------------------------------------------------------------------------
  initial begin
    swclk_r    = 1'b0;
    tdi_r      = 1'b0;
    ntrst_r    = 1'b1;
    swdio_r    = 1'b0;
    swdio_oe   = 1'b1;
    test_done  = 1'b0;
    test_pass  = 1'b0;

    #START_DELAY_NS;

    $display("[%0t] DAP BFM: starting", $time);

    dap_reset();

    //---------------------------------------------------------------------
    // 1. JTAG TAP identification
    //---------------------------------------------------------------------
    jtag_set_ir(IR_IDCODE);
    jtag_shift_dr('0, 32, dr_in);
    idcode = dr_in[31:0];
    $display("[%0t] DAP BFM: TAP IDCODE = 0x%08x", $time, idcode);
    check_eq32(idcode, TAP_IDCODE_EXPECTED, "JTAG TAP IDCODE");

    //---------------------------------------------------------------------
    // 2. Request debug power up in the DP
    //---------------------------------------------------------------------
    dp_write(32'h1000_0000, DP_REG_CTRL);   // CDBGPWRUPREQ (bit 28)
    jtag_idle(AP_TX_WAIT_CLKS);

    dp_read(DP_REG_CTRL, stat);
    $display("[%0t] DAP BFM: DP STAT = 0x%08x", $time, stat);
    check(stat[DP_STAT_CDBGPWRUPREQ] == 1'b1, "DP CDBGPWRUPREQ set");
    check(stat[DP_STAT_CDBGPWRUPACK] == 1'b1, "DP CDBGPWRUPACK set");
    check(stat[DP_STAT_STICKYERR] == 1'b0, "DP sticky error clear");

    //---------------------------------------------------------------------
    // 3. Select AP0 (the APB fabric behind the SoC-400 APB interconnect)
    //---------------------------------------------------------------------
    ap_select(AP_APBIC, 4'd0);
    dp_read(DP_REG_ADDR, addr_rb);
    $display("[%0t] DAP BFM: DP ADDR = 0x%08x", $time, addr_rb);
    check_eq32(addr_rb[31:24], 8'd0, "DP ADDR ap_sel");
    check_eq32(addr_rb[7:4], 4'd0, "DP ADDR ap_banksel");

    //---------------------------------------------------------------------
    // 4. Read the AP0 control and status word
    //---------------------------------------------------------------------
    ap_read(AP_REG_CSW, csw);
    $display("[%0t] DAP BFM: AP0 CSW = 0x%08x", $time, csw);
    check_eq32(csw[3:0], 4'h2, "AP0 CSW AP type");

    //---------------------------------------------------------------------
    // 5. Read the AP0 identification register (AP offset 0xFC)
    //---------------------------------------------------------------------
    ap_select(AP_APBIC, 4'hF);
    ap_read(AP_REG_DRW, idr);
    $display("[%0t] DAP BFM: AP0 IDR = 0x%08x", $time, idr);
    check_eq32(idr, APBAP_IDR_EXPECTED, "AP0 identification register");

    //---------------------------------------------------------------------
    // 6. AP1 - AXI-AP through the NIC400 DEBUG port
    //---------------------------------------------------------------------
    ap_select(AP_AXI, 4'd0);
    ap_check_read(32'hFFFF_0000, BOOTROM_FIRST_WORD,
                  "AP1 NIC400 DEBUG boot ROM read");
    ap_mem_write(32'h0000_FFFC, 32'hA185_CAFE);
    ap_check_read(32'h0000_FFFC, 32'hA185_CAFE,
                  "AP1 NIC400 DEBUG M85 ITCM write/read");
    ap_mem_write(32'h8000_3FFC, 32'hA5C5_3C5A);
    ap_check_read(32'h8000_3FFC, 32'hA5C5_3C5A,
                  "AP1 NIC400 DEBUG R5 ATCM write/read");
    ap_check_read(32'h4403_0004, 32'h0000_0001,
                  "AP1 NIC400 DEBUG SYS_CTRL CPUWAIT read");

    //---------------------------------------------------------------------
    // 7. AP2 - APB-AP whose target is the Cortex-R5 external debug interface
    //---------------------------------------------------------------------
    ap_select(AP_R5, 4'hF);
    ap_read(AP_REG_DRW, idr);
    $display("[%0t] DAP BFM: AP2 IDR = 0x%08x", $time, idr);
    check_eq32(idr, APBAP_IDR_EXPECTED, "AP2 identification register");

    ap_select(AP_R5, 4'd0);   // AP bank 0
    ap_read(AP_REG_CSW, csw);
    $display("[%0t] DAP BFM: AP2 CSW = 0x%08x", $time, csw);
    check_eq32(csw[3:0], 4'h2, "AP2 CSW AP type");
    check(csw[31] == 1'b1, "AP2 CSW debug power domain active");

    // The Cortex-R5 debug register file publishes its CoreSight identification
    // registers at 0xFF0-0xFFC and the device type register at 0xFCC.
    ap_check_read(32'h0000_0FF0, R5_COMP0_EXPECTED,   "AP2 R5 COMP0");
    ap_check_read(32'h0000_0FF4, R5_COMP1_EXPECTED,   "AP2 R5 COMP1");
    ap_check_read(32'h0000_0FF8, R5_COMP2_EXPECTED,   "AP2 R5 COMP2");
    ap_check_read(32'h0000_0FFC, R5_COMP3_EXPECTED,   "AP2 R5 COMP3");
    ap_check_read(32'h0000_0FCC, R5_DEVTYPE_EXPECTED, "AP2 R5 DEVTYPE");

    //---------------------------------------------------------------------
    // 8. AP3 - AHB-AP whose target is the Cortex-M85 external PPB
    //---------------------------------------------------------------------
    ap_select(AP_M85, 4'hF);
    ap_read(AP_REG_DRW, idr);
    $display("[%0t] DAP BFM: AP3 IDR = 0x%08x", $time, idr);
    check_eq32(idr, AHBAP_IDR_EXPECTED, "AP3 identification register");

    ap_select(AP_M85, 4'd0);
    ap_read(AP_REG_CSW, csw);
    $display("[%0t] DAP BFM: AP3 CSW = 0x%08x", $time, csw);
    check_eq32(csw[3:0], 4'h2, "AP3 CSW AP type");

    // The Cortex-M85 debug ROM table is mapped at 0xE00FF000.
    ap_check_read(M85_ROM_BASE + 32'h000, M85_ROM_SCS_ENTRY, "AP3 M85 ROM SCS entry");
    ap_check_read(M85_ROM_BASE + 32'hFF0, M85_ROM_CID0,      "AP3 M85 ROM CID0");
    ap_check_read(M85_ROM_BASE + 32'hFF4, M85_ROM_CID1,      "AP3 M85 ROM CID1");
    ap_check_read(M85_ROM_BASE + 32'hFF8, M85_ROM_CID2,      "AP3 M85 ROM CID2");
    ap_check_read(M85_ROM_BASE + 32'hFFC, M85_ROM_CID3,      "AP3 M85 ROM CID3");

    //---------------------------------------------------------------------
    // 9. Switch the SWJ-DP from JTAG to Serial Wire and repeat the
    //    identification, power-up and AP identification sequence over the
    //    two wire protocol.
    //---------------------------------------------------------------------
    // Park the TAP in Test-Logic-Reset, which also returns the SWJ mode
    // watcher to its JTAG reset state.
    for (int i = 0; i < 5; i++) jtag_clk(1'b1, 1'b0);

    // JTAG to SWD select sequence: 0xE79E transmitted least significant bit
    // first, decoded by cxdapswjdp_swj_watcher.
    swd_switch = 16'hE79E;
    for (int i = 0; i < 16; i++) jtag_clk(swd_switch[i], 1'b0);

    // Line reset: more than 50 SWCLK cycles with SWDIO held high, followed by
    // two low cycles so that the port leaves the reset state.
    for (int i = 0; i < 56; i++) swd_out(1'b1);
    swd_out(1'b0);
    swd_out(1'b0);

    // SW-DP identification register (DP address 0x0, read).
    swd_dp_read_ack(2'b00, swd_data, swd_ack_r);
    $display("[%0t] DAP BFM: SWD DPIDR = 0x%08x ack=0b%03b",
             $time, swd_data, swd_ack_r);
    check_eq32({29'd0, swd_ack_r}, SWD_ACK_OK, "SWD DPIDR response");
    check_eq32(swd_data, SWD_DPIDR_EXPECTED, "SWD DP identification register");

    // Request debug power up over Serial Wire.
    swd_dp_write(2'b01, 32'h1000_0000, "SWD DP CTRL write");
    swd_dp_read(2'b01, swd_stat, "SWD DP STAT read");
    $display("[%0t] DAP BFM: SWD DP STAT = 0x%08x", $time, swd_stat);
    check(swd_stat[DP_STAT_CDBGPWRUPREQ] === 1'b1, "SWD DP CDBGPWRUPREQ set");
    check(swd_stat[DP_STAT_CDBGPWRUPACK] === 1'b1, "SWD DP CDBGPWRUPACK set");
    check(swd_stat[DP_STAT_STICKYERR]    === 1'b0, "SWD DP sticky error clear");

    // Select AP0 bank 0 through the DP address register and read it back.
    swd_dp_write(2'b10, 32'h0000_0000, "SWD DP ADDR write");
    swd_dp_read(2'b10, swd_addr, "SWD DP ADDR read");
    $display("[%0t] DAP BFM: SWD DP ADDR = 0x%08x", $time, swd_addr);
    check_eq32(swd_addr, 32'h0000_0000, "SWD DP ADDR readback");

    // AP0 identification register at bank 0xF / 0xFC.  The DP address register
    // holds the AP select in [31:24] and the AP bank in [7:4].
    swd_dp_write(2'b10, 32'h0000_00F0, "SWD DP ADDR write AP0 bank 0xF");
    swd_ap_read(2'b11, swd_data, "SWD AP0 IDR read");
    $display("[%0t] DAP BFM: SWD AP0 IDR = 0x%08x", $time, swd_data);
    check_eq32(swd_data, APBAP_IDR_EXPECTED, "SWD AP0 identification register");

    // Select AP2 (Cortex-R5 external debug interface) bank 0 and read the R5
    // debug component identification through the Serial Wire AP.
    swd_dp_write(2'b10, 32'h0200_0000, "SWD DP ADDR write AP2 bank 0");
    swd_ap_check_read(32'h0000_0FF0, R5_COMP0_EXPECTED, "SWD AP2 R5 COMP0");
    swd_ap_check_read(32'h0000_0FCC, R5_DEVTYPE_EXPECTED, "SWD AP2 R5 DEVTYPE");

    // Confirm that no AP transaction raised an error: the DP sticky error flag
    // would be set by any failed bus access.
    swd_dp_read(2'b01, swd_stat, "SWD final DP STAT read");
    $display("[%0t] DAP BFM: SWD final DP STAT = 0x%08x", $time, swd_stat);
    check(swd_stat[DP_STAT_STICKYERR] === 1'b0, "SWD no sticky error after AP reads");

    //---------------------------------------------------------------------
    // Result
    //---------------------------------------------------------------------
    if (errors == 0) begin
      $display("[%0t] DAP BFM: ALL TESTS PASSED", $time);
      test_pass = 1'b1;
    end
    else begin
      $display("[%0t] DAP BFM: %0d TEST(S) FAILED", $time, errors);
      test_pass = 1'b0;
    end
    test_done = 1'b1;
  end

endmodule

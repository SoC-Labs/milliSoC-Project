//-----------------------------------------------------------------------------
// milliSoC Verification
// AXI3 bus activity logger (simulation only)
//
// One instance monitors ONE AXI3 port and writes ONE log file
// ("axi3_<NAME>.log") into the simulator's run directory. Hook the inputs up
// to the DUT nets via hierarchical references from the testbench (see the
// "AXI port monitors" section in millisoc_tb.sv).
//
// Log format, one line per event:
//   <time> <cycle> AW  id=<> addr=<> len=<> size=<> burst=<> lock=<> cache=<> prot=<>
//   <time> <cycle> W   id=<WID> data=<> strb=<> last=<>
//   <time> <cycle> B   id=<> resp=<>
//   <time> <cycle> AR  id=<> addr=<> len=<> size=<> burst=<> lock=<> cache=<> prot=<>
//   <time> <cycle> R   id=<> data=<> resp=<> last=<>
//   <time> <cycle> STALL <chan> valid=1 ready=0 for <N> cycles
//   <time> <cycle> --  ARESETn=<0|1>
//
// Only VALID&&READY handshakes are logged, so every AW/W/B/AR/R line is a
// real bus transfer. A hung access shows up as an address line with no
// matching response line afterwards; a request that is never accepted shows
// up as a STALL line. Useful for boot debugging, e.g.:
//   grep 'addr=0000000044021084' axi3_r5m.log axi4_gic.log
//
// Note: AXI3 WID tags which transaction a write data beat belongs to (AXI3
// permits write data interleaving); AXI4 has no WID, see axi4_logger.
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module axi3_logger #(
    parameter NAME        = "axi",   // instance tag, used in the log filename
    parameter ID_W        = 4,
    parameter ADDR_W      = 32,
    parameter DATA_W      = 64,
    parameter ENABLE      = 1,       // 0 = silent (no file, no output)
    parameter STALL_LIMIT = 64       // cycles of VALID&&!READY before a STALL line (0 = off)
)(
    input wire                     ACLK,
    input wire                     ARESETn,

    // Write address channel
    input wire [ID_W-1:0]          AWID,
    input wire [ADDR_W-1:0]        AWADDR,
    input wire [7:0]               AWLEN,
    input wire [2:0]               AWSIZE,
    input wire [1:0]               AWBURST,
    input wire                     AWLOCK,
    input wire [3:0]               AWCACHE,
    input wire [2:0]               AWPROT,
    input wire                     AWVALID,
    input wire                     AWREADY,

    // Write data channel
    input wire [ID_W-1:0]          WID,
    input wire [DATA_W-1:0]        WDATA,
    input wire [(DATA_W/8)-1:0]    WSTRB,
    input wire                     WLAST,
    input wire                     WVALID,
    input wire                     WREADY,

    // Write response channel
    input wire [ID_W-1:0]          BID,
    input wire [1:0]               BRESP,
    input wire                     BVALID,
    input wire                     BREADY,

    // Read address channel
    input wire [ID_W-1:0]          ARID,
    input wire [ADDR_W-1:0]        ARADDR,
    input wire [7:0]               ARLEN,
    input wire [2:0]               ARSIZE,
    input wire [1:0]               ARBURST,
    input wire                     ARLOCK,
    input wire [3:0]               ARCACHE,
    input wire [2:0]               ARPROT,
    input wire                     ARVALID,
    input wire                     ARREADY,

    // Read data channel
    input wire [ID_W-1:0]          RID,
    input wire [DATA_W-1:0]        RDATA,
    input wire [1:0]               RRESP,
    input wire                     RLAST,
    input wire                     RVALID,
    input wire                     RREADY
);

    integer fd;
    integer cycle;
    reg     rst_q;

    // Stall watchdog state, indexed as {0:AW, 1:W, 2:B, 3:AR, 4:R}
    integer    stall_cnt [0:4];
    reg  [4:0] stalled;
    wire [4:0] ch_valid = {RVALID,  BVALID,  WVALID,  ARVALID,  AWVALID};
    wire [4:0] ch_ready = {RREADY,  BREADY,  WREADY,  ARREADY,  AWREADY};

    integer     i;

    // Channel label for STALL lines
    function [15:0] ch_name(input integer idx);
        case (idx)
            0:       ch_name = "AW";
            1:       ch_name = "W ";
            2:       ch_name = "B ";
            3:       ch_name = "AR";
            default: ch_name = "R ";
        endcase
    endfunction

    initial begin
        fd      = 0;
        cycle   = 0;
        rst_q   = 1'b1;
        stalled = 5'b0;
        for (i = 0; i < 5; i = i + 1)
            stall_cnt[i] = 0;
        if (ENABLE) begin
            fd = $fopen({"axi3_", NAME, ".log"}, "w");
            if (fd == 0) begin
                $display("[axi3_logger:%0s] ERROR: could not open log file", NAME);
            end else begin
                $fdisplay(fd, "# milliSoC AXI3 bus log: port=%0s", NAME);
                $fdisplay(fd, "# ID_W=%0d ADDR_W=%0d DATA_W=%0d STALL_LIMIT=%0d", ID_W, ADDR_W, DATA_W, STALL_LIMIT);
                $fdisplay(fd, "# <time> <cycle> <chan> <fields>");
            end
        end
    end

    always @(posedge ACLK) begin
        if (ENABLE && fd != 0) begin
            cycle <= cycle + 1;

            // Reset edges (log when the design is released from reset)
            if (ARESETn !== rst_q)
                $fdisplay(fd, "%8t %6d  --  ARESETn=%b", $time, cycle, ARESETn);
            rst_q <= ARESETn;

            // Channel handshakes: one line per real bus transfer
            if (AWVALID && AWREADY)
                $fdisplay(fd, "%8t %6d  AW  id=%0h addr=%08h len=%02h size=%0h burst=%0h lock=%0h cache=%0h prot=%0h",
                          $time, cycle, AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT);
            if (WVALID && WREADY)
                $fdisplay(fd, "%8t %6d  W   id=%0h data=%0h strb=%02h last=%b",
                          $time, cycle, WID, WDATA, WSTRB, WLAST);
            if (BVALID && BREADY)
                $fdisplay(fd, "%8t %6d  B   id=%0h resp=%0h", $time, cycle, BID, BRESP);
            if (ARVALID && ARREADY)
                $fdisplay(fd, "%8t %6d  AR  id=%0h addr=%08h len=%02h size=%0h burst=%0h lock=%0h cache=%0h prot=%0h",
                          $time, cycle, ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT);
            if (RVALID && RREADY)
                $fdisplay(fd, "%8t %6d  R   id=%0h data=%0h resp=%0h last=%b",
                          $time, cycle, RID, RDATA, RRESP, RLAST);

            // Stall watchdog: report a channel stuck VALID&&!READY once per stall
            for (i = 0; i < 5; i = i + 1) begin
                if (ch_valid[i] && !ch_ready[i]) begin
                    stall_cnt[i] <= stall_cnt[i] + 1;
                    if ((STALL_LIMIT != 0) && (stall_cnt[i] == STALL_LIMIT-1) && !stalled[i]) begin
                        $fdisplay(fd, "%8t %6d  STALL %0s valid=1 ready=0 for %0d cycles",
                                  $time, cycle, ch_name(i), STALL_LIMIT);
                        stalled[i] <= 1'b1;
                    end
                end else begin
                    stall_cnt[i] <= 0;
                    stalled[i]   <= 1'b0;
                end
            end
        end
    end

endmodule

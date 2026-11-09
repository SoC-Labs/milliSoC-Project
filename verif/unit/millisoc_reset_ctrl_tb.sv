module millisoc_reset_ctrl_tb;
timeunit 1ns;
timeprecision 1ps;

reg clk = 1'b0;
reg nporeset = 1'b1;
reg sysresetreq = 1'b0;
reg watchdogreq = 1'b0;
reg dapsysresetreq = 1'b0;
reg sw_sysresetreq = 1'b0;
reg r5_dbgresetreq = 1'b0;
reg sw_r5resetreq = 1'b0;
reg sw_m85resetreq = 1'b0;

wire nsysreset;
wire nr5reset;
wire nm85reset;
wire dapsysresetack;

always #5 clk = ~clk;

millisoc_reset_ctrl dut (
    .CLKIN(clk),
    .nPORESET(nporeset),
    .SYSRESETREQ(sysresetreq),
    .WATCHDOGREQ(watchdogreq),
    .DAPSYSRESETREQ(dapsysresetreq),
    .SW_SYSRESETREQ(sw_sysresetreq),
    .R5_DBGRESETREQ(r5_dbgresetreq),
    .SW_R5RESETREQ(sw_r5resetreq),
    .SW_M85RESETREQ(sw_m85resetreq),
    .nSYSRESET(nsysreset),
    .nR5RESET(nr5reset),
    .nM85RESET(nm85reset),
    .DAPSYSRESETACK(dapsysresetack)
);

task automatic check_resets(
    input expected_sys,
    input expected_r5,
    input expected_m85
);
    #1;
    if (nsysreset !== expected_sys ||
        nr5reset !== expected_r5 ||
        nm85reset !== expected_m85)
        $fatal(1, "Unexpected reset state: SYS=%b R5=%b M85=%b",
               nsysreset, nr5reset, nm85reset);
endtask

task automatic wait_reset_release;
    repeat (4) @(posedge clk);
    check_resets(1'b1, 1'b1, 1'b1);
endtask

initial begin
    #1 nporeset = 1'b0;
    check_resets(1'b0, 1'b0, 1'b0);
    @(negedge clk) nporeset = 1'b1;
    repeat (5) @(posedge clk);
    check_resets(1'b1, 1'b1, 1'b1);

    @(negedge clk) r5_dbgresetreq = 1'b1;
    @(posedge clk);
    check_resets(1'b1, 1'b0, 1'b1);
    @(negedge clk) r5_dbgresetreq = 1'b0;
    wait_reset_release();

    @(negedge clk) sw_r5resetreq = 1'b1;
    @(posedge clk);
    check_resets(1'b1, 1'b0, 1'b1);
    @(negedge clk) sw_r5resetreq = 1'b0;
    wait_reset_release();

    @(negedge clk) sw_m85resetreq = 1'b1;
    @(posedge clk);
    check_resets(1'b1, 1'b1, 1'b0);
    @(negedge clk) sw_m85resetreq = 1'b0;
    wait_reset_release();

    @(negedge clk) sysresetreq = 1'b1;
    @(posedge clk);
    check_resets(1'b0, 1'b0, 1'b0);
    @(negedge clk) sysresetreq = 1'b0;
    wait_reset_release();

    @(negedge clk) watchdogreq = 1'b1;
    @(posedge clk);
    check_resets(1'b0, 1'b0, 1'b0);
    @(negedge clk) watchdogreq = 1'b0;
    wait_reset_release();

    @(negedge clk) sw_sysresetreq = 1'b1;
    @(posedge clk);
    check_resets(1'b0, 1'b0, 1'b0);
    @(negedge clk) sw_sysresetreq = 1'b0;
    wait_reset_release();

    @(negedge clk) dapsysresetreq = 1'b1;
    @(posedge clk);
    check_resets(1'b0, 1'b0, 1'b0);
    wait (dapsysresetack);
    check_resets(1'b1, 1'b1, 1'b1);
    repeat (3) @(posedge clk);
    check_resets(1'b1, 1'b1, 1'b1);
    if (dapsysresetack !== 1'b1)
        $fatal(1, "DAP reset acknowledgement did not remain asserted");
    @(negedge clk) dapsysresetreq = 1'b0;
    @(posedge clk);
    #1;
    if (dapsysresetack !== 1'b0)
        $fatal(1, "DAP reset acknowledgement did not clear");

    $display("PASS: reset controller source and scope checks");
    $finish;
end

endmodule

module millisoc_sys_ctrl_tb;
timeunit 1ns;
timeprecision 1ps;

reg pclk = 1'b0;
reg nporeset = 1'b1;
reg [31:0] paddr = 32'd0;
reg [31:0] pwdata = 32'd0;
reg penable = 1'b0;
reg pwrite = 1'b0;
reg psel = 1'b0;
reg [2:0] pprot = 3'd0;
reg [3:0] pstrb = 4'd0;

wire [31:0] prdata;
wire pready;
wire pslverr;
wire sw_sysresetreq;
wire sw_r5resetreq;
wire sw_m85resetreq;
wire cpu_mx_wait;

wire sysresetreq = 1'b0;
wire watchdogreq = 1'b0;
wire dapresetreq = 1'b0;
wire r5dbgresetreq = 1'b0;

apb4_if sys_ctrl_apb();

assign sys_ctrl_apb.paddr = paddr;
assign sys_ctrl_apb.pwdata = pwdata;
assign sys_ctrl_apb.penable = penable;
assign sys_ctrl_apb.pwrite = pwrite;
assign sys_ctrl_apb.psel = psel;
assign sys_ctrl_apb.pprot = pprot;
assign sys_ctrl_apb.pstrb = pstrb;
assign prdata = sys_ctrl_apb.prdata;
assign pready = sys_ctrl_apb.pready;
assign pslverr = sys_ctrl_apb.pslverr;

always #5 pclk = ~pclk;

millisoc_sys_ctrl dut (
    .pclk(pclk),
    .nporeset(nporeset),
    .sys_ctrl_apb(sys_ctrl_apb),
    .sysresetreq(sysresetreq),
    .watchdogreq(watchdogreq),
    .dapresetreq(dapresetreq),
    .r5dbgresetreq(r5dbgresetreq),
    .sw_sysresetreq(sw_sysresetreq),
    .sw_r5resetreq(sw_r5resetreq),
    .sw_m85resetreq(sw_m85resetreq),
    .cpu_mx_wait(cpu_mx_wait)
);

task automatic apb_write(input [31:0] address, input [31:0] data, input [3:0] strobe);
    @(negedge pclk);
    paddr = address;
    pwdata = data;
    pstrb = strobe;
    pwrite = 1'b1;
    psel = 1'b1;
    penable = 1'b0;
    @(negedge pclk);
    penable = 1'b1;
    #1;
    if (!pready || pslverr)
        $fatal(1, "SYS_CTRL APB write did not complete successfully");
    @(posedge pclk);
    #1;
    @(negedge pclk);
    psel = 1'b0;
    penable = 1'b0;
    pwrite = 1'b0;
    pstrb = 4'd0;
endtask

task automatic check_command_outputs(input expected_sys, input expected_r5, input expected_m85);
    #1;
    if (sw_sysresetreq !== expected_sys ||
        sw_r5resetreq !== expected_r5 ||
        sw_m85resetreq !== expected_m85)
        $fatal(1, "Unexpected SYS_CTRL reset command outputs");
endtask

task automatic apb_write_and_check_command(
    input [31:0] address,
    input [31:0] data,
    input expected_sys,
    input expected_r5,
    input expected_m85
);
    fork
        apb_write(address, data, 4'h1);
        begin
            wait (sw_sysresetreq || sw_r5resetreq || sw_m85resetreq);
            check_command_outputs(expected_sys, expected_r5, expected_m85);
        end
    join
    check_command_outputs(1'b0, 1'b0, 1'b0);
endtask

initial begin
    #1 nporeset = 1'b0;
    @(negedge pclk) nporeset = 1'b1;
    @(posedge pclk);
    #1;
    if (cpu_mx_wait !== 1'b1)
        $fatal(1, "CPUWAIT reset value changed");

    apb_write(32'h0000_0004, 32'd0, 4'h1);
    if (cpu_mx_wait !== 1'b0)
        $fatal(1, "CPUWAIT APB write did not take effect");

    apb_write_and_check_command(32'h0000_0008, 32'h0000_0001, 1'b0, 1'b1, 1'b0);
    apb_write_and_check_command(32'h0000_0008, 32'h0000_0002, 1'b0, 1'b0, 1'b1);
    apb_write_and_check_command(32'h0000_0008, 32'h0000_0004, 1'b1, 1'b0, 1'b0);

    @(negedge pclk);
    paddr = 32'h0000_0000;
    pwrite = 1'b0;
    psel = 1'b1;
    #1;
    if (prdata[7:0] !== 8'h08)
        $fatal(1, "Reset cause register did not record the software system reset: %h", prdata);
    psel = 1'b0;

    if (!pready || pslverr)
        $fatal(1, "SYS_CTRL APB response is invalid");

    $display("PASS: SYS_CTRL reset command and cause register checks");
    $finish;
end

endmodule

`timescale 1ns/1ns

module millisoc_tb();

wire CLK;
wire nPORST;
wire         QSPI_SCLK;
wire         QSPI_nCS;
wire [3:0]   QSPI_IO;

wire  UARTTXD0;
wire  UARTTXD0_RT;

millisoc_chip_pads u_millisoc(
    .CLK(CLK),
    .nPORST(nPORST),
    .QSPI_SCLK(QSPI_SCLK),
    .QSPI_nCS(QSPI_nCS),
    .QSPI_IO(QSPI_IO),

    .UARTTXD0(UARTTXD0),

    .UARTTXD0_RT(UARTTXD0_RT)
);

millisoc_clkreset u_millisoc_clkreset(
    .CLK(CLK),
    .NRST(nPORST)
);


sst26vf064b FLASH(
    .SCK(QSPI_SCLK),
    .SIO(QSPI_IO),
    .CEb(QSPI_nCS)
);

initial begin
    #1 $readmemh("image.hex", FLASH.I0.memory);
end


wire test_done;

always @(posedge CLK) begin
    if(test_done) begin
        $stop;
    end
end


 // --------------------------------------------------------------------------------
 // UART output capture
 // --------------------------------------------------------------------------------

assign PCLK = u_millisoc.u_millisoc_system.u_rt_peripheral.u_rx_periphs.u_apb_uart_0.BAUDTICK;

reg [3:0] pllq;

always @(posedge PCLK or negedge nPORST) begin
  if(!nPORST) begin
    pllq <= 4'b0;
  end else begin
    pllq <= pllq + 1'b1;
  end
end

cmsdk_uart_capture u_uart_capture(
  .RESETn(nPORST),
  .CLK(pllq[3]),
  .RXD(UARTTXD0_RT),
  .SIMULATIONEND(test_done),
  .DEBUG_TESTER_ENABLE(),
  .AUXCTRL()
);

  bind olympus_core olympus_core_instrid u_instrid();
  bind olympus_epu olympus_epu_instrid u_epu_instrid();




endmodule

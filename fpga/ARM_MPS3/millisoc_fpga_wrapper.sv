

module millisoc_fpga_wrapper(

    input  wire [1:0]       OSCCLK,
    input  wire             CB_nPOR,
    // User QSPI Flash
    inout wire  [17:0]      SH0_IO,
    // UART
    input  wire [3:0]       UART_RX_F,
    output wire [3:0]       UART_TX_F,


    // DAP-LITE external signals
    input  wire             CS_nTRST,
    input  wire             CS_TCK,
    inout  wire             CS_TMS, // TMS SWDIO
    input  wire             CS_TDI,
    output wire             CS_TDO,

    // M85 ITM trace output through the CoreSight TPIU
    output wire             CS_T_CLK,
    output wire [15:0]      CS_T_D,
    output wire             CS_T_CTL

);

// Attach QSPI To PMOD0
wire [3:0]  QSPI_IO_o;
wire [3:0]  QSPI_IO_i;
wire [3:0]  QSPI_IO_e;
wire        QSPI_SCLK;
wire        QSPI_nCS;

assign SH0_IO[10] = QSPI_nCS;
assign SH0_IO[13] = QSPI_SCLK;

assign SH0_IO[11] = QSPI_IO_e[0] ? QSPI_IO_o[0] : 1'bz;
assign SH0_IO[12] = QSPI_IO_e[1] ? QSPI_IO_o[1] : 1'bz;
assign SH0_IO[7] = QSPI_IO_e[2] ? QSPI_IO_o[2] : 1'bz;
assign SH0_IO[8] = QSPI_IO_e[3] ? QSPI_IO_o[3] : 1'bz;

assign QSPI_IO_i[0] = SH0_IO[11];
assign QSPI_IO_i[1] = SH0_IO[12];
assign QSPI_IO_i[2] = SH0_IO[7];
assign QSPI_IO_i[3] = SH0_IO[8];

assign SH0_IO[6] = CB_nPOR; // Reset for flash chip

wire SWDITMS;
wire SWDO;
wire SWDOEN;

assign SWDITMS = CS_TMS;
assign CS_TMS = SWDOEN ? SWDO : 1'bz;

millisoc_system u_millisoc(
    .FCLK(OSCCLK[1]),
    .nPORESET(CB_nPOR),
    .QSPI_SCLK(QSPI_SCLK),
    .QSPI_nCS(QSPI_nCS),
    .QSPI_IO_o(QSPI_IO_o),
    .QSPI_IO_i(QSPI_IO_i),
    .QSPI_IO_e(QSPI_IO_e),

    .UARTRXD0(UART_RX_F[2]),
    .UARTTXD0(UART_TX_F[2]),
    .UARTTXEN0(),
    .UARTRXD1(),
    .UARTTXD1(),
    .UARTTXEN1(),
    .UARTRXD0_RT(UART_RX_F[3]),
    .UARTTXD0_RT(UART_TX_F[3]),
    .UARTTXEN0_RT(),
    .UARTRXD1_RT(),
    .UARTTXD1_RT(),
    .UARTTXEN1_RT(),

    .nTRST(CS_nTRST),
    .SWCLKTCK(CS_TCK),
    .SWDITMS(SWDITMS),
    .TDI(CS_TDI),
    .TDO(CS_TDO),
    .nTDOEN(),
    .SWDO(SWDO),
    .SWDOEN(SWDOEN),

    .SPI_SSn(),
    .SPI_SCLK(),
    .SPI_MOSI(),
    .SPI_MISO(),
    .P0_IN(),
    .P0_OUT(),
    .P0_EN(),
    .P0_FUNC(),
    .P1_IN(),
    .P1_OUT(),
    .P1_EN(),
    .P1_FUNC(),

    .TRACECLK(CS_T_CLK),
    .TRACEDATA(CS_T_D[3:0]),
    .TRACECTL(CS_T_CTL)
);

endmodule

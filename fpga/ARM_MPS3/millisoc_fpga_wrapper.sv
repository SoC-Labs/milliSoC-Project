

module millisoc_fpga_wrapper(

    input  wire [1:0]       OSCCLK,
    input  wire             CB_nPOR,
    // User QSPI Flash
    inout  wire             QSPI_D0,
    inout  wire             QSPI_D1,
    inout  wire             QSPI_D2,
    inout  wire             QSPI_D3,
    output wire             QSPI_nCS,
    output wire             QSPI_SCLK,
    // UART
    input  wire [3:0]       UART_RX_F,
    output wire [3:0]       UART_TX_F,


    // DAP-LITE external signals
    input  wire             CS_nTRST,
    input  wire             CS_TCK,
    input  wire             CS_TMS,
    input  wire             CS_TDI,
    output wire             CS_TDO,
    output wire             nTDOEN,
    output wire             SWDO,
    output wire             SWDOEN,


    // M85 ITM trace output through the CoreSight TPIU
    output wire             CS_T_CLK,
    output wire [15:0]      CS_T_D,
    output wire             CS_T_CTL

);


wire [3:0]  QSPI_IO_o;
wire [3:0]  QSPI_IO_i;
wire [3:0]  QSPI_IO_e;

assign QSPI_D0 = QSPI_IO_e[0] ? QSPI_IO_o[0] : 1'bz;
assign QSPI_D1 = QSPI_IO_e[1] ? QSPI_IO_o[1] : 1'bz;
assign QSPI_D2 = QSPI_IO_e[2] ? QSPI_IO_o[2] : 1'bz;
assign QSPI_D3 = QSPI_IO_e[3] ? QSPI_IO_o[3] : 1'bz;

assign QSPI_IO_i[0] = QSPI_D0;
assign QSPI_IO_i[1] = QSPI_D1;
assign QSPI_IO_i[2] = QSPI_D2;
assign QSPI_IO_i[3] = QSPI_D3;


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
    .SWDITMS(CS_TMS),
    .TDI(CS_TDI),
    .TDO(CS_TDO),
    .nTDOEN(),
    .SWDO(),
    .SWDOEN(),

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

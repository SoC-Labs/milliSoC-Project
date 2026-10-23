

module millisoc_fpga_wrapper(

);


millisoc_system u_millisoc(
    .FCLK(),
    .nPORESET(),
    .QSPI_SCLK(),
    .QSPI_nCS(),
    .QSPI_IO_o(),
    .QSPI_IO_i(),
    .QSPI_IO_e(),
    .UARTRXD0(),
    .UARTTXD0(),
    .UARTTXEN0(),
    .UARTRXD1(),
    .UARTTXD1(),
    .UARTTXEN1(),
    .UARTRXD0_RT(),
    .UARTTXD0_RT(),
    .UARTTXEN0_RT(),
    .UARTRXD1_RT(),
    .UARTTXD1_RT(),
    .UARTTXEN1_RT(),

    .nTRST(),
    .SWCLKTCK(),
    .SWDITMS(),
    .TDI(),,
    .TDO(),,
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
    .TRACECLK(),
    .TRACEDATA(),
    .TRACECTL()
);

endmodule

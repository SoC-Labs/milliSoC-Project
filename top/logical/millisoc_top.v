

module millisoc_top(
    input  wire       CLK,      // System clock
    input  wire       nPORST,    // Active low power-on reset

    output wire         QSPI_SCLK,
    output wire         QSPI_nCS,
    inout  wire [3:0]   QSPI_IO,

    inout  wire [3:0]   EXTIO_IO,
    output wire         EXTIO_IOREQ1,
    output wire         EXTIO_IOREQ2,
    input  wire         EXTIO_IOACK

);

millisoc_chip_pads u_millisoc_chip_pads(
    .CLK    (CLK    ),
    .nPORST (nPORST ),
    .QSPI_SCLK(QSPI_SCLK),
    .QSPI_nCS(QSPI_nCS),
    .QSPI_IO(QSPI_IO),
    .EXTIO_IO(EXTIO_IO),
    .EXTIO_IOREQ1(EXTIO_IOREQ1),
    .EXTIO_IOREQ2(EXTIO_IOREQ2),
    .EXTIO_IOACK(EXTIO_IOACK)
);


endmodule

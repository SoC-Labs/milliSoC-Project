`timescale 1ns/1ps
module millisoc_tb();

wire CLK;
wire nPORST;
wire         QSPI_SCLK;
wire         QSPI_nCS;
wire [3:0]   QSPI_IO;
wire [3:0]   EXTIO_IO;
wire         EXTIO_IOREQ1;
wire         EXTIO_IOREQ2;
wire         EXTIO_IOACK;
millisoc_top u_millisoc(
    .CLK(CLK),
    .nPORST(nPORST),
    .QSPI_SCLK(QSPI_SCLK),
    .QSPI_nCS(QSPI_nCS),
    .QSPI_IO(QSPI_IO),
    .EXTIO_IO(EXTIO_IO),
    .EXTIO_IOREQ1(EXTIO_IOREQ1),
    .EXTIO_IOREQ2(EXTIO_IOREQ2),
    .EXTIO_IOACK(EXTIO_IOACK)
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


// 4-channel AXIS interface - Subordinate side
  wire       axis_rx0_tready;
  wire       axis_rx0_tvalid;
  wire [7:0] axis_rx0_tdata8;
  wire       axis_rx1_tready;
  wire       axis_rx1_tvalid;
  wire [7:0] axis_rx1_tdata8;
  wire       axis_tx0_tready;
  wire       axis_tx0_tvalid;
  wire [7:0] axis_tx0_tdata8;
  wire       axis_tx1_tready;
  wire       axis_tx1_tvalid;
  wire [7:0] axis_tx1_tdata8;
// external io interface
  tri  [3:0] iodata4;
  wire [3:0] iodata4_i;
  wire [3:0] iodata4_o;
  wire [3:0] iodata4_e;
  wire [3:0] iodata4_t;
  wire       ioreq1;
  wire       ioreq2;
  wire       ioack;

wire test_done;

always @(posedge CLK) begin
    if(test_done) begin
        $stop;
    end
end

extio8x4_axis_target u_extio8x4_axis_target(
  .clk             ( CLK             ),
  .resetn          ( nPORST            ),
  .testmode        ( 1'b0            ),
// RX 4-channel AXIS interface
  .axis_rx0_tready ( axis_rx0_tready ),
  .axis_rx0_tvalid ( axis_rx0_tvalid ),
  .axis_rx0_tdata8 ( axis_rx0_tdata8 ),
  .axis_rx1_tready ( axis_rx1_tready ),
  .axis_rx1_tvalid ( axis_rx1_tvalid ),
  .axis_rx1_tdata8 ( axis_rx1_tdata8 ),
  .axis_tx0_tready ( axis_tx0_tready ),
  .axis_tx0_tvalid ( axis_tx0_tvalid ),
  .axis_tx0_tdata8 ( axis_tx0_tdata8 ),
  .axis_tx1_tready ( axis_tx1_tready ),
  .axis_tx1_tvalid ( axis_tx1_tvalid ),
  .axis_tx1_tdata8 ( axis_tx1_tdata8 ),
// external io interface
  .iodata4_i       ( iodata4_i       ),
  .iodata4_o       ( iodata4_o       ),
  .iodata4_e       ( iodata4_e       ),
  .iodata4_t       ( iodata4_t       ),
  .ioreq1_a        ( ioreq1          ),
  .ioreq2_a        ( ioreq2          ),
  .ioack_o         ( ioack           )
);

// EXTIO trace mapping
bufif0 #1 (EXTIO_IO[0], iodata4_o[0] , iodata4_t[0]);
bufif0 #1 (EXTIO_IO[1], iodata4_o[1] , iodata4_t[1]);
bufif0 #1 (EXTIO_IO[2], iodata4_o[2] , iodata4_t[2]);
bufif0 #1 (EXTIO_IO[3], iodata4_o[3] , iodata4_t[3]);
assign iodata4_i = EXTIO_IO[3:0];
assign ioreq1 = EXTIO_IOREQ1;
assign ioreq2 = EXTIO_IOREQ2;
assign EXTIO_IOACK = ioack;
assign axis_rx1_tvalid = 1'b0;

  millisoc_axi_stream_io_8_rxd_to_file#(
    .RXDFILENAME("logs/extadp_out.log"),
    .VERBOSE(1)
  ) u_millisoc_axi_stream_io_stream_adp_rxd_to_file (
    .aclk         (CLK),
    .aresetn      (nPORST),
    .eof_received (test_done),
    .rxd8_ready   (axis_tx0_tready),
    .rxd8_valid   (axis_tx0_tvalid),
    .rxd8_data    (axis_tx0_tdata8)
  );

  millisoc_axi_stream_io_8_rxd_to_file#(
    .RXDFILENAME("logs/extdat_out.log"),
    .VERBOSE(0)
  ) u_millisoc_axi_stream_io_stream_dat_rxd_to_file (
    .aclk         (CLK),
    .aresetn      (nPORST),
    .eof_received (),
    .rxd8_ready   (axis_tx1_tready),
    .rxd8_valid   (axis_tx1_tvalid),
    .rxd8_data    (axis_tx1_tdata8)
  );



endmodule

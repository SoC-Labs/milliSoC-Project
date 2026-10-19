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
wire test_done_M;

always @(posedge CLK) begin
    if(test_done || test_done_M) begin
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

uart_logger #(.LOGFILENAME("./logs/uart_R5.log")) u_uart_R5(
  .RESETn(nPORST),
  .CLK(pllq[3]),
  .RXD(UARTTXD0_RT),
  .SIMULATIONEND(test_done),
  .DEBUG_TESTER_ENABLE(),
  .AUXCTRL()
);

assign PCLK_M = u_millisoc.u_millisoc_system.u_millisoc_peripheral_subsystem.u_apb_uart_0.BAUDTICK;

reg [3:0] pllq_m;

always @(posedge PCLK_M or negedge nPORST) begin
  if(!nPORST) begin
    pllq_m <= 4'b0;
  end else begin
    pllq_m <= pllq_m + 1'b1;
  end
end

uart_logger #(.LOGFILENAME("./logs/uart_M85.log")) u_uart_M85(
  .RESETn(nPORST),
  .CLK(pllq_m[3]),
  .RXD(UARTTXD0),
  .SIMULATIONEND(test_done_M),
  .DEBUG_TESTER_ENABLE(),
  .AUXCTRL()
);


  bind olympus_core olympus_core_instrid u_instrid();
  bind olympus_epu olympus_epu_instrid u_epu_instrid();


 // --------------------------------------------------------------------------------
 // AXI port monitors
 //
 // One logger instance per AXI port, each writing its own log file
 // (axi3_<name>.log / axi4_<name>.log) in the sim run directory.
 // Ports are tapped by hierarchical reference into u_millisoc.u_millisoc_system,
 // the same way PCLK is captured above. All AXI in the system is clocked by
 // FCLK (= CLK at the pads).
 //
 // Note: the axi3_if interface declares RDATA one bit wide (typo in the
 // interface), the logger port is DATA_W wide and truncates it.
 // --------------------------------------------------------------------------------

 // -- AXI3: Cortex-R5 master port into NIC400 (code/data fetches, peripheral access)
axi3_logger #(
    .NAME("r5_master"), .ID_W(4), .DATA_W(64)
) u_axi3_r5_master (
    .ACLK(CLK),
    .ARESETn(u_millisoc.u_millisoc_system.nSYSRESET),

    .AWID(u_millisoc.u_millisoc_system.CPU_Rx_AXI.AWID),
    .AWADDR(u_millisoc.u_millisoc_system.CPU_Rx_AXI.AWADDR),
    .AWLEN(u_millisoc.u_millisoc_system.CPU_Rx_AXI.AWLEN),
    .AWSIZE(u_millisoc.u_millisoc_system.CPU_Rx_AXI.AWSIZE),
    .AWBURST(u_millisoc.u_millisoc_system.CPU_Rx_AXI.AWBURST),
    .AWLOCK(u_millisoc.u_millisoc_system.CPU_Rx_AXI.AWLOCK),
    .AWCACHE(u_millisoc.u_millisoc_system.CPU_Rx_AXI.AWCACHE),
    .AWPROT(u_millisoc.u_millisoc_system.CPU_Rx_AXI.AWPROT),
    .AWVALID(u_millisoc.u_millisoc_system.CPU_Rx_AXI.AWVALID),
    .AWREADY(u_millisoc.u_millisoc_system.CPU_Rx_AXI.AWREADY),

    .WID(u_millisoc.u_millisoc_system.CPU_Rx_AXI.WID),
    .WDATA(u_millisoc.u_millisoc_system.CPU_Rx_AXI.WDATA),
    .WSTRB(u_millisoc.u_millisoc_system.CPU_Rx_AXI.WSTRB),
    .WLAST(u_millisoc.u_millisoc_system.CPU_Rx_AXI.WLAST),
    .WVALID(u_millisoc.u_millisoc_system.CPU_Rx_AXI.WVALID),
    .WREADY(u_millisoc.u_millisoc_system.CPU_Rx_AXI.WREADY),

    .BID(u_millisoc.u_millisoc_system.CPU_Rx_AXI.BID),
    .BRESP(u_millisoc.u_millisoc_system.CPU_Rx_AXI.BRESP),
    .BVALID(u_millisoc.u_millisoc_system.CPU_Rx_AXI.BVALID),
    .BREADY(u_millisoc.u_millisoc_system.CPU_Rx_AXI.BREADY),

    .ARID(u_millisoc.u_millisoc_system.CPU_Rx_AXI.ARID),
    .ARADDR(u_millisoc.u_millisoc_system.CPU_Rx_AXI.ARADDR),
    .ARLEN(u_millisoc.u_millisoc_system.CPU_Rx_AXI.ARLEN),
    .ARSIZE(u_millisoc.u_millisoc_system.CPU_Rx_AXI.ARSIZE),
    .ARBURST(u_millisoc.u_millisoc_system.CPU_Rx_AXI.ARBURST),
    .ARLOCK(u_millisoc.u_millisoc_system.CPU_Rx_AXI.ARLOCK),
    .ARCACHE(u_millisoc.u_millisoc_system.CPU_Rx_AXI.ARCACHE),
    .ARPROT(u_millisoc.u_millisoc_system.CPU_Rx_AXI.ARPROT),
    .ARVALID(u_millisoc.u_millisoc_system.CPU_Rx_AXI.ARVALID),
    .ARREADY(u_millisoc.u_millisoc_system.CPU_Rx_AXI.ARREADY),

    .RID(u_millisoc.u_millisoc_system.CPU_Rx_AXI.RID),
    .RDATA(u_millisoc.u_millisoc_system.CPU_Rx_AXI.RDATA),
    .RRESP(u_millisoc.u_millisoc_system.CPU_Rx_AXI.RRESP),
    .RLAST(u_millisoc.u_millisoc_system.CPU_Rx_AXI.RLAST),
    .RVALID(u_millisoc.u_millisoc_system.CPU_Rx_AXI.RVALID),
    .RREADY(u_millisoc.u_millisoc_system.CPU_Rx_AXI.RREADY)
);

 // -- AXI3: NIC400 -> R5 subsystem subordinate port (inbound accesses to R5 TCM etc.)
axi3_logger #(
    .NAME("r5_subord"), .ID_W(8), .DATA_W(64)
) u_axi3_r5_subord (
    .ACLK(CLK),
    .ARESETn(u_millisoc.u_millisoc_system.nSYSRESET),

    .AWID(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.AWID),
    .AWADDR(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.AWADDR),
    .AWLEN(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.AWLEN),
    .AWSIZE(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.AWSIZE),
    .AWBURST(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.AWBURST),
    .AWLOCK(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.AWLOCK),
    .AWCACHE(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.AWCACHE),
    .AWPROT(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.AWPROT),
    .AWVALID(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.AWVALID),
    .AWREADY(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.AWREADY),

    .WID(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.WID),
    .WDATA(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.WDATA),
    .WSTRB(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.WSTRB),
    .WLAST(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.WLAST),
    .WVALID(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.WVALID),
    .WREADY(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.WREADY),

    .BID(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.BID),
    .BRESP(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.BRESP),
    .BVALID(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.BVALID),
    .BREADY(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.BREADY),

    .ARID(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.ARID),
    .ARADDR(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.ARADDR),
    .ARLEN(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.ARLEN),
    .ARSIZE(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.ARSIZE),
    .ARBURST(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.ARBURST),
    .ARLOCK(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.ARLOCK),
    .ARCACHE(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.ARCACHE),
    .ARPROT(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.ARPROT),
    .ARVALID(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.ARVALID),
    .ARREADY(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.ARREADY),

    .RID(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.RID),
    .RDATA(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.RDATA),
    .RRESP(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.RRESP),
    .RLAST(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.RLAST),
    .RVALID(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.RVALID),
    .RREADY(u_millisoc.u_millisoc_system.CPU_Rx_S_AXI.RREADY)
);

 // -- AXI3: R5 real-time peripheral bus (UART, timers, sysctrl on the RT cluster)
axi3_logger #(
    .NAME("r5_peri"), .ID_W(4), .DATA_W(32)
) u_axi3_r5_peri (
    .ACLK(CLK),
    .ARESETn(u_millisoc.u_millisoc_system.nSYSRESET),

    .AWID(u_millisoc.u_millisoc_system.Rx_PERI_AXI.AWID),
    .AWADDR(u_millisoc.u_millisoc_system.Rx_PERI_AXI.AWADDR),
    .AWLEN(u_millisoc.u_millisoc_system.Rx_PERI_AXI.AWLEN),
    .AWSIZE(u_millisoc.u_millisoc_system.Rx_PERI_AXI.AWSIZE),
    .AWBURST(u_millisoc.u_millisoc_system.Rx_PERI_AXI.AWBURST),
    .AWLOCK(u_millisoc.u_millisoc_system.Rx_PERI_AXI.AWLOCK),
    .AWCACHE(u_millisoc.u_millisoc_system.Rx_PERI_AXI.AWCACHE),
    .AWPROT(u_millisoc.u_millisoc_system.Rx_PERI_AXI.AWPROT),
    .AWVALID(u_millisoc.u_millisoc_system.Rx_PERI_AXI.AWVALID),
    .AWREADY(u_millisoc.u_millisoc_system.Rx_PERI_AXI.AWREADY),

    .WID(u_millisoc.u_millisoc_system.Rx_PERI_AXI.WID),
    .WDATA(u_millisoc.u_millisoc_system.Rx_PERI_AXI.WDATA),
    .WSTRB(u_millisoc.u_millisoc_system.Rx_PERI_AXI.WSTRB),
    .WLAST(u_millisoc.u_millisoc_system.Rx_PERI_AXI.WLAST),
    .WVALID(u_millisoc.u_millisoc_system.Rx_PERI_AXI.WVALID),
    .WREADY(u_millisoc.u_millisoc_system.Rx_PERI_AXI.WREADY),

    .BID(u_millisoc.u_millisoc_system.Rx_PERI_AXI.BID),
    .BRESP(u_millisoc.u_millisoc_system.Rx_PERI_AXI.BRESP),
    .BVALID(u_millisoc.u_millisoc_system.Rx_PERI_AXI.BVALID),
    .BREADY(u_millisoc.u_millisoc_system.Rx_PERI_AXI.BREADY),

    .ARID(u_millisoc.u_millisoc_system.Rx_PERI_AXI.ARID),
    .ARADDR(u_millisoc.u_millisoc_system.Rx_PERI_AXI.ARADDR),
    .ARLEN(u_millisoc.u_millisoc_system.Rx_PERI_AXI.ARLEN),
    .ARSIZE(u_millisoc.u_millisoc_system.Rx_PERI_AXI.ARSIZE),
    .ARBURST(u_millisoc.u_millisoc_system.Rx_PERI_AXI.ARBURST),
    .ARLOCK(u_millisoc.u_millisoc_system.Rx_PERI_AXI.ARLOCK),
    .ARCACHE(u_millisoc.u_millisoc_system.Rx_PERI_AXI.ARCACHE),
    .ARPROT(u_millisoc.u_millisoc_system.Rx_PERI_AXI.ARPROT),
    .ARVALID(u_millisoc.u_millisoc_system.Rx_PERI_AXI.ARVALID),
    .ARREADY(u_millisoc.u_millisoc_system.Rx_PERI_AXI.ARREADY),

    .RID(u_millisoc.u_millisoc_system.Rx_PERI_AXI.RID),
    .RDATA(u_millisoc.u_millisoc_system.Rx_PERI_AXI.RDATA),
    .RRESP(u_millisoc.u_millisoc_system.Rx_PERI_AXI.RRESP),
    .RLAST(u_millisoc.u_millisoc_system.Rx_PERI_AXI.RLAST),
    .RVALID(u_millisoc.u_millisoc_system.Rx_PERI_AXI.RVALID),
    .RREADY(u_millisoc.u_millisoc_system.Rx_PERI_AXI.RREADY)
);

 // -- AXI4: Cortex-M85 master port into NIC400
axi4_logger #(
    .NAME("m85_master"), .ID_W(3), .DATA_W(64)
) u_axi4_m85_master (
    .ACLK(CLK),
    .ARESETn(nPORST),

    .AWID(u_millisoc.u_millisoc_system.CPU_AXI.AWID),
    .AWADDR(u_millisoc.u_millisoc_system.CPU_AXI.AWADDR),
    .AWLEN(u_millisoc.u_millisoc_system.CPU_AXI.AWLEN),
    .AWSIZE(u_millisoc.u_millisoc_system.CPU_AXI.AWSIZE),
    .AWBURST(u_millisoc.u_millisoc_system.CPU_AXI.AWBURST),
    .AWLOCK(u_millisoc.u_millisoc_system.CPU_AXI.AWLOCK),
    .AWCACHE(u_millisoc.u_millisoc_system.CPU_AXI.AWCACHE),
    .AWPROT(u_millisoc.u_millisoc_system.CPU_AXI.AWPROT),
    .AWVALID(u_millisoc.u_millisoc_system.CPU_AXI.AWVALID),
    .AWREADY(u_millisoc.u_millisoc_system.CPU_AXI.AWREADY),

    .WDATA(u_millisoc.u_millisoc_system.CPU_AXI.WDATA),
    .WSTRB(u_millisoc.u_millisoc_system.CPU_AXI.WSTRB),
    .WLAST(u_millisoc.u_millisoc_system.CPU_AXI.WLAST),
    .WVALID(u_millisoc.u_millisoc_system.CPU_AXI.WVALID),
    .WREADY(u_millisoc.u_millisoc_system.CPU_AXI.WREADY),

    .BID(u_millisoc.u_millisoc_system.CPU_AXI.BID),
    .BRESP(u_millisoc.u_millisoc_system.CPU_AXI.BRESP),
    .BVALID(u_millisoc.u_millisoc_system.CPU_AXI.BVALID),
    .BREADY(u_millisoc.u_millisoc_system.CPU_AXI.BREADY),

    .ARID(u_millisoc.u_millisoc_system.CPU_AXI.ARID),
    .ARADDR(u_millisoc.u_millisoc_system.CPU_AXI.ARADDR),
    .ARLEN(u_millisoc.u_millisoc_system.CPU_AXI.ARLEN),
    .ARSIZE(u_millisoc.u_millisoc_system.CPU_AXI.ARSIZE),
    .ARBURST(u_millisoc.u_millisoc_system.CPU_AXI.ARBURST),
    .ARLOCK(u_millisoc.u_millisoc_system.CPU_AXI.ARLOCK),
    .ARCACHE(u_millisoc.u_millisoc_system.CPU_AXI.ARCACHE),
    .ARPROT(u_millisoc.u_millisoc_system.CPU_AXI.ARPROT),
    .ARVALID(u_millisoc.u_millisoc_system.CPU_AXI.ARVALID),
    .ARREADY(u_millisoc.u_millisoc_system.CPU_AXI.ARREADY),

    .RID(u_millisoc.u_millisoc_system.CPU_AXI.RID),
    .RDATA(u_millisoc.u_millisoc_system.CPU_AXI.RDATA),
    .RRESP(u_millisoc.u_millisoc_system.CPU_AXI.RRESP),
    .RLAST(u_millisoc.u_millisoc_system.CPU_AXI.RLAST),
    .RVALID(u_millisoc.u_millisoc_system.CPU_AXI.RVALID),
    .RREADY(u_millisoc.u_millisoc_system.CPU_AXI.RREADY)
);


 // -- AXI4: DMA350 master port into NIC400
axi4_logger #(
    .NAME("dma"), .ID_W(2), .DATA_W(64)
) u_axi4_dma (
    .ACLK(CLK),
    .ARESETn(nPORST),

    .AWID(u_millisoc.u_millisoc_system.DMA_AXI.AWID),
    .AWADDR(u_millisoc.u_millisoc_system.DMA_AXI.AWADDR),
    .AWLEN(u_millisoc.u_millisoc_system.DMA_AXI.AWLEN),
    .AWSIZE(u_millisoc.u_millisoc_system.DMA_AXI.AWSIZE),
    .AWBURST(u_millisoc.u_millisoc_system.DMA_AXI.AWBURST),
    .AWLOCK(u_millisoc.u_millisoc_system.DMA_AXI.AWLOCK),
    .AWCACHE(u_millisoc.u_millisoc_system.DMA_AXI.AWCACHE),
    .AWPROT(u_millisoc.u_millisoc_system.DMA_AXI.AWPROT),
    .AWVALID(u_millisoc.u_millisoc_system.DMA_AXI.AWVALID),
    .AWREADY(u_millisoc.u_millisoc_system.DMA_AXI.AWREADY),

    .WDATA(u_millisoc.u_millisoc_system.DMA_AXI.WDATA),
    .WSTRB(u_millisoc.u_millisoc_system.DMA_AXI.WSTRB),
    .WLAST(u_millisoc.u_millisoc_system.DMA_AXI.WLAST),
    .WVALID(u_millisoc.u_millisoc_system.DMA_AXI.WVALID),
    .WREADY(u_millisoc.u_millisoc_system.DMA_AXI.WREADY),

    .BID(u_millisoc.u_millisoc_system.DMA_AXI.BID),
    .BRESP(u_millisoc.u_millisoc_system.DMA_AXI.BRESP),
    .BVALID(u_millisoc.u_millisoc_system.DMA_AXI.BVALID),
    .BREADY(u_millisoc.u_millisoc_system.DMA_AXI.BREADY),

    .ARID(u_millisoc.u_millisoc_system.DMA_AXI.ARID),
    .ARADDR(u_millisoc.u_millisoc_system.DMA_AXI.ARADDR),
    .ARLEN(u_millisoc.u_millisoc_system.DMA_AXI.ARLEN),
    .ARSIZE(u_millisoc.u_millisoc_system.DMA_AXI.ARSIZE),
    .ARBURST(u_millisoc.u_millisoc_system.DMA_AXI.ARBURST),
    .ARLOCK(u_millisoc.u_millisoc_system.DMA_AXI.ARLOCK),
    .ARCACHE(u_millisoc.u_millisoc_system.DMA_AXI.ARCACHE),
    .ARPROT(u_millisoc.u_millisoc_system.DMA_AXI.ARPROT),
    .ARVALID(u_millisoc.u_millisoc_system.DMA_AXI.ARVALID),
    .ARREADY(u_millisoc.u_millisoc_system.DMA_AXI.ARREADY),

    .RID(u_millisoc.u_millisoc_system.DMA_AXI.RID),
    .RDATA(u_millisoc.u_millisoc_system.DMA_AXI.RDATA),
    .RRESP(u_millisoc.u_millisoc_system.DMA_AXI.RRESP),
    .RLAST(u_millisoc.u_millisoc_system.DMA_AXI.RLAST),
    .RVALID(u_millisoc.u_millisoc_system.DMA_AXI.RVALID),
    .RREADY(u_millisoc.u_millisoc_system.DMA_AXI.RREADY)
);


endmodule

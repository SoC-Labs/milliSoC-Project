

module dspsoc_top(
    input  wire       CLK,      // System clock
    input  wire       nPORST    // Active low power-on reset
);

dspsoc_chip_pads u_dspsoc_chip_pads(
    .CLK    (CLK    ),
    .nPORST (nPORST )
);


endmodule

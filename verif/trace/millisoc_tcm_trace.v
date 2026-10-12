
module millisoc_tcm_trace (
    input  wire         clk,
    input  wire         rst_n,
     // - ITCM
    input  wire         ITCMCS,
    input  wire [23:3]  ITCMADDR,
    input  wire         ITCMWR,
    input  wire [ 7:0]  ITCMBYTEWR,
    input  wire [ 3:0]  ITCMMASTER,
    input  wire [63:0]  ITCMWDATA,
    input  wire [63:0]  ITCMRDATA

);


endmodule
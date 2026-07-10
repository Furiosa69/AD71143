// Xilinx primitives behavioral models for simulation

module fifo_generator_0 (
    input  wire         wr_clk,
    input  wire         rd_clk,
    input  wire [255:0] din,
    input  wire         wr_en,
    input  wire         rd_en,
    output wire [255:0] dout,
    output wire         full,
    output wire         empty
);
    // Simple behavioral: no data ever written (test mode), always empty
    assign empty = 1'b1;
    assign full  = 1'b0;
    assign dout  = 256'd0;
endmodule

module ODDR #(
    parameter DDR_CLK_EDGE = "OPPOSITE_EDGE",
    parameter INIT = 1'b0,
    parameter SRTYPE = "SYNC"
) (
    output wire Q,
    input  wire C,
    input  wire CE,
    input  wire D1,
    input  wire D2,
    input  wire R,
    input  wire S
);
    reg q_out;
    always @(posedge C) q_out <= D1;
    always @(negedge C) q_out <= D2;
    assign Q = q_out;
endmodule

// Vendored unmodified from ../../../NanoTangAI/gateware/rtl/dot_product_lane_array.v,
// part of the AI accelerator integration - see docs/PERIPHERALS.md "AI accelerator".
// License: Apache-2.0 (see that project's library.properties/README;
// same author as this repo).
//
`timescale 1ns / 1ps
//
// LANES-wide INT8 multiply + reduce, for one weight-tile row.
//
// Every cycle `en` is asserted, all LANES int8_mac_lane instances multiply
// their (a,b) pair; one cycle later `sum` is the signed sum of all LANES
// products for that cycle's inputs (`sum_valid` follows `en` by one cycle).
// This is one "chunk" of a longer dot product -- dot_product_engine.v
// accumulates `sum` across ceil(cin_padded/LANES) chunks to get a full
// row's INT8 dot product, matching dspsDotProdS8()'s semantics
// (TinyTTS/src/int8-dotprod/dsps_dp_s8_ansi.c): int32 accumulate of
// a[i]*b[i] over the full vector.
//
// The summation below is written as a plain behavioral reduction, not a
// hand-balanced tree -- Yosys/nextpnr are expected to balance the actual
// adder structure during synthesis; this only fixes the *bit-exact*
// result, which is order-independent for integer addition.
//
module dot_product_lane_array #(
    parameter integer LANES = 16
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     en,
    input  wire signed [LANES*8-1:0] a_vec,  // shared activation chunk, LANES signed int8 lanes packed LSB-first
    input  wire signed [LANES*8-1:0] b_vec,  // this row's weight chunk, same packing
    output reg  signed [31:0]        sum,
    output reg                       sum_valid
);

  wire signed [16:0] prod [0:LANES-1];

  genvar gi;
  generate
    for (gi = 0; gi < LANES; gi = gi + 1) begin : g_lanes
      int8_mac_lane u_lane (
          .clk  (clk),
          .rst_n(rst_n),
          .en   (en),
          .a    (a_vec[gi*8 +: 8]),
          .b    (b_vec[gi*8 +: 8]),
          .prod (prod[gi])
      );
    end
  endgenerate

  integer i;
  reg en_d;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      en_d <= 1'b0;
    end else begin
      en_d <= en;
    end
  end

  always @(*) begin
    sum = 32'sd0;
    for (i = 0; i < LANES; i = i + 1) begin
      sum = sum + prod[i];
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sum_valid <= 1'b0;
    else sum_valid <= en_d;
  end

endmodule

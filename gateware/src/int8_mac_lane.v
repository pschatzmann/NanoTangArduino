// Vendored unmodified from ../../../NanoTangAI/gateware/rtl/int8_mac_lane.v,
// part of the AI accelerator integration - see docs/PERIPHERALS.md "AI accelerator".
// License: Apache-2.0 (see that project's library.properties/README;
// same author as this repo).
//
`timescale 1ns / 1ps
//
// Single INT8 x INT8 -> INT32-safe multiply-accumulate lane.
//
// One clock of pipeline latency: `prod` registers the product of `a`/`b`
// (both signed 8-bit, matching TinyTTS's symmetric-quantized activations
// and weights, see WeightStore.h dtype 2 / Ops.h conv1d()'s `xq`/`wtile_i8`).
// `clear` loads `prod` with the multiply result instead of accumulating,
// used by dot_product_engine.v to start a new reduction chunk.
//
module int8_mac_lane (
    input  wire        clk,
    input  wire        rst_n,
    input  wire         en,     // advance the pipeline this cycle
    input  wire  signed [7:0] a,
    input  wire  signed [7:0] b,
    output reg   signed [16:0] prod  // max |a*b| = 128*128 = 16384, fits comfortably in 17 bits
);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      prod <= 17'sd0;
    end else if (en) begin
      prod <= $signed(a) * $signed(b);
    end
  end

endmodule

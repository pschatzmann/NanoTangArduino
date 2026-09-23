// Vendored from ../../../NanoTangAI/gateware/rtl/int8_mac_lane.v,
// part of the AI accelerator integration - see docs/PERIPHERALS.md "AI accelerator".
// License: Apache-2.0 (see that project's library.properties/README;
// same author as this repo). One deliberate deviation from the vendored
// original: under synthesis the multiply uses a Gowin MULT9X9 DSP block
// instead of `*`. This yosys (0.33) has no DSP inference for Gowin, and
// maps each 8x8 signed `*` onto ~250 LUT4s plus muxes - with 32 lanes
// that alone overflowed the GW2AR-18. Simulation (no SYNTHESIS define)
// keeps the plain `*`, since yosys's MULT9X9 is a blackbox with no model.
//
// The pipeline register sits in the DSP block's own input registers
// (AREG/BREG, clock-enabled by `en`) rather than in fabric after the
// multiplier: registering the operands and multiplying is the same
// one-cycle latency and the same values as registering the product. It
// also saves 17 fabric flip-flops per lane - but the reason is a packer
// bug: apicula 0.33's gowin_pack (the newest release as of 2026-09) builds
// the wrong fuse name for an unregistered MULT9X9 B input
// ("KeyError: 'IRBY_IREG0BL_0'", set_mult9x9_attrvals() uses the A input's
// index for B), so any design with AREG/BREG=0 fails to pack. Fixed in
// apicula master (attr_off), not yet released.
//
`timescale 1ns / 1ps
//
// Single INT8 x INT8 -> INT32-safe multiply-accumulate lane.
//
// One clock of pipeline latency: `prod` is the product of the `a`/`b`
// captured at the last clock edge with `en` set (both signed 8-bit,
// matching TinyTTS's symmetric-quantized activations and weights, see
// WeightStore.h dtype 2 / Ops.h conv1d()'s `xq`/`wtile_i8`), holding its
// value while `en` is low; 0 after reset.
//
module int8_mac_lane (
    input  wire        clk,
    input  wire        rst_n,
    input  wire         en,     // advance the pipeline this cycle
    input  wire  signed [7:0] a,
    input  wire  signed [7:0] b,
    output wire  signed [16:0] prod  // max |a*b| = 128*128 = 16384, fits comfortably in 17 bits
);

`ifdef SYNTHESIS
  wire [17:0] mult_out;
  MULT9X9 #(
      .AREG(1'b1), .BREG(1'b1), .OUT_REG(1'b0), .PIPE_REG(1'b0),
      .ASIGN_REG(1'b0), .BSIGN_REG(1'b0), .SOA_REG(1'b0),
      .MULT_RESET_MODE("ASYNC")
  ) u_mult (
      .A({a[7], a}), .B({b[7], b}),   // sign-extended to 9 bits
      .SIA(9'd0), .SIB(9'd0),
      .ASIGN(1'b1), .BSIGN(1'b1),
      .ASEL(1'b0), .BSEL(1'b0),       // use A/B, not the shift-chain inputs
      .CE(en), .CLK(clk), .RESET(!rst_n),
      .DOUT(mult_out),
      .SOA(), .SOB()
  );
  assign prod = mult_out[16:0];
`else
  // Same structure as the DSP configuration above: registered operands.
  reg signed [7:0] a_q, b_q;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a_q <= 8'sd0;
      b_q <= 8'sd0;
    end else if (en) begin
      a_q <= a;
      b_q <= b;
    end
  end
  wire signed [17:0] mult_out = a_q * b_q;
  assign prod = mult_out[16:0];
`endif

endmodule

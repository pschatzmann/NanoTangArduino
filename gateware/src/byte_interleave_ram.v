// Vendored unmodified from ../../../NanoTangAI/gateware/rtl/byte_interleave_ram.v,
// part of the AI accelerator integration - see docs/PERIPHERALS.md "AI accelerator".
// License: Apache-2.0 (see that project's library.properties/README;
// same author as this repo).
//
`timescale 1ns / 1ps
//
// Byte-serial-write, LANES-wide-parallel-read RAM.
//
// Used for both the shared activation-window buffer and each row's weight
// tile: bytes arrive one at a time over SPI (spi_slave.v's shift register),
// but dot_product_lane_array.v needs to read LANES of them at once every
// cycle. LANES (a power of two, default 16) separate byte-wide memories are
// interleaved by the low bits of the byte address, so consecutive bytes
// land in different lanes and a "word" (one read) is LANES *consecutive*
// bytes -- exactly the [tap][cin_padded] contiguous layout Ops.h already
// uses for wtile_i8/xtap (see that file's doc for why it's laid out
// contiguously in the first place: one dot product per tap is a
// cin_padded-long contiguous run).
//
// byte_addr = {word_addr, lane_sel} (lane_sel = LOG2LANES low bits).
// Read has 1 cycle of latency (registered), matching int8_mac_lane's own
// 1-cycle multiply latency so dot_product_engine.v's pipeline stays simple.
//
module byte_interleave_ram #(
    parameter integer LANES     = 16,
    parameter integer LOG2LANES = 4,      // must satisfy 2**LOG2LANES == LANES
    parameter integer WORDS     = 64,     // depth in LANES-byte words
    parameter integer WORD_AW   = 6       // ceil(log2(WORDS))
) (
    input  wire                      clk,
    // byte-serial write port
    input  wire                       wr_en,
    input  wire [WORD_AW+LOG2LANES-1:0] wr_byte_addr,
    input  wire [7:0]                   wr_data,
    // LANES-wide read port, 1 cycle latency
    input  wire [WORD_AW-1:0]           rd_word_addr,
    output wire signed [LANES*8-1:0]    rd_data
);

  wire [LOG2LANES-1:0] wr_lane = wr_byte_addr[LOG2LANES-1:0];
  wire [WORD_AW-1:0]   wr_word = wr_byte_addr[WORD_AW+LOG2LANES-1:LOG2LANES];

  genvar gi;
  generate
    for (gi = 0; gi < LANES; gi = gi + 1) begin : g_lane_mem
      reg [7:0] mem [0:WORDS-1];
      reg [7:0] rdata_r;

      always @(posedge clk) begin
        if (wr_en && (wr_lane == gi[LOG2LANES-1:0])) mem[wr_word] <= wr_data;
        rdata_r <= mem[rd_word_addr];
      end

      assign rd_data[gi*8 +: 8] = rdata_r;
    end
  endgenerate

endmodule

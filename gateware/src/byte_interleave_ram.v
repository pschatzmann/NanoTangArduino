// Vendored from ../../../NanoTangAI/gateware/rtl/byte_interleave_ram.v,
// part of the AI accelerator integration - see docs/PERIPHERALS.md "AI accelerator".
// License: Apache-2.0 (see that project's library.properties/README;
// same author as this repo). One deliberate deviation from the vendored
// original: the LANES byte-wide lane memories are a single LANES*8-bit
// wide single-port memory with per-byte writes instead of LANES separate
// arrays. Separate arrays are each far too small for a Gowin BSRAM
// block, so yosys put every one of them in LUT RAM - across the 9
// instances in dot_product_engine.v that needed ~1,150 RAM16SDP4 cells
// against the GW2AR-18's 648, the actual reason Tools > AI Accelerator
// failed place & route. One memory maps onto a single BSRAM block per
// instance instead (SPX9, byte-enabled, so LANES*8 must be <= 32).
// Single-port rather than dual-port because this yosys (0.33) emits the
// legacy SDP/SDPX9 primitives for simple-dual-port RAM, which
// nextpnr-himbaechel can't place (it only knows SDPB/SDPX9B) - and
// loading and computing never overlap, so one port is enough. Behavior is unchanged:
// byte-serial writes, a LANES-wide registered read with 1 cycle latency.
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

  // One LANES*8-bit wide memory with per-byte writes and a single
  // address shared by both directions (write address while wr_en, read
  // address otherwise) - a single-port RAM, see this file's header for
  // why. While a write is in progress rd_data is meaningless; the engine
  // only reads during compute, when nothing is being loaded.
  (* ram_style = "block" *)
  reg [LANES*8-1:0] mem [0:WORDS-1];
  reg [LANES*8-1:0] rdata_r;
  wire [WORD_AW-1:0] addr = wr_en ? wr_word : rd_word_addr;

  integer gi;
  always @(posedge clk) begin
    for (gi = 0; gi < LANES; gi = gi + 1)
      if (wr_en && (wr_lane == gi)) mem[addr][gi*8 +: 8] <= wr_data;
    rdata_r <= mem[addr];
  end

  assign rd_data = rdata_r;

endmodule

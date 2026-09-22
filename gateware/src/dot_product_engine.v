// Vendored from ../../../NanoTangAI/gateware/rtl/dot_product_engine.v,
// part of the AI accelerator integration - see docs/PERIPHERALS.md "AI accelerator".
// License: Apache-2.0 (see that project's library.properties/README;
// same author as this repo). One deliberate deviation from the vendored
// original: the result memory is split into one small memory per row
// (see `g_result` below). The original single `result_mem` was written by
// up to ROWS rows in the same cycle, from inside the async-reset FSM
// block - neither of which any Gowin RAM primitive supports - so yosys
// silently built it from ROWS*MAX_K*32 flip-flops plus a 128-way read
// mux, whatever ram_style attribute it carried. Per-row memories have one
// write port each and map onto LUT RAM. Results are unchanged.
// See also byte_interleave_ram.v's deviation, and ai_accel_bus.v for the
// LANES/WORDS values this core instantiates the engine with.
//
`timescale 1ns / 1ps
//
// Row-parallel, lane-parallel INT8 dot-product engine.
//
// Computes, for every resident weight-tile row (up to ROWS, matching
// TinyTTS's own kWeightTileRows=8, Ops.h:216) and every kernel tap (up to
// MAX_K, matching the decoder's largest real kernel size, 16 -- see
// Ops.h:193-201's doc), one INT8x INT8 -> INT32 dot product over
// cin_padded elements. Numerically identical to what
// TinyTTS/src/int8-dotprod/dsps_dp_s8_ansi.c computes per call
// (`dspsDotProdS8(xqrows[kk], wrow + kk*cin_padded, &dot, cin_padded)`,
// Ops.h:504/510) -- this engine just computes all ROWS*k of those calls
// with ROWS-way row parallelism and LANES-way lane parallelism instead of
// one scalar/SIMD call at a time on a CPU.
//
// Rescaling (dot * x_scale[ti] * w_rowScale(co), summed across taps, plus
// bias) is intentionally NOT done here -- it stays on the host exactly as
// in Ops.h, unchanged. This engine is a pure integer MAC array.
//
module dot_product_engine #(
    parameter integer ROWS      = 8,   // resident weight-tile rows, matches kWeightTileRows
    parameter integer LANES     = 16,  // parallel INT8 multiplies per row per cycle
    parameter integer LOG2LANES = 4,
    parameter integer MAX_K     = 16,  // largest kernel size this engine supports (decoder's real max)
    // Per-row/window depth in LANES-byte words: WORDS*LANES must be >=
    // kMaxRowSize=768 (TinyTTS's own verified worst-case cin*k across
    // every conv1d()/convTranspose1d() call in the shipped decoder, see
    // Ops.h's kMaxRowSize doc) -- 64*16=1024B clears that with headroom.
    // A (rows,k,cin_padded) combination whose product exceeds WORDS*LANES
    // silently wraps addresses (see gateware/tb/gen_vectors.py's own
    // note); this is a real capacity bound, not tunable without also
    // raising WORD_AW to match.
    parameter integer WORDS     = 64,
    parameter integer WORD_AW   = 6,
    parameter integer BYTE_AW   = WORD_AW + LOG2LANES
) (
    input  wire clk,
    input  wire rst_n,

    // --- configuration (latched on cfg_valid) ---
    input  wire        cfg_valid,
    input  wire [15:0] cfg_cin_padded,  // must be a multiple of LANES
    input  wire [7:0]  cfg_k,           // <= MAX_K
    input  wire [3:0]  cfg_rows,        // active rows this tile, <= ROWS

    // --- weight tile load (byte-serial, one row selected at a time) ---
    input  wire              wr_weight_en,
    input  wire [3:0]        wr_weight_row,
    input  wire [BYTE_AW-1:0] wr_weight_addr,
    input  wire [7:0]         wr_weight_data,

    // --- activation window load (byte-serial, shared across all rows) ---
    input  wire               wr_act_en,
    input  wire [BYTE_AW-1:0] wr_act_addr,
    input  wire [7:0]         wr_act_data,

    // --- control ---
    input  wire start,   // pulse: begin computing over the loaded window/tile
    output reg  busy,
    output reg  done,    // one-cycle pulse when all rows*k results are ready

    // --- result readout: index = row*MAX_K + tap ---
    input  wire [10:0]  result_rd_addr,
    output wire signed [31:0] result_rd_data
);

  // ---------------------------------------------------------------------
  // Latched config
  // ---------------------------------------------------------------------
  reg [15:0] cin_padded_r;
  reg [7:0]  k_r;
  reg [3:0]  rows_r;
  reg [WORD_AW-1:0] chunks_per_tap_r;  // cin_padded_r >> LOG2LANES

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cin_padded_r     <= 16'd0;
      k_r              <= 8'd0;
      rows_r           <= 4'd0;
      chunks_per_tap_r <= {WORD_AW{1'b0}};
    end else if (cfg_valid) begin
      cin_padded_r     <= cfg_cin_padded;
      k_r              <= cfg_k;
      rows_r           <= cfg_rows;
      chunks_per_tap_r <= cfg_cin_padded[WORD_AW+LOG2LANES-1:LOG2LANES];
    end
  end

  // ---------------------------------------------------------------------
  // Shared activation-window RAM + one weight-tile RAM per row
  // ---------------------------------------------------------------------
  wire signed [LANES*8-1:0] act_rd_data;
  wire [WORD_AW-1:0] word_addr;

  byte_interleave_ram #(.LANES(LANES), .LOG2LANES(LOG2LANES), .WORDS(WORDS), .WORD_AW(WORD_AW)) u_act_ram (
      .clk         (clk),
      .wr_en       (wr_act_en),
      .wr_byte_addr(wr_act_addr),
      .wr_data     (wr_act_data),
      .rd_word_addr(word_addr),
      .rd_data     (act_rd_data)
  );

  wire signed [LANES*8-1:0] weight_rd_data [0:ROWS-1];
  wire signed [31:0]        row_sum        [0:ROWS-1];

  genvar r;
  generate
    for (r = 0; r < ROWS; r = r + 1) begin : g_rows
      wire this_row_wr = wr_weight_en && (wr_weight_row == r[3:0]);

      byte_interleave_ram #(.LANES(LANES), .LOG2LANES(LOG2LANES), .WORDS(WORDS), .WORD_AW(WORD_AW)) u_wtile_ram (
          .clk         (clk),
          .wr_en       (this_row_wr),
          .wr_byte_addr(wr_weight_addr),
          .wr_data     (wr_weight_data),
          .rd_word_addr(word_addr),
          .rd_data     (weight_rd_data[r])
      );

      wire lane_en;  // driven by the FSM below
      dot_product_lane_array #(.LANES(LANES)) u_lane_array (
          .clk      (clk),
          .rst_n    (rst_n),
          .en       (lane_en),
          .a_vec    (act_rd_data),
          .b_vec    (weight_rd_data[r]),
          .sum      (row_sum[r]),
          .sum_valid()
      );
      assign lane_en = fsm_en;
    end
  endgenerate

  // ---------------------------------------------------------------------
  // Control FSM -- 3 cycles per chunk (ADDR -> LOAD -> MAC), see this
  // file's module doc for the pipeline-latency reasoning. Simplicity over
  // maximum throughput for this first, correctness-focused pass; revisit
  // once a synthesis report shows real Fmax headroom (see docs/architecture.md).
  // ---------------------------------------------------------------------
  localparam S_IDLE  = 3'd0,
             S_ADDR   = 3'd1,
             S_LOAD   = 3'd2,
             S_MAC    = 3'd3,
             S_STORE  = 3'd4,
             S_DONE   = 3'd5;

  reg [2:0] state;
  reg [7:0] tap;
  reg [WORD_AW-1:0] chunk;
  reg [WORD_AW-1:0] base_addr;   // tap * chunks_per_tap
  reg signed [31:0] acc [0:ROWS-1];

  assign word_addr = base_addr + chunk;
  // Combinational, NOT registered: must be high the SAME cycle a_vec/b_vec
  // (this state's RAM read output) are valid, so int8_mac_lane captures
  // the right product at this cycle's end -- a registered version would
  // add an extra cycle of delay and make dot_product_lane_array's `sum`
  // stale by one cycle relative to when S_MAC samples it.
  wire fsm_en = (state == S_LOAD);

  // result memory: ROWS*MAX_K entries, indexed [row*MAX_K + tap] -
  // one MAX_K-entry memory per row, see this file's header comment.
  // Assumes ROWS and MAX_K are powers of two (row = the index's upper bits).
  localparam integer LOG2K    = $clog2(MAX_K);
  localparam integer LOG2ROWS = $clog2(ROWS);
  wire signed [31:0] result_row_data [0:ROWS-1];

  generate
    for (r = 0; r < ROWS; r = r + 1) begin : g_result
      reg signed [31:0] mem [0:MAX_K-1];
      always @(posedge clk)
        if (state == S_STORE && r < rows_r)
          mem[tap[LOG2K-1:0]] <= acc[r];
      assign result_row_data[r] = mem[result_rd_addr[LOG2K-1:0]];
    end
  endgenerate

  assign result_rd_data = result_row_data[result_rd_addr[LOG2K +: LOG2ROWS]];

  integer ri;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= S_IDLE;
      tap       <= 8'd0;
      chunk     <= {WORD_AW{1'b0}};
      base_addr <= {WORD_AW{1'b0}};
      busy      <= 1'b0;
      done      <= 1'b0;
      for (ri = 0; ri < ROWS; ri = ri + 1) acc[ri] <= 32'sd0;
    end else begin
      done <= 1'b0;

      case (state)
        S_IDLE: begin
          busy <= 1'b0;
          if (start) begin
            busy      <= 1'b1;
            tap       <= 8'd0;
            chunk     <= {WORD_AW{1'b0}};
            base_addr <= {WORD_AW{1'b0}};
            for (ri = 0; ri < ROWS; ri = ri + 1) acc[ri] <= 32'sd0;
            state <= S_ADDR;
          end
        end

        S_ADDR: begin
          // word_addr = base_addr+chunk already combinationally correct
          state <= S_LOAD;
        end

        S_LOAD: begin
          // fsm_en (combinational, see its `wire` decl above) is already
          // high throughout this state -- int8_mac_lane captures the
          // product at the edge leaving this state, so `sum` is valid
          // next cycle (S_MAC).
          state <= S_MAC;
        end

        S_MAC: begin
          for (ri = 0; ri < ROWS; ri = ri + 1)
            if (ri < rows_r) acc[ri] <= acc[ri] + row_sum[ri];
          if (chunk == chunks_per_tap_r - 1'b1) begin
            state <= S_STORE;
          end else begin
            chunk <= chunk + 1'b1;
            state <= S_ADDR;
          end
        end

        S_STORE: begin
          // acc[] is written into g_result's per-row memories this cycle.
          if (tap == k_r - 1'b1) begin
            state <= S_DONE;
          end else begin
            tap       <= tap + 1'b1;
            chunk     <= {WORD_AW{1'b0}};
            base_addr <= base_addr + chunks_per_tap_r;
            for (ri = 0; ri < ROWS; ri = ri + 1) acc[ri] <= 32'sd0;
            state <= S_ADDR;
          end
        end

        S_DONE: begin
          busy  <= 1'b0;
          done  <= 1'b1;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule

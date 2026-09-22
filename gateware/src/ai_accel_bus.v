/* New for the Arduino core: bridges picorv32's memory bus directly to
 * NanoTangAI's dot_product_engine.v (vendored unmodified from
 * ../../../NanoTangAI/gateware/rtl/ - see docs/PERIPHERALS.md "AI accelerator" -
 * Apache-2.0), replacing that project's SPI-slave link entirely. Since
 * the engine and our CPU are on the same chip, every byte that used to
 * cross an SPI wire one bit at a time now moves in a single bus store -
 * the entire reason for doing this integration.
 *
 * Register interface (all offsets from the block base):
 *   0x00 CFG        (write) - {rows[27:24], k[23:16], cin_padded[15:0]},
 *                    pulses the engine's cfg_valid.
 *   0x04 WEIGHT_SEL (write) - bits[3:0] = row to load (0..ROWS-1); also
 *                    resets the weight byte-address counter for that row.
 *   0x08 WEIGHT_DATA(write) - bits[7:0] = next weight byte at the current
 *                    (auto-incrementing) address for the selected row.
 *   0x0C ACT_RESET  (write) - any value resets the activation-window
 *                    byte-address counter to 0.
 *   0x10 ACT_DATA   (write) - bits[7:0] = next activation byte at the
 *                    current (auto-incrementing) address.
 *   0x14 START      (write) - any value pulses the engine's `start` and
 *                    clears the "result ready" latch below.
 *   0x18 RESULT_ADDR(write) - sets the result index (row*MAX_K + tap).
 *   0x1C RESULT_DATA(read)  - blocks (bus backpressure, not a software
 *                    poll loop) until the engine's `done` fires after the
 *                    most recent START, then returns the signed INT32
 *                    result at RESULT_ADDR. Further reads after the first
 *                    return immediately, since "done" stays latched until
 *                    the next START.
 */

module ai_accel_bus
  (
   input wire         clk,
   input wire         reset_n,

   input wire         sel,
   input wire [4:0]   addr,
   input wire [3:0]   wstrb,
   input wire [31:0]  wdata,
   output wire        ready,
   output wire [31:0] rdata
   );

   localparam ROWS      = 8;
   // LANES/WORDS differ from the vendored engine's defaults (16/64): each
   // byte_interleave_ram instance must fit one 32-bit-wide Gowin BSRAM
   // block (see that file's header), so 4 lanes x 256 words - the same
   // 1024 bytes per row/window, so BYTE_AW and every register below are
   // unchanged. cin_padded only needs to be a multiple of 4 now (any
   // multiple of 16 still is), and MAC throughput per cycle is 4x lower,
   // negligible next to loading weights one bus write per byte.
   localparam LANES     = 4;
   localparam LOG2LANES = 2;
   localparam MAX_K     = 16;
   localparam WORDS     = 256;
   localparam WORD_AW   = 8;
   localparam BYTE_AW   = WORD_AW + LOG2LANES; // 10

   wire we = |wstrb;
   wire cfg_sel         = sel && (addr == 5'h00);
   wire weight_sel_sel  = sel && (addr == 5'h04);
   wire weight_data_sel = sel && (addr == 5'h08);
   wire act_reset_sel   = sel && (addr == 5'h0C);
   wire act_data_sel    = sel && (addr == 5'h10);
   wire start_sel       = sel && (addr == 5'h14);
   wire result_addr_sel = sel && (addr == 5'h18);
   wire result_data_sel = sel && (addr == 5'h1C);

   // ---- Weight/activation byte-address counters ----
   reg [3:0]        weight_row = 4'd0;
   reg [BYTE_AW-1:0] weight_addr = {BYTE_AW{1'b0}};
   reg [BYTE_AW-1:0] act_addr = {BYTE_AW{1'b0}};

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       weight_row  <= 4'd0;
       weight_addr <= {BYTE_AW{1'b0}};
       act_addr    <= {BYTE_AW{1'b0}};
     end else begin
       if (weight_sel_sel && we) begin
         weight_row  <= wdata[3:0];
         weight_addr <= {BYTE_AW{1'b0}};
       end else if (weight_data_sel && we) begin
         weight_addr <= weight_addr + 1'b1;
       end

       if (act_reset_sel && we)
         act_addr <= {BYTE_AW{1'b0}};
       else if (act_data_sel && we)
         act_addr <= act_addr + 1'b1;
     end

   // ---- Result-ready latch: cleared by START, set by the engine's `done` ----
   reg result_ready;
   wire engine_busy, engine_done;

   always @(posedge clk or negedge reset_n)
     if (!reset_n)
       result_ready <= 1'b0;
     else if (start_sel && we)
       result_ready <= 1'b0;
     else if (engine_done)
       result_ready <= 1'b1;

   reg [10:0] result_addr_r = 11'd0;
   always @(posedge clk or negedge reset_n)
     if (!reset_n)
       result_addr_r <= 11'd0;
     else if (result_addr_sel && we)
       result_addr_r <= wdata[10:0];

   wire [31:0] result_rd_data;

   assign ready = cfg_sel || weight_sel_sel || weight_data_sel ||
                  act_reset_sel || act_data_sel || start_sel ||
                  result_addr_sel || (result_data_sel && result_ready);
   assign rdata = result_data_sel ? result_rd_data : 32'h0;

   dot_product_engine
     #(
       .ROWS(ROWS), .LANES(LANES), .LOG2LANES(LOG2LANES), .MAX_K(MAX_K),
       .WORDS(WORDS), .WORD_AW(WORD_AW)
       )
   engine
     (
      .clk(clk),
      .rst_n(reset_n),

      .cfg_valid(cfg_sel && we),
      .cfg_cin_padded(wdata[15:0]),
      .cfg_k(wdata[23:16]),
      .cfg_rows(wdata[27:24]),

      .wr_weight_en(weight_data_sel && we),
      .wr_weight_row(weight_row),
      .wr_weight_addr(weight_addr),
      .wr_weight_data(wdata[7:0]),

      .wr_act_en(act_data_sel && we),
      .wr_act_addr(act_addr),
      .wr_act_data(wdata[7:0]),

      .start(start_sel && we),
      .busy(engine_busy),
      .done(engine_done),

      .result_rd_addr(result_addr_r),
      .result_rd_data(result_rd_data)
      );

endmodule // ai_accel_bus

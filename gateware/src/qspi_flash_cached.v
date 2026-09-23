/* Tools > Flash Cache: Enabled variant of qspi_flash.v (same ports, same
 * bus behavior - top.v instantiates one or the other). Costs ~1,700 LUT4s
 * in place & route, mostly tag/valid/mux logic, so it's opt-in.
 *
 * New for the Arduino core: a read-only SPI NOR flash reader, exposed as a
 * raw memory-mapped window (like gateware/src/sdram_bus.v's convention -
 * `addr` is a byte offset within the flash chip, not a register index).
 * Reads go through a small direct-mapped read cache (LINES lines of 32
 * bytes, in LUT RAM, with a valid bit per 32-bit word): a hit answers in
 * 2 clocks. A miss starts one "03h Read Data" SPI NOR transaction at the
 * requested word (command byte + 3 address bytes, CS held low) and keeps
 * streaming the following words up to the end of that 32-byte line,
 * answering as soon as the requested word has arrived. Later requests
 * for words that have arrived (or are cached elsewhere) are served
 * straight away while the stream continues; a miss anywhere else aborts
 * the stream (words already received stay valid) and starts its own.
 *
 * So a scattered single-word read costs the same one short transaction
 * as before, while sequential PROGMEM/FLASH_DATA reads and boot.S's
 * program copy pay one command/address overhead per line instead of per
 * word, and repeated reads of a small table cost almost nothing. The
 * uncached qspi_flash.v makes every 32-bit load its own 8-byte
 * transaction (~512 clocks at CLK_DIV=3). Flash is read-only through
 * this window, so the cache never needs invalidating except at reset (a
 * new upload reconfigures the FPGA).
 * invalidating except at reset (a new upload reconfigures the FPGA). The
 * bit-shifting engine below is adapted directly from spi_master.v's own
 * proven byte-transfer core (see that file), extended to chain 8 bytes
 * back-to-back automatically instead of stopping after one
 * externally-triggered byte - not re-derived bit timing from scratch.
 *
 * Serves two callers through the same bus interface (see top.v):
 *   - cores/tangnano20k/boot.S's fixed boot stub, copying the sketch's
 *     program from flash into SRAM at reset.
 *   - Sketch code reading FLASH_DATA-attributed `const` arrays directly by
 *     pointer/array dereference, blocking via this same bus backpressure
 *     like any other peripheral in this design.
 * See docs/PERIPHERALS.md "Flash".
 *
 * Not true QSPI (single data line only, matching spi_master.v's existing
 * complexity level) - "QSPI" in the module name matches the chip's own
 * capability, not what's implemented here.
 *
 * Received bytes are packed little-endian into rdata (the first byte read,
 * from the given address, becomes rdata[7:0]; the last becomes
 * rdata[31:24]) - matching this SoC's existing byte-addressing convention
 * (SRAM/SDRAM) so byte-level loads from a FLASH_DATA array give the
 * expected value regardless of which byte lane of a word they land in.
 */

module qspi_flash_cached
  #(
    parameter CLK_DIV = 3, // SCLK ~= clk/8 (~3.4MHz at this SoC's default 27MHz, scaling with the Tools > Clock Speed menu) - well under any SPI NOR flash's Read Data command's max clock; correctness over speed since this isn't on the instruction-fetch path.
    parameter LOG2_LINES = 4 // 16 lines x 32 bytes = 512 bytes of cache
    )
   (
    input wire         clk,
    input wire         reset_n,

    input wire         sel,
    input wire [23:0]  addr,     // byte address within the flash chip
    output reg         ready,
    output reg [31:0]  rdata,

    output wire        flash_sclk,
    output wire        flash_mosi,
    input wire         flash_miso,
    output reg         flash_cs_n
    );

   localparam LINES = 1 << LOG2_LINES;
   localparam TAG_W = 24 - 5 - LOG2_LINES; // above the line index and the 32-byte offset

   /* Address split: [4:2] word within the line, then the line index, then
    * the tag. picorv32 always issues word-aligned addresses. */
   wire [2:0]            req_word  = addr[4:2];
   wire [LOG2_LINES-1:0] req_index = addr[5 +: LOG2_LINES];
   wire [TAG_W-1:0]      req_tag   = addr[23 -: TAG_W];

   /* Cache storage: data in LUT RAM (written from its own un-reset
    * process so yosys can infer RAM); a tag and 8 per-word valid bits per
    * line in registers, one small block per line (g_line below) rather
    * than dynamically indexed arrays, which yosys turns into barrel
    * shifters several times the size of the cache itself. */
   (* ram_style = "distributed" *) // block RAM maps to SDPX9, which nextpnr can't place
   reg [31:0]            line_mem [0:LINES*8-1];
   wire [TAG_W-1:0]      line_tag   [0:LINES-1];
   wire [7:0]            line_valid [0:LINES-1];

   wire tag_match = (line_tag[req_index] == req_tag);
   wire hit = tag_match && line_valid[req_index][req_word];

   localparam ST_IDLE = 1'b0, ST_FILL = 1'b1;
   reg        state;
   reg [7:0]  tx_shift;
   reg [7:0]  rx_shift;
   reg [3:0]  bit_cnt;
   reg [1:0]  div_cnt;       // counts up to CLK_DIV (<= 3)
   reg        sclk_phase;
   reg [2:0]  hdr_idx;       // 0=cmd, 1..3=address bytes, 4=streaming data
   reg [23:0] fill_addr;     // byte address of the word currently arriving
   reg [1:0]  lane;          // byte within that word
   reg [23:0] captured;      // bytes 0..2 of the arriving word

   wire       tick = (div_cnt == CLK_DIV);
   wire       byte_end = (state == ST_FILL) && tick && sclk_phase && (bit_cnt == 4'd1);
   wire       word_done = byte_end && (hdr_idx == 3'd4) && (lane == 2'd3);
   wire [LOG2_LINES+2:0] fill_slot = fill_addr[2 +: LOG2_LINES+3]; // {index, word}

   /* Abort the stream for a miss outside it - only with SCLK low, between
    * bits, and never for a word the stream is about to deliver. */
   wire       req_in_stream = (addr[23:5] == fill_addr[23:5]) && (req_word >= fill_addr[4:2]);
   wire       abort = (state == ST_FILL) && sel && !ready && !hit && !req_in_stream && !sclk_phase;

   assign flash_sclk = (state == ST_FILL) && sclk_phase;
   assign flash_mosi = tx_shift[7];

   function [7:0] tx_byte_for(input [2:0] idx);
      case (idx)
        3'd0: tx_byte_for = 8'h03; // SPI NOR "Read Data" command
        3'd1: tx_byte_for = fill_addr[23:16];
        3'd2: tx_byte_for = fill_addr[15:8];
        3'd3: tx_byte_for = fill_addr[7:0];
        default: tx_byte_for = 8'h00; // dummy byte while clocking in data
      endcase
   endfunction

   always @(posedge clk)
     if (word_done)
       line_mem[fill_slot] <= {rx_shift, captured};

   /* Fill start (evicting a different line at this index) and word
    * arrival, decoded once here and applied per line below. */
   wire start_fill = (state == ST_IDLE) && sel && !ready && !hit;
   wire evict      = start_fill && !tag_match;

   genvar gl;
   generate
     for (gl = 0; gl < LINES; gl = gl + 1) begin : g_line
       reg [TAG_W-1:0] tag = {TAG_W{1'b0}};
       reg [7:0]       valid = 8'd0;
       always @(posedge clk)
         if (!reset_n) begin
           tag <= {TAG_W{1'b0}};
           valid <= 8'd0;
         end else if (evict && req_index == gl) begin
           tag <= req_tag;
           valid <= 8'd0;
         end else if (word_done && fill_slot[3 +: LOG2_LINES] == gl) begin
           valid[fill_slot[2:0]] <= 1'b1;
         end
       assign line_tag[gl] = tag;
       assign line_valid[gl] = valid;
     end
   endgenerate

   always @(posedge clk) begin
      ready <= 1'b0;

      if (!reset_n) begin
         state <= ST_IDLE;
         flash_cs_n <= 1'b1;
         div_cnt <= 2'd0;
         sclk_phase <= 1'b0;
      end else begin
         if (sel && !ready && hit) begin
            // Cached (including words the running stream already delivered).
            rdata <= line_mem[{req_index, req_word}];
            ready <= 1'b1;
         end

         if (state == ST_IDLE || abort) begin
            flash_cs_n <= 1'b1;
            state <= ST_IDLE;
            if (start_fill) begin
               // Start streaming at the requested word (g_line evicts a
               // different line at this index: new tag, all words invalid).
               fill_addr <= {addr[23:2], 2'b00};
               hdr_idx <= 3'd0;
               lane <= 2'd0;
               flash_cs_n <= 1'b0;
               tx_shift <= 8'h03;
               bit_cnt <= 4'd8;
               div_cnt <= 2'd0;
               sclk_phase <= 1'b0;
               state <= ST_FILL;
            end
         end else if (tick) begin // ST_FILL, streaming
            div_cnt <= 2'd0;
            sclk_phase <= !sclk_phase;

            /* sclk_phase: 0 = clock low half, 1 = clock high half - same
             * convention as spi_master.v: MOSI/tx_shift change while sclk
             * is low (setup), MISO is sampled while sclk is high (mode 0). */
            if (!sclk_phase) begin
               rx_shift <= {rx_shift[6:0], flash_miso};
            end else begin
               tx_shift <= {tx_shift[6:0], 1'b0};
               if (bit_cnt == 4'd1) begin
                  /* Last bit of this byte: rx_shift already holds all 8
                   * bits (sampled on each rising edge above). Earlier
                   * revisions stored {rx_shift[6:0], flash_miso} here,
                   * sampling MISO a 9th time - dropping bit 7 and
                   * duplicating bit 0 of every byte read. Data bytes are
                   * packed little-endian: the first byte of each word
                   * becomes bits [7:0] (see this file's header). */
                  bit_cnt <= 4'd8;
                  if (hdr_idx != 3'd4) begin
                     hdr_idx <= hdr_idx + 3'd1;
                     tx_shift <= tx_byte_for(hdr_idx + 3'd1);
                  end else begin
                     tx_shift <= 8'h00;
                     case (lane)
                       2'd0: captured[7:0]   <= rx_shift;
                       2'd1: captured[15:8]  <= rx_shift;
                       2'd2: captured[23:16] <= rx_shift;
                       default: begin
                          // Word complete (written to line_mem and
                          // marked valid in g_line above).
                          if (fill_addr[4:2] == 3'd7) begin
                             flash_cs_n <= 1'b1; // end of line
                             state <= ST_IDLE;
                          end
                          fill_addr <= fill_addr + 24'd4;
                       end
                     endcase
                     lane <= lane + 2'd1;
                  end
               end else begin
                  bit_cnt <= bit_cnt - 4'd1;
               end
            end
         end else begin
            div_cnt <= div_cnt + 2'd1;
         end
      end
   end
endmodule

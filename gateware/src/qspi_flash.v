/* New for the Arduino core: a read-only SPI NOR flash reader, exposed as a
 * raw memory-mapped window (like gateware/src/sdram_bus.v's convention -
 * `addr` is a byte offset within the flash chip, not a register index).
 * One 32-bit word read = one "03h Read Data" SPI NOR transaction (command
 * byte + 3 address bytes + 4 data bytes, CS held low throughout). The
 * bit-shifting engine below is adapted directly from spi_master.v's own
 * proven byte-transfer core (see that file), extended to chain 8 bytes
 * back-to-back automatically instead of stopping after one
 * externally-triggered byte - not re-derived bit timing from scratch.
 *
 * This is the default, uncached reader; Tools > Flash Cache: Enabled
 * swaps in qspi_flash_cached.v instead (same ports and bus behavior,
 * plus a 512-byte read cache that costs ~1,700 LUTs) - see top.v.
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

module qspi_flash
  #(
    parameter CLK_DIV = 3 // SCLK ~= clk/8 (~3.4MHz at this SoC's default 27MHz, scaling with the Tools > Clock Speed menu) - well under any SPI NOR flash's Read Data command's max clock; correctness over speed since this isn't on the instruction-fetch path.
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

   localparam ST_IDLE = 1'b0, ST_XFER = 1'b1;
   reg        state;
   reg        busy;
   reg [7:0]  tx_shift;
   reg [7:0]  rx_shift;
   reg [3:0]  bit_cnt;
   reg [31:0] div_cnt;
   reg        sclk_phase;
   reg [3:0]  byte_idx;      // 0=cmd, 1..3=address bytes, 4..7=data bytes
   reg [23:0] latched_addr;
   reg [31:0] captured;
   reg        present;       // one cycle delay so captured's last byte settles before rdata/ready

   wire       tick = (div_cnt == CLK_DIV);

   assign flash_sclk = busy && sclk_phase;
   assign flash_mosi = tx_shift[7];

   function [7:0] tx_byte_for(input [3:0] idx);
      case (idx)
        4'd0: tx_byte_for = 8'h03; // SPI NOR "Read Data" command
        4'd1: tx_byte_for = latched_addr[23:16];
        4'd2: tx_byte_for = latched_addr[15:8];
        4'd3: tx_byte_for = latched_addr[7:0];
        default: tx_byte_for = 8'h00; // dummy byte while clocking in data
      endcase
   endfunction

   always @(posedge clk) begin
      ready <= 1'b0;
      present <= 1'b0;

      if (!reset_n) begin
         state <= ST_IDLE;
         busy <= 1'b0;
         flash_cs_n <= 1'b1;
         div_cnt <= 32'd0;
         sclk_phase <= 1'b0;
      end else if (present) begin
         rdata <= captured;
         ready <= 1'b1;
      end else if (state == ST_IDLE) begin
         flash_cs_n <= 1'b1;
         if (sel && !ready) begin
            latched_addr <= addr;
            byte_idx <= 4'd0;
            flash_cs_n <= 1'b0;
            tx_shift <= 8'h03;
            bit_cnt <= 4'd8;
            div_cnt <= 32'd0;
            sclk_phase <= 1'b0;
            busy <= 1'b1;
            state <= ST_XFER;
         end
      end else if (busy) begin
         if (tick) begin
            div_cnt <= 32'd0;
            sclk_phase <= !sclk_phase;

            /* sclk_phase: 0 = clock low half, 1 = clock high half - same
             * convention as spi_master.v: MOSI/tx_shift change while sclk
             * is low (setup), MISO is sampled while sclk is high (mode 0). */
            if (!sclk_phase) begin
               rx_shift <= {rx_shift[6:0], flash_miso};
            end else begin
               tx_shift <= {tx_shift[6:0], 1'b0};
               if (bit_cnt == 4'd1) begin
                  // Last bit of this byte.
                  /* rx_shift already holds all 8 bits of this byte
                   * (sampled on each rising edge above). Earlier revisions
                   * stored {rx_shift[6:0], flash_miso} here, sampling MISO
                   * a 9th time - dropping bit 7 and duplicating bit 0 of
                   * every byte read. */
                  if (byte_idx >= 4'd4) begin
                     case (byte_idx)
                       4'd4: captured[7:0]   <= rx_shift;
                       4'd5: captured[15:8]  <= rx_shift;
                       4'd6: captured[23:16] <= rx_shift;
                       4'd7: captured[31:24] <= rx_shift;
                     endcase
                  end

                  if (byte_idx == 4'd7) begin
                     busy <= 1'b0;
                     flash_cs_n <= 1'b1;
                     state <= ST_IDLE;
                     present <= 1'b1;
                  end else begin
                     byte_idx <= byte_idx + 4'd1;
                     bit_cnt <= 4'd8;
                     tx_shift <= tx_byte_for(byte_idx + 4'd1);
                  end
               end else begin
                  bit_cnt <= bit_cnt - 4'd1;
               end
            end
         end else begin
            div_cnt <= div_cnt + 32'd1;
         end
      end
   end
endmodule

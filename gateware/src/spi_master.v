/* New for the Arduino core: a simple SPI master, SPI modes 0-3, MSB or
 * LSB first. Reuses the microSD card slot's bus pins in SPI-mode wiring
 * (CLK/CMD=MOSI/DAT0=MISO/DAT3=CS) - see docs/PERIPHERALS.md, this is mutually
 * exclusive with using the onboard microSD slot.
 *
 * Register interface:
 *   div_sel (offset 0x0, write) - SCLK divisor, same convention as
 *            uart_wrap/i2s: sclk toggles every (div+1) clk cycles.
 *   cs_sel  (offset 0x4, write) - bit0: 1 asserts CS (drives it low),
 *            0 releases it (high). Software controls CS explicitly around
 *            a multi-byte transfer, same as the Arduino SPI convention.
 *   dat_sel (offset 0x8, read/write) - write a byte to transfer (blocks,
 *            via bus backpressure, until the previous transfer finishes);
 *            read returns the byte most recently received.
 *   cfg_sel (offset 0xc, write) - bit0: CPHA, bit1: CPOL, bit2: LSB
 *            first. Reset value 0 = SPI mode 0, MSB first.
 */

module spi_master
  (
   input wire         clk,
   input wire         reset_n,

   input wire         spi_sel,
   input wire [3:0]   addr,
   input wire [3:0]   wstrb,
   input wire [31:0]  wdata,
   output wire        spi_ready,
   output wire [31:0] spi_rdata,

   output wire        spi_sclk,
   output wire        spi_mosi,
   input wire         spi_miso,
   output wire        spi_cs_n
   );

   wire               div_sel = spi_sel && (addr == 4'h0);
   wire               cs_sel  = spi_sel && (addr == 4'h4);
   wire               dat_sel = spi_sel && (addr == 4'h8);
   wire               cfg_sel = spi_sel && (addr == 4'hc);
   wire               we      = |wstrb;

   reg [31:0]         divider = 32'd0;
   reg                cs_assert = 1'b0;
   reg                cpha = 1'b0;
   reg                cpol = 1'b0;
   reg                lsb_first = 1'b0;
   assign spi_cs_n = !cs_assert;

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       divider <= 32'd0;
       cs_assert <= 1'b0;
       cpha <= 1'b0;
       cpol <= 1'b0;
       lsb_first <= 1'b0;
     end else begin
       if (div_sel && we)
         divider <= wdata;
       if (cs_sel && we)
         cs_assert <= wdata[0];
       if (cfg_sel && we) begin
         cpha <= wdata[0];
         cpol <= wdata[1];
         lsb_first <= wdata[2];
       end
     end

   /* Transfer state: bit_cnt/tx_shift/rx_shift/rx_data/busy/div_cnt/
    * sclk_phase are all driven from a single always block below - each
    * had a second driver in an earlier revision (a real multi-driver bug
    * caught by yosys's synth_gowin CHECK pass, not just a lint nag). */
   reg                busy = 1'b0;
   reg [7:0]          tx_shift = 8'd0;
   reg [7:0]          rx_shift = 8'd0;
   reg [7:0]          rx_data = 8'd0;
   reg [3:0]          bit_cnt = 4'd0;
   reg [31:0]         div_cnt = 32'd0;
   reg                sclk_phase = 1'b0;

   wire               tick = (div_cnt == divider);
   wire               start = dat_sel && we && !busy;

   assign spi_ready = div_sel || cs_sel || cfg_sel || (dat_sel && !busy);
   assign spi_rdata = {24'b0, rx_data};
   assign spi_mosi = lsb_first ? tx_shift[0] : tx_shift[7];

   /* sclk_phase 0/1 = first/second half of a bit. MISO is always sampled
    * at the 0->1 transition and the next bit shifted out at the 1->0 one.
    * CPHA picks which of those is the clock's leading edge (with CPHA=1
    * the clock is already active during the first half, so its leading
    * edge is the bit start); CPOL inverts the whole clock, idle included. */
   assign spi_sclk = cpol ^ (busy && (sclk_phase ^ cpha));

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       busy <= 1'b0;
       tx_shift <= 8'd0;
       rx_shift <= 8'd0;
       rx_data <= 8'd0;
       bit_cnt <= 4'd0;
       div_cnt <= 32'd0;
       sclk_phase <= 1'b0;
     end else if (start) begin
       busy <= 1'b1;
       tx_shift <= wdata[7:0];
       bit_cnt <= 4'd8;
       div_cnt <= 32'd0;
       sclk_phase <= 1'b0;
     end else if (busy) begin
       if (tick) begin
         div_cnt <= 32'd0;
         sclk_phase <= !sclk_phase;

         /* The byte is complete in rx_shift once its last bit has been
          * sampled. (An earlier revision sampled MISO once more at the
          * very end, duplicating the last bit and dropping the first -
          * every received byte came back shifted left by one.) */
         if (!sclk_phase) begin
           rx_shift <= lsb_first ? {spi_miso, rx_shift[7:1]} : {rx_shift[6:0], spi_miso};
         end else begin
           tx_shift <= lsb_first ? {1'b0, tx_shift[7:1]} : {tx_shift[6:0], 1'b0};
           if (bit_cnt == 4'd1) begin
             rx_data <= rx_shift;
             busy <= 1'b0;
           end
           bit_cnt <= bit_cnt - 4'd1;
         end
       end else begin
         div_cnt <= div_cnt + 32'd1;
       end
     end

endmodule // spi_master

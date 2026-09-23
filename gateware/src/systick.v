/* New for the Arduino core: free-running, read-only 32-bit up-counters
 * backing millis()/micros():
 *
 *   offset 0x0 - CYCLES: +1 per clock cycle (wraps every 2^32 cycles)
 *   offset 0x4 - MICROS: +1 per microsecond (wraps every 2^32 us, ~71 min)
 *   offset 0x8 - MILLIS: +1 per millisecond (wraps every 2^32 ms, ~49 days)
 *
 * MICROS/MILLIS wrap at the full 2^32 like on any other Arduino board, so
 * the usual `millis() - last >= interval` idiom stays correct across the
 * wrap - dividing CYCLES in software can't give that (the quotient wraps
 * at 2^32/cycles-per-unit instead), and would also cost a software
 * division per call on RV32I. The microsecond tick is a fractional
 * accumulator (+1_000_000 per clock, tick on reaching CLK_FREQ), so it is
 * exact for clocks that aren't a whole number of MHz (13.5MHz Low Power).
 * The reference SoC only had a one-shot countdown timer, which can't back
 * a continuously-running Arduino clock.
 */
module systick
  #(
    parameter CLK_FREQ = 27000000
    )
  (
   input wire         clk,
   input wire         reset_n,
   input wire         systick_sel,
   input wire [3:0]   addr,
   output wire        systick_ready,
   output wire [31:0] systick_data_o
   );

   reg [31:0]         cycles = 32'b0;
   reg [31:0]         micros = 32'b0;
   reg [31:0]         millis = 32'b0;
   reg [31:0]         us_acc = 32'b0; // fractional microsecond accumulator
   reg [9:0]          ms_div = 10'b0; // microseconds into the current millisecond

   wire               us_tick = (us_acc + 32'd1000000) >= CLK_FREQ;

   assign systick_data_o = (addr == 4'h4) ? micros :
                           (addr == 4'h8) ? millis : cycles;
   assign systick_ready = systick_sel;

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       cycles <= 32'b0;
       micros <= 32'b0;
       millis <= 32'b0;
       us_acc <= 32'b0;
       ms_div <= 10'b0;
     end else begin
       cycles <= cycles + 32'b1;
       if (us_tick) begin
         us_acc <= us_acc + 32'd1000000 - CLK_FREQ;
         micros <= micros + 32'b1;
         if (ms_div == 10'd999) begin
           ms_div <= 10'b0;
           millis <= millis + 32'b1;
         end else begin
           ms_div <= ms_div + 10'b1;
         end
       end else begin
         us_acc <= us_acc + 32'd1000000;
       end
     end
endmodule

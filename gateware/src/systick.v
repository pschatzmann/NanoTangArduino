/* New for the Arduino core: a free-running 32-bit up-counter, read-only,
 * incrementing once per clock cycle. Software divides by CLK_FREQ to derive
 * millis()/micros(). The reference SoC only had a one-shot countdown timer,
 * which can't back a continuously-running Arduino clock.
 */

module systick
  (
   input wire         clk,
   input wire         reset_n,
   input wire         systick_sel,
   output wire        systick_ready,
   output wire [31:0] systick_data_o
   );

   reg [31:0]         counter = 32'b0;

   assign systick_data_o = counter;
   assign systick_ready = systick_sel;

   always @(posedge clk or negedge reset_n)
     if (!reset_n)
       counter <= 32'b0;
     else
       counter <= counter + 32'b1;

endmodule

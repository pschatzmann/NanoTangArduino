/* Adapted from grughuhler/picorv32_tang_nano_20k (BSD-2-Clause), same module
 * renamed from tang_nano_9k_leds.v -> tang_leds.v for the 20K core.
 *
 * tang_leds is a toy peripheral that lets software write to a register
 * that drives the 6 onboard LEDs.  It can also read the register back.
 */

module tang_leds
  (
   input wire         clk,
   input wire         reset_n,
   input wire         leds_sel,
   input wire [5:0]   leds_data_i,
   input wire         we,
   output wire        leds_ready,
   output wire [31:0] leds_data_o
   );

   reg [5:0]          leds = 'b0;

   assign leds_data_o = {26'b0, leds};
   assign leds_ready = leds_sel;

   always @(posedge clk or negedge reset_n)
     if (!reset_n)
       leds <= 'b0;
     else if (leds_sel)
       if (we) leds <= leds_data_i;

endmodule // tang_leds

/* Adapted from grughuhler/picorv32_tang_nano_20k (BSD-2-Clause), same module
 * renamed from tang_nano_9k_leds.v -> tang_leds.v for the 20K core.
 *
 * tang_leds is a toy peripheral that lets software write to a register
 * that drives the 6 onboard LEDs.  It can also read the register back.
 *
 * Extended for the Arduino core with single-write bit operations, so an
 * interrupt handler (e.g. tone()) can't clobber a concurrent
 * read-modify-write from loop(): offset 0x00 = value, 0x10 = SET,
 * 0x14 = CLR, 0x18 = TOGGLE (1 bits act, 0 bits untouched). Every offset
 * reads back the current value.
 */

module tang_leds
  (
   input wire         clk,
   input wire         reset_n,
   input wire         leds_sel,
   input wire [4:0]   addr,
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
     else if (leds_sel && we)
       case (addr)
         5'h10:   leds <= leds | leds_data_i;
         5'h14:   leds <= leds & ~leds_data_i;
         5'h18:   leds <= leds ^ leds_data_i;
         default: leds <= leds_data_i;
       endcase

endmodule // tang_leds

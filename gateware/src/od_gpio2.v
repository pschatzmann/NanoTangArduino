/* New for the Arduino core: a 2-line open-drain GPIO peripheral, used to
 * bit-bang I2C (Wire) in software over SDA/SCL. Each line is tri-stated
 * (released high via the pin's internal pull-up, set PULL_MODE=UP in the
 * .cst) when its drive bit is 0, and driven low when its drive bit is 1 -
 * a plain register can't pull a shared bus high, only release it, which is
 * exactly what I2C needs.
 *
 * Register (single address): write bit0/bit1 = drive SDA/SCL low (1) or
 * release them (0). Read returns the actual pin levels in bit0/bit1, which
 * is how software both reads a bit sent by a slave and does clock
 * stretching (poll SCL until it reads back high).
 */

module od_gpio2
  (
   input wire         clk,
   input wire         reset_n,

   input wire         sel,
   input wire [3:0]   wstrb,
   input wire [31:0]  wdata,
   output wire        ready,
   output wire [31:0] rdata,

   inout wire         sda,
   inout wire         scl
   );

   wire               we = |wstrb;
   reg                sda_drive = 1'b0;
   reg                scl_drive = 1'b0;

   assign ready = sel;
   assign sda = sda_drive ? 1'b0 : 1'bz;
   assign scl = scl_drive ? 1'b0 : 1'bz;
   assign rdata = {30'b0, scl, sda};

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       sda_drive <= 1'b0;
       scl_drive <= 1'b0;
     end else if (sel && we) begin
       sda_drive <= wdata[0];
       scl_drive <= wdata[1];
     end

endmodule // od_gpio2

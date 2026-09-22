/* New for the Arduino core: 8-bit PWM on each of the 6 onboard LEDs, for
 * analogWrite(). One shared free-running 8-bit counter; each channel
 * compares its own duty register against the counter.
 *
 * Register interface: one 32-bit register per channel at
 * base + 4*channel (channel 0..5). Bit 8 = enable (PWM drives the LED);
 * when disabled, tang_leds.v's plain digital value is used instead (see
 * top.v's per-bit mux) - this mirrors analogWrite()/digitalWrite()
 * switching a pin between PWM and plain digital modes on a real Arduino.
 * Bits [7:0] = duty cycle (0-255).
 */

module pwm6
  (
   input wire         clk,
   input wire         reset_n,

   input wire         pwm_sel,
   input wire [4:0]   addr,
   input wire [3:0]   wstrb,
   input wire [31:0]  wdata,
   output wire        pwm_ready,

   output wire [5:0]  pwm_out,
   output wire [5:0]  pwm_enabled
   );

   wire               we = |wstrb;
   wire [2:0]         channel = addr[4:2];
   wire               channel_valid = (channel < 3'd6);

   assign pwm_ready = pwm_sel;

   reg [7:0]          duty [0:5];
   reg [5:0]          enabled = 6'b0;

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       enabled <= 6'b0;
     end else if (pwm_sel && we && channel_valid) begin
       duty[channel] <= wdata[7:0];
       enabled[channel] <= wdata[8];
     end

   reg [7:0]          counter = 8'd0;
   always @(posedge clk or negedge reset_n)
     if (!reset_n)
       counter <= 8'd0;
     else
       counter <= counter + 8'd1;

   assign pwm_enabled = enabled;

   genvar i;
   generate
     for (i = 0; i < 6; i = i + 1) begin : ch
       assign pwm_out[i] = (counter < duty[i]);
     end
   endgenerate

endmodule // pwm6

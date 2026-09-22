/* New for the Arduino core: PWM for analogWrite()/analogWriteFrequency().
 *
 * A pool of CHANNELS PWM channels, each routable to any one PWM-capable
 * pin: target 0..LED_WIDTH-1 is an onboard LED, target LED_WIDTH.. is
 * expansion-header GPIO (target - LED_WIDTH). Software assigns a free
 * channel on the first analogWrite() to a pin and releases it on
 * pinMode()/digitalWrite() (see cores/tangnano20k/wiring_analog.cpp), so
 * LEDs and GPIO pins are treated alike and at most CHANNELS pins are in
 * PWM mode at once. Every channel has its own counter, period and
 * prescaler, so each pin's frequency is independent: frequency =
 * CLK_FREQ / ((prescale+1) * (period+1)).
 *
 * While an enabled channel targets a pin, it overrides that pin: an LED
 * shows the PWM output instead of tang_leds.v's plain digital value (see
 * top.v's per-bit mux), a GPIO pin becomes an output driven by PWM (see
 * gpio_bank.v's override inputs). Disabling the channel hands the pin
 * back to its plain digital register, untouched.
 *
 * Register interface: two 32-bit registers per channel at
 * base + 8*channel (channel 0..CHANNELS-1):
 *   DUTY (offset 0x0, write) - bits[16:0]: compare value; the output is
 *        high while the counter is below it, so 0 = always low and
 *        period+1 = always high. bit31: enable. A new compare value takes
 *        effect at the next period boundary, so a change never produces a
 *        truncated pulse.
 *   CFG  (offset 0x4, write) - bits[15:0]: period (counter runs
 *        0..period); bits[23:16]: prescale (counter advances every
 *        prescale+1 clocks); bits[28:24]: target pin (see above). Reset
 *        value: period 255, prescale 0 - the fixed CLK_FREQ/256 carrier
 *        this peripheral's 8-bit, LED-only predecessor (pwm6.v) always
 *        ran at.
 */

module pwm_bank
  #(
    parameter CHANNELS = 6,
    parameter LED_WIDTH = 6,
    parameter GPIO_WIDTH = 21
    )
  (
   input wire                    clk,
   input wire                    reset_n,

   input wire                    pwm_sel,
   input wire [6:0]              addr,
   input wire [3:0]              wstrb,
   input wire [31:0]             wdata,
   output wire                   pwm_ready,

   output wire [LED_WIDTH-1:0]   led_override,
   output wire [LED_WIDTH-1:0]   led_value,

   output wire [GPIO_WIDTH-1:0]  gpio_override,
   output wire [GPIO_WIDTH-1:0]  gpio_value
   );

   localparam TARGETS = LED_WIDTH + GPIO_WIDTH;

   wire               we = |wstrb;
   wire [3:0]         channel = addr[6:3];
   wire               duty_we = pwm_sel && we && !addr[2];
   wire               cfg_we  = pwm_sel && we && addr[2];

   assign pwm_ready = pwm_sel;

   wire [CHANNELS-1:0] ch_out;
   wire [CHANNELS-1:0] ch_enabled;
   wire [5*CHANNELS-1:0] ch_pin; // 5 bits per channel, flattened

   genvar c;
   generate
     for (c = 0; c < CHANNELS; c = c + 1) begin : ch
       reg [16:0] duty = 17'd0;
       reg [16:0] duty_active = 17'd0;
       reg        enabled = 1'b0;
       reg [15:0] period = 16'd255;
       reg [7:0]  prescale = 8'd0;
       reg [4:0]  pin = 5'd0;
       reg [7:0]  pre_cnt = 8'd0;
       reg [15:0] cnt = 16'd0;

       wire       tick = (pre_cnt == prescale);
       wire       wrap = tick && (cnt >= period);

       always @(posedge clk or negedge reset_n)
         if (!reset_n) begin
           duty <= 17'd0;
           duty_active <= 17'd0;
           enabled <= 1'b0;
           period <= 16'd255;
           prescale <= 8'd0;
           pin <= 5'd0;
           pre_cnt <= 8'd0;
           cnt <= 16'd0;
         end else begin
           if (duty_we && channel == c) begin
             duty <= wdata[16:0];
             enabled <= wdata[31];
           end
           if (cfg_we && channel == c) begin
             period <= wdata[15:0];
             prescale <= wdata[23:16];
             pin <= wdata[28:24];
           end

           pre_cnt <= tick ? 8'd0 : pre_cnt + 8'd1;
           if (wrap) begin
             cnt <= 16'd0;
             duty_active <= duty;
           end else if (tick) begin
             cnt <= cnt + 16'd1;
           end
         end

       assign ch_out[c] = ({1'b0, cnt} < duty_active);
       assign ch_enabled[c] = enabled;
       assign ch_pin[5*c +: 5] = pin;
     end
   endgenerate

   /* Routing: each enabled channel claims the target its CFG names.
    * Software never assigns two channels to one target; if it did, their
    * outputs would simply be OR-ed. */
   wire [TARGETS-1:0] override;
   wire [TARGETS-1:0] value;

   genvar t;
   generate
     for (t = 0; t < TARGETS; t = t + 1) begin : route
       wire [CHANNELS-1:0] hit;
       genvar g;
       for (g = 0; g < CHANNELS; g = g + 1) begin : pool
         assign hit[g] = ch_enabled[g] && (ch_pin[5*g +: 5] == t);
       end
       assign override[t] = |hit;
       assign value[t] = |(hit & ch_out);
     end
   endgenerate

   assign led_override  = override[LED_WIDTH-1:0];
   assign led_value     = value[LED_WIDTH-1:0];
   assign gpio_override = override[TARGETS-1:LED_WIDTH];
   assign gpio_value    = value[TARGETS-1:LED_WIDTH];

endmodule // pwm_bank

/* New for the Arduino core: stereo PWM audio output on two GPIO pins
 * (Tools > PWM Audio, disabled by default - see docs/PERIPHERALS.md
 * "Audio (PWM)"). Each output is a plain PWM carrier whose duty cycle
 * follows the audio sample; an external RC low-pass filter (or just a
 * small speaker/headphone's own inductance) recovers the audio.
 *
 * Unlike pwm_bank.v (analogWrite()'s per-pin PWM), the sample rate is
 * programmable as well as the carrier frequency, and samples are paced by hardware from a FIFO_DEPTH-deep queue, the
 * same way i2s.v paces its transmit path - software only has to keep
 * the FIFO topped up, not hit each sample period exactly.
 *
 * Samples are written as signed 16-bit PCM, exactly like i2s.v's
 * dat_sel. The scaling onto the PWM period (duty = unsigned(sample) *
 * (period+1) / 65536) happens here, in a small 16-cycle shift-add
 * multiplier started once per sample, so software never has to do a
 * multiply per sample (picorv32 has no hardware multiplier unless Tools >
 * Hardware Multiply/Divide is enabled). A new duty value only takes
 * effect at the start of the next PWM period, so a sample change never
 * produces a truncated/glitched pulse.
 *
 * Register interface (offsets relative to the peripheral's base address):
 *   period_sel (offset 0x0, write) - PWM period in system clock cycles,
 *              minus 1 (bits [15:0]). Carrier frequency is CLK_FREQ /
 *              (period+1); resolution is log2(period+1) bits. Writing it
 *              also resets both outputs to 50% duty (silence).
 *   div_sel    (offset 0x4, write) - sample period in system clock
 *              cycles, minus 1 (bits [23:0]). Sample rate is CLK_FREQ /
 *              (div+1).
 *   dat_sel    (offset 0x8, write) - {left[15:0], right[15:0]}, signed.
 *              Pushes onto the transmit FIFO; a write is only accepted
 *              (pwm_audio_ready asserted) while that FIFO has room, so
 *              the bus stalls the CPU once it's FIFO_DEPTH samples ahead
 *              - same backpressure as i2s.v. If the FIFO runs dry, the
 *              last duty cycle simply keeps repeating.
 *   ctrl_sel   (offset 0xC, write) - bit0: enable outputs (low while
 *              disabled). bit1: raise pwm_audio_irq_out while the FIFO
 *              is at most half full (level-triggered, like i2s.v's, but
 *              with a half-full low-water mark rather than "any room",
 *              so an ISR refills in bursts of FIFO_DEPTH/2 or more
 *              instead of once per sample). bit2: flush the FIFO (write
 *              only, self-clearing).
 *              (offset 0xC, read) - bits[4:0]: free FIFO slots
 *              (0-FIFO_DEPTH); bit8: enable; bit9: IRQ enable; bit31:
 *              always 1, so software can tell this peripheral was
 *              actually synthesized (top.v's stand-in when Tools > PWM
 *              Audio is disabled reads back all zeros).
 */

module pwm_audio
  (
   input wire         clk,
   input wire         reset_n,

   input wire         pwm_audio_sel,
   input wire [3:0]   addr,
   input wire [3:0]   wstrb,
   input wire [31:0]  wdata,
   output wire        pwm_audio_ready,
   output wire [31:0] pwm_audio_rdata,
   output wire        pwm_audio_irq_out,

   output wire        pwm_left,
   output wire        pwm_right
   );

   localparam FIFO_DEPTH = 16;

   wire               period_sel = pwm_audio_sel && (addr == 4'h0);
   wire               div_sel    = pwm_audio_sel && (addr == 4'h4);
   wire               dat_sel    = pwm_audio_sel && (addr == 4'h8);
   wire               ctrl_sel   = pwm_audio_sel && (addr == 4'hC);
   wire               we         = |wstrb;

   reg [15:0]         period = 16'd539;    // 50kHz at 27MHz
   reg [23:0]         sample_div = 24'd611; // ~44.1kHz at 27MHz
   reg                enable = 1'b0;
   reg                irq_enable = 1'b0;

   /* Transmit FIFO - small enough (and only present when Tools > PWM
    * Audio is enabled) that LUT RAM is fine here, unlike i2s.v's
    * always-instantiated FIFOs. */
   reg [31:0]         fifo_mem [0:FIFO_DEPTH-1];
   reg [3:0]          fifo_wptr = 4'd0;
   reg [3:0]          fifo_rptr = 4'd0;
   reg [4:0]          fifo_count = 5'd0;
   wire               fifo_full  = (fifo_count == FIFO_DEPTH[4:0]);
   wire               fifo_empty = (fifo_count == 5'd0);
   wire [4:0]         fifo_free  = FIFO_DEPTH[4:0] - fifo_count;
   wire               flush      = ctrl_sel && we && wdata[2];
   wire               push       = dat_sel && we && !fifo_full;
   wire               pop; // driven by the sample clock below

   assign pwm_audio_irq_out = irq_enable && (fifo_count <= (FIFO_DEPTH / 2));

   assign pwm_audio_ready = period_sel || div_sel || ctrl_sel ||
                            (dat_sel && (!we || !fifo_full));
   assign pwm_audio_rdata = ctrl_sel ? {1'b1, 21'b0, irq_enable, enable, 3'b0, fifo_free} :
                            32'h0;

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       enable <= 1'b0;
       irq_enable <= 1'b0;
       sample_div <= 24'd611;
     end else begin
       if (div_sel && we)
         sample_div <= wdata[23:0];
       if (ctrl_sel && we) begin
         enable <= wdata[0];
         irq_enable <= wdata[1];
       end
     end

   /* Kept out of the reset/flush block below: a memory written from an
    * async-reset process can't be inferred as RAM, and yosys falls back
    * to FIFO_DEPTH x 32 flip-flops instead. */
   always @(posedge clk)
     if (push)
       fifo_mem[fifo_wptr] <= wdata;

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       fifo_wptr <= 4'd0;
       fifo_rptr <= 4'd0;
       fifo_count <= 5'd0;
     end else if (flush) begin
       fifo_wptr <= 4'd0;
       fifo_rptr <= 4'd0;
       fifo_count <= 5'd0;
     end else begin
       if (push)
         fifo_wptr <= fifo_wptr + 4'd1;
       if (pop)
         fifo_rptr <= fifo_rptr + 4'd1;
       case ({push, pop})
         2'b10: fifo_count <= fifo_count + 5'd1;
         2'b01: fifo_count <= fifo_count - 5'd1;
         default: fifo_count <= fifo_count; // 2'b00 or 2'b11: no net change
       endcase
     end

   /* Sample clock: one tick every (sample_div+1) clk cycles pops the next
    * queued sample (if any) and starts scaling it onto the PWM period. */
   reg [23:0]         div_cnt = 24'd0;
   wire               sample_tick = (div_cnt == sample_div);

   always @(posedge clk or negedge reset_n)
     if (!reset_n)
       div_cnt <= 24'd0;
     else if (sample_tick)
       div_cnt <= 24'd0;
     else
       div_cnt <= div_cnt + 24'd1;

   /* Serial MSB-first shift-add multiplier, both channels in parallel:
    * acc = unsigned(sample) * (period+1), 16 cycles - far shorter than
    * any sensible sample period. Flipping the sign bit turns signed PCM
    * into offset-binary (0x8000 = silence = 50% duty). */
   wire [16:0]        period_p1 = {1'b0, period} + 17'd1;
   reg [15:0]         mul_left = 16'd0;
   reg [15:0]         mul_right = 16'd0;
   reg [32:0]         acc_left = 33'd0;
   reg [32:0]         acc_right = 33'd0;
   reg [4:0]          mul_cnt = 5'd0;
   reg                mul_busy = 1'b0;
   reg [15:0]         pending_left = 16'd270;
   reg [15:0]         pending_right = 16'd270;

   assign pop = sample_tick && !fifo_empty && !mul_busy;

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       mul_busy <= 1'b0;
       mul_cnt <= 5'd0;
       pending_left <= 16'd270;
       pending_right <= 16'd270;
     end else if (period_sel && we) begin
       /* New period: any in-flight result was scaled for the old one. */
       mul_busy <= 1'b0;
       pending_left <= (wdata[15:0] >> 1) + 16'd1;
       pending_right <= (wdata[15:0] >> 1) + 16'd1;
     end else if (pop) begin
       mul_left <= fifo_mem[fifo_rptr][31:16] ^ 16'h8000;
       mul_right <= fifo_mem[fifo_rptr][15:0] ^ 16'h8000;
       acc_left <= 33'd0;
       acc_right <= 33'd0;
       mul_cnt <= 5'd0;
       mul_busy <= 1'b1;
     end else if (mul_busy) begin
       acc_left <= (acc_left << 1) + (mul_left[15] ? {16'd0, period_p1} : 33'd0);
       acc_right <= (acc_right << 1) + (mul_right[15] ? {16'd0, period_p1} : 33'd0);
       mul_left <= {mul_left[14:0], 1'b0};
       mul_right <= {mul_right[14:0], 1'b0};
       mul_cnt <= mul_cnt + 5'd1;
       if (mul_cnt == 5'd15)
         mul_busy <= 1'b0;
     end else if (mul_cnt == 5'd16) begin
       pending_left <= acc_left[31:16];
       pending_right <= acc_right[31:16];
       mul_cnt <= 5'd0;
     end

   /* PWM carrier: counter runs 0..period; the duty compare values are
    * only reloaded at wrap-around so every pulse is a whole one. */
   reg [15:0]         pwm_cnt = 16'd0;
   reg [15:0]         duty_left = 16'd270;
   reg [15:0]         duty_right = 16'd270;
   wire               pwm_wrap = (pwm_cnt >= period);

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       period <= 16'd539;
       pwm_cnt <= 16'd0;
       duty_left <= 16'd270;
       duty_right <= 16'd270;
     end else if (period_sel && we) begin
       period <= wdata[15:0];
       pwm_cnt <= 16'd0;
       duty_left <= (wdata[15:0] >> 1) + 16'd1;
       duty_right <= (wdata[15:0] >> 1) + 16'd1;
     end else if (pwm_wrap) begin
       pwm_cnt <= 16'd0;
       duty_left <= pending_left;
       duty_right <= pending_right;
     end else begin
       pwm_cnt <= pwm_cnt + 16'd1;
     end

   assign pwm_left  = enable && (pwm_cnt < duty_left);
   assign pwm_right = enable && (pwm_cnt < duty_right);

endmodule // pwm_audio

/* New for the Arduino core: a Philips-format stereo I2S transmitter for the
 * Tang Nano 20K's onboard MAX98357A amplifier.
 *
 * Register interface (see uart_wrap.v for the analogous UART pattern):
 *   div_sel  (offset 0x0, write) - BCLK divisor. bclk toggles every
 *            (div+1) system clock cycles, so bclk frequency is
 *            CLK_FREQ / (2*(div+1)). Choose div so that
 *            bclk = sample_rate * 32 (16 bits/channel x 2 channels).
 *   dat_sel  (offset 0x4, write) - {left[15:0], right[15:0]}. Software
 *            writes are one-sample buffered: a write is only accepted
 *            (i2s_ready asserted) once the previous buffered sample has
 *            been picked up by the shifter, so the bus naturally stalls
 *            the CPU until it's time for the next sample - the same
 *            backpressure trick simpleuart uses for uart_tx. If software
 *            doesn't refill in time, the last active sample keeps
 *            repeating rather than glitching to silence.
 *   ctrl_sel (offset 0x8, write) - bit0: PA_EN (MAX98357A shutdown/enable,
 *            active high).
 */

module i2s_tx
  (
   input wire         clk,
   input wire         reset_n,

   input wire         i2s_sel,
   input wire [3:0]   addr,
   input wire [3:0]   wstrb,
   input wire [31:0]  wdata,
   output wire        i2s_ready,

   output wire        i2s_bclk,
   output wire        i2s_ws,
   output wire        i2s_din,
   output wire        i2s_pa_en
   );

   wire               div_sel  = i2s_sel && (addr == 4'h0);
   wire               dat_sel  = i2s_sel && (addr == 4'h4);
   wire               ctrl_sel = i2s_sel && (addr == 4'h8);
   wire               we       = |wstrb;

   reg [31:0]         divider = 32'd0;
   reg                pa_en = 1'b0;
   assign i2s_pa_en = pa_en;

   reg [15:0]         shadow_left, shadow_right;
   reg                shadow_valid = 1'b0;

   /* Only div/ctrl writes and a shadow-buffer-empty data write are ever
    * "ready" in the same cycle; a data write while shadow_valid stalls the
    * bus (i2s_ready low) until the shifter drains the shadow buffer. */
   assign i2s_ready = div_sel || ctrl_sel || (dat_sel && !shadow_valid);

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       divider <= 32'd0;
       pa_en <= 1'b0;
     end else begin
       if (div_sel && we)
         divider <= wdata;
       if (ctrl_sel && we)
         pa_en <= wdata[0];
     end

   always @(posedge clk or negedge reset_n)
     if (!reset_n)
       shadow_valid <= 1'b0;
     else if (dat_sel && we && !shadow_valid) begin
       shadow_left  <= wdata[31:16];
       shadow_right <= wdata[15:0];
       shadow_valid <= 1'b1;
     end else if (frame_load)
       shadow_valid <= 1'b0;

   /* BCLK generator: toggles every (divider+1) clk cycles. */
   reg [31:0]         div_cnt = 32'd0;
   reg                bclk_reg = 1'b0;
   wire               bclk_tick = (div_cnt == divider);

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       div_cnt <= 32'd0;
       bclk_reg <= 1'b0;
     end else if (bclk_tick) begin
       div_cnt <= 32'd0;
       bclk_reg <= ~bclk_reg;
     end else begin
       div_cnt <= div_cnt + 32'd1;
     end

   assign i2s_bclk = bclk_reg;

   /* Shift out on the falling edge of bclk (data changes on falling edge,
    * sampled by the receiver on the rising edge - standard I2S/Philips
    * timing), 16 bits per channel, MSB first. bit_cnt counts 0..31 across
    * one full left+right frame. */
   reg [4:0]          bit_cnt = 5'd0;
   reg [15:0]         active_left = 16'd0;
   reg [15:0]         active_right = 16'd0;
   reg [15:0]         shift_reg = 16'd0;
   reg                ws_reg = 1'b0;
   reg                din_reg = 1'b0;
   wire               frame_load = bclk_tick && bclk_reg && (bit_cnt == 5'd31);

   assign i2s_ws = ws_reg;
   assign i2s_din = din_reg;

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       bit_cnt <= 5'd0;
       active_left <= 16'd0;
       active_right <= 16'd0;
       shift_reg <= 16'd0;
       ws_reg <= 1'b0;
       din_reg <= 1'b0;
     end else if (bclk_tick && bclk_reg) begin
       /* Falling edge of bclk (bclk_reg about to go 1 -> 0): shift out the
        * next bit and, at channel/frame boundaries, reload. */
       bit_cnt <= bit_cnt + 5'd1;

       if (bit_cnt == 5'd31) begin
         /* Start of a new frame: pull in the next sample if one is
          * queued, else repeat the current one. */
         if (shadow_valid) begin
           active_left <= shadow_left;
           active_right <= shadow_right;
         end
         shift_reg <= shadow_valid ? shadow_left : active_left;
         ws_reg <= 1'b0;
       end else if (bit_cnt == 5'd15) begin
         shift_reg <= active_right;
         ws_reg <= 1'b1;
       end else begin
         shift_reg <= {shift_reg[14:0], 1'b0};
       end

       din_reg <= shift_reg[15];
     end

endmodule // i2s_tx

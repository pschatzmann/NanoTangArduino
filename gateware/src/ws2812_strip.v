/* New for the Arduino core: WS2812/WS2812B ("NeoPixel") driver for whole
 * LED strips, replacing the ws2812b.v/ws2812b_tgt.v vendored from
 * grughuhler/picorv32_tang_nano_20k, which ended every single pixel with a latch/reset pulse - fine for the one
 * onboard LED, but it meant a strip only ever showed the first pixel.
 *
 * Pixels written back-to-back stream out as one frame: a one-pixel
 * holding register lets the CPU queue the next pixel while the current
 * one is shifting, so the line never pauses as long as software writes
 * the next pixel within one pixel time (~30us). Once no pixel is
 * pending, the line is held low for the ~300us reset time that latches
 * the frame; BUSY stays set until then, so the next frame can wait for
 * it (see libraries/WS2812).
 *
 * Bit timing (per the WS2812B datasheet, +-150ns): a bit is 1.25us; a 0
 * is 0.4us high, a 1 is 0.8us high, the rest low.
 *
 * Registers (word accesses):
 *   0x0 DATA   write: queue a pixel {G[7:0],R[7:0],B[7:0]} in bits
 *              [23:0] (the bus stalls while the holding register is
 *              full); read: bit0 = BUSY (a frame is still being sent or
 *              latched).
 *   0x4 CONFIG read/write: bits[4:0] = GPIO index, bit5 = also drive
 *              that GPIO pin (for an external strip), bit6 = don't drive
 *              the onboard LED's pin.
 */
module ws2812_strip
  #(
    parameter CLK_FREQ = 27000000, // Must be a multiple of 100kHz.
    parameter GPIO_WIDTH = 21
    )
  (
   input wire                   clk,
   input wire                   reset_n,
   input wire                   sel,
   input wire [3:0]             addr,
   input wire                   we,
   input wire [31:0]            wdata,
   output wire                  ready,
   output wire [31:0]           rdata,
   output wire                  to_din,
   output wire [GPIO_WIDTH-1:0] gpio_override,
   output wire [GPIO_WIDTH-1:0] gpio_value
   );

   // Integer-only timing math: CLK_FREQ * 1.25e-6 would overflow a 32-bit
   // Verilog integer if computed as CLK_FREQ * 125 first.
   localparam CLK_100K = CLK_FREQ / 100000;
   localparam CLKS_PER_BIT = (CLK_100K * 125 + 500) / 1000; // 1.25us
   localparam T0H_CLKS = (CLK_100K * 4 + 50) / 100;         // 0.4us
   localparam T1H_CLKS = (CLK_100K * 8 + 50) / 100;         // 0.8us
   localparam T0L_CLKS = CLKS_PER_BIT - T0H_CLKS;
   localparam T1L_CLKS = CLKS_PER_BIT - T1H_CLKS;
   localparam RES_CLKS = (CLK_100K * 302 + 5) / 10;         // 302us

   localparam S_IDLE = 2'd0;
   localparam S_HIGH = 2'd1;
   localparam S_LOW  = 2'd2;
   localparam S_GAP  = 2'd3; // Line low after the last pixel: latching.

   wire data_sel = sel && (addr == 4'h0);
   wire cfg_sel  = sel && (addr == 4'h4);

   reg [1:0]  state = S_IDLE;
   reg [23:0] hold = 24'd0;
   reg        hold_valid = 1'b0;
   reg [23:0] shift = 24'd0;
   reg [4:0]  bits_left = 5'd0;
   reg [15:0] cnt = 16'd0;
   reg        cur_bit = 1'b0; // Bit being sent, for its LOW time.
   reg        dout = 1'b0;
   reg [4:0]  gpio_index = 5'd0;
   reg        gpio_enable = 1'b0;
   reg        onboard_off = 1'b0;

   wire busy = (state != S_IDLE) || hold_valid;
   wire push = data_sel && we && !hold_valid;

   assign ready = cfg_sel || (data_sel && (!we || !hold_valid));
   assign rdata = cfg_sel ? {25'b0, onboard_off, gpio_enable, gpio_index} : {31'b0, busy};
   assign to_din = dout && !onboard_off;

   genvar i;
   generate
     for (i = 0; i < GPIO_WIDTH; i = i + 1) begin : route
       assign gpio_override[i] = gpio_enable && (gpio_index == i);
       assign gpio_value[i] = gpio_override[i] && dout;
     end
   endgenerate

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       state <= S_IDLE;
       hold <= 24'd0;
       hold_valid <= 1'b0;
       shift <= 24'd0;
       bits_left <= 5'd0;
       cnt <= 16'd0;
       cur_bit <= 1'b0;
       dout <= 1'b0;
       gpio_index <= 5'd0;
       gpio_enable <= 1'b0;
       onboard_off <= 1'b0;
     end else begin
       if (cfg_sel && we) begin
         gpio_index <= wdata[4:0];
         gpio_enable <= wdata[5];
         onboard_off <= wdata[6];
       end

       if (push) begin
         hold <= wdata[23:0];
         hold_valid <= 1'b1;
       end

       case (state)
         S_IDLE, S_GAP: begin
           // A queued pixel starts (or, during the gap, continues) a frame.
           if (hold_valid) begin
             hold_valid <= 1'b0;
             shift <= {hold[22:0], 1'b0};
             bits_left <= 5'd23;
             cur_bit <= hold[23];
             dout <= 1'b1;
             cnt <= (hold[23] ? T1H_CLKS : T0H_CLKS) - 1;
             state <= S_HIGH;
           end else if (state == S_GAP) begin
             if (cnt == 0)
               state <= S_IDLE;
             else
               cnt <= cnt - 16'd1;
           end
         end

         S_HIGH: begin
           if (cnt == 0) begin
             dout <= 1'b0;
             cnt <= (cur_bit ? T1L_CLKS : T0L_CLKS) - 1;
             state <= S_LOW;
           end else begin
             cnt <= cnt - 16'd1;
           end
         end

         S_LOW: begin
           if (cnt != 0) begin
             cnt <= cnt - 16'd1;
           end else if (bits_left != 0) begin
             // Next bit of this pixel.
             bits_left <= bits_left - 5'd1;
             shift <= {shift[22:0], 1'b0};
             cur_bit <= shift[23];
             dout <= 1'b1;
             cnt <= (shift[23] ? T1H_CLKS : T0H_CLKS) - 1;
             state <= S_HIGH;
           end else if (hold_valid) begin
             // Next pixel, straight after this one.
             hold_valid <= 1'b0;
             shift <= {hold[22:0], 1'b0};
             bits_left <= 5'd23;
             cur_bit <= hold[23];
             dout <= 1'b1;
             cnt <= (hold[23] ? T1H_CLKS : T0H_CLKS) - 1;
             state <= S_HIGH;
           end else begin
             cnt <= RES_CLKS - 1;
             state <= S_GAP;
           end
         end

         default: state <= S_IDLE;
       endcase
     end

endmodule

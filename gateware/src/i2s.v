/* New for the Arduino core: a Philips-format stereo I2S peripheral for the
 * Tang Nano 20K's onboard MAX98357A amplifier (transmit), with an
 * optional receive path for an external I2S microphone (Tools > I2S
 * Input, disabled by default - see docs/PERIPHERALS.md "Audio (I2S)").
 * Transmit and receive share one BCLK/WS generator, so once enabled both
 * directions run simultaneously (full duplex) with no separate mode to
 * select in software - a sketch that calls both write() and read() is
 * already running duplex.
 *
 * Both directions are backed by a small (FIFO_DEPTH-deep) sample queue
 * rather than the single-sample shadow buffer earlier revisions of this
 * file used: software can get up to FIFO_DEPTH samples ahead (transmit)
 * or behind (receive) the hardware shifter before write()/read() ever
 * has to block, instead of needing to service the peripheral within one
 * sample period every time. An optional interrupt (see the IRQ_ENABLE/
 * STATUS registers below) lets software refill/drain in bulk from an
 * ISR instead of polling - see docs/PERIPHERALS.md "Audio (I2S)".
 *
 * Register interface (see uart_wrap.v for the analogous UART pattern).
 * Original window (offsets relative to the peripheral's base address):
 *   div_sel    (offset 0x0, write) - BCLK divisor. bclk toggles every
 *              (div+1) system clock cycles, so bclk frequency is
 *              CLK_FREQ / (2*(div+1)). Choose div so that
 *              bclk = sample_rate * 32 (16 bits/channel x 2 channels).
 *   dat_sel    (offset 0x4, write) - transmit: {left[15:0], right[15:0]}.
 *              Pushes onto the FIFO_DEPTH-deep transmit FIFO; a write is
 *              only accepted (i2s_ready asserted) while that FIFO has
 *              room, so the bus naturally stalls the CPU once it's
 *              FIFO_DEPTH samples ahead of the shifter - the same
 *              backpressure trick simpleuart uses for uart_tx, just with
 *              more slack than a single-sample buffer. If software
 *              doesn't refill in time (FIFO runs dry), the last active
 *              sample keeps repeating rather than glitching to silence.
 *   ctrl_sel   (offset 0x8, write) - bit0: PA_EN (MAX98357A shutdown/
 *              enable, active high). Unrelated to receive - a sketch that
 *              only wants to record doesn't need to set this.
 *   dat_rx_sel (offset 0xC, read) - receive: {left[15:0], right[15:0]}
 *              pops the oldest sample off the FIFO_DEPTH-deep receive
 *              FIFO. Mirrors dat_sel's backpressure in the opposite
 *              direction: a read only completes (i2s_ready asserted)
 *              once the FIFO has at least one captured sample, so reads
 *              are naturally paced at the configured sample rate but can
 *              also be drained in a FIFO_DEPTH-sample burst without
 *              blocking. If software falls behind and the FIFO fills up,
 *              the newest captured sample is dropped (oldest data is
 *              preserved) rather than overwriting unread data. When
 *              Tools > I2S Input is disabled at synthesis time,
 *              i2s_rx_din is tied to 0 in top.v, so captured samples are
 *              always silence, but the FIFO/backpressure behavior is
 *              otherwise unchanged.
 *
 * Second window, i2s_ext_sel (see top.v - a separate address decode from
 * i2s_sel above, reusing the same addr[3:0] offsets independently):
 *   irqen_sel  (offset 0x0, read/write) - bit0: raise i2s_irq_out
 *              whenever the transmit FIFO has room (i.e. a write would
 *              not block). bit1: raise i2s_irq_out whenever the receive
 *              FIFO has at least one sample (i.e. a read would not
 *              block). Both level-triggered, not sticky/edge-latched -
 *              the line simply tracks live FIFO occupancy, the same way
 *              a real UART's TX-empty/RX-not-empty interrupts work, so
 *              it self-clears once an ISR has filled/drained the FIFO
 *              back past the condition (or software disables the
 *              relevant bit first). Both bits are 0 (no interrupt) after
 *              reset.
 *   status_sel (offset 0x4, read-only) - bits[4:0]: number of free
 *              slots in the transmit FIFO (0-FIFO_DEPTH); bits[9:5]:
 *              number of captured samples waiting in the receive FIFO
 *              (0-FIFO_DEPTH). Lets an ISR (or polling code) know how
 *              many samples it can push/pop in one burst without
 *              blocking.
 */

module i2s
  (
   input wire         clk,
   input wire         reset_n,

   input wire         i2s_sel,
   input wire         i2s_ext_sel,
   input wire [3:0]   addr,
   input wire [3:0]   wstrb,
   input wire [31:0]  wdata,
   output wire        i2s_ready,
   output wire [31:0] i2s_rdata,
   output wire        i2s_irq_out,

   output wire        i2s_bclk,
   output wire        i2s_ws,
   output wire        i2s_din,
   output wire        i2s_pa_en,

   input wire         i2s_rx_din
   );

   localparam FIFO_DEPTH = 16;

   wire               div_sel    = i2s_sel && (addr == 4'h0);
   wire               dat_sel    = i2s_sel && (addr == 4'h4);
   wire               ctrl_sel   = i2s_sel && (addr == 4'h8);
   wire               dat_rx_sel = i2s_sel && (addr == 4'hC);
   wire               irqen_sel  = i2s_ext_sel && (addr == 4'h0);
   wire               status_sel = i2s_ext_sel && (addr == 4'h4);
   wire               we         = |wstrb;

   reg [31:0]         divider = 32'd0;
   reg                pa_en = 1'b0;
   assign i2s_pa_en = pa_en;

   reg                tx_irq_enable = 1'b0;
   reg                rx_irq_enable = 1'b0;

   /* Transmit FIFO: pushed by dat_sel writes, popped by the shifter at
    * each frame boundary (frame_load, defined below). */
   reg [31:0]         tx_fifo_mem [0:FIFO_DEPTH-1];
   reg [3:0]          tx_fifo_wptr = 4'd0;
   reg [3:0]          tx_fifo_rptr = 4'd0;
   reg [4:0]          tx_fifo_count = 5'd0;
   wire               tx_fifo_full  = (tx_fifo_count == FIFO_DEPTH[4:0]);
   wire               tx_fifo_empty = (tx_fifo_count == 5'd0);
   wire               tx_push = dat_sel && we && !tx_fifo_full;
   wire               tx_pop; // driven by the shifter block below

   /* Receive FIFO: pushed by the capture logic at each frame boundary
    * (rx_frame_done, defined below), popped by dat_rx_sel reads. */
   reg [31:0]         rx_fifo_mem [0:FIFO_DEPTH-1];
   reg [3:0]          rx_fifo_wptr = 4'd0;
   reg [3:0]          rx_fifo_rptr = 4'd0;
   reg [4:0]          rx_fifo_count = 5'd0;
   wire               rx_fifo_full  = (rx_fifo_count == FIFO_DEPTH[4:0]);
   wire               rx_fifo_empty = (rx_fifo_count == 5'd0);
   wire               rx_push; // driven by the capture block below
   wire               rx_pop = dat_rx_sel && !we && !rx_fifo_empty;

   wire [4:0]         tx_fifo_free = FIFO_DEPTH[4:0] - tx_fifo_count;

   assign i2s_irq_out = (tx_irq_enable && !tx_fifo_full) ||
                         (rx_irq_enable && !rx_fifo_empty);

   /* Transmit-side writes are ready whenever there's FIFO room; a
    * dat_rx read is ready once the receive FIFO has a sample (a dat_rx
    * write is a no-op but still accepted immediately, same as before). */
   assign i2s_ready = div_sel || ctrl_sel || (dat_sel && !tx_fifo_full) ||
                       (dat_rx_sel && (we || !rx_fifo_empty)) ||
                       irqen_sel || status_sel;
   assign i2s_rdata = dat_rx_sel ? rx_fifo_mem[rx_fifo_rptr] :
                       status_sel ? {22'b0, rx_fifo_count, tx_fifo_free} :
                       32'h0;

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       divider <= 32'd0;
       pa_en <= 1'b0;
       tx_irq_enable <= 1'b0;
       rx_irq_enable <= 1'b0;
     end else begin
       if (div_sel && we)
         divider <= wdata;
       if (ctrl_sel && we)
         pa_en <= wdata[0];
       if (irqen_sel && we) begin
         tx_irq_enable <= wdata[0];
         rx_irq_enable <= wdata[1];
       end
     end

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       tx_fifo_wptr <= 4'd0;
       tx_fifo_rptr <= 4'd0;
       tx_fifo_count <= 5'd0;
     end else begin
       if (tx_push) begin
         tx_fifo_mem[tx_fifo_wptr] <= wdata;
         tx_fifo_wptr <= tx_fifo_wptr + 4'd1;
       end
       if (tx_pop)
         tx_fifo_rptr <= tx_fifo_rptr + 4'd1;
       case ({tx_push, tx_pop})
         2'b10: tx_fifo_count <= tx_fifo_count + 5'd1;
         2'b01: tx_fifo_count <= tx_fifo_count - 5'd1;
         default: tx_fifo_count <= tx_fifo_count; // 2'b00 or 2'b11: no net change
       endcase
     end

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       rx_fifo_wptr <= 4'd0;
       rx_fifo_rptr <= 4'd0;
       rx_fifo_count <= 5'd0;
     end else begin
       if (rx_push) begin
         rx_fifo_mem[rx_fifo_wptr] <= {rx_left_latched, rx_shift_next};
         rx_fifo_wptr <= rx_fifo_wptr + 4'd1;
       end
       if (rx_pop)
         rx_fifo_rptr <= rx_fifo_rptr + 4'd1;
       case ({rx_push, rx_pop})
         2'b10: rx_fifo_count <= rx_fifo_count + 5'd1;
         2'b01: rx_fifo_count <= rx_fifo_count - 5'd1;
         default: rx_fifo_count <= rx_fifo_count; // 2'b00 or 2'b11: no net change
       endcase
     end

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
    * one full left+right frame, and also serves as the shared frame
    * position for the receive path below (same BCLK/WS drives both). */
   reg [4:0]          bit_cnt = 5'd0;
   reg [15:0]         active_left = 16'd0;
   reg [15:0]         active_right = 16'd0;
   reg [15:0]         shift_reg = 16'd0;
   reg                ws_reg = 1'b0;
   reg                din_reg = 1'b0;
   wire               frame_load = bclk_tick && bclk_reg && (bit_cnt == 5'd31);
   assign tx_pop = frame_load && !tx_fifo_empty;

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
         /* Start of a new frame: pull in the next queued sample if the
          * transmit FIFO has one, else repeat the current one. */
         if (!tx_fifo_empty) begin
           active_left <= tx_fifo_mem[tx_fifo_rptr][31:16];
           active_right <= tx_fifo_mem[tx_fifo_rptr][15:0];
         end
         shift_reg <= !tx_fifo_empty ? tx_fifo_mem[tx_fifo_rptr][31:16] : active_left;
         ws_reg <= 1'b0;
       end else if (bit_cnt == 5'd15) begin
         shift_reg <= active_right;
         ws_reg <= 1'b1;
       end else begin
         shift_reg <= {shift_reg[14:0], 1'b0};
       end

       din_reg <= shift_reg[15];
     end

   /* Receive: sample i2s_rx_din on the rising edge of bclk (the
    * complementary edge to where the block above changes i2s_din/where a
    * transmitter on this bus would change its own data) - standard
    * receiver-side I2S timing. bit_cnt still holds the position set by
    * the last falling edge, so it directly indexes which bit of which
    * channel is being captured: 0-15 = left (MSB first), 16-31 = right. */
   reg [15:0]         rx_shift_reg = 16'd0;
   reg [15:0]         rx_left_latched = 16'd0;
   wire               capture_tick = bclk_tick && !bclk_reg;
   wire [15:0]        rx_shift_next = {rx_shift_reg[14:0], i2s_rx_din};
   wire               rx_frame_done = capture_tick && (bit_cnt == 5'd31);
   assign rx_push = rx_frame_done && !rx_fifo_full;

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       rx_shift_reg <= 16'd0;
       rx_left_latched <= 16'd0;
     end else if (capture_tick) begin
       rx_shift_reg <= rx_shift_next;
       if (bit_cnt == 5'd15)
         rx_left_latched <= rx_shift_next;
     end

endmodule // i2s

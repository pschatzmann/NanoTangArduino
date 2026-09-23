/* Adapted from grughuhler/picorv32_tang_nano_20k (BSD-2-Clause).
 * Wraps picorv32's simpleuart with a memory-mapped register interface:
 * offset 0x4 = status register, 0x8 = clock divisor register,
 * 0xc = data register.
 *
 * Extended for the Arduino core with FIFOs between the CPU and
 * simpleuart, so Serial neither drops received bytes whenever loop()
 * doesn't poll within one character time, nor stalls the CPU for every
 * transmitted byte:
 *
 *   DAT read   - pops the oldest received byte, or returns ~0 when the RX
 *                FIFO is empty (same convention as bare simpleuart).
 *   DAT write  - pushes onto the TX FIFO; stalls the bus only while it
 *                is full.
 *   STATUS     - bits [6:0]   RX FIFO count
 *     (read)     bits [14:8]  TX FIFO free slots
 *                bit  16      TX idle (FIFO empty and last stop bit sent)
 *                bit  17      RX overflow since the last STATUS read
 *                             (sticky, cleared by the read)
 */
module uart_wrap
  #(
    parameter RX_DEPTH_LOG2 = 6, // 64 bytes: ~5.5ms of slack at 115200 baud
    parameter TX_DEPTH_LOG2 = 5  // 32 bytes
    )
  (
   input wire         clk,
   input wire         reset_n,
   input wire         uart_rx,
   output wire        uart_tx,
   input wire         uart_sel,
   input wire [3:0]   addr, // Choose status, div or dat
   input wire [3:0]   uart_wstrb,
   input wire [31:0]  uart_di,
   output wire [31:0] uart_do,
   output wire        uart_ready
   );

   localparam RX_DEPTH = 1 << RX_DEPTH_LOG2;
   localparam TX_DEPTH = 1 << TX_DEPTH_LOG2;

   wire               status_sel;
   wire               div_sel;
   wire               dat_sel;
   wire [31:0]        div_do;
   wire [31:0]        core_dat_do;
   wire               core_dat_wait;
   wire               core_tx_busy;
   wire               core_rx_lost;

   assign status_sel = uart_sel && (addr == 4'h4);
   assign div_sel    = uart_sel && (addr == 4'h8);
   assign dat_sel    = uart_sel && (addr == 4'hc);

   wire cpu_write = dat_sel && uart_wstrb[0];
   wire cpu_read  = dat_sel && !uart_wstrb;

   /* --- RX FIFO: simpleuart's one-byte buffer -> CPU ------------------- */

   reg [7:0]               rx_mem [0:RX_DEPTH-1];
   reg [RX_DEPTH_LOG2:0]   rx_wr = 0;
   reg [RX_DEPTH_LOG2:0]   rx_rd = 0;
   reg                     rx_overflow = 1'b0;
   wire [RX_DEPTH_LOG2:0]  rx_count = rx_wr - rx_rd;
   wire                    rx_empty = (rx_count == 0);
   wire                    rx_full  = (rx_count == RX_DEPTH);
   // simpleuart reports "no byte" as ~0; a received byte has bit 31 clear.
   wire                    core_rx_valid = !core_dat_do[31];
   wire                    rx_push = core_rx_valid && !rx_full;
   wire                    rx_pop  = cpu_read && !rx_empty;

   always @(posedge clk) begin
      if (rx_push)
        rx_mem[rx_wr[RX_DEPTH_LOG2-1:0]] <= core_dat_do[7:0];
   end

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
        rx_wr <= 0;
        rx_rd <= 0;
        rx_overflow <= 1'b0;
     end else begin
        if (rx_push)
          rx_wr <= rx_wr + 1'b1;
        if (rx_pop)
          rx_rd <= rx_rd + 1'b1;
        if (status_sel && !uart_wstrb)
          rx_overflow <= 1'b0;
        // simpleuart received a byte while still holding one the full
        // FIFO couldn't take - that held byte is gone.
        if (core_rx_lost)
          rx_overflow <= 1'b1;
     end

   /* --- TX FIFO: CPU -> simpleuart ------------------------------------- */

   reg [7:0]               tx_mem [0:TX_DEPTH-1];
   reg [TX_DEPTH_LOG2:0]   tx_wr = 0;
   reg [TX_DEPTH_LOG2:0]   tx_rd = 0;
   wire [TX_DEPTH_LOG2:0]  tx_count = tx_wr - tx_rd;
   wire                    tx_empty = (tx_count == 0);
   wire                    tx_full  = (tx_count == TX_DEPTH);
   wire [TX_DEPTH_LOG2:0]  tx_free  = TX_DEPTH - tx_count;
   wire                    tx_push  = cpu_write && !tx_full;
   // Offer the head byte to simpleuart whenever there is one; it's taken
   // on the first cycle simpleuart doesn't assert wait.
   wire                    core_we  = !tx_empty;
   wire                    tx_pop   = core_we && !core_dat_wait;

   always @(posedge clk) begin
      if (tx_push)
        tx_mem[tx_wr[TX_DEPTH_LOG2-1:0]] <= uart_di[7:0];
   end

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
        tx_wr <= 0;
        tx_rd <= 0;
     end else begin
        if (tx_push)
          tx_wr <= tx_wr + 1'b1;
        if (tx_pop)
          tx_rd <= tx_rd + 1'b1;
     end

   /* --- CPU-facing registers ------------------------------------------- */

   wire [31:0] status = {14'b0, rx_overflow, tx_empty && !core_tx_busy,
                         {(8 - TX_DEPTH_LOG2 - 1){1'b0}}, tx_free,
                         {(8 - RX_DEPTH_LOG2 - 1){1'b0}}, rx_count};

   assign uart_do = status_sel ? status :
                    div_sel ? div_do :
                    dat_sel ? (rx_empty ? 32'hffff_ffff : {24'b0, rx_mem[rx_rd[RX_DEPTH_LOG2-1:0]]}) :
                    32'h0;
   assign uart_ready = status_sel | div_sel | cpu_read | (cpu_write && !tx_full);

   simpleuart uart
     (
      .clk(clk),
      .resetn(reset_n),
      .ser_tx(uart_tx),
      .ser_rx(uart_rx),
      .reg_div_we(div_sel ? uart_wstrb : 4'b0000),
      .reg_div_di(uart_di),
      .reg_div_do(div_do),
      .reg_dat_we(core_we),
      .reg_dat_re(rx_push),
      .reg_dat_di({24'b0, tx_mem[tx_rd[TX_DEPTH_LOG2-1:0]]}),
      .reg_dat_do(core_dat_do),
      .reg_dat_wait(core_dat_wait),
      .tx_busy(core_tx_busy),
      .rx_lost(core_rx_lost)
      );
endmodule

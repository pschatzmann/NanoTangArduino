// Word-at-a-time bulk memory copy engine, with two independent copy paths:
//
// - "Blocking" mode (mode bit=0): the original design. This module
//   becomes the SoC's *first* true second bus master - see top.v's
//   arbiter for how it shares the whole CPU bus. While `active` is high it
//   drives the shared mem_valid/mem_addr/mem_wdata/mem_wstrb bus that
//   feeds the existing address-decoded peripherals/memory unchanged, and
//   picorv32's own bus is held stalled (mem_ready low) for the duration -
//   picorv32 has no separate instruction bus, so this is throughput-only
//   "cycle stealing" DMA: the CPU cannot run other code while a transfer
//   is in flight. Works for any address (SRAM, SDRAM, or a mix).
//
// - "Async" mode (mode bit=1): a second, independent copy FSM with its own
//   dedicated bus-master port wired *directly* to gateware/src/sdram_bus.v's
//   second port (see top.v) - it never touches the CPU's shared bus at
//   all, so the CPU keeps running (instruction fetch, SRAM, peripherals)
//   completely unimpeded. This only works for SDRAM<->SDRAM copies (the
//   only slave wired to this port); addresses are byte offsets within the
//   8MB SDRAM window (bits [22:0] of whatever's written to SRC/DST), same
//   truncation top.v's normal SDRAM path already applies. Raises `irq_out`
//   (sticky, cleared by reading STATUS) when done - see
//   cores/tangnano20k/wiring_irq.cpp and docs/PERIPHERALS.md "DMA".
//
// Control registers (word-addressed, base 0x8000_0130):
//   0x00 SRC   (r/w) - source address (word-aligned)
//   0x04 DST   (r/w) - destination address (word-aligned)
//   0x08 LEN   (r/w) - word count
//   0x0C START (write: bit0=start (if LEN!=0 and that mode isn't already
//              busy), bit1=mode (0=blocking, 1=async);
//              read: bit0=blocking busy, bit1=async busy, bit2=async done
//              (sticky, cleared by this read))
// Software should not touch SRC/DST/LEN for a mode while that mode is
// busy - see libraries/DMA/src/DMA.cpp.
module dma_engine
  (
   input wire         clk,
   input wire         reset_n,

   // Control-register bus - a normal MMIO slave, decoded exactly like any
   // other peripheral in top.v.
   input wire         ctrl_sel,
   input wire [1:0]   ctrl_addr,
   input wire [3:0]   ctrl_wstrb,
   input wire [31:0]  ctrl_wdata,
   output reg         ctrl_ready,
   output reg [31:0]  ctrl_rdata,

   // Blocking-mode bus-master interface into top.v's whole-CPU-bus arbiter.
   output reg         active,
   output reg         mem_valid,
   output reg [31:0]  mem_addr,
   output reg [31:0]  mem_wdata,
   output reg [3:0]   mem_wstrb,
   input wire         mem_ready,
   input wire [31:0]  mem_rdata,

   // Async-mode bus-master interface, direct to sdram_bus.v's second port.
   output reg         async_mem_valid,
   output reg [22:0]  async_mem_addr,
   output reg [31:0]  async_mem_wdata,
   output reg [3:0]   async_mem_wstrb,
   input wire         async_mem_ready,
   input wire [31:0]  async_mem_rdata,

   output wire        irq_out
   );

   // ---- Blocking mode (unchanged from the original single-mode design) ----
   reg [31:0] src_addr;
   reg [31:0] dst_addr;
   reg [31:0] word_count;
   reg [31:0] words_done;
   reg [31:0] hold_data;
   reg        busy;
   reg        phase; // 0 = reading src_addr[words_done], 1 = writing dst_addr[words_done]

   // ---- Async mode ----
   reg [31:0] a_src_addr;
   reg [31:0] a_dst_addr;
   reg [31:0] a_word_count;
   reg [31:0] a_words_done;
   reg [31:0] a_hold_data;
   reg        a_busy;
   reg        a_phase;
   reg        a_done_pending;

   assign irq_out = a_done_pending;

   always @(posedge clk) begin
      ctrl_ready <= 1'b0;
      ctrl_rdata <= 32'h0;

      if (!reset_n) begin
         busy            <= 1'b0;
         active          <= 1'b0;
         mem_valid       <= 1'b0;
         phase           <= 1'b0;
         a_busy          <= 1'b0;
         a_phase         <= 1'b0;
         a_done_pending  <= 1'b0;
         async_mem_valid <= 1'b0;
      end else begin
         if (ctrl_sel) begin
            ctrl_ready <= 1'b1;
            case (ctrl_addr)
              2'h0: if (|ctrl_wstrb) src_addr <= ctrl_wdata; else ctrl_rdata <= src_addr;
              2'h1: if (|ctrl_wstrb) dst_addr <= ctrl_wdata; else ctrl_rdata <= dst_addr;
              2'h2: if (|ctrl_wstrb) word_count <= ctrl_wdata; else ctrl_rdata <= word_count;
              2'h3: begin
                 if (|ctrl_wstrb) begin
                    if (ctrl_wdata[1]) begin
                       // Async: SRC/DST/LEN reused as the async transfer's
                       // parameters too (mutually exclusive with a
                       // simultaneous blocking transfer in practice, since
                       // software only ever uses one mode at a time - see
                       // DMA.cpp).
                       if (!a_busy && word_count != 0) begin
                          a_src_addr   <= src_addr;
                          a_dst_addr   <= dst_addr;
                          a_word_count <= word_count;
                          a_busy       <= 1'b1;
                          a_words_done <= 32'h0;
                          a_phase      <= 1'b0;
                       end
                    end else begin
                       if (!busy && word_count != 0) begin
                          busy       <= 1'b1;
                          active     <= 1'b1;
                          words_done <= 32'h0;
                          phase      <= 1'b0;
                       end
                    end
                 end else begin
                    ctrl_rdata     <= {29'b0, a_done_pending, a_busy, busy};
                    a_done_pending <= 1'b0;
                 end
              end
            endcase
         end

         if (busy) begin
            if (!phase) begin
               mem_valid <= 1'b1;
               mem_addr  <= src_addr + (words_done << 2);
               mem_wstrb <= 4'h0;
               if (mem_valid && mem_ready) begin
                  hold_data <= mem_rdata;
                  phase     <= 1'b1;
                  mem_valid <= 1'b0;
               end
            end else begin
               mem_valid <= 1'b1;
               mem_addr  <= dst_addr + (words_done << 2);
               mem_wdata <= hold_data;
               mem_wstrb <= 4'hF;
               if (mem_valid && mem_ready) begin
                  mem_valid  <= 1'b0;
                  phase      <= 1'b0;
                  words_done <= words_done + 1;
                  if (words_done + 1 == word_count) begin
                     busy   <= 1'b0;
                     active <= 1'b0;
                  end
               end
            end
         end

         if (a_busy) begin
            if (!a_phase) begin
               async_mem_valid <= 1'b1;
               async_mem_addr  <= a_src_addr[22:0] + (a_words_done << 2);
               async_mem_wstrb <= 4'h0;
               if (async_mem_valid && async_mem_ready) begin
                  a_hold_data     <= async_mem_rdata;
                  a_phase         <= 1'b1;
                  async_mem_valid <= 1'b0;
               end
            end else begin
               async_mem_valid <= 1'b1;
               async_mem_addr  <= a_dst_addr[22:0] + (a_words_done << 2);
               async_mem_wdata <= a_hold_data;
               async_mem_wstrb <= 4'hF;
               if (async_mem_valid && async_mem_ready) begin
                  async_mem_valid <= 1'b0;
                  a_phase         <= 1'b0;
                  a_words_done    <= a_words_done + 1;
                  if (a_words_done + 1 == a_word_count) begin
                     a_busy         <= 1'b0;
                     a_done_pending <= 1'b1;
                  end
               end
            end
         end
      end
   end
endmodule

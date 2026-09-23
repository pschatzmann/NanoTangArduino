/* New for the Arduino core: bridges picorv32's word-oriented memory bus to
 * nand2mario's byte-oriented sdram.v controller (see sdram.v), and
 * schedules periodic refresh.
 *
 * sdram.v reads a full 32-bit word in one operation (dout32), but only
 * accepts one byte per write (with DQM byte masking) - so a CPU word
 * write with multiple wstrb bits set is done as a short sequence of
 * single-byte writes here, one per set bit, each ~5 sdram.v cycles.
 *
 * FREQ is passed straight to sdram.v (only used there for its 200us
 * power-on delay counter) and used here to derive the ~15us refresh
 * interval sdram.v's own documentation asks for.
 *
 * Two request ports share the one physical SDRAM chip (which, being real
 * SDR SDRAM hardware, only ever serves one command at a time regardless of
 * what's built around it): port A is the CPU's normal path via top.v's
 * address-decoded bus (unchanged); port B is gateware/src/dma_engine.v's
 * dedicated async-DMA path, arbitrated here at word granularity (CPU
 * always wins ties) so a long DMA transfer never starves ordinary CPU
 * SDRAM access for more than the current in-flight word - see
 * docs/PERIPHERALS.md "DMA".
 */

module sdram_bus
  #(
    parameter FREQ = 27_000_000
    )
  (
   input wire         clk,
   input wire         clk_sdram,
   input wire         reset_n,

   input wire         sel,
   input wire [22:0]  addr,     // byte address within the 8MB SDRAM window
   input wire [3:0]   wstrb,
   input wire [31:0]  wdata,
   output reg         ready,
   output wire [31:0] rdata,

   // Port B: dma_engine.v's dedicated async-DMA path (see module header).
   input wire         dma_sel,
   input wire [22:0]  dma_addr,
   input wire [3:0]   dma_wstrb,
   input wire [31:0]  dma_wdata,
   output reg         dma_ready,
   output wire [31:0] dma_rdata,

   inout wire [31:0]  SDRAM_DQ,
   output wire [10:0] SDRAM_A,
   output wire [1:0]  SDRAM_BA,
   output wire        SDRAM_nCS,
   output wire        SDRAM_nWE,
   output wire        SDRAM_nRAS,
   output wire        SDRAM_nCAS,
   output wire        SDRAM_CLK,
   output wire        SDRAM_CKE,
   output wire [3:0]  SDRAM_DQM
   );

   // ---- Periodic refresh (once every ~15us, per sdram.v's contract) ----
   localparam integer REFRESH_CYCLES = FREQ / 1000 * 15 / 1000;
   reg [31:0]          refresh_cnt = 32'd0;
   reg                 refresh_due = 1'b0;

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       refresh_cnt <= 32'd0;
       refresh_due <= 1'b0;
     end else if (refresh_cnt >= REFRESH_CYCLES) begin
       refresh_cnt <= 32'd0;
       refresh_due <= 1'b1;
     end else begin
       refresh_cnt <= refresh_cnt + 32'd1;
       if (ctl_refresh)
         refresh_due <= 1'b0;
     end

   // ---- Bus-facing FSM ----
   localparam ST_IDLE = 2'd0, ST_ISSUE = 2'd1, ST_WAIT = 2'd2;
   reg [1:0]           state = ST_IDLE;
   reg [1:0]           lane;         // which byte lane a write is currently on
   reg                 is_write;
   reg                 serving_dma;  // which port's request is latched below
   reg [22:0]          op_addr;
   reg [3:0]           op_wstrb;
   reg [31:0]          op_wdata;
   reg [31:0]          rdata_reg;

   // Only the port whose own `ready`/`dma_ready` pulses ever latches this,
   // so both ports safely observing the same register is not a hazard.
   assign rdata = rdata_reg;
   assign dma_rdata = rdata_reg;

   wire                ctl_busy;
   wire                ctl_rd = (state == ST_ISSUE) && !is_write;
   wire                ctl_wr = (state == ST_ISSUE) && is_write;
   /* sdram.v only takes a command while it's idle, and a one-cycle rd/wr
    * pulse arriving while it's busy is silently dropped. So a refresh is
    * issued only when it's idle, and a new request is accepted only when
    * it's idle and no refresh is due - otherwise a request arriving in
    * the same cycle as a refresh was lost, and this FSM, seeing busy
    * drop once the refresh finished, reported stale read data or a write
    * that never happened (found on real hardware: intermittently wrong
    * SDRAM words). */
   wire                ctl_refresh = (state == ST_IDLE) && refresh_due && !ctl_busy;
   wire                can_accept = !refresh_due && !ctl_busy;

   // Lowest byte lane a write mask selects: a write starts there, not at
   // lane 0 (which wrote byte 0 on every byte/halfword write - found on
   // real hardware).
   function [1:0] first_lane(input [3:0] m);
      first_lane = m[0] ? 2'd0 : m[1] ? 2'd1 : m[2] ? 2'd2 : 2'd3;
   endfunction
   wire                ctl_data_ready;
   wire [7:0]          ctl_dout;
   wire [31:0]         ctl_dout32;

   // Combinationally finds the next set wstrb bit above the current lane,
   // for sequencing a multi-byte write (see sdram.v's byte-at-a-time
   // write interface).
   reg                 next_lane_valid;
   reg [1:0]           next_lane;
   integer              scan_i;
   always @(*) begin
     next_lane_valid = 1'b0;
     next_lane = 2'd0;
     for (scan_i = 0; scan_i < 4; scan_i = scan_i + 1)
       if (scan_i > lane && op_wstrb[scan_i] && !next_lane_valid) begin
         next_lane = scan_i[1:0];
         next_lane_valid = 1'b1;
       end
   end

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       state <= ST_IDLE;
       ready <= 1'b0;
       dma_ready <= 1'b0;
       lane <= 2'd0;
     end else begin
       ready <= 1'b0;
       dma_ready <= 1'b0;
       case (state)
         ST_IDLE: begin
           // CPU port always wins ties, so a long DMA transfer never
           // starves ordinary CPU SDRAM access for more than the current
           // in-flight word (re-arbitrated every word, see module header).
           if (sel && !ready && can_accept) begin
             op_addr <= addr;
             op_wstrb <= wstrb;
             op_wdata <= wdata;
             is_write <= |wstrb;
             serving_dma <= 1'b0;
             lane <= first_lane(wstrb);
             state <= ST_ISSUE;
           end else if (dma_sel && !dma_ready && can_accept) begin
             op_addr <= dma_addr;
             op_wstrb <= dma_wstrb;
             op_wdata <= dma_wdata;
             is_write <= |dma_wstrb;
             serving_dma <= 1'b1;
             lane <= first_lane(dma_wstrb);
             state <= ST_ISSUE;
           end
         end

         ST_ISSUE: begin
           state <= ST_WAIT;
         end

         ST_WAIT: begin
           if (ctl_data_ready)
             rdata_reg <= ctl_dout32;

           if (!ctl_busy) begin
             if (is_write) begin
               if (next_lane_valid) begin
                 lane <= next_lane;
                 state <= ST_ISSUE;
               end else begin
                 state <= ST_IDLE;
                 if (serving_dma) dma_ready <= 1'b1; else ready <= 1'b1;
               end
             end else begin
               state <= ST_IDLE;
               if (serving_dma) dma_ready <= 1'b1; else ready <= 1'b1;
             end
           end
         end
       endcase
     end

   wire [22:0] lane_addr = {op_addr[22:2], lane};
   wire [7:0]  wbyte = lane == 2'd0 ? op_wdata[7:0] :
                       lane == 2'd1 ? op_wdata[15:8] :
                       lane == 2'd2 ? op_wdata[23:16] : op_wdata[31:24];

   sdram #(.FREQ(FREQ)) ctl
     (
      .SDRAM_DQ(SDRAM_DQ),
      .SDRAM_A(SDRAM_A),
      .SDRAM_BA(SDRAM_BA),
      .SDRAM_nCS(SDRAM_nCS),
      .SDRAM_nWE(SDRAM_nWE),
      .SDRAM_nRAS(SDRAM_nRAS),
      .SDRAM_nCAS(SDRAM_nCAS),
      .SDRAM_CLK(SDRAM_CLK),
      .SDRAM_CKE(SDRAM_CKE),
      .SDRAM_DQM(SDRAM_DQM),
      .clk(clk),
      .clk_sdram(clk_sdram),
      .resetn(reset_n),
      .rd(ctl_rd),
      .wr(ctl_wr),
      .refresh(ctl_refresh),
      .addr(is_write ? lane_addr : op_addr),
      .din(wbyte),
      .dout(ctl_dout),
      .dout32(ctl_dout32),
      .data_ready(ctl_data_ready),
      .busy(ctl_busy)
      );

endmodule // sdram_bus

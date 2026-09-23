`timescale 1ns/1ps
/* Test bench for gateware/src/sdram_bus.v against sdram_stub.v: 20,000
 * random word/halfword/byte writes and reads with refresh firing every
 * 15 cycles, checked against a byte model. Catches the two bugs found on
 * real hardware: a request issued while a refresh starts being dropped,
 * and byte/halfword writes also writing byte 0. */
module tb;
  reg clk = 0, rst_n = 0; always #5 clk = ~clk;
  reg sel = 0; reg [22:0] addr = 0; reg [3:0] wstrb = 0; reg [31:0] wdata = 0;
  wire ready; wire [31:0] rdata; wire [31:0] dq;
  sdram_bus #(.FREQ(1_000_000)) dut (.clk(clk), .clk_sdram(clk), .reset_n(rst_n), .sel(sel), .addr(addr),
    .wstrb(wstrb), .wdata(wdata), .ready(ready), .rdata(rdata), .dma_sel(1'b0), .dma_addr(23'd0),
    .dma_wstrb(4'd0), .dma_wdata(32'd0), .SDRAM_DQ(dq));
  reg [7:0] model [0:4095];
  integer i, j, errors = 0, seed = 3; reg [31:0] r, exp; reg [3:0] m;
  task bus(input [22:0] a, input [3:0] ws, input [31:0] d, output [31:0] q);
    begin @(negedge clk); sel = 1; addr = a; wstrb = ws; wdata = d;
      @(posedge clk); while (!ready) @(posedge clk); q = rdata; #1 sel = 0; wstrb = 0; end
  endtask
  initial begin
    for (i = 0; i < 4096; i = i + 1) begin model[i] = 0; dut.ctl.mem[i] = 0; end
    #20 rst_n = 1;
    for (i = 0; i < 20000; i = i + 1) begin
      addr = ($random(seed) & 1023) << 2;
      if ($random(seed) & 1) begin
        case ($random(seed) & 3) 0: m = 4'b1111; 1: m = 4'b0001 << ($random(seed) & 3); 2: m = ($random(seed) & 1) ? 4'b1100 : 4'b0011; default: m = $random(seed); endcase
        if (m == 0) m = 4'b1000;
        r = $random(seed);
        bus(addr, m, r, exp);
        for (j = 0; j < 4; j = j + 1) if (m[j]) model[addr + j] = r[8*j +: 8];
      end else begin
        bus(addr, 4'b0000, 0, r);
        exp = {model[addr+3], model[addr+2], model[addr+1], model[addr]};
        if (r !== exp) begin errors = errors + 1; if (errors < 5) $display("read %h: got %h want %h", addr, r, exp); end
      end
    end
    if (errors) $display("SDRAM BUS FAIL (%0d), dropped commands: %0d", errors, dut.ctl.dropped);
    else $display("SDRAM BUS PASS (20000 random ops, refresh active, dropped commands: %0d)", dut.ctl.dropped);
    $finish;
  end
endmodule

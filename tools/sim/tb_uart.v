`timescale 1ns/1ps
module tb;
  reg clk = 0, rst_n = 0;
  always #1 clk = ~clk;
  reg sel = 0; reg [3:0] addr = 0; reg [3:0] wstrb = 0; reg [31:0] di = 0;
  wire [31:0] dout; wire ready; wire line;
  uart_wrap dut (.clk(clk), .reset_n(rst_n), .uart_rx(line), .uart_tx(line),
                 .uart_sel(sel), .addr(addr), .uart_wstrb(wstrb), .uart_di(di),
                 .uart_do(dout), .uart_ready(ready));
  integer errors = 0;
  reg [31:0] r;

  // One bus transaction, picorv32-style: hold valid until ready, one cycle.
  task bus(input [3:0] a, input [3:0] ws, input [31:0] d, output [31:0] q);
    begin
      @(negedge clk); sel = 1; addr = a; wstrb = ws; di = d;
      #0.1; while (!ready) begin @(negedge clk); #0.1; end
      q = dout;
      @(posedge clk); #0.1; sel = 0; wstrb = 0;
    end
  endtask

  integer i, t0, t1;
  initial begin
    #4 rst_n = 1;
    bus(4'h8, 4'hf, 32'd4, r);          // divisor 4 -> expect 6-cycle bits
    repeat (200) @(posedge clk);        // let the post-divisor dummy idle frame pass

    // Bit period: time the start bit of one byte on the line.
    bus(4'hc, 4'h1, 32'h00, r);         // 0x00: start + 8 zero bits = 9 low bits
    @(negedge line); t0 = $time;
    @(posedge line); t1 = $time;
    if ((t1 - t0) != 9 * 6 * 2) begin $display("bit period: low for %0d ns, want %0d", t1 - t0, 9*6*2); errors = errors + 1; end
    bus(4'hc, 4'h0, 0, r);              // drain that byte (after it arrives)

    // 40 bytes through the loopback; the 32-deep TX FIFO backpressures.
    repeat (200) @(posedge clk);
    bus(4'hc, 4'h0, 0, r);
    for (i = 0; i < 40; i = i + 1) bus(4'hc, 4'h1, 8'hA0 + i, r);
    bus(4'h4, 4'h0, 0, r);
    if (r[16]) begin $display("TX idle while bytes queued"); errors = errors + 1; end
    repeat (40 * 10 * 6 + 200) @(posedge clk);
    bus(4'h4, 4'h0, 0, r);
    if (r[6:0] != 40) begin $display("rx count %0d, want 40", r[6:0]); errors = errors + 1; end
    if (r[14:8] != 32) begin $display("tx free %0d, want 32", r[14:8]); errors = errors + 1; end
    if (!r[16]) begin $display("TX not idle after draining"); errors = errors + 1; end
    if (r[17]) begin $display("unexpected overflow"); errors = errors + 1; end
    for (i = 0; i < 40; i = i + 1) begin
      bus(4'hc, 4'h0, 0, r);
      if (r !== 8'hA0 + i) begin $display("byte %0d = %h, want %h", i, r, 8'hA0 + i); errors = errors + 1; end
    end
    bus(4'hc, 4'h0, 0, r);
    if (r !== 32'hffffffff) begin $display("empty read = %h", r); errors = errors + 1; end

    // Overflow: 70 bytes without reading -> 64 kept, overflow flagged, then cleared.
    for (i = 0; i < 70; i = i + 1) bus(4'hc, 4'h1, i, r);
    repeat (70 * 10 * 6 + 200) @(posedge clk);
    bus(4'h4, 4'h0, 0, r);
    if (r[6:0] != 64) begin $display("rx count %0d, want 64", r[6:0]); errors = errors + 1; end
    if (!r[17]) begin $display("overflow not flagged"); errors = errors + 1; end
    bus(4'h4, 4'h0, 0, r);
    if (r[17]) begin $display("overflow not cleared by read"); errors = errors + 1; end
    for (i = 0; i < 64; i = i + 1) begin
      bus(4'hc, 4'h0, 0, r);
      if (r !== i) begin $display("ovf byte %0d = %h", i, r); errors = errors + 1; end
    end

    if (errors) $display("UART FAIL (%0d)", errors); else $display("UART PASS");
    $finish;
  end
endmodule

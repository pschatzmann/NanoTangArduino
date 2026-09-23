`timescale 1ns/1ps
module tb;
  reg clk = 0, rst_n = 0;
  always #1 clk = ~clk;      // 1 cycle = 2ns; timing checked in cycles
  reg sel = 0; reg [3:0] addr = 0; reg we = 0; reg [31:0] wd = 0;
  wire rdy, din; wire [31:0] rd; wire [20:0] ov, val;
  ws2812_strip #(.CLK_FREQ(27000000)) dut (.clk(clk), .reset_n(rst_n), .sel(sel), .addr(addr), .we(we),
    .wdata(wd), .ready(rdy), .rdata(rd), .to_din(din), .gpio_override(ov), .gpio_value(val));
  integer errors = 0;
  reg [31:0] q;
  task bus(input [3:0] a, input w, input [31:0] d, output [31:0] r);
    begin @(negedge clk); sel = 1; addr = a; we = w; wd = d; #0.1;
      while (!rdy) begin @(negedge clk); #0.1; end
      r = rd; @(posedge clk); #0.1; sel = 0; we = 0; end
  endtask

  // Line decoder, counting cycles.
  integer cyc = 0; always @(posedge clk) cyc = cyc + 1;
  integer rise, fall, nbits = 0, maxlow = 0, lowstart = 0, badtiming = 0;
  reg [71:0] got = 0;
  always @(posedge din) begin
    rise = cyc;
    if (nbits > 0 && nbits < 72 && rise - lowstart > maxlow) maxlow = rise - lowstart;
  end
  always @(negedge din) if (rst_n) begin
    fall = cyc; lowstart = cyc;
    if (fall - rise == 22) got = {got[70:0], 1'b1};
    else if (fall - rise == 11) got = {got[70:0], 1'b0};
    else begin badtiming = badtiming + 1; $display("high time %0d at bit %0d (cyc %0d)", fall - rise, nbits, cyc); end
    nbits = nbits + 1;
  end
  // Bit period: rise-to-rise must be 34 cycles within the frame.
  integer lastrise = -1;
  always @(posedge din) begin
    if (lastrise >= 0 && nbits < 72 && cyc - lastrise != 34) begin
      $display("bit %0d period %0d", nbits, cyc - lastrise); badtiming = badtiming + 1; end
    lastrise = cyc;
  end

  initial begin
    #4 rst_n = 1;
    bus(4'h4, 1, {25'b0, 1'b0, 1'b1, 5'd7}, q);    // route to GPIO7
    bus(4'h0, 1, 24'hFF0081, q);
    bus(4'h0, 1, 24'h00AA55, q);
    bus(4'h0, 1, 24'h123456, q);
    bus(4'h0, 0, 0, q); if (!q[0]) begin $display("not busy mid-frame"); errors = errors + 1; end
    if (ov !== 21'd1 << 7) begin $display("override %b", ov); errors = errors + 1; end
    wait (nbits == 72);
    repeat (5000) @(posedge clk);
    bus(4'h0, 0, 0, q); if (!q[0]) begin $display("not busy during latch"); errors = errors + 1; end
    repeat (8200) @(posedge clk);  // 302us = 8154 cycles at 27MHz
    bus(4'h0, 0, 0, q); if (q[0]) begin $display("still busy after latch"); errors = errors + 1; end
    if (got !== 72'hFF0081_00AA55_123456) begin $display("got %h", got); errors = errors + 1; end
    if (badtiming) begin $display("%0d timing errors", badtiming); errors = errors + 1; end
    if (maxlow > 34) begin $display("gap inside frame: %0d cycles low", maxlow); errors = errors + 1; end
    if (errors) $display("WS2812 FAIL"); else $display("WS2812 PASS (72 bits, no gaps, latched)");
    $finish;
  end
endmodule

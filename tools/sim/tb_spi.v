`timescale 1ns/1ps
module tb;
  reg clk = 0, rst_n = 0;
  always #1 clk = ~clk;
  reg sel = 0; reg [3:0] addr = 0; reg [3:0] wstrb = 0; reg [31:0] wd = 0;
  wire rdy, sclk, mosi, cs_n; wire [31:0] rd;
  reg miso = 0;
  spi_master dut (.clk(clk), .reset_n(rst_n), .spi_sel(sel), .addr(addr), .wstrb(wstrb), .wdata(wd),
    .spi_ready(rdy), .spi_rdata(rd), .spi_sclk(sclk), .spi_mosi(mosi), .spi_miso(miso), .spi_cs_n(cs_n));

  // Spec-following slave: CPHA=0 samples on the leading edge and shifts on
  // the trailing one (first bit valid when CS falls); CPHA=1 shifts on the
  // leading edge and samples on the trailing one.
  reg cpol = 0, cpha = 0, lsb = 0;
  reg [7:0] s_tx, s_rx; integer s_n;
  function [7:0] outbit; input [7:0] v; input integer i; outbit = lsb ? v[i] : v[7 - i]; endfunction
  always @(negedge cs_n) begin s_n = 0; s_rx = 0; s_tx = 8'h5A; if (!cpha) miso = outbit(s_tx, 0); end
  always @(sclk) if (!cs_n) begin
    if (sclk != cpol) begin // leading edge
      if (!cpha) begin if (lsb) s_rx = {mosi, s_rx[7:1]}; else s_rx = {s_rx[6:0], mosi}; s_n = s_n + 1; end
      else miso = outbit(s_tx, s_n);
    end else begin          // trailing edge
      if (cpha) begin if (lsb) s_rx = {mosi, s_rx[7:1]}; else s_rx = {s_rx[6:0], mosi}; s_n = s_n + 1; end
      else if (s_n < 8) miso = outbit(s_tx, s_n);
    end
  end

  reg [31:0] q; integer errors = 0, m, l, edges;
  always @(sclk) edges = edges + 1;
  task bus(input [3:0] a, input [3:0] ws, input [31:0] d, output [31:0] r);
    begin @(negedge clk); sel = 1; addr = a; wstrb = ws; wd = d; #0.1;
      while (!rdy) begin @(negedge clk); #0.1; end
      r = rd; @(posedge clk); #0.1; sel = 0; wstrb = 0; end
  endtask
  initial begin
    #4 rst_n = 1;
    bus(4'h0, 4'hf, 3, q);
    for (m = 0; m < 4; m = m + 1) for (l = 0; l < 2; l = l + 1) begin
      cpha = m[0]; cpol = m[1]; lsb = l;
      bus(4'hc, 4'hf, {29'b0, lsb, cpol, cpha}, q);
      #10; if (sclk !== cpol) begin $display("mode %0d: idle sclk %b", m, sclk); errors = errors + 1; end
      bus(4'h4, 4'hf, 1, q); edges = 0;
      bus(4'h8, 4'hf, 8'hC3, q); bus(4'h8, 4'h0, 0, q);
      if (edges != 16) begin $display("mode %0d lsb %0d: %0d clock edges", m, l, edges); errors = errors + 1; end
      if (q[7:0] !== 8'h5A) begin $display("mode %0d lsb %0d: master got %h", m, l, q[7:0]); errors = errors + 1; end
      if (s_rx !== 8'hC3) begin $display("mode %0d lsb %0d: slave got %h", m, l, s_rx); errors = errors + 1; end
      bus(4'h4, 4'hf, 0, q);
    end
    if (errors) $display("SPI FAIL"); else $display("SPI PASS (4 modes x MSB/LSB)");
    $finish;
  end
endmodule

`timescale 1ns/1ps
module tb;
  reg clk = 0, rst_n = 0;
  always #1 clk = ~clk;
  reg sel = 0, asel = 0, lsel = 0; reg [4:0] addr = 0; reg [3:0] wstrb = 0; reg [31:0] wd = 0;
  wire [31:0] rd, lrd; wire rdy, lrdy;
  wire [7:0] pins;
  pullup p[7:0] (pins);  // like the .cst's PULL_MODE=UP
  gpio_bank #(.WIDTH(8)) g (.clk(clk), .reset_n(rst_n), .sel(sel), .atomic_sel(asel), .addr(addr),
    .wstrb(wstrb), .wdata(wd), .ready(rdy), .rdata(rd), .override(8'h0), .override_value(8'h0), .gpio(pins));
  tang_leds l (.clk(clk), .reset_n(rst_n), .leds_sel(lsel), .addr(addr), .leds_data_i(wd[5:0]), .we(wstrb[0]),
    .leds_ready(lrdy), .leds_data_o(lrd));
  integer errors = 0;
  task w(input s, input a, input ls, input [4:0] ad, input [31:0] d);
    begin @(negedge clk); sel = s; asel = a; lsel = ls; addr = ad; wstrb = 4'hf; wd = d;
      @(negedge clk); sel = 0; asel = 0; lsel = 0; wstrb = 0; end
  endtask
  task chk(input s, input a, input ls, input [4:0] ad, input [31:0] want, input [8*16-1:0] what);
    begin @(negedge clk); sel = s; asel = a; lsel = ls; addr = ad; #0.1;
      if ((ls ? lrd : rd) !== want) begin $display("%0s = %h, want %h", what, ls ? lrd : rd, want); errors = errors + 1; end
      @(negedge clk); sel = 0; asel = 0; lsel = 0; end
  endtask
  initial begin
    #4 rst_n = 1;
    w(1,0,0, 5'h04, 32'h0F);           // OUT = 0F
    w(0,1,0, 5'h00, 32'h30);           // OUT_SET 30  -> 3F
    w(0,1,0, 5'h04, 32'h03);           // OUT_CLR 03  -> 3C
    w(0,1,0, 5'h08, 32'hFF);           // OUT_TGL FF  -> C3
    chk(1,0,0, 5'h04, 32'hC3, "out");
    w(0,1,0, 5'h10, 32'h81);           // DIR_SET 81
    w(0,1,0, 5'h14, 32'h01);           // DIR_CLR 01 -> 80
    chk(1,0,0, 5'h00, 32'h80, "dir");
    chk(0,1,0, 5'h10, 32'h80, "dir via atomic");
    chk(1,0,0, 5'h08, 32'hFF, "in (pin7 drives 1, rest pulled up)");
    w(0,1,0, 5'h04, 32'h80);           // OUT_CLR bit7 -> pin 7 low
    chk(1,0,0, 5'h08, 32'h7F, "in after clr");
    w(0,0,1, 5'h00, 32'h05);           // LED = 05
    w(0,0,1, 5'h10, 32'h02);           // SET -> 07
    w(0,0,1, 5'h14, 32'h01);           // CLR -> 06
    w(0,0,1, 5'h18, 32'h21);           // TGL -> 27
    chk(0,0,1, 5'h00, 32'h27, "leds");
    if (errors) $display("GPIO FAIL"); else $display("GPIO PASS");
    $finish;
  end
endmodule

`timescale 1ns/1ps
module tb;
  reg clk = 0, rst_n = 0;
  always #1 clk = ~clk;
  reg [3:0] addr = 0;
  wire [31:0] d13, d27;
  systick #(.CLK_FREQ(13500000)) s13 (.clk(clk), .reset_n(rst_n), .systick_sel(1'b1), .addr(addr), .systick_ready(), .systick_data_o(d13));
  systick #(.CLK_FREQ(27000000)) s27 (.clk(clk), .reset_n(rst_n), .systick_sel(1'b1), .addr(addr), .systick_ready(), .systick_data_o(d27));
  integer errors = 0;
  initial begin
    #4 rst_n = 1;
    // 2,700,000 cycles = 200ms at 13.5MHz, 100ms at 27MHz
    repeat (2700000) @(posedge clk);
    #0.1;
    addr = 4'h0; #0.1 if (d13 !== 2700000) begin $display("cycles %0d", d13); errors = errors + 1; end
    addr = 4'h4; #0.1 if (d13 !== 200000 || d27 !== 100000) begin $display("micros13 %0d micros27 %0d", d13, d27); errors = errors + 1; end
    addr = 4'h8; #0.1 if (d13 !== 200 || d27 !== 100) begin $display("millis13 %0d millis27 %0d", d13, d27); errors = errors + 1; end
    if (errors) $display("SYSTICK FAIL"); else $display("SYSTICK PASS");
    $finish;
  end
endmodule

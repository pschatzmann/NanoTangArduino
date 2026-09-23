// Stand-in for gateware/src/sdram.v, for tb_sdram_bus.v: byte writes,
// 32-bit reads, a few cycles busy per command - and, like the real
// controller, a command arriving while it's busy is dropped. (The real
// sdram.v needs the SiP SDRAM chip's pins; this keeps the adapter test
// self-contained.)
module sdram #(parameter FREQ = 27000000) (
  inout [31:0] SDRAM_DQ, output [10:0] SDRAM_A, output [1:0] SDRAM_BA, output SDRAM_nCS, SDRAM_nWE,
  SDRAM_nRAS, SDRAM_nCAS, SDRAM_CLK, SDRAM_CKE, output [3:0] SDRAM_DQM,
  input clk, clk_sdram, resetn, rd, wr, refresh, input [22:0] addr, input [7:0] din,
  output [7:0] dout, output reg [31:0] dout32, output reg data_ready, output reg busy);
  reg [7:0] mem [0:4095];
  integer cnt = 0, dropped = 0;
  always @(posedge clk) begin
    data_ready <= 0;
    if (!resetn) begin busy <= 0; cnt <= 0; end
    else if (busy) begin
      if (rd | wr) dropped = dropped + 1;
      if (cnt == 0) busy <= 0; else cnt <= cnt - 1;
    end else if (rd) begin
      dout32 <= {mem[{addr[11:2],2'd3}], mem[{addr[11:2],2'd2}], mem[{addr[11:2],2'd1}], mem[{addr[11:2],2'd0}]};
      data_ready <= 1; busy <= 1; cnt <= 4;
    end else if (wr) begin mem[addr[11:0]] <= din; busy <= 1; cnt <= 4; end
    else if (refresh) begin busy <= 1; cnt <= 7; end
  end
endmodule

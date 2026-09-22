/* New for the Arduino core: a WIDTH-bit general-purpose push-pull GPIO
 * bank for the Tang Nano 20K's J5/J6 expansion header pins (the ones the
 * official datasheet counts among its "34 free IOs" and that aren't
 * already claimed by another peripheral in this SoC - see docs/PERIPHERALS.md
 * "General GPIO").
 *
 * Register interface: one direction register (1=output, default 0=input
 * at reset), one output register (driven value when that bit's direction
 * is output), and one read-only input register (actual pin level,
 * readable regardless of direction).
 *
 * `override`/`override_value` let another peripheral take over a pin
 * without software touching dir/out: while override[i] is set, pin i is
 * an output driving override_value[i] (used by pwm_bank.v's GPIO PWM
 * pool for analogWrite()). The registers themselves are unaffected.
 */

module gpio_bank
  #(
    parameter WIDTH = 22
    )
  (
   input wire              clk,
   input wire              reset_n,

   input wire              sel,
   input wire [3:0]        addr,
   input wire [3:0]        wstrb,
   input wire [31:0]       wdata,
   output wire             ready,
   output wire [31:0]      rdata,

   input wire [WIDTH-1:0]  override,
   input wire [WIDTH-1:0]  override_value,

   inout wire [WIDTH-1:0]  gpio
   );

   wire we = |wstrb;
   wire dir_sel = sel && (addr == 4'h0);
   wire out_sel = sel && (addr == 4'h4);
   wire in_sel  = sel && (addr == 4'h8);

   reg [WIDTH-1:0] dir = {WIDTH{1'b0}};
   reg [WIDTH-1:0] out = {WIDTH{1'b0}};

   assign ready = sel;
   assign rdata = dir_sel ? {{(32 - WIDTH){1'b0}}, dir} :
                  out_sel ? {{(32 - WIDTH){1'b0}}, out} :
                  in_sel  ? {{(32 - WIDTH){1'b0}}, gpio} : 32'h0;

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       dir <= {WIDTH{1'b0}};
       out <= {WIDTH{1'b0}};
     end else begin
       if (dir_sel && we)
         dir <= wdata[WIDTH-1:0];
       if (out_sel && we)
         out <= wdata[WIDTH-1:0];
     end

   genvar i;
   generate
     for (i = 0; i < WIDTH; i = i + 1) begin : bit
       assign gpio[i] = override[i] ? override_value[i] :
                        dir[i] ? out[i] : 1'bz;
     end
   endgenerate

endmodule // gpio_bank

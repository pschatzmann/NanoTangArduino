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
 * A second, write-only window (`atomic_sel`) changes individual bits in
 * a single bus write, so an interrupt handler touching one pin can never
 * clobber a concurrent read-modify-write of another pin from loop():
 *   0x00 OUT_SET, 0x04 OUT_CLR, 0x08 OUT_TOGGLE (1 bits act, 0 bits
 *   untouched), 0x10 DIR_SET, 0x14 DIR_CLR. Reads return OUT (0x0x) or
 *   DIR (0x1x).
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
   input wire              atomic_sel,
   input wire [4:0]        addr,
   input wire [3:0]        wstrb,
   input wire [31:0]       wdata,
   output wire             ready,
   output wire [31:0]      rdata,

   input wire [WIDTH-1:0]  override,
   input wire [WIDTH-1:0]  override_value,

   inout wire [WIDTH-1:0]  gpio
   );

   wire we = |wstrb;
   wire dir_sel = sel && (addr == 5'h00);
   wire out_sel = sel && (addr == 5'h04);
   wire in_sel  = sel && (addr == 5'h08);

   wire set_sel     = atomic_sel && we && (addr == 5'h00);
   wire clr_sel     = atomic_sel && we && (addr == 5'h04);
   wire tgl_sel     = atomic_sel && we && (addr == 5'h08);
   wire dir_set_sel = atomic_sel && we && (addr == 5'h10);
   wire dir_clr_sel = atomic_sel && we && (addr == 5'h14);

   reg [WIDTH-1:0] dir = {WIDTH{1'b0}};
   reg [WIDTH-1:0] out = {WIDTH{1'b0}};

   assign ready = sel | atomic_sel;
   assign rdata = (atomic_sel && addr[4])  ? {{(32 - WIDTH){1'b0}}, dir} :
                  (atomic_sel && !addr[4]) ? {{(32 - WIDTH){1'b0}}, out} :
                  dir_sel ? {{(32 - WIDTH){1'b0}}, dir} :
                  out_sel ? {{(32 - WIDTH){1'b0}}, out} :
                  in_sel  ? {{(32 - WIDTH){1'b0}}, gpio} : 32'h0;

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
       dir <= {WIDTH{1'b0}};
       out <= {WIDTH{1'b0}};
     end else begin
       if (dir_sel && we)
         dir <= wdata[WIDTH-1:0];
       else if (dir_set_sel)
         dir <= dir | wdata[WIDTH-1:0];
       else if (dir_clr_sel)
         dir <= dir & ~wdata[WIDTH-1:0];

       if (out_sel && we)
         out <= wdata[WIDTH-1:0];
       else if (set_sel)
         out <= out | wdata[WIDTH-1:0];
       else if (clr_sel)
         out <= out & ~wdata[WIDTH-1:0];
       else if (tgl_sel)
         out <= out ^ wdata[WIDTH-1:0];
     end

   genvar i;
   generate
     for (i = 0; i < WIDTH; i = i + 1) begin : bit
       /* Canonical `enable ? data : 1'bz` form, one per pin: yosys 0.33
        * only turns that into a bidirectional IOBUF. The nested
        * `override ? v : dir ? out : 1'bz` this used to be came out as a
        * plain output buffer - the pin could never be read as an input
        * (found on real hardware: pull-ups and inputs read 0, while
        * reading back a pin's own output still worked). */
       wire oe = override[i] | dir[i];
       wire od = override[i] ? override_value[i] : out[i];
       assign gpio[i] = oe ? od : 1'bz;
     end
   endgenerate

endmodule // gpio_bank

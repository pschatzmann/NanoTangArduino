// External pin-change interrupt source for Arduino attachInterrupt().
// Watches the 21 expansion GPIO inputs plus the KEY_S2 button (bit 21) for
// any level change, latching a sticky per-bit "changed" flag and driving
// picorv32's irq[3] (see top.v) whenever any watched, enabled bit has
// changed since the last STATUS read. Direction (RISING/FALLING/CHANGE) is
// classified in software (wiring_irq.cpp) by comparing LEVEL against the
// previously-seen level it keeps per pin - the hardware only needs to
// report "something enabled changed" cheaply and edge-trigger reliably
// without missing a pulse between software polls.
//
// Registers (word accesses only):
//   ENABLE  (r/w) - bit i = 1: watch input bit i for changes
//   STATUS  (r, read-clears) - bit i = 1: input bit i changed since last read
//   LEVEL   (r)   - live level of all watched inputs, for edge classification
module extirq
  #(parameter WIDTH = 22)
   (
    input wire              clk,
    input wire              reset_n,
    input wire [WIDTH-1:0]  level_in,

    input wire              enable_sel,
    input wire              status_sel,
    input wire              level_sel,
    input wire              we,
    input wire [31:0]       wdata,

    output reg              ready,
    output reg [31:0]       rdata,

    output wire             irq_out
    );

   reg [WIDTH-1:0] enable_mask;
   reg [WIDTH-1:0] prev_level;
   reg [WIDTH-1:0] pending;

   wire [WIDTH-1:0] changed_now = (level_in ^ prev_level) & enable_mask;

   assign irq_out = |pending;

   always @(posedge clk) begin
      ready <= 1'b0;
      rdata <= 32'h0;

      if (!reset_n) begin
         enable_mask <= {WIDTH{1'b0}};
         prev_level  <= level_in;
         pending     <= {WIDTH{1'b0}};
      end else begin
         prev_level <= level_in;
         pending    <= (pending | changed_now);

         if (enable_sel) begin
            ready <= 1'b1;
            if (we)
              enable_mask <= wdata[WIDTH-1:0];
            else
              rdata <= {{(32-WIDTH){1'b0}}, enable_mask};
         end else if (status_sel) begin
            ready <= 1'b1;
            rdata <= {{(32-WIDTH){1'b0}}, pending};
            if (!we)
              pending <= changed_now; // clear old flags, keep this-cycle's
         end else if (level_sel) begin
            ready <= 1'b1;
            rdata <= {{(32-WIDTH){1'b0}}, level_in};
         end
      end
   end
endmodule

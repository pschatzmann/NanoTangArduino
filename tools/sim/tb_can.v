`timescale 1ps/1ps
/* Test bench for gateware/src/can_ctrl.v: three controllers on one
 * wired-AND bus (node B's clock runs 0.5% slow, so resynchronization is
 * exercised), plus a plain injector that replays reference bitstreams
 * from gen_can_ref.py (an independent encoder) and a monitor that checks
 * what a controller transmits against the same references. 1 Mbit/s,
 * 27 clocks per bit at 27MHz. */

module node #(parameter PERIOD = 37037) (input wire bus, output wire tx);
   reg clk = 0, rst_n = 0;
   always #(PERIOD / 2) clk = ~clk;
   initial #(PERIOD * 3) rst_n = 1;

   reg sel = 0; reg [4:0] addr = 0; reg [3:0] wstrb = 0; reg [31:0] wdata = 0;
   wire ready, irq; wire [31:0] rdata; wire [20:0] ov, val;
   can_ctrl dut (.clk(clk), .reset_n(rst_n), .sel(sel), .addr(addr), .wstrb(wstrb),
                 .wdata(wdata), .ready(ready), .rdata(rdata),
                 .gpio_in({21{bus}}), .gpio_override(ov), .gpio_value(val), .irq(irq));
   assign tx = ov[18] ? val[18] : 1'b1;

   task wr(input [4:0] a, input [31:0] d);
      begin @(negedge clk); sel = 1; addr = a; wstrb = 4'hf; wdata = d;
         @(negedge clk); sel = 0; wstrb = 0; end
   endtask
   task rd(input [4:0] a, output [31:0] d);
      begin @(negedge clk); sel = 1; addr = a; wstrb = 0; #1 d = rdata;
         @(negedge clk); sel = 0; end
   endtask
   // 1 Mbit/s at 27MHz: BRP 1, TSEG1 21, TSEG2 5, SJW 4 -> 27 tq/bit.
   task start(input loopback);
      begin wr(5'h04, {6'd0, 2'd3, 4'd0, 4'd4, 3'd0, 5'd20, 8'd0});
         wr(5'h00, {11'd0, 5'd11, 3'd0, 5'd18, 5'd0, 1'b1, loopback, 1'b1}); end
   endtask
   task stop; wr(5'h00, 32'd0); endtask
   task send(input ext, input [28:0] id, input [3:0] dlc, input [63:0] data);
      begin // data: byte 0 in bits [63:56]
         wr(5'h08, {ext, 2'b0, id});
         wr(5'h0c, {data[39:32], data[47:40], data[55:48], data[63:56]});
         wr(5'h10, {data[7:0], data[15:8], data[23:16], data[31:24]});
         wr(5'h14, {23'd0, 1'b1, 4'd0, dlc});
      end
   endtask
   task recv(output [31:0] id, output [3:0] dlc, output [63:0] data);
      reg [31:0] d0, d1, x;
      begin rd(5'h08, id); rd(5'h0c, d0); rd(5'h10, d1); rd(5'h14, x); dlc = x[3:0];
         data = {d0[7:0], d0[15:8], d0[23:16], d0[31:24], d1[7:0], d1[15:8], d1[23:16], d1[31:24]};
         wr(5'h18, 0); end
   endtask
endmodule

module tb;
   localparam BIT = 1000000; // 1us in ps

   reg inj = 1;        // injector output
   reg stuck = 1;      // forces the bus dominant when 0
   wire txa, txb, txc;
   wire bus = txa & txb & txc & inj & stuck;

   node #(37037) A (.bus(bus), .tx(txa));
   node #(37222) B (.bus(bus), .tx(txb)); // 0.5% slow
   node #(37037) C (.bus(bus), .tx(txc));

   reg [199:0] ref_bits [0:7];
   integer ref_len [0:7], ref_stuffed [0:7];
   `include "can_ref.vh"

   reg [31:0] id, st, ec; reg [3:0] dlc; reg [63:0] data; reg acked;
   integer errors = 0;
   task check(input cond, input [8*64-1:0] what);
      if (!cond) begin $display("FAIL: %0s (id=%h dlc=%0d data=%h st=%h ec=%h t=%0t)", what, id, dlc, data, st, ec, $time); errors = errors + 1; end
   endtask

   // Waits until the bus has been recessive for 11 bit times.
   task wait_idle;
      integer quiet;
      begin quiet = 0;
         while (quiet < 11) begin #(BIT); if (bus) quiet = quiet + 1; else quiet = 0; end
      end
   endtask

   // Replays reference frame r; returns whether the ACK slot was dominant.
   task inject(input integer r, output acked);
      integer k;
      begin acked = 0;
         for (k = 0; k < ref_len[r]; k = k + 1) begin
            inj = ref_bits[r][ref_len[r] - 1 - k];
            if (k == ref_stuffed[r] + 1) begin #(BIT * 7 / 10); acked = !bus; #(BIT * 3 / 10); end
            else #(BIT);
         end
         inj = 1;
      end
   endtask

   // Samples the next frame on the bus at 80% of each bit and compares it
   // with reference r from SOF through the CRC delimiter.
   task expect_tx(input integer r, input [8*32-1:0] what);
      integer k, bad;
      begin bad = 0;
         @(negedge bus);
         #(BIT * 8 / 10);
         for (k = 0; k <= ref_stuffed[r]; k = k + 1) begin
            if (bus !== ref_bits[r][ref_len[r] - 1 - k] && bad == 0) begin
               $display("  %0s: bit %0d is %b, reference %b", what, k, bus, ref_bits[r][ref_len[r] - 1 - k]);
               bad = 1;
            end
            #(BIT);
         end
         check(!bad, what);
      end
   endtask

   integer i;

   initial begin
      load_refs;
      #(BIT);
      A.start(0); B.start(0); C.start(0);
      wait_idle;

      // 1. Standard frame A -> B, C; bitstream must match the reference.
      fork
         A.send(0, 29'h123, 8, 64'h1122334455667788);
         expect_tx(REF_STD_123, "A's STD_123 bitstream");
      join
      wait_idle;
      A.rd(5'h00, st); check(st[5] && !st[0], "A: TX succeeded");
      B.recv(id, dlc, data);
      check(id == 32'h123 && dlc == 8 && data == 64'h1122334455667788, "B received STD_123");
      C.recv(id, dlc, data); check(id == 32'h123, "C received STD_123");

      // 2. Extended frame from B (slow clock) -> A.
      fork
         B.send(1, 29'h1ABCDEF5, 3, 64'hA55AFF0000000000);
         expect_tx(REF_EXT_1ABCDEF5, "B's EXT_1ABCDEF5 bitstream");
      join
      wait_idle;
      A.recv(id, dlc, data);
      check(id == {1'b1, 2'b0, 29'h1ABCDEF5} && dlc == 3 && data[63:40] == 24'hA55AFF, "A received EXT from B");
      C.recv(id, dlc, data);

      // 3. Reference frames from the injector, received by all three.
      inject(REF_STD_000, acked); check(acked, "STD_000 acknowledged"); wait_idle;
      A.recv(id, dlc, data); check(id == 0 && dlc == 0, "A received STD_000");
      B.recv(id, dlc, data); C.recv(id, dlc, data);
      inject(REF_EXT_RTR_1, acked); check(acked, "EXT_RTR_1 acknowledged"); wait_idle;
      B.recv(id, dlc, data); check(id == {1'b1, 1'b1, 1'b0, 29'd1} && dlc == 2, "B received remote frame");
      A.recv(id, dlc, data); C.recv(id, dlc, data);
      inject(REF_STD_555, acked); check(acked, "STD_555 acknowledged"); wait_idle;
      C.recv(id, dlc, data); check(id == 32'h555 && dlc == 5 && data[63:24] == 40'h00FF00FF0F, "C received STD_555");
      A.recv(id, dlc, data); B.recv(id, dlc, data);

      // 4. Corrupted CRC: nobody may accept it; receivers count an error.
      inject(REF_STD_555_BAD, acked); check(!acked, "bad-CRC frame not acknowledged");
      wait_idle;
      A.rd(5'h00, st); check(!st[1], "A dropped the bad-CRC frame");
      A.rd(5'h18, ec); check(ec[15:8] == 1, "A's REC counted the CRC error");

      // 5. Arbitration: A (0x100) and B (0x0FF) queue frames while C's
      //    frame is on the bus, so both start right after it; B wins, A
      //    retries automatically. C sees both, B's first.
      C.send(0, 29'h300, 8, 64'h0102030405060708);
      @(negedge bus); #(BIT * 20);
      A.send(0, 29'h100, 1, 64'hAA00000000000000);
      B.send(0, 29'h0FF, 1, 64'hBB00000000000000);
      wait_idle; wait_idle; wait_idle;
      C.recv(id, dlc, data); check(id == 32'h0FF && data[63:56] == 8'hBB, "C: arbitration winner first");
      C.recv(id, dlc, data); check(id == 32'h100 && data[63:56] == 8'hAA, "C: loser retried second");
      A.rd(5'h00, st); check(!st[0], "A's retry completed");
      A.recv(id, dlc, data); check(id == 32'h300, "A received C's frame");
      A.recv(id, dlc, data); check(id == 32'h0FF, "A received the winner");
      B.recv(id, dlc, data); B.recv(id, dlc, data); check(id == 32'h100, "B received the loser's retry");

      // 6. Alone on the bus: no ACK -> error frames; TEC climbs to error
      //    passive and stays there (ACK errors while passive don't count).
      B.stop; C.stop;
      A.send(0, 29'h042, 0, 0);
      for (i = 0; i < 40; i = i + 1) #(BIT * 40);
      A.rd(5'h00, st); check(st[0] && st[3] && !st[4], "A pending, error passive, not bus off");
      A.rd(5'h18, ec); check(ec[7:0] >= 128 && ec[7:0] < 140, "A's TEC stopped at error passive");
      B.start(0);
      wait_idle; wait_idle; wait_idle;
      A.rd(5'h00, st); check(!st[0], "A's frame went out once B acknowledged");
      A.rd(5'h18, ec); check(ec[7:0] < 128, "A left error passive");
      B.recv(id, dlc, data); check(id == 32'h042, "B received A's retried frame");
      C.start(0);

      // 7. Bit errors while transmitting -> bus off; recovery after
      //    128 x 11 recessive bits.
      B.stop; C.stop;
      A.stop; A.start(0); wait_idle;
      A.send(0, 29'h001, 0, 0);
      @(negedge bus); #(BIT * 3);     // Into the ID field...
      stuck = 0; #(BIT * 400); stuck = 1; // ...hold the bus dominant.
      A.rd(5'h00, st); check(st[4], "A went bus off");
      A.wr(5'h14, 32'h200);           // Abort the frame.
      for (i = 0; i < 20; i = i + 1) #(BIT * 100);
      A.rd(5'h00, st); check(!st[4], "A recovered from bus off");
      A.rd(5'h18, ec); check(ec[7:0] == 0, "A's TEC reset after recovery");

      // 8. Loopback: A alone, bus untouched, receives its own frame.
      A.stop; A.start(1);
      for (i = 0; i < 20; i = i + 1) #(BIT);
      A.send(1, 29'h0ABCDEF, 2, 64'h1234000000000000);
      for (i = 0; i < 200; i = i + 1) #(BIT);
      A.rd(5'h00, st); check(st[5] && st[1], "loopback: sent and received");
      A.recv(id, dlc, data); check(id == {1'b1, 2'b0, 29'h0ABCDEF} && data[63:48] == 16'h1234, "loopback frame content");
      check(bus === 1'b1, "loopback leaves the bus recessive");

      if (errors) $display("CAN FAIL (%0d)", errors);
      else $display("CAN PASS (bitstreams, ext/std/remote, arbitration, CRC/ACK/bit errors, bus-off recovery, loopback)");
      $finish;
   end

   // Timeout: 60ms of bus time (a loop, since 60000 * BIT overflows 32 bits).
   initial begin repeat (60000) #(BIT); $display("CAN FAIL (timeout)"); $finish; end
endmodule

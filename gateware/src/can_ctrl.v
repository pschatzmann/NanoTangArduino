/* New for the Arduino core: a compact CAN 2.0A/B controller (Tools >
 * CAN only - see top.v's `ifdef WITH_CAN and libraries/CAN).
 *
 * Covers standard (11-bit) and extended (29-bit) data frames, receiving
 * remote frames, bit timing with hard and soft resynchronization, bit
 * stuffing, CRC-15, arbitration (losing it turns the node into a
 * receiver and the frame is retried), ACK, bit/stuff/CRC/form/ACK error
 * detection with error frames, the TEC/REC error counters with
 * error-passive and bus-off states, bus-off recovery (128 x 11 recessive
 * bits) and automatic retransmission. Simplifications: overload frames
 * aren't generated, and a dominant bit anywhere in the intermission is
 * taken as a start of frame. It never receives its own frames, except in
 * loopback mode.
 *
 * The TX and RX pins are chosen at run time among the expansion GPIOs
 * (CTRL register), like the WS2812 output, so an external transceiver
 * (e.g. SN65HVD230) can go on any pair. LOOPBACK connects TX to RX
 * internally, leaves the pin recessive and acknowledges its own frames -
 * a self-test that needs no transceiver.
 *
 * Registers (word accesses, offsets from the peripheral base):
 *   0x00 W CTRL    bit0 enable, bit1 loopback, bit2 RX interrupt enable,
 *                  bits[12:8] TX GPIO index, bits[20:16] RX GPIO index
 *        R STATUS  bit0 TX pending, bit1 RX FIFO not empty, bit2 RX
 *                  overflow (sticky, cleared by this read), bit3 error
 *                  passive, bit4 bus off, bit5 last TX succeeded
 *                  (sticky, cleared by this read), bits[11:8] RX count,
 *                  bit31 present (reads 0 when Tools > CAN is disabled)
 *   0x04 RW TIMING bits[7:0] BRP-1 (time quantum = BRP clocks),
 *                  bits[12:8] TSEG1-1 (1-32 tq), bits[19:16] TSEG2-1
 *                  (1-16 tq), bits[25:24] SJW-1 (1-4 tq). A bit is
 *                  1 + TSEG1 + TSEG2 tq, sampled at the end of TSEG1.
 *   0x08 W TX_ID   bits[28:0] ID, bit31 extended
 *        R RX_ID   same, plus bit30 remote frame (FIFO head)
 *   0x0C W TX_DATA0 / R RX_DATA0  data bytes 0-3 (byte 0 in bits[7:0])
 *   0x10 W TX_DATA1 / R RX_DATA1  data bytes 4-7
 *   0x14 W TX_CMD  bits[3:0] DLC, bit8 send, bit9 abort (only takes
 *                  effect while the frame isn't on the bus)
 *        R RX_DLC  bits[3:0] (FIFO head)
 *   0x18 W RX_POP  (any value) drops the FIFO head
 *        R ERRCNT  bits[7:0] TEC (saturating), bits[15:8] REC
 */
module can_ctrl
  #(
    parameter RX_DEPTH_LOG2 = 3, // 8 received frames
    parameter GPIO_WIDTH = 21
    )
  (
   input wire                   clk,
   input wire                   reset_n,
   input wire                   sel,
   input wire [4:0]             addr,
   input wire [3:0]             wstrb,
   input wire [31:0]            wdata,
   output wire                  ready,
   output wire [31:0]           rdata,
   input wire [GPIO_WIDTH-1:0]  gpio_in,
   output wire [GPIO_WIDTH-1:0] gpio_override,
   output wire [GPIO_WIDTH-1:0] gpio_value,
   output wire                  irq
   );

   /* --- Registers ---------------------------------------------------- */

   wire we = |wstrb;
   wire rd = sel && !we;
   wire ctrl_sel   = sel && (addr == 5'h00);
   wire timing_sel = sel && (addr == 5'h04);
   wire id_sel     = sel && (addr == 5'h08);
   wire d0_sel     = sel && (addr == 5'h0c);
   wire d1_sel     = sel && (addr == 5'h10);
   wire cmd_sel    = sel && (addr == 5'h14);
   wire pop_sel    = sel && (addr == 5'h18);

   reg        enable = 1'b0;
   reg        loopback = 1'b0;
   reg        rx_irq_en = 1'b0;
   reg [4:0]  tx_pin = 5'd18;
   reg [4:0]  rx_pin = 5'd11;
   reg [7:0]  brp = 8'd0;
   reg [4:0]  tseg1 = 5'd20; // value-1
   reg [3:0]  tseg2 = 4'd4;  // value-1
   reg [1:0]  sjw = 2'd3;    // value-1

   reg [31:0] tx_id = 32'd0;
   reg [31:0] tx_d0 = 32'd0;
   reg [31:0] tx_d1 = 32'd0;
   reg [3:0]  tx_dlc = 4'd0;
   reg        tx_pending = 1'b0;
   reg        tx_ok_flag = 1'b0;
   reg        rx_ovf_flag = 1'b0;

   /* --- Pins and bus ----------------------------------------------------- */

   reg        tx_out = 1'b1; // What this node drives (1 = recessive).
   wire       pin_rx = gpio_in[rx_pin];
   wire       bus_in = loopback ? tx_out : pin_rx;

   genvar gi;
   generate
     for (gi = 0; gi < GPIO_WIDTH; gi = gi + 1) begin : route
       assign gpio_override[gi] = enable && (tx_pin == gi);
       assign gpio_value[gi] = gpio_override[gi] && (loopback || tx_out);
     end
   endgenerate

   reg [1:0]  rx_sync = 2'b11;
   reg        rx_prev = 1'b1;
   always @(posedge clk) begin
      rx_sync <= {rx_sync[0], bus_in};
      rx_prev <= rx_sync[1];
   end
   wire rx_s = rx_sync[1];
   wire falling = rx_prev && !rx_s;

   /* --- Protocol state (declared early: the bit timing unit needs it) --- */

   localparam P_OFF      = 5'd0,  P_INTEGRATE = 5'd1,  P_IDLE    = 5'd2,
              P_ID_A     = 5'd3,  P_SRR_RTR   = 5'd4,  P_IDE     = 5'd5,
              P_ID_B     = 5'd6,  P_RTR_B     = 5'd7,  P_R1      = 5'd8,
              P_R0       = 5'd9,  P_DLC       = 5'd10, P_DATA    = 5'd11,
              P_CRC      = 5'd12, P_CRC_DEL   = 5'd13, P_ACK     = 5'd14,
              P_ACK_DEL  = 5'd15, P_EOF       = 5'd16, P_IFS     = 5'd17,
              P_ERR_FLAG = 5'd18, P_ERR_DEL   = 5'd19, P_BUSOFF  = 5'd20;

   reg [4:0]  pstate = P_OFF;
   reg        transmitting = 1'b0;
   wire       bus_idle = (pstate == P_IDLE) || (pstate == P_IFS) ||
                         (pstate == P_INTEGRATE);

   /* --- Bit timing: time quanta, segments, resynchronization ---------- */

   localparam SEG_SYNC = 2'd0, SEG_T1 = 2'd1, SEG_T2 = 2'd2;
   reg [1:0]  seg = SEG_SYNC;
   reg [7:0]  pcnt = 8'd0;
   reg [5:0]  tqcnt = 6'd0;
   reg [5:0]  t1_len = 6'd21;
   reg [4:0]  t2_len = 5'd5;
   reg        resynced = 1'b0;
   reg        sample_p = 1'b0;    // one-clock pulse at the sample point
   reg        bitstart_p = 1'b0;  // one-clock pulse at a bit's start
   reg        hard_synced = 1'b0; // pulse: hard sync on a SOF edge

   wire       tq_tick = (pcnt == brp);
   wire [5:0] sjw_tq = {4'd0, sjw} + 6'd1;
   wire [5:0] t1_nom = {1'b0, tseg1} + 6'd1;
   wire [4:0] t2_nom = {1'b0, tseg2} + 5'd1;
   // A node resyncs on recessive-to-dominant edges it didn't cause.
   wire       edge_ok = falling && tx_out;

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
        seg <= SEG_SYNC; pcnt <= 8'd0; tqcnt <= 6'd0;
        t1_len <= 6'd21; t2_len <= 5'd5; resynced <= 1'b0;
        sample_p <= 1'b0; bitstart_p <= 1'b0; hard_synced <= 1'b0;
     end else begin
        sample_p <= 1'b0;
        bitstart_p <= 1'b0;
        hard_synced <= 1'b0;

        if (!enable) begin
           seg <= SEG_SYNC; pcnt <= 8'd0; tqcnt <= 6'd0;
        end else if (edge_ok && bus_idle) begin
           // Hard sync: the edge's quantum is the new bit's SYNC_SEG.
           hard_synced <= 1'b1;
           seg <= SEG_T1; pcnt <= 8'd0; tqcnt <= 6'd0;
           t1_len <= t1_nom; t2_len <= t2_nom; resynced <= 1'b1;
        end else if (edge_ok && !resynced && seg == SEG_T1) begin
           // Edge late: lengthen TSEG1 by the phase error, up to SJW.
           resynced <= 1'b1;
           t1_len <= t1_nom + ((tqcnt + 6'd1 < sjw_tq) ? tqcnt + 6'd1 : sjw_tq);
        end else if (edge_ok && !resynced && seg == SEG_T2 &&
                     ({1'b0, t2_len} - tqcnt) <= sjw_tq) begin
           // Edge early, within SJW: end this bit now; the edge's quantum
           // is the next bit's SYNC_SEG.
           resynced <= 1'b1;
           bitstart_p <= 1'b1;
           seg <= SEG_T1; pcnt <= 8'd0; tqcnt <= 6'd0;
           t1_len <= t1_nom; t2_len <= t2_nom;
        end else if (edge_ok && !resynced && seg == SEG_T2) begin
           // Edge early by more than SJW: shorten TSEG2 by SJW.
           resynced <= 1'b1;
           t2_len <= t2_len - sjw_tq[4:0];
           if (tq_tick) begin
              pcnt <= 8'd0;
              tqcnt <= tqcnt + 6'd1;
           end else begin
              pcnt <= pcnt + 8'd1;
           end
        end else if (tq_tick) begin
           pcnt <= 8'd0;
           case (seg)
             SEG_SYNC: begin
                seg <= SEG_T1; tqcnt <= 6'd0;
             end
             SEG_T1: begin
                if (tqcnt + 6'd1 >= t1_len) begin
                   sample_p <= 1'b1;
                   resynced <= 1'b0; // One resync allowed between samples.
                   seg <= SEG_T2; tqcnt <= 6'd0;
                end else
                  tqcnt <= tqcnt + 6'd1;
             end
             default: begin
                if ({1'b0, tqcnt} + 6'd1 >= {1'b0, t2_len}) begin
                   bitstart_p <= 1'b1;
                   seg <= SEG_SYNC; tqcnt <= 6'd0;
                   t1_len <= t1_nom; t2_len <= t2_nom;
                end else
                  tqcnt <= tqcnt + 6'd1;
             end
           endcase
        end else begin
           pcnt <= pcnt + 8'd1;
        end
     end

   /* --- Frame processing ------------------------------------------------ */

   reg [6:0]  pcnt_bits = 7'd0;  // bit counter within a field
   reg [14:0] crc = 15'd0;
   reg [14:0] crc_calc = 15'd0;  // CRC over SOF..data, latched
   reg [14:0] crc_rx = 15'd0;
   reg        crc_ok = 1'b0;
   reg        stuff_en = 1'b0;
   reg        last_bit = 1'b1;
   reg [2:0]  same_cnt = 3'd0;
   reg [10:0] rx_id_a = 11'd0;
   reg [17:0] rx_id_b = 18'd0;
   reg        rx_srr_rtr = 1'b0;
   reg        rx_ide = 1'b0;
   reg        rx_rtr = 1'b0;
   reg [3:0]  rx_dlc = 4'd0;
   reg [63:0] rx_data = 64'd0;
   reg [8:0]  tec = 9'd0;
   reg [7:0]  rec = 8'd0;
   reg [3:0]  recess_cnt = 4'd0; // consecutive recessive bits
   reg [7:0]  busoff_cnt = 8'd0; // 11-bit recessive sequences seen
   reg        err_flag_passive = 1'b0; // Error flag polarity, fixed when it starts.
   reg        err_was_tx = 1'b0;       // The error happened while transmitting.
   reg [2:0]  dom_cnt = 3'd0;          // Dominant bits seen after the flag.

   wire       err_passive = (tec > 9'd127) || (rec > 8'd127);
   wire [3:0] data_bytes = (rx_dlc > 4'd8) ? 4'd8 : rx_dlc;
   wire       tx_ext = tx_id[31];
   wire [63:0] tx_seq = {tx_d0[7:0], tx_d0[15:8], tx_d0[23:16], tx_d0[31:24],
                         tx_d1[7:0], tx_d1[15:8], tx_d1[23:16], tx_d1[31:24]};
   wire       stuff_now = stuff_en && (same_cnt == 3'd5);

   // Next frame bit this node transmits (when it is the transmitter).
   reg        tx_frame_bit;
   always @(*) begin
      case (pstate)
        P_ID_A:    tx_frame_bit = tx_ext ? tx_id[28 - pcnt_bits] : tx_id[10 - pcnt_bits];
        P_SRR_RTR: tx_frame_bit = tx_ext;  // SRR recessive / RTR dominant
        P_IDE:     tx_frame_bit = tx_ext;
        P_ID_B:    tx_frame_bit = tx_id[17 - pcnt_bits];
        P_RTR_B, P_R1, P_R0: tx_frame_bit = 1'b0;
        P_DLC:     tx_frame_bit = tx_dlc[3 - pcnt_bits];
        P_DATA:    tx_frame_bit = tx_seq[63 - pcnt_bits];
        P_CRC:     tx_frame_bit = crc_calc[14 - pcnt_bits];
        default:   tx_frame_bit = 1'b1;
      endcase
   end

   wire in_arbitration = (pstate == P_ID_A) || (pstate == P_SRR_RTR) ||
                         (pstate == P_IDE) || (pstate == P_ID_B) ||
                         (pstate == P_RTR_B);
   wire can_start_tx = tx_pending && enable && (pstate == P_IDLE);

   // RX FIFO.
   localparam RX_DEPTH = 1 << RX_DEPTH_LOG2;
   reg [98:0] rx_mem [0:RX_DEPTH-1]; // {ext, rtr, id[28:0], dlc, data[63:0]}
   reg [RX_DEPTH_LOG2:0] rx_wr = 0;
   reg [RX_DEPTH_LOG2:0] rx_rd = 0;
   wire [RX_DEPTH_LOG2:0] rx_count = rx_wr - rx_rd;
   wire rx_empty = (rx_count == 0);
   wire rx_full = (rx_count == RX_DEPTH);
   reg  rx_store = 1'b0;
   reg [98:0] rx_entry = 99'd0;
   wire [98:0] rx_head = rx_mem[rx_rd[RX_DEPTH_LOG2-1:0]];

   always @(posedge clk)
     if (rx_store && !rx_full)
       rx_mem[rx_wr[RX_DEPTH_LOG2-1:0]] <= rx_entry;

   task start_error;
      begin
         // Transmitter errors count 8, receiver errors 1 - except an ACK
         // error while error passive, which the standard exempts (so a
         // node alone on the bus stays error passive instead of going
         // bus off).
         if (transmitting) begin
            if (!(pstate == P_ACK && err_passive))
              tec <= tec + 9'd8;
         end else if (rec != 8'd255)
            rec <= rec + 8'd1;
         err_flag_passive <= err_passive;
         err_was_tx <= transmitting;
         dom_cnt <= 3'd0;
         transmitting <= 1'b0;
         stuff_en <= 1'b0;
         pstate <= P_ERR_FLAG;
         pcnt_bits <= 7'd0;
      end
   endtask

   task start_frame;
      begin
         pstate <= P_ID_A;
         pcnt_bits <= 7'd0;
         crc <= 15'd0; // CRC over SOF (a 0 bit) leaves it 0.
         stuff_en <= 1'b1;
         last_bit <= 1'b0;
         same_cnt <= 3'd1;
         rx_data <= 64'd0;
         crc_ok <= 1'b0;
      end
   endtask

   wire [14:0] crc_next = {crc[13:0], 1'b0} ^ ((rx_s ^ crc[14]) ? 15'h4599 : 15'h0);

   always @(posedge clk or negedge reset_n)
     if (!reset_n) begin
        pstate <= P_OFF; transmitting <= 1'b0; tx_out <= 1'b1;
        pcnt_bits <= 7'd0; crc <= 15'd0; crc_calc <= 15'd0; crc_rx <= 15'd0;
        crc_ok <= 1'b0; stuff_en <= 1'b0; last_bit <= 1'b1; same_cnt <= 3'd0;
        tec <= 9'd0; rec <= 8'd0; recess_cnt <= 4'd0; busoff_cnt <= 8'd0;
        err_flag_passive <= 1'b0; err_was_tx <= 1'b0; dom_cnt <= 3'd0; rx_store <= 1'b0;
        rx_id_a <= 11'd0; rx_id_b <= 18'd0; rx_srr_rtr <= 1'b0; rx_ide <= 1'b0;
        rx_rtr <= 1'b0; rx_dlc <= 4'd0; rx_data <= 64'd0;
        enable <= 1'b0; loopback <= 1'b0; rx_irq_en <= 1'b0;
        tx_pin <= 5'd18; rx_pin <= 5'd11;
        brp <= 8'd0; tseg1 <= 5'd20; tseg2 <= 4'd4; sjw <= 2'd3;
        tx_id <= 32'd0; tx_d0 <= 32'd0; tx_d1 <= 32'd0; tx_dlc <= 4'd0;
        tx_pending <= 1'b0; tx_ok_flag <= 1'b0; rx_ovf_flag <= 1'b0;
        rx_wr <= 0; rx_rd <= 0; rx_entry <= 99'd0;
     end else begin
        rx_store <= 1'b0;

        /* CPU side */
        if (ctrl_sel && we) begin
           enable <= wdata[0];
           loopback <= wdata[1];
           rx_irq_en <= wdata[2];
           tx_pin <= wdata[12:8];
           rx_pin <= wdata[20:16];
        end
        if (timing_sel && we) begin
           brp <= wdata[7:0];
           tseg1 <= wdata[12:8];
           tseg2 <= wdata[19:16];
           sjw <= wdata[25:24];
        end
        if (id_sel && we) tx_id <= wdata;
        if (d0_sel && we) tx_d0 <= wdata;
        if (d1_sel && we) tx_d1 <= wdata;
        if (cmd_sel && we) begin
           tx_dlc <= wdata[3:0];
           if (wdata[8])
             tx_pending <= 1'b1;
           if (wdata[9] && !transmitting)
             tx_pending <= 1'b0;
        end
        if (ctrl_sel && rd) begin
           tx_ok_flag <= 1'b0;
           rx_ovf_flag <= 1'b0;
        end
        if (pop_sel && we && !rx_empty)
          rx_rd <= rx_rd + 1'b1;
        if (rx_store) begin
           if (rx_full)
             rx_ovf_flag <= 1'b1;
           else
             rx_wr <= rx_wr + 1'b1;
        end

        /* Bus side */
        if (!enable) begin
           pstate <= P_OFF;
           transmitting <= 1'b0;
           tx_out <= 1'b1;
        end else begin
           if (pstate == P_OFF) begin
              pstate <= P_INTEGRATE;
              recess_cnt <= 4'd0;
           end

           // Someone else's SOF while idle: with a frame pending, join in
           // as a transmitter (that SOF is ours too, arbitration decides).
           // (The SOF bit itself is processed at its sample point.)
           if (hard_synced && (pstate == P_IDLE || pstate == P_IFS)) begin
              transmitting <= tx_pending;
              tx_out <= !tx_pending;
           end

           /* Drive the next bit at the start of each bit */
           if (bitstart_p) begin
              if (can_start_tx) begin
                 tx_out <= 1'b0; // SOF
                 transmitting <= 1'b1;
              end else if (stuff_now) begin
                 tx_out <= transmitting ? !last_bit : 1'b1;
              end else begin
                 case (pstate)
                   P_ACK:      tx_out <= !(transmitting ? loopback : crc_ok);
                   P_ERR_FLAG: tx_out <= (pcnt_bits < 7'd6 && !err_flag_passive) ? 1'b0 : 1'b1;
                   default:    tx_out <= transmitting ? tx_frame_bit : 1'b1;
                 endcase
              end
           end

           /* Evaluate the sampled bit */
           if (sample_p) begin
              recess_cnt <= rx_s ? ((recess_cnt == 4'd15) ? recess_cnt : recess_cnt + 4'd1) : 4'd0;

              if (stuff_now) begin
                 // Stuff bit: must differ from the previous five.
                 if (rx_s == last_bit)
                   start_error;
                 else if (transmitting && rx_s != tx_out)
                   start_error; // Bit error on our own stuff bit.
                 else begin
                    last_bit <= rx_s;
                    same_cnt <= 3'd1;
                 end
              end else if (transmitting && rx_s != tx_out && in_arbitration && tx_out) begin
                 // Sent recessive, saw dominant: lost arbitration.
                 transmitting <= 1'b0;
                 tx_out <= 1'b1;
                 process_bit;
              end else if (transmitting && rx_s != tx_out && pstate != P_ACK &&
                           pstate != P_IDLE) begin
                 start_error; // Bit error.
              end else begin
                 process_bit;
              end
           end
        end
     end


   task process_bit;
      begin
         if (stuff_en) begin
            if (rx_s == last_bit)
              same_cnt <= same_cnt + 3'd1;
            else begin
               last_bit <= rx_s;
               same_cnt <= 3'd1;
            end
         end
         if (pstate >= P_ID_A && pstate <= P_DATA)
           crc <= crc_next;

         case (pstate)
           P_INTEGRATE: begin
              // Join the bus after 11 recessive bits.
              if (rx_s && recess_cnt >= 4'd10)
                pstate <= P_IDLE;
           end
           P_IDLE: begin
              if (!rx_s)
                start_frame;
           end
           P_ID_A: begin
              rx_id_a <= {rx_id_a[9:0], rx_s};
              if (pcnt_bits == 7'd10) begin pstate <= P_SRR_RTR; pcnt_bits <= 7'd0; end
              else pcnt_bits <= pcnt_bits + 7'd1;
           end
           P_SRR_RTR: begin rx_srr_rtr <= rx_s; pstate <= P_IDE; end
           P_IDE: begin
              rx_ide <= rx_s;
              if (rx_s) begin pstate <= P_ID_B; pcnt_bits <= 7'd0; end
              else begin rx_rtr <= rx_srr_rtr; pstate <= P_R0; end
           end
           P_ID_B: begin
              rx_id_b <= {rx_id_b[16:0], rx_s};
              if (pcnt_bits == 7'd17) pstate <= P_RTR_B;
              else pcnt_bits <= pcnt_bits + 7'd1;
           end
           P_RTR_B: begin rx_rtr <= rx_s; pstate <= P_R1; end
           P_R1: pstate <= P_R0;
           P_R0: begin pstate <= P_DLC; pcnt_bits <= 7'd0; end
           P_DLC: begin
              rx_dlc <= {rx_dlc[2:0], rx_s};
              if (pcnt_bits == 7'd3) begin
                 pcnt_bits <= 7'd0;
                 if (rx_rtr || {rx_dlc[2:0], rx_s} == 4'd0) begin
                    pstate <= P_CRC;
                    crc_calc <= crc_next;
                 end else
                   pstate <= P_DATA;
              end else
                pcnt_bits <= pcnt_bits + 7'd1;
           end
           P_DATA: begin
              rx_data[63 - pcnt_bits[5:0]] <= rx_s;
              if (pcnt_bits + 7'd1 == {data_bytes, 3'b000}) begin
                 pstate <= P_CRC;
                 pcnt_bits <= 7'd0;
                 crc_calc <= crc_next;
              end else
                pcnt_bits <= pcnt_bits + 7'd1;
           end
           P_CRC: begin
              crc_rx <= {crc_rx[13:0], rx_s};
              if (pcnt_bits == 7'd14) begin
                 pstate <= P_CRC_DEL;
                 crc_ok <= ({crc_rx[13:0], rx_s} == crc_calc);
              end else
                pcnt_bits <= pcnt_bits + 7'd1;
           end
           P_CRC_DEL: begin
              stuff_en <= 1'b0;
              if (!rx_s) start_error; // Form error.
              else pstate <= P_ACK;
           end
           P_ACK: begin
              if (transmitting && rx_s && !loopback) start_error; // ACK error.
              else pstate <= P_ACK_DEL;
           end
           P_ACK_DEL: begin
              if (!rx_s) start_error; // Form error.
              else if (!transmitting && !crc_ok) start_error; // CRC error.
              else begin pstate <= P_EOF; pcnt_bits <= 7'd0; end
           end
           P_EOF: begin
              if (!rx_s && pcnt_bits != 7'd6) start_error; // Form error.
              else if (pcnt_bits == 7'd6) begin
                 // Frame complete.
                 pstate <= P_IFS;
                 pcnt_bits <= 7'd0;
                 if (transmitting) begin
                    transmitting <= 1'b0;
                    tx_pending <= 1'b0;
                    tx_ok_flag <= 1'b1;
                    if (tec != 9'd0) tec <= tec - 9'd1;
                 end else begin
                    if (rec > 8'd127) rec <= 8'd120;
                    else if (rec != 8'd0) rec <= rec - 8'd1;
                 end
                 if (!transmitting || loopback) begin
                    rx_store <= 1'b1;
                    rx_entry <= {rx_ide, rx_rtr,
                                 rx_ide ? {rx_id_a, rx_id_b} : {18'd0, rx_id_a},
                                 rx_dlc, rx_data};
                 end
              end else
                pcnt_bits <= pcnt_bits + 7'd1;
           end
           P_IFS: begin
              if (!rx_s) start_frame; // Taken as a SOF.
              else if (pcnt_bits == 7'd2) begin
                 pstate <= (tec > 9'd255) ? P_BUSOFF : P_IDLE;
                 pcnt_bits <= 7'd0;
              end else pcnt_bits <= pcnt_bits + 7'd1;
           end
           P_ERR_FLAG: begin
              // 6 flag bits (dominant, or recessive when error passive).
              if (pcnt_bits == 7'd5) begin pstate <= P_ERR_DEL; pcnt_bits <= 7'd0; end
              else pcnt_bits <= pcnt_bits + 7'd1;
           end
           P_ERR_DEL: begin
              // Other nodes' flags may keep the bus dominant a while:
              // wait for 8 recessive bits in a row. Every 8 dominant bits
              // in a row counts as another error (ISO 11898-1), so a
              // transmitter facing a stuck bus ends up bus off.
              if (tec > 9'd255) begin
                 pstate <= P_BUSOFF;
                 pcnt_bits <= 7'd0;
              end else if (!rx_s) begin
                 pcnt_bits <= 7'd0;
                 dom_cnt <= dom_cnt + 3'd1;
                 if (dom_cnt == 3'd7) begin
                    if (err_was_tx) tec <= tec + 9'd8;
                    else rec <= (rec > 8'd247) ? 8'd255 : rec + 8'd8;
                 end
              end else if (pcnt_bits == 7'd7) begin
                 pstate <= (tec > 9'd255) ? P_BUSOFF : P_IFS;
                 pcnt_bits <= 7'd0;
              end else pcnt_bits <= pcnt_bits + 7'd1;
           end
           P_BUSOFF: begin
              // Recover after 128 sequences of 11 recessive bits.
              if (!rx_s)
                pcnt_bits <= 7'd0;
              else if (pcnt_bits == 7'd10) begin
                 pcnt_bits <= 7'd0;
                 if (busoff_cnt == 8'd127) begin
                    busoff_cnt <= 8'd0;
                    tec <= 9'd0;
                    rec <= 8'd0;
                    pstate <= P_IDLE;
                 end else
                   busoff_cnt <= busoff_cnt + 8'd1;
              end else
                pcnt_bits <= pcnt_bits + 7'd1;
           end
           default: ;
         endcase
      end
   endtask

   /* --- CPU read side ----------------------------------------------------- */

   wire [3:0] rx_count4 = rx_count; // STATUS has 4 bits for it.
   wire [31:0] status = {1'b1, 19'd0, rx_count4,
                         2'b00, tx_ok_flag, (pstate == P_BUSOFF), err_passive,
                         rx_ovf_flag, !rx_empty, tx_pending};

   assign ready = sel;
   assign rdata = ctrl_sel   ? status :
                  timing_sel ? {6'd0, sjw, 4'd0, tseg2, 3'd0, tseg1, brp} :
                  id_sel     ? {rx_head[98], rx_head[97], 1'b0, rx_head[96:68]} :
                  d0_sel     ? {rx_head[39:32], rx_head[47:40], rx_head[55:48], rx_head[63:56]} :
                  d1_sel     ? {rx_head[7:0], rx_head[15:8], rx_head[23:16], rx_head[31:24]} :
                  cmd_sel    ? {28'd0, rx_head[67:64]} :
                  pop_sel    ? {16'd0, rec, (tec > 9'd255) ? 8'hff : tec[7:0]} :
                  32'h0;
   assign irq = rx_irq_en && !rx_empty;
endmodule

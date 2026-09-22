/* Top level SoC for the NanoTangArduino core (Sipeed Tang Nano 20K).
 *
 * Derived from grughuhler/picorv32_tang_nano_20k's top.v (BSD-2-Clause),
 * trimmed for v1 (LEDs + UART only, WS2812B/countdown timer dropped) and
 * extended with a free-running systick peripheral for millis()/micros();
 * the same project's ws2812b.v/ws2812b_tgt.v were later vendored back in
 * unchanged for the onboard WS2812 LED (see docs/PERIPHERALS.md "WS2812 LED").
 *
 * Memory map:
 *   0x0000_0000 - SRAM_BYTES-1   SRAM (program + data, size set by
 *                                 SRAM_ADDR_WIDTH, see sys_parameters.v)
 *   0x8000_0000                  LEDs (bits [5:0], read/write)
 *   0x8000_0008                  UART clock divisor register
 *   0x8000_000c                  UART data register
 *   0x8000_0020                  systick free-running counter (read-only)
 *   0x8000_0040                  I2S BCLK divisor register (write)
 *   0x8000_0044                  I2S transmit data register: {left16,right16} (write)
 *   0x8000_0048                  I2S control register: bit0 = PA_EN (write)
 *   0x8000_004c                  I2S receive data register: {left16,right16}
 *                                 (read, blocks until a fresh sample - Tools >
 *                                 I2S Input only, see docs/PERIPHERALS.md)
 *   0x8000_0160                  I2S IRQ_ENABLE register: bit0=TX room,
 *                                 bit1=RX data (read/write, see i2s.v)
 *   0x8000_0164                  I2S STATUS register: bits[4:0]=TX FIFO
 *                                 free slots, bits[9:5]=RX FIFO count
 *                                 (read-only, see i2s.v)
 *   0x8000_0050                  KEY_S2 button, bit0, read-only
 *   0x8000_0060 - 0x8000_0074    PWM duty/enable, one reg per LED channel
 *                                 0-5 (bit8=enable, bits[7:0]=duty)
 *   0x8000_0080                  SPI SCLK divisor register (write)
 *   0x8000_0084                  SPI CS register: bit0 = asserted (write)
 *   0x8000_0088                  SPI data register (read/write)
 *   0x8000_0090                  I2C open-drain SDA/SCL: write bit0/bit1 =
 *                                 drive low, read bit0/bit1 = pin level
 *   0x1000_0000 - 0x107f_ffff    Embedded SDRAM, 8MB (heap - see
 *                                 tangnano20k_malloc.c)
 *   0x8000_0100                  GPIO direction register (bits [20:0],
 *                                 1=output, default input)
 *   0x8000_0104                  GPIO output register (bits [20:0])
 *   0x8000_0108                  GPIO input register (bits [20:0],
 *                                 read-only, valid regardless of direction)
 *   0x8000_0110                  WS2812 LED: write {G[7:0],R[7:0],B[7:0]}
 *                                 in bits [23:0] (write blocks/backpressures
 *                                 until the peripheral can accept the next
 *                                 pixel - see ws2812b.v)
 *
 * GPIO covers 21 of the J5/J6 expansion header's 34 free I/O pins (per
 * the official datasheet's pinout table) - the other 13 are the same
 * physical pins already wired to the LEDs, I2S, I2C, and WS2812
 * peripherals above (this board ties header positions directly to those
 * onboard functions; there's no separate "header copy" of those specific
 * pins to expose). See docs/PERIPHERALS.md "General GPIO" for the full
 * pin table and which GPIO bits double as the optional LCD/HDMI-EDID
 * connectors.
 *   0x8000_0140                  AI accelerator (dot_product_engine.v,
 *                                 vendored from ../../../NanoTangAI) -
 *                                 CFG/WEIGHT_SEL/WEIGHT_DATA/ACT_RESET/
 *                                 ACT_DATA/START/RESULT_ADDR/RESULT_DATA
 *                                 registers at offsets 0x00-0x1C; see
 *                                 ai_accel_bus.v and docs/PERIPHERALS.md "AI accelerator"
 *
 * SPI and I2C both reuse the onboard microSD card slot's bus pins (SPI:
 * CLK/CMD/DAT0/DAT3; I2C: DAT1/DAT2) - using either is mutually exclusive
 * with using the microSD slot. Both are present by default but can be
 * removed (Tools > SPI Buses / I2C Buses: None) to save LUTs, or doubled
 * (Two) for a second, independent port on GPIO0-3 (SPI2)/GPIO4-5 (I2C2) -
 * see docs/PERIPHERALS.md.
 *
 * The system clock is derived from the board's fixed 27MHz oscillator via
 * an on-chip PLL (Gowin_rPLL_sys - see sys_parameters.v), rather than the
 * external clock-generator-chip trick earlier versions of this core used;
 * no one-time board setup is needed any more. Output frequency (27MHz by
 * default) is selected by the Tools > Clock Speed board menu - see
 * boards.txt. The PLL's phase-shifted second output clocks the embedded
 * SDRAM (sdram_bus.v).
 *
 * The picorv32 core has a very simple memory interface; see
 * https://github.com/YosysHQ/picorv32
 */

module top
  (
   input wire         clk_27m,
   input wire         reset_button,
   input wire         key2_button,
   input wire         uart_rx,
   output wire        uart_tx,
   output wire [5:0]  leds,
   output wire        i2s_bclk,
   output wire        i2s_ws,
   output wire        i2s_din,
   output wire        i2s_pa_en,
   output wire        spi_sclk,
   output wire        spi_mosi,
   input wire         spi_miso,
   output wire        spi_cs_n,
   inout wire         i2c_sda,
   inout wire         i2c_scl,
   inout wire [20:0]  gpio,
   output wire        ws2812_din,

   // Onboard SPI NOR flash - see gateware/src/qspi_flash.v and
   // docs/PERIPHERALS.md "Flash".
   output wire        flash_cs_n,
   output wire        flash_sclk,
   output wire        flash_mosi,
   input wire         flash_miso,
   output wire        flash_wp_n,
   output wire        flash_hold_n,

   // Embedded SDRAM (GW2AR-18 SiP memory - fixed internal package bonding,
   // not a normal externally-wired chip). These exact port names
   // (O_sdram_*/IO_sdram_dq, matching Sipeed/nand2mario's own
   // nestang/TangNano-20K-example convention - see gateware/src/sdram.v's
   // header) are load-bearing, not stylistic: nextpnr-himbaechel's Gowin
   // backend (Project Apicula, see YosysHQ/nextpnr#1370 "apicula: add
   // support for magic sip pins") auto-places these specific, pre-known
   // net names onto the GW2AR-LV18QN88C8/I7 package's embedded-SDRAM bond
   // pads - a lookup baked into Apycula's chip database for this exact
   // device/package, keyed on this precise naming, not a `.cst` file
   // entry. Renaming this port (or naming a new SDRAM design differently)
   // silently loses that auto-placement and fails place & route with
   // "Unconstrained IO:..." instead.
   inout wire [31:0]  IO_sdram_dq,
   output wire [10:0] O_sdram_addr,
   output wire [1:0]  O_sdram_ba,
   output wire        O_sdram_cs_n,
   output wire        O_sdram_wen_n,
   output wire        O_sdram_ras_n,
   output wire        O_sdram_cas_n,
   output wire        O_sdram_clk,
   output wire        O_sdram_cke,
   output wire [3:0]  O_sdram_dqm
   );

   // Provides SRAM_ADDR_WIDTH and CLK_FREQ, regenerated by the build
   // pipeline (tools/build_bitstream.py) from the platform's board config.
   `include "sys_parameters.v"

   parameter        MEMBYTES = 4*(1 << SRAM_ADDR_WIDTH);
   parameter [31:0] STACKADDR = MEMBYTES; // Grows down; runtime sets it.
   // Fixed low-memory interrupt layout - see cores/tangnano20k/link_cmd.ld
   // and cores/tangnano20k/irq_vec.S: the IRQ entry point lives at 0x000,
   // normal program execution starts at 0x400 (0x100-0x3ff is reserved
   // register-save scratch + IRQ handler stack) - UNLESS Tools > Boot
   // Mode: Flash is selected (`BOOT_FROM_FLASH`, off by default), in
   // which case picorv32 instead starts at the fixed boot stub
   // (cores/tangnano20k/boot.S, baked into this same low SRAM region at
   // 0x380) that copies the sketch's real program from flash into SRAM at
   // 0x400 before jumping there - see docs/PERIPHERALS.md "Flash". Gated
   // behind a Tools menu rather than made the default because it's a
   // fundamentally different boot model requiring a matching upload-side
   // toolchain change (see docs/BUILDING.md) - the default keeps every
   // existing sketch/example working exactly as before, unchanged.
`ifdef BOOT_FROM_FLASH
   parameter [31:0] PROGADDR_RESET = 32'h0000_0380;
`else
   parameter [31:0] PROGADDR_RESET = 32'h0000_0400;
`endif
   parameter [31:0] PROGADDR_IRQ = 32'h0000_0000;

   wire              clk_sys;
   wire              clk_sdram;
   wire              pll_lock;

   Gowin_rPLL_sys pll
     (
      .clkout(clk_sys),
      .clkoutp(clk_sdram),
      .lock(pll_lock),
      .reset(reset_button),
      .clkin(clk_27m)
      );

   wire              reset_n_raw;
   wire              reset_n;

   // Shared request bus feeding the address-decoded peripherals/memory
   // below (sram_sel, sdram_sel, etc. - all unchanged, they don't know or
   // care which master is talking). Driven by the arbiter further down,
   // which selects between the CPU and dma_engine.v - see "DMA bus
   // arbiter" below and docs/PERIPHERALS.md "DMA".
   wire              mem_valid;
   wire [31:0]       mem_addr;
   wire [31:0]       mem_wdata;
   wire [31:0]       mem_rdata;
   wire [3:0]        mem_wstrb;
   wire              mem_ready;

   // picorv32's own bus signals, pre-arbitration.
   wire              cpu_mem_valid;
   wire              cpu_mem_instr;
   wire [31:0]       cpu_mem_addr;
   wire [31:0]       cpu_mem_wdata;
   wire [3:0]        cpu_mem_wstrb;
   wire              cpu_mem_ready;
   wire [31:0]       cpu_mem_rdata;

   // dma_engine.v's own bus signals, pre-arbitration.
   wire              dma_active;
   wire              dma_mem_valid;
   wire [31:0]       dma_mem_addr;
   wire [31:0]       dma_mem_wdata;
   wire [3:0]        dma_mem_wstrb;
   wire              dma_mem_ready;
   wire [31:0]       dma_mem_rdata;

   wire              dma_ctrl_sel;
   wire              dma_ctrl_ready;
   wire [31:0]       dma_ctrl_rdata;
   wire              dma_irq_out;

   // dma_engine.v's async-mode port: a dedicated, direct link to
   // sdram_bus.v's second port (see that module and dma_engine.v) - not
   // arbitrated with the CPU bus above at all, so async DMA never stalls
   // the CPU.
   wire              dma_async_mem_valid;
   wire [22:0]       dma_async_mem_addr;
   wire [31:0]       dma_async_mem_wdata;
   wire [3:0]        dma_async_mem_wstrb;
   wire              dma_async_mem_ready;
   wire [31:0]       dma_async_mem_rdata;

   // DMA bus arbiter: while dma_engine.v owns the bus (dma_active), it
   // drives the shared request bus instead of the CPU, and the CPU's own
   // mem_ready is held low - it just stalls, same as it already does
   // waiting on any slow peripheral, until DMA hands the bus back.
   // picorv32 has no separate instruction bus, so instruction fetch stalls
   // too during a transfer: this is throughput-only "cycle stealing" DMA,
   // not a way to keep the CPU running while a copy is in flight.
   assign mem_valid = dma_active ? dma_mem_valid : cpu_mem_valid;
   assign mem_addr  = dma_active ? dma_mem_addr  : cpu_mem_addr;
   assign mem_wdata = dma_active ? dma_mem_wdata : cpu_mem_wdata;
   assign mem_wstrb = dma_active ? dma_mem_wstrb : cpu_mem_wstrb;

   assign cpu_mem_ready = !dma_active && mem_ready;
   assign dma_mem_ready = dma_active && mem_ready;
   assign cpu_mem_rdata = mem_rdata;
   assign dma_mem_rdata = mem_rdata;

   wire              leds_sel;
   wire              leds_ready;
   wire [31:0]       leds_data_o;
   wire              sram_sel;
   wire              sram_ready;
   wire [31:0]       sram_data_o;
   wire              uart_sel;
   wire [31:0]       uart_data_o;
   wire              uart_ready;
   wire              systick_sel;
   wire              systick_ready;
   wire [31:0]       systick_data_o;
   wire              i2s_sel;
   wire              i2s_ext_sel;
   wire              i2s_ready;
   wire [31:0]       i2s_rdata;
   wire              i2s_irq_out;
   wire              key2_sel;
   wire              pwm_sel;
   wire              pwm_ready;
   wire [5:0]        pwm_out;
   wire [5:0]        pwm_enabled;
   wire [5:0]        leds_muxed;
   wire              spi_sel;
   wire              spi_ready;
   wire [31:0]       spi_rdata;
   wire              i2c_sel;
   wire              i2c_ready;
   wire [31:0]       i2c_rdata;
   wire              sdram_sel;
   wire              sdram_ready;
   wire [31:0]       sdram_rdata;
   wire              gpio_sel;
   wire              gpio_ready;
   wire [31:0]       gpio_rdata;
   wire              ai_sel;
   wire              ai_ready;
   wire [31:0]       ai_rdata;
   wire              ws2812_sel;
   wire              ws2812_ready;
   wire              extirq_enable_sel;
   wire              extirq_status_sel;
   wire              extirq_level_sel;
   wire              extirq_ready;
   wire [31:0]       extirq_rdata;
   wire              extirq_out;
   wire              flash_sel;
   wire              flash_ready;
   wire [31:0]       flash_rdata;
   wire              spi2_sel;
   wire              spi2_ready;
   wire [31:0]       spi2_rdata;
   wire              i2c2_sel;
   wire              i2c2_ready;
   wire [31:0]       i2c2_rdata;

   assign flash_wp_n   = 1'b1; // Not used - held inactive (protection disabled).
   assign flash_hold_n = 1'b1; // Not used - held inactive (never paused mid-transfer).

   assign sram_sel    = mem_valid && (mem_addr < MEMBYTES);
   assign sdram_sel   = mem_valid && ((mem_addr & 32'hff80_0000) == 32'h1000_0000);
   assign leds_sel    = mem_valid && (mem_addr == 32'h8000_0000);
   assign uart_sel    = mem_valid && ((mem_addr & 32'hffff_fff8) == 32'h8000_0008);
   assign systick_sel = mem_valid && (mem_addr == 32'h8000_0020);
   assign i2s_sel     = mem_valid && ((mem_addr & 32'hffff_fff0) == 32'h8000_0040);
   // I2S FIFO IRQ_ENABLE/STATUS registers (see i2s.v) - a separate 16-byte
   // window from i2s_sel above, clear of ai_sel's 0x140-0x15F range and
   // gpio_sel's 0x100 window.
   assign i2s_ext_sel = mem_valid && ((mem_addr & 32'hffff_fff0) == 32'h8000_0160);
   assign key2_sel    = mem_valid && (mem_addr == 32'h8000_0050);
   assign pwm_sel     = mem_valid && ((mem_addr & 32'hffff_ffe0) == 32'h8000_0060);
   assign spi_sel     = mem_valid && ((mem_addr & 32'hffff_fff0) == 32'h8000_0080);
   assign i2c_sel     = mem_valid && (mem_addr == 32'h8000_0090);
   assign gpio_sel    = mem_valid && ((mem_addr & 32'hffff_fff0) == 32'h8000_0100);
   assign ws2812_sel  = mem_valid && (mem_addr == 32'h8000_0110);
   assign ai_sel      = mem_valid && ((mem_addr & 32'hffff_ffe0) == 32'h8000_0140);
   assign extirq_enable_sel = mem_valid && (mem_addr == 32'h8000_0120);
   assign extirq_status_sel = mem_valid && (mem_addr == 32'h8000_0124);
   assign extirq_level_sel  = mem_valid && (mem_addr == 32'h8000_0128);
   assign dma_ctrl_sel      = mem_valid && ((mem_addr & 32'hffff_fff0) == 32'h8000_0130);
   assign flash_sel         = mem_valid && ((mem_addr & 32'hff80_0000) == 32'h2000_0000);
   assign spi2_sel          = mem_valid && ((mem_addr & 32'hffff_fff0) == 32'h8000_00A0);
   assign i2c2_sel          = mem_valid && (mem_addr == 32'h8000_00B0);
`ifndef WITH_SPI1
   // Tools > SPI Buses: None. Same silently-wrong-not-hung rationale as
   // the AI accelerator's fallback below: SPI/Wire (the primary port)
   // just reads back 0 and accepts writes as no-ops instead of hanging a
   // sketch that still calls into it (e.g. via libraries/SD, which sits
   // on top of SPI).
   assign spi_ready  = spi_sel;
   assign spi_rdata  = 32'h0;
`endif
`ifndef WITH_I2C1
   // Tools > I2C Buses: None - same rationale as WITH_SPI1 above.
   assign i2c_ready  = i2c_sel;
   assign i2c_rdata  = 32'h0;
`endif
`ifndef WITH_SPI2
   // Tools > SPI Buses: One (the default) - see gpio_bank's instantiation
   // below for why GPIO0-3 are otherwise reserved for this. Same
   // silently-wrong-not-hung rationale as WITH_SPI1 above.
   assign spi2_ready = spi2_sel;
   assign spi2_rdata = 32'h0;
`endif
`ifndef WITH_I2C2
   // Tools > I2C Buses: One (the default) - see gpio_bank's instantiation
   // below for why GPIO4-5 are otherwise reserved for this. Same
   // silently-wrong-not-hung rationale as WITH_SPI1 above.
   assign i2c2_ready = i2c2_sel;
   assign i2c2_rdata = 32'h0;
`endif
`ifndef WITH_AI_ACCEL
   // AI accelerator gateware not built in (Tools > AI Accelerator:
   // Disabled, the default). Still claim the address range and answer
   // immediately with 0 rather than leaving it fully unclaimed - a sketch
   // that uses the AIAccelerator library without enabling the menu gets
   // silently-wrong results, not a CPU hang waiting for a mem_ready that
   // would otherwise never come.
   assign ai_ready    = ai_sel;
   assign ai_rdata    = 32'h0;
`endif

   assign mem_ready = mem_valid &
                       (sram_ready | leds_ready | uart_ready | systick_ready |
                        i2s_ready | key2_sel | pwm_ready | spi_ready | i2c_ready |
                        sdram_ready | gpio_ready | ai_ready | ws2812_ready |
                        extirq_ready | dma_ctrl_ready | flash_ready |
                        spi2_ready | i2c2_ready);

   assign mem_rdata = sram_sel    ? sram_data_o :
                      leds_sel    ? leds_data_o :
                      uart_sel    ? uart_data_o :
                      systick_sel ? systick_data_o :
                      (i2s_sel | i2s_ext_sel) ? i2s_rdata :
                      key2_sel    ? {31'b0, key2_button} :
                      spi_sel     ? spi_rdata :
                      i2c_sel     ? i2c_rdata :
                      sdram_sel   ? sdram_rdata :
                      gpio_sel    ? gpio_rdata :
                      ai_sel      ? ai_rdata :
                      (extirq_enable_sel | extirq_status_sel | extirq_level_sel) ?
                        extirq_rdata :
                      dma_ctrl_sel ? dma_ctrl_rdata :
                      flash_sel    ? flash_rdata :
                      spi2_sel     ? spi2_rdata :
                      i2c2_sel     ? i2c2_rdata : 32'h0;

   // Per-LED mux: PWM output when analogWrite() has enabled that channel,
   // else the plain digital value from tang_leds.
   assign leds_muxed = (pwm_out & pwm_enabled) | (leds_data_o[5:0] & ~pwm_enabled);
   assign leds = ~leds_muxed; // Onboard LEDs are active-low.

   reset_control reset_controller
     (
      .clk(clk_sys),
      .reset_button(reset_button),
      .reset_n(reset_n_raw)
      );

   // Hold the whole SoC in reset until the PLL has locked, in addition to
   // the button/power-on reset sequencing above.
   assign reset_n = reset_n_raw & pll_lock;

   uart_wrap uart
     (
      .clk(clk_sys),
      .reset_n(reset_n),
      .uart_tx(uart_tx),
      .uart_rx(uart_rx),
      .uart_sel(uart_sel),
      .addr(mem_addr[3:0]),
      .uart_wstrb(mem_wstrb),
      .uart_di(mem_wdata),
      .uart_do(uart_data_o),
      .uart_ready(uart_ready)
      );

   systick tick
     (
      .clk(clk_sys),
      .reset_n(reset_n),
      .systick_sel(systick_sel),
      .systick_ready(systick_ready),
      .systick_data_o(systick_data_o)
      );

   i2s i2s
     (
      .clk(clk_sys),
      .reset_n(reset_n),
      .i2s_sel(i2s_sel),
      .i2s_ext_sel(i2s_ext_sel),
      .addr(mem_addr[3:0]),
      .wstrb(mem_wstrb),
      .wdata(mem_wdata),
      .i2s_ready(i2s_ready),
      .i2s_rdata(i2s_rdata),
      .i2s_irq_out(i2s_irq_out),
      .i2s_bclk(i2s_bclk),
      .i2s_ws(i2s_ws),
      .i2s_din(i2s_din),
      .i2s_pa_en(i2s_pa_en),
`ifdef WITH_I2S_RX
      .i2s_rx_din(gpio[6])
`else
      .i2s_rx_din(1'b0)
`endif
      );

   pwm6 leds_pwm
     (
      .clk(clk_sys),
      .reset_n(reset_n),
      .pwm_sel(pwm_sel),
      .addr(mem_addr[4:0]),
      .wstrb(mem_wstrb),
      .wdata(mem_wdata),
      .pwm_ready(pwm_ready),
      .pwm_out(pwm_out),
      .pwm_enabled(pwm_enabled)
      );

`ifdef WITH_SPI1
   spi_master spi
     (
      .clk(clk_sys),
      .reset_n(reset_n),
      .spi_sel(spi_sel),
      .addr(mem_addr[3:0]),
      .wstrb(mem_wstrb),
      .wdata(mem_wdata),
      .spi_ready(spi_ready),
      .spi_rdata(spi_rdata),
      .spi_sclk(spi_sclk),
      .spi_mosi(spi_mosi),
      .spi_miso(spi_miso),
      .spi_cs_n(spi_cs_n)
      );
`else
   // Tools > SPI Buses: None - idle the microSD slot's SPI pins (clock
   // low, CS deasserted) instead of leaving them undriven.
   assign spi_sclk = 1'b0;
   assign spi_mosi = 1'b0;
   assign spi_cs_n = 1'b1;
`endif

`ifdef WITH_I2C1
   od_gpio2 i2c
     (
      .clk(clk_sys),
      .reset_n(reset_n),
      .sel(i2c_sel),
      .wstrb(mem_wstrb),
      .wdata(mem_wdata),
      .ready(i2c_ready),
      .rdata(i2c_rdata),
      .sda(i2c_sda),
      .scl(i2c_scl)
      );
`else
   // Tools > I2C Buses: None - let the microSD slot's I2C pins float
   // (open-drain idle, matching a real I2C bus with no active driver)
   // instead of leaving them undriven.
   assign i2c_sda = 1'bz;
   assign i2c_scl = 1'bz;
`endif

`ifdef WITH_SPI2
   // GPIO0-3 are claimed by the second SPI port below when Tools > SPI
   // Buses: Two is selected - gpio_bank still owns bits 0-3 in the
   // register map (GPIOx numbering never changes), but those specific
   // bits no longer reach a real pin; gpio_bank_dummy_spi2 is a dead-end
   // sink for its own drive of those bits. See docs/PERIPHERALS.md "SPI,
   // I2C (Wire), and the SD card".
   wire [3:0] gpio_bank_dummy_spi2;
`endif
`ifdef WITH_I2C2
   // Same idea as gpio_bank_dummy_spi2 above, but for GPIO4-5, claimed by
   // the second I2C port when Tools > I2C Buses: Two is selected.
   wire [1:0] gpio_bank_dummy_i2c2;
`endif
`ifdef WITH_I2S_RX
   // Same idea again, but for the single GPIO6 pin Tools > I2S Input
   // claims as the external microphone's data-out line - see
   // docs/PERIPHERALS.md "Audio (I2S)".
   wire       gpio_bank_dummy_i2s_rx;
`endif

   gpio_bank #(.WIDTH(21)) expansion_gpio
     (
      .clk(clk_sys),
      .reset_n(reset_n),
      .sel(gpio_sel),
      .addr(mem_addr[3:0]),
      .wstrb(mem_wstrb),
      .wdata(mem_wdata),
      .ready(gpio_ready),
      .rdata(gpio_rdata),
      .gpio({gpio[20:7],
`ifdef WITH_I2S_RX
             gpio_bank_dummy_i2s_rx,
`else
             gpio[6],
`endif
`ifdef WITH_I2C2
             gpio_bank_dummy_i2c2,
`else
             gpio[5:4],
`endif
`ifdef WITH_SPI2
             gpio_bank_dummy_spi2
`else
             gpio[3:0]
`endif
             })
      );

`ifdef WITH_SPI2
   // Tools > SPI Buses: Two. A second SPI port, reusing this project's own
   // proven spi_master.v module exactly as the first port does, wired
   // directly onto GPIO0-3 instead of a dedicated bus (this board has only
   // one hardware SPI-capable bus, the microSD slot's pins, already used
   // by the first SPI port above).
   spi_master spi2
     (
      .clk(clk_sys),
      .reset_n(reset_n),
      .spi_sel(spi2_sel),
      .addr(mem_addr[3:0]),
      .wstrb(mem_wstrb),
      .wdata(mem_wdata),
      .spi_ready(spi2_ready),
      .spi_rdata(spi2_rdata),
      .spi_sclk(gpio[0]),
      .spi_mosi(gpio[1]),
      .spi_miso(gpio[2]),
      .spi_cs_n(gpio[3])
      );
`endif

`ifdef WITH_I2C2
   // Tools > I2C Buses: Two - same rationale as WITH_SPI2 above, wired
   // onto GPIO4-5 instead.
   od_gpio2 i2c2
     (
      .clk(clk_sys),
      .reset_n(reset_n),
      .sel(i2c2_sel),
      .wstrb(mem_wstrb),
      .wdata(mem_wdata),
      .ready(i2c2_ready),
      .rdata(i2c2_rdata),
      .sda(gpio[4]),
      .scl(gpio[5])
      );
`endif

   // attachInterrupt() source: watches the 21 GPIO pins (live pin level,
   // regardless of gpio_bank's own direction setting) plus KEY_S2 for
   // changes and drives picorv32's irq[3] - see extirq.v and
   // cores/tangnano20k/wiring_irq.cpp.
   extirq #(.WIDTH(22)) ext_irq_src
     (
      .clk(clk_sys),
      .reset_n(reset_n),
      .level_in({key2_button, gpio}),
      .enable_sel(extirq_enable_sel),
      .status_sel(extirq_status_sel),
      .level_sel(extirq_level_sel),
      .we(|mem_wstrb),
      .wdata(mem_wdata),
      .ready(extirq_ready),
      .rdata(extirq_rdata),
      .irq_out(extirq_out)
      );

   ws2812b_tgt #(.CLK_FREQ(CLK_FREQ)) ws2812
     (
      .clk(clk_sys),
      .reset_n(reset_n),
      .ws2812b_sel(ws2812_sel),
      .we(|mem_wstrb),
      .wdata(mem_wdata[23:0]),
      .ws2812b_ready(ws2812_ready),
      .to_din(ws2812_din)
      );

`ifdef WITH_AI_ACCEL
   ai_accel_bus ai_accel
     (
      .clk(clk_sys),
      .reset_n(reset_n),
      .sel(ai_sel),
      .addr(mem_addr[4:0]),
      .wstrb(mem_wstrb),
      .wdata(mem_wdata),
      .ready(ai_ready),
      .rdata(ai_rdata)
      );
`endif

   sdram_bus #(.FREQ(CLK_FREQ)) sdram
     (
      .clk(clk_sys),
      .clk_sdram(clk_sdram),
      .reset_n(reset_n),
      .sel(sdram_sel),
      .addr(mem_addr[22:0]),
      .wstrb(mem_wstrb),
      .wdata(mem_wdata),
      .ready(sdram_ready),
      .rdata(sdram_rdata),
      .dma_sel(dma_async_mem_valid),
      .dma_addr(dma_async_mem_addr),
      .dma_wstrb(dma_async_mem_wstrb),
      .dma_wdata(dma_async_mem_wdata),
      .dma_ready(dma_async_mem_ready),
      .dma_rdata(dma_async_mem_rdata),
      .SDRAM_DQ(IO_sdram_dq),
      .SDRAM_A(O_sdram_addr),
      .SDRAM_BA(O_sdram_ba),
      .SDRAM_nCS(O_sdram_cs_n),
      .SDRAM_nWE(O_sdram_wen_n),
      .SDRAM_nRAS(O_sdram_ras_n),
      .SDRAM_nCAS(O_sdram_cas_n),
      .SDRAM_CLK(O_sdram_clk),
      .SDRAM_CKE(O_sdram_cke),
      .SDRAM_DQM(O_sdram_dqm)
      );

   sram #(.SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH)) memory
     (
      .clk(clk_sys),
      .reset_n(reset_n),
      .sram_sel(sram_sel),
      .wstrb(mem_wstrb),
      .addr(mem_addr[SRAM_ADDR_WIDTH + 1:0]),
      .sram_data_i(mem_wdata),
      .sram_ready(sram_ready),
      .sram_data_o(sram_data_o)
      );

   tang_leds soc_leds
     (
      .clk(clk_sys),
      .reset_n(reset_n),
      .leds_sel(leds_sel),
      .leds_data_i(mem_wdata[5:0]),
      .we(mem_wstrb[0]),
      .leds_ready(leds_ready),
      .leds_data_o(leds_data_o)
      );

   picorv32
     #(
       .STACKADDR(STACKADDR),
       .PROGADDR_RESET(PROGADDR_RESET),
       .PROGADDR_IRQ(PROGADDR_IRQ),
       .BARREL_SHIFTER(0),
       .COMPRESSED_ISA(0),
`ifdef WITH_HW_MULDIV
       // Tools > Hardware Multiply/Divide: Enabled - real M-extension
       // mul/div opcodes instead of software emulation, matching
       // compiler.march's rv32im_zicsr_zifencei (see platform.txt/
       // boards.txt). This MUST stay paired with that compiler flag: a
       // sketch compiled expecting hardware mul/div would execute an
       // illegal instruction on a bitstream built without this, and vice
       // versa a plain-RV32I sketch still runs fine here regardless (the
       // CPU just has an unused capability) - see docs/PERIPHERALS.md.
       .ENABLE_MUL(1),
       .ENABLE_DIV(1),
       .ENABLE_FAST_MUL(1),
`else
       .ENABLE_MUL(0),
       .ENABLE_DIV(0),
       .ENABLE_FAST_MUL(0),
`endif
       .ENABLE_IRQ(1),
       .ENABLE_IRQ_QREGS(0)
       ) cpu
       (
        .clk         (clk_sys),
        .resetn      (reset_n),
        .mem_valid   (cpu_mem_valid),
        .mem_instr   (cpu_mem_instr),
        .mem_ready   (cpu_mem_ready),
        .mem_addr    (cpu_mem_addr),
        .mem_wdata   (cpu_mem_wdata),
        .mem_wstrb   (cpu_mem_wstrb),
        .mem_rdata   (cpu_mem_rdata),
        .irq         ({26'b0, i2s_irq_out, dma_irq_out, extirq_out, 3'b0})
        );

   dma_engine dma
     (
      .clk(clk_sys),
      .reset_n(reset_n),
      .ctrl_sel(dma_ctrl_sel),
      .ctrl_addr(mem_addr[3:2]),
      .ctrl_wstrb(mem_wstrb),
      .ctrl_wdata(mem_wdata),
      .ctrl_ready(dma_ctrl_ready),
      .ctrl_rdata(dma_ctrl_rdata),
      .active(dma_active),
      .mem_valid(dma_mem_valid),
      .mem_addr(dma_mem_addr),
      .mem_wdata(dma_mem_wdata),
      .mem_wstrb(dma_mem_wstrb),
      .mem_ready(dma_mem_ready),
      .mem_rdata(dma_mem_rdata),
      .async_mem_valid(dma_async_mem_valid),
      .async_mem_addr(dma_async_mem_addr),
      .async_mem_wdata(dma_async_mem_wdata),
      .async_mem_wstrb(dma_async_mem_wstrb),
      .async_mem_ready(dma_async_mem_ready),
      .async_mem_rdata(dma_async_mem_rdata),
      .irq_out(dma_irq_out)
      );

   qspi_flash flash
     (
      .clk(clk_sys),
      .reset_n(reset_n),
      .sel(flash_sel),
      .addr(mem_addr[23:0]),
      .ready(flash_ready),
      .rdata(flash_rdata),
      .flash_sclk(flash_sclk),
      .flash_mosi(flash_mosi),
      .flash_miso(flash_miso),
      .flash_cs_n(flash_cs_n)
      );

endmodule // top

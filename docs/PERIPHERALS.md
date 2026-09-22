# Peripherals

## Digital I/O and PWM

Pins 0-5 are the 6 onboard LEDs: `pinMode`/`digitalWrite`/`digitalRead`
work, plus `analogWrite()` (real 8-bit PWM, `gateware/src/pwm6.v`) — calling
it switches that LED into PWM mode; a later `digitalWrite()`/`pinMode()`
call switches it back to plain on/off, matching real-Arduino behavior. Pin
6 (`BTN1`) is the board's second button (KEY_S2), `digitalRead`-only.
Pins 14-35 (`GPIO0`-`GPIO21`) are real general-purpose I/O — see
[General GPIO](#general-gpio) below. There's no `analogRead()` — the board
has no ADC wired to any pin, so that function is stubbed to always
return 0.

## General GPIO

`gateware/src/gpio_bank.v` exposes 21 pins as real `pinMode(INPUT/OUTPUT)`/
`digitalWrite`/`digitalRead` GPIO, as `GPIO0`-`GPIO20` (pins 14-34). Unlike
the LED/`BTN1` pins above, `pinMode()` here actually changes hardware
direction.

These are 21 of the official datasheet's "34 free IOs" on the J5/J6
expansion headers — the other 13 header positions are the *same physical
pins* already wired to the LEDs (15-20), I2S (51/54/55/56), I2C (80/85),
and WS2812 (79) peripherals documented elsewhere on this page; this board
ties those header positions directly to those onboard functions, so
there's no separate way to reach them as plain GPIO. Several of the 21
below also double as the optional RGB LCD FPC connector or the HDMI EDID
I2C bus — using them as GPIO is fine as long as you're not also using
that connector/bus.

| Pin | FPGA pin | Also known as (if in use elsewhere on the board) |
|---|---|---|
| GPIO0 | 73 | — |
| GPIO1 | 74 | — |
| GPIO2 | 75 | — |
| GPIO3 | 77 | RGB LCD connector: LCD_CLK |
| GPIO4 | 27 | RGB LCD connector: LCD_B7 |
| GPIO5 | 28 | RGB LCD connector: LCD_B6 |
| GPIO6 | 25 | RGB LCD connector: LCD_HS |
| GPIO7 | 26 | RGB LCD connector: LCD_VS |
| GPIO8 | 29 | RGB LCD connector: LCD_B5 |
| GPIO9 | 30 | RGB LCD connector: LCD_B4 |
| GPIO10 | 31 | RGB LCD connector: LCD_B3 |
| GPIO11 | 76 | — |
| GPIO12 | 42 | RGB LCD connector: LCD_R3 |
| GPIO13 | 41 | RGB LCD connector: LCD_R4 |
| GPIO14 | 48 | RGB LCD connector: LCD_DE |
| GPIO15 | 49 | RGB LCD connector: LCD_BL (backlight) |
| GPIO16 | 86 | — |
| GPIO17 | 72 | — |
| GPIO18 | 71 | — |
| GPIO19 | 53 | HDMI connector: EDID_CLK |
| GPIO20 | 52 | HDMI connector: EDID_DAT |

(Pin 79, formerly `GPIO17`, is now the dedicated [WS2812 LED](#ws2812-led) pin.)

See `examples/GPIOBlink`. Pin numbers are sourced from the official
[Tang Nano 20K Datasheet v1.3](https://dl.sipeed.com/fileList/TANG/Nano_20K/1_Datasheet/Sipeed%20Tang%20nano%2020K%20Datasheet%20V1.3-en_US.pdf)'s
pinout table, cross-checked against the schematic pin numbers used
elsewhere in this file.

## WS2812 LED

`#include <WS2812.h>` (`libraries/WS2812/`). `WS2812.write(r, g, b)` sets
the onboard addressable RGB LED (physical FPGA pin 79) - it blocks (via
bus backpressure, not a software poll loop) until the peripheral can
accept the next pixel. Backed by `gateware/src/ws2812b.v`/`ws2812b_tgt.v`,
vendored unmodified from
[grughuhler/picorv32_tang_nano_20k](https://github.com/grughuhler/picorv32_tang_nano_20k)
(BSD-2-Clause) - a real hardware shift-timer, not software bit-banging,
since WS2812's protocol needs ~400ns-precision pulses well beyond what's
reliably achievable in C at this core's default 27MHz. See
`examples/WS2812Rainbow`.

## Audio (I2S)

`#include <I2S.h>` (`libraries/I2S/`, backed by `gateware/src/i2s.v`).
`I2S.begin(sampleRate, mode, channels, bits, ringSamples)` configures
the shared BCLK divisor for `sampleRate * 32` (the hardware always moves
16-bit samples, regardless of `bits` below) - this same clock paces both
transmit and receive, regardless of `mode`. `mode` is one of
`I2S_MODE_OUTPUT` (default), `I2S_MODE_INPUT`, or `I2S_MODE_DUPLEX` - it
only controls whether `begin()` enables the amplifier (`PA_EN`, skipped
for `I2S_MODE_INPUT`) and what `available()` reports (see Stream below);
the hardware runs transmit and receive simultaneously either way, so a
sketch calling `write()` and `read()` around the same loop is running
duplex regardless of which `mode` was passed - there's no separate
hardware mode to switch into. `channels` is `1` (mono) or `2` (stereo,
the default); with `1`, writes duplicate the sample onto both hardware
channels and reads only expose the left channel. `ringSamples` (default
`64`) sets the depth of each direction's software ring buffer - see
"Buffering and interrupts" below; it's heap-allocated (4 bytes/sample,
from this core's SDRAM heap), and `I2S.ringSamples()` reports the size
actually in effect if an oversized request fell back to a smaller one.

`I2SClass` is an `arduino::Stream` - `write(uint8_t)`/`read()`/`peek()`/
`available()` (plus `Print`'s bulk `write(const uint8_t*, size_t)`) are
the only way in or out, working on raw little-endian PCM bytes at the
configured `bits` depth - `I2S_BITS_8`, `I2S_BITS_8_UNSIGNED`,
`I2S_BITS_16` (default), `I2S_BITS_24`, or `I2S_BITS_32` - channels
interleaved left-then-right, converting to/from the hardware's native
16-bit samples internally. This lets I2S output/input be piped directly
into or out of any other `Stream`-based code (e.g. playing a PCM WAV
file's bytes straight through). To write or read a single sample pair
directly, go through the bulk form: `int16_t frame[2] = {left, right};
I2S.write((uint8_t*)frame, sizeof(frame));` (and the receive-side
mirror, `I2S.readBytes((uint8_t*)frame, sizeof(frame));`, inherited from
`Stream`). See "Buffering and interrupts" below for what backs this.

### Buffering and interrupts

Both directions in `i2s.v` are backed by a 16-sample hardware FIFO
(rather than a single-sample shadow register), plus a software ring
buffer per direction (`libraries/I2S/src/I2S.cpp`, `ringSamples` deep,
default `64`) that a dedicated interrupt keeps synchronized with the
hardware FIFO in the background: `write()` pushes onto the software ring
and arms the interrupt; an ISR drains it into the hardware FIFO as room
appears, disarming itself once the ring is empty so an always-true
"FIFO has room" hardware condition doesn't turn into a permanent
interrupt storm. Receive mirrors this: the interrupt continuously fills
the software ring from the hardware FIFO whenever `mode` includes input,
disarming itself if the ring fills up (freed again the next time
`read()` pops a sample). This means a sketch can call `write()`/`read()`
in bursts, or skip a few `loop()` iterations doing other work, without
needing to hit the exact sample rate every time - up to `ringSamples`
(plus the hardware FIFO's own 16) of slack in either direction; raise it
in `begin()` for a sketch with bursty timing, or lower it to save SDRAM
heap if `loop()` is reliably fast and regular. `available()` is
genuinely non-blocking, reporting exactly what's already been captured
in the background rather than assuming more is always imminent.

- **Transmit** (always available): like `Serial`'s UART writes, `write()`
  blocks via hardware bus backpressure (ultimately - see above) rather
  than a software timer, pacing output to the configured sample rate
  automatically. Pin numbers (`PA_EN`=51, `DIN`=54, `WS`=55, `BCLK`=56)
  are confirmed against Sipeed's own
  [audio example](https://github.com/sipeed/TangNano-20K-example/tree/main/audio).
  See `examples/I2SToneTest`.
- **Receive**: select **Tools > I2S Input: Enabled** (disabled by
  default, same real GPIO-pin cost/opt-in pattern as
  [Extra SPI/I2C](#a-second-spi--i2c-port)) and wire an external I2S
  microphone's data-out line to `GPIO6`, sharing the same `WS`/`BCLK`
  lines the onboard amplifier uses - this is a synthesis-time decision
  (it removes `GPIO6` from the general-purpose GPIO pool in the
  bitstream itself), independent of the `mode` passed to `begin()`. With
  the menu left disabled, `GPIO6` stays plain GPIO and captured samples
  are always silence.
- **Duplex**: see above - `examples/I2SDuplexTest` passes each captured
  frame straight back out to the amplifier.

The exact bit alignment of the frame follows the Philips/I2S convention but
is unverified on real hardware and may need a one-`BCLK` tweak.

## SPI, I2C (`Wire`), and the SD card

All three **share the onboard microSD card slot's bus pins** — use at most
one of them at a time. This was a deliberate tradeoff: those are the only
pins on this board I could confirm the exact FPGA pin numbers for from
Sipeed's schematic without risking an unsafe guess (see
[Known limitations](KNOWN_LIMITATIONS.md)).

- **SPI** (`#include <SPI.h>`, `libraries/SPI/`, backed by
  `gateware/src/spi_master.v`): a real hardware shift register, mode 0
  only, MSB-first. Wiring matches standard SD-over-SPI: `SCLK`=83,
  `MOSI`=82, `MISO`=84, `CS`=81 (physical FPGA pin numbers). There's a
  single fixed CS line asserted for the duration of
  `beginTransaction()`/`endTransaction()`, not a general-purpose CS pin —
  only one SPI device at a time. See `examples/SPITransfer`.
- **I2C** (`#include <Wire.h>`, `libraries/Wire/`, backed by
  `gateware/src/od_gpio2.v`): bit-banged in software over an open-drain
  SDA/SCL pair (internal pull-ups enabled in the `.cst`), master mode
  only. `SDA`=85, `SCL`=80. See `examples/I2CScanner`.

### A second SPI + I2C port

Select **Tools > Extra SPI/I2C: Enabled** (disabled by default) for a
second, fully independent SPI and I2C port - `SPI2`/`Wire2`, same
`TangNanoSPIClass`/`TwoWire` API as the first port, backed by a second
instance of the same `spi_master.v`/`od_gpio2.v` gateware. This board has
only one dedicated SPI/I2C-capable bus (the microSD slot's pins used
above), so the second port runs on general-purpose GPIO instead:
`SPI2` = `SCLK`=GPIO0, `MOSI`=GPIO1, `MISO`=GPIO2, `CS`=GPIO3; `Wire2` =
`SDA`=GPIO4, `SCL`=GPIO5. Enabling this menu permanently removes GPIO0-5
from the general-purpose GPIO pool (see [General GPIO](#general-gpio)) -
same tradeoff as AI Accelerator's LUT/BRAM cost, but for GPIO pins
instead. See `examples/ExtraSPII2CTest`.

### SD card

`#include <SD.h>` (`libraries/SD/`, plus `#include <SPI.h>`) **and**
select **Tools > SD Card: Enabled (GPLv3)** - unlike every other library
in this repo, `SD.h` won't compile (a deliberate `#error`) unless you've
explicitly made that menu choice; see [Tools menus](BUILDING.md#tools-menus)
for why. This is the real [arduino-libraries/SD](https://github.com/arduino-libraries/SD)
(**GPLv3** - see [Licensing](LICENSING.md)) talking to the onboard microSD slot
over the `SPI` library above, in standard SD-over-SPI mode - the same
electrical wiring the slot actually uses. Call `SD.begin(SS)`.

Two deliberate patches to the otherwise-vendored-unmodified code:

1. This hardware's SPI chip select is controlled internally by the SPI
   peripheral (asserted for a whole transaction), not through an arbitrary
   GPIO pin the way the SD library expects to toggle it directly.
   `pins_arduino.h` defines a virtual `SS` pin (10) that
   `wiring_digital.cpp`'s `digitalWrite()`/`digitalRead()` special-case to
   drive/read that hardware CS bit, so the vendored library's plain
   `pinMode()`/`digitalWrite()` calls on `SS` work unmodified; the actual
   edit is a small added architecture branch in
   `libraries/SD/src/utility/Sd2PinMap.h` (clearly marked in that file),
   since it otherwise `#error`s on any board it doesn't explicitly recognize.
2. The `TANGNANO20K_SD_ENABLED` guard at the top of `libraries/SD/src/SD.h`
   described above.

Enabling the menu doesn't change the gateware/bitstream at all -
`libraries/SD` is pure software on top of the always-present SPI
peripheral; the menu only gates whether `SD.h` compiles.

Untested on real hardware, like everything else in this repo (see
[Known limitations](KNOWN_LIMITATIONS.md)) - card detection, FAT parsing,
and the SPI timing this library assumes have not been exercised against
an actual card or the real gateware. See `examples/SDReadWrite`.

## Heap / `malloc`

The board's GW2AR-18 package has an **embedded** 64Mbit (8MB, 32-bit bus)
SDR SDRAM — not a separate chip, so it needs no `IO_LOC` pin constraints
(it's fixed internal package bonding), but it does need its own PLL-derived
clock (see [Clock architecture](#clock-architecture)). `gateware/src/sdram.v`
(vendored, see [Licensing](LICENSING.md)) is the controller;
`gateware/src/sdram_bus.v` bridges picorv32's word-oriented bus to its
byte-oriented interface and handles periodic refresh.
`cores/tangnano20k/tangnano20k_malloc.c` implements
`malloc()`/`free()`/`calloc()`/`realloc()` — a small first-fit, address-
sorted free list with coalescing (this is `-nostdlib`, so there is no libc
heap unless we provide one) — backed by that 8MB region. The internal
64KB block-RAM (program/data/stack) is **not** part of this heap. See
`examples/MallocTest`.

## AI accelerator

`#include <AIAccelerator.h>` (`libraries/AIAccelerator/`), select
**Tools > AI Accelerator: Enabled** (see [Tools menus](BUILDING.md#tools-menus) -
it's disabled by default, since unlike a software library it has a real
gateware cost whether or not a sketch uses it).

This is the compute engine from the standalone
[NanoTangAI](https://github.com/pschatzmann/NanoTangAI) project (same
author, Apache-2.0) - a row-parallel, lane-parallel INT8 dot-product
engine sized for TinyTTS's decoder (8 weight-tile rows, 16-wide SIMD
lanes, up to 16 taps) - but integrated directly onto this core's own
picorv32 bus (`gateware/src/ai_accel_bus.v`) instead of going through
NanoTangAI's original external SPI link to a *second* Tang Nano 20K board.
`gateware/src/dot_product_engine.v`, `dot_product_lane_array.v`,
`int8_mac_lane.v`, and `byte_interleave_ram.v` are vendored from that
project, with one deliberate deviation: `dot_product_engine.v`'s
`result_mem` array carries an added `(* ram_style = "block" *)`
attribute, the same BRAM-inference fix `gateware/src/sram8bit.v` needed
for the same reason (see [Known limitations](KNOWN_LIMITATIONS.md)) -
without it, this always-instantiated-when-enabled 128-entry array maps
onto distributed LUT logic instead of a BRAM block, a real cost that
caused a `nextpnr-himbaechel` placement failure ("no BELs remaining")
when combined with other LUT-hungry Tools menu options.

The API is a simplified, instance-based take on NanoTangAI's
`TangNanoAccelerator`: `AIAccelerator accel(cinPadded, k, rows);` sets
the tile shape at construction (instead of a separate `config()` call);
`begin()` then allocates this instance's own weight/results buffers on
the heap (constructors stay light - no allocation before `setup()`
runs); `loadWeights()` copies in the weight tile once, and `compute()`
returns the result pointer directly - no separate `getResults()` call,
and no `begin(SPIClass&, csPin, sckHz)`/`ping()`/`protocolVersion()`/
`computeDelayMicros()` at all, since there's no SPI link to manage or
probe. `compute()`'s underlying register read blocks in hardware until
the engine's `done` actually fires, rather than a software poll loop or
a delay sized from a cycle-count formula. See `examples/AIAcceleratorTest`.

**Multiple instances**: `AIAccelerator instanceA(...), instanceB(...);`
each keep their own weight tile and results buffer in heap-allocated
copies, letting a sketch juggle several weight tiles/shapes with a plain
C++ object per tile. There is only one physical engine
(`ai_accel_bus.v` isn't duplicated - real LUT/BRAM cost, same as the
Tools menu note above), so instances time-slice it: `compute()` only
re-pushes an instance's config/weights to hardware if a *different*
instance's `compute()` ran more recently - free if you stick to one
instance, one weight-tile reload if you alternate. Each instance's
`compute()` always blocks until its own result is ready before
returning, so there's no way to interleave two instances' in-flight
computations - one instance's `compute()` call fully finishes before
another instance's can start. See `examples/AIAcceleratorMultiInstanceTest`.

Untested on real hardware, like everything else in this repo - and more
than most, since it also inherits NanoTangAI's own from-simulation-only
status (see that project's README): its gateware has been checked
bit-exact against a reference kernel in RTL simulation, but never
synthesized or run on the actual chip.

## Interrupts

picorv32 is built with `ENABLE_IRQ(1)`, `ENABLE_IRQ_QREGS(0)` (see
`gateware/src/top.v`). The IRQ entry point (`cores/tangnano20k/irq_vec.S`)
lives at a fixed low address (`PROGADDR_IRQ=0x000`); normal program
execution starts at `PROGADDR_RESET=0x400` instead of `0x000` — see
`cores/tangnano20k/link_cmd.ld`. This is adapted directly from
[YosysHQ/picorv32](https://github.com/YosysHQ/picorv32)'s own official
`firmware/start.S`/`custom_ops.S` non-QREGS register save/restore sequence
and custom-0 opcode encodings (public domain) rather than hand-derived, since
there's no hardware here yet to verify a mistake against.

- `interrupts()`/`noInterrupts()` mask/unmask **all** maskable IRQ lines via
  picorv32's `maskirq` instruction (`cores/tangnano20k/irq_asm.S`) — like
  AVR's `sei()`/`cli()`, these aren't nesting-counted.
- `attachInterrupt(digitalPinToInterrupt(pin), callback, mode)` /
  `detachInterrupt()` work on the 21 `GPIO0`-`GPIO20` pins and `BTN1`
  (`digitalPinToInterrupt()` is the identity function on this core — the
  "interrupt number" is just the pin number, like SAMD/ESP32, not the old
  Uno-style 0/1 mapping). `mode` supports `CHANGE`, `RISING`, `FALLING`
  (not `LOW`, which needs a held-level interrupt this core doesn't
  implement). Backed by `gateware/src/extirq.v`, a small peripheral that
  watches all 22 pins for a level change each clock cycle and latches a
  sticky per-pin flag, driving picorv32's `irq[3]`; software classifies
  the edge direction by comparing the latched level against what it saw
  last time.
- `tone(pin, frequency, duration)`/`noTone(pin)` toggle `pin` from a
  repeating software timer (see below) — no dedicated gateware, since
  picorv32's own countdown timer is enough to hit useful audible
  frequencies.
- `#include <TangTimer.h>` (`libraries/TangTimer/`) — a general-purpose
  one-shot/repeating callback timer: `TangTimer t; t.begin(callback,
  interval_us, repeat);`. Runs the callback in interrupt context, same as
  `attachInterrupt()`.

All of the above share one software timer engine
(`cores/tangnano20k/tangnano20k_timer.h`/`wiring_irq.cpp`) driven by
picorv32's single built-in one-shot countdown timer (`irq[0]`, the `timer`
custom instruction): each active timer's deadline is an absolute tick count
against the free-running `systick` counter (not the countdown register
itself, which is only ever armed for whichever deadline is soonest), so
timers don't drift and re-arming never needs to "peek" a decrementing
register mid-countdown. There are `TANGNANO20K_SW_TIMER_COUNT` (6) slots
total; `tone()` always occupies one, leaving up to 5 concurrent `TangTimer`
instances.

See `examples/ButtonInterrupt`, `examples/ToneTest`,
`examples/TangTimerBlink`.

## Software Serial

`#include <SoftwareSerial.h>` (`libraries/SoftwareSerial/`) - a
bit-banged 8N1 UART on any two of the 21 `GPIO0`-`GPIO20` pins, for a
second/third serial port beyond the hardware `Serial` when you don't
need it fast: `SoftwareSerial ss(rxPin, txPin); ss.begin(9600);`.

- **Transmit** is blocking, bit-banged against the free-running
  `systick` counter with interrupts disabled for the whole byte to keep
  timing jitter-free - the same "blocks, no software buffering"
  tradeoff as this project's other blocking peripherals.
- **Receive** is interrupt-driven: `begin()` uses `attachInterrupt()`
  (see [Interrupts](#interrupts) above) to catch the start bit's edge,
  then the ISR busy-waits to sample the remaining bits and buffers the
  completed byte - so `available()`/`read()` are non-blocking. Because
  sampling happens *inside* that interrupt handler, receiving one byte
  blocks every other interrupt (timers, `tone()`, other
  `attachInterrupt()` callbacks, DMA completion, I2S's own background
  buffering, another `SoftwareSerial` instance's start-bit edge...) for
  roughly one byte period - keep baud rates modest (9600 is a safe
  default) and avoid overlapping traffic across multiple simultaneous
  instances if you can help it. Unlike the classic Arduino
  `SoftwareSerial`, there's no shared "listening" hardware to arbitrate
  between instances - each gets its own `attachInterrupt()` slot (one
  per GPIO pin already), so multiple instances can each buffer
  independently; `listen()`/`stopListening()` here just pause/resume
  that one instance's own interrupt, kept for API familiarity.
- `overflow()` reports (and clears) whether the small receive buffer
  (16 bytes) has dropped a byte since the last call - there's no flow
  control to slow a sender down.

See `examples/SoftwareSerialTest`.

## DMA

`#include <DMA.h>` (`libraries/DMA/`), backed by `gateware/src/dma_engine.v`
— the SoC's **first true second bus master**. Every other peripheral added
to this core is a new *slave* on picorv32's single-master bus, decoded the
same way `leds_sel`/`sram_sel`/etc. always have been; `dma_engine.v`
instead becomes bus master itself to copy memory in hardware instead of a
software loop. It has two independent modes:

- **Blocking**: `dmaCopyWords(dst, src, wordCount)` / `dmaCopy(dst, src,
  byteCount)`. Works for any address (SRAM, SDRAM, or a mix). Writing the
  `START` register hands the *entire* shared CPU request bus
  (`mem_valid`/`mem_addr`/`mem_wdata`/`mem_wstrb` in `top.v`) to the DMA
  engine, which issues its own read-then-write cycles against the same,
  unmodified address-decoded peripherals/memory every other master uses,
  while picorv32's own `mem_ready` is held low. Since picorv32 has no
  separate instruction bus, that stalls instruction fetch too — the CPU
  cannot run any other code during the transfer, and just resumes
  automatically, on the instruction after `dmaCopyWords()` returns, the
  instant the engine hands the bus back. There is nothing to poll: by the
  time any of your code after the call runs, the copy has already
  finished. This is a throughput accelerator for the copy itself, not a
  way to overlap a copy with other work. See `examples/DMACopyTest`.
- **Async**: `dmaCopyWordsAsync(dst, src, wordCount, callback)`. Returns
  immediately; `loop()` (and timers, `tone()`, `attachInterrupt()`
  callbacks, everything) keeps running normally while the copy happens in
  the background, and `callback` runs from interrupt context when it's
  done. This works by giving the async path its **own dedicated
  bus-master port straight into `gateware/src/sdram_bus.v`'s second port**
  (see that module), entirely bypassing the CPU's shared bus arbiter above
  — so it only ever reaches the embedded SDRAM heap (`dst`/`src` must both
  lie within `TANGNANO20K_SDRAM_BASE`/`TANGNANO20K_SDRAM_SIZE`;
  `dmaCopyWordsAsync()` returns `false` otherwise), and only one
  background transfer can be in flight at a time. `sdram_bus.v` arbitrates
  its one physical SDR SDRAM chip between the CPU's normal path and this
  dedicated DMA path at **word granularity** (the CPU always wins ties),
  so a long background copy never delays an ordinary CPU SDRAM access
  (e.g. a `malloc()`'d buffer touched from `loop()`) by more than the
  current in-flight word. Completion is a sticky interrupt (`irq[3]` is
  `extirq`; this is `irq[4]`), read-clear like `extirq`'s `STATUS`
  register — `dmaAsyncBusy()` polls the same register, so don't mix
  polling and the callback for the same transfer (whichever reads first
  clears it for the other). See `examples/DMAAsyncTest`, which blinks an
  LED from `loop()` throughout a 1MB background copy to make the
  difference from the blocking mode visible.

Async mode is deliberately scoped to SDRAM↔SDRAM: giving the internal SRAM
a second, independent port for true background SRAM copies too would need
true dual-port block RAM with both ports doing flexible read/write, which
this toolchain's BRAM inference cannot produce - see
[Known limitations](KNOWN_LIMITATIONS.md).

## Flash

The onboard SPI NOR flash (also used by the Gowin configuration engine to
boot the bitstream itself) is memory-mapped read-only at
`TANGNANO20K_FLASH_WINDOW_BASE` (`0x20000000`) via
`gateware/src/qspi_flash.v` - a raw window, like the SDRAM's convention
(`addr` is a byte offset within the flash chip). Layout:

| Offset | Contents |
|---|---|
| `0x000000` | Gowin bitstream |
| `0x100000` | Program partition: a 4-byte little-endian size, then the program bytes (Boot Mode: Flash only) |
| `0x110000` - end | Constant-data partition (`FLASH_DATA`) |

### Boot Mode (Tools menu)

- **SRAM (default)**: the sketch is baked directly into internal SRAM at
  synthesis time, exactly as every other peripheral in this core assumes.
  Every upload re-runs the full FPGA flow.
- **Flash**: `cores/tangnano20k/boot.S`, a fixed stub baked into SRAM as
  part of the *core* (not the sketch), copies the sketch's program from
  the flash's program partition into SRAM at `0x400` on reset, then jumps
  there - the sketch itself is linked exactly the same way as in SRAM
  mode (same `0x400` start address, same `link_cmd.ld` layout), so nothing
  about writing a sketch changes. `tools/upload.py` writes the program to
  flash via `openFPGALoader -f -o <offset>` instead of reprogramming the
  whole bitstream.

### Constant data (`FLASH_DATA`)

Independent of Boot Mode - available in either setting. Mark a big
`const` array with the `FLASH_DATA` attribute
(`cores/tangnano20k/tangnano20k_soc.h`) to place it in the flash's
constant-data partition instead of the 64KB internal SRAM:

```cpp
const uint8_t bigTable[4096] FLASH_DATA = { ... };
```

Reads happen through ordinary array/pointer syntax - no special API -
blocking via the same bus backpressure every other peripheral in this
design uses. `tools/build_bitstream.py` extracts the `.flash_data`
section's raw bytes from the compiled ELF; `tools/upload.py` writes them
to the flash's data partition as part of every upload, in either boot
mode. See `examples/FlashDataTest`.

## CPU features

**Tools > Hardware Multiply/Divide** (disabled by default) enables
picorv32's real M-extension (`ENABLE_MUL`/`ENABLE_DIV`/`ENABLE_FAST_MUL`
in `top.v`) instead of software-emulated integer multiply/divide. This
speeds up every integer `*`/`/`/`%` in a sketch, and indirectly speeds up
`float`/`double` math too, since libgcc's software floating-point
routines are themselves built from integer multiplies and shifts - see
[Known limitations](KNOWN_LIMITATIONS.md) for why floating-point itself
is always software-emulated regardless (picorv32 has no FPU option at
all). The compiler flag (`-march=rv32im_zicsr_zifencei` instead
of the default `rv32i2p0`) and the gateware always change together from
this one menu choice - never set independently, since a sketch compiled
expecting hardware `mul`/`div` would execute an illegal instruction on a
bitstream built without this enabled.

## Clock architecture

The system clock is derived from the board's fixed 27MHz oscillator (pin
4) through an on-chip PLL (`Gowin_rPLL_sys`, vendored from `nestang`'s
configuration) — **no one-time board setup is needed**. The PLL's
phase-shifted second output clocks the embedded SDRAM.

The output frequency is selectable via **Tools > Clock Speed**:

| Option | Frequency | Notes |
| --- | --- | --- |
| Normal (Recommended) | 27 MHz | Original, unchanged clock this core has always shipped with |
| Low Power | 13.5 MHz | Roughly half the dynamic power/heat/EMI; proportionally slower UART/I2S/WS2812 timing and sketch execution |
| Overclocked | 54 MHz | Verified against this design's synthesized timing (~75MHz closing frequency with default menu settings) and against `sdram.v`'s documented 66.7MHz SDRAM timing ceiling — both leave real margin. Enabling other gateware-cost menu options (AI Accelerator, Extra SPI/I2C, I2S Input) alongside this adds logic that may lower the design's actual closing frequency |

Every option regenerates both the PLL's dividers (`gowin_rpll_sys.v`) and
`sys_parameters.v`'s `CLK_FREQ` together (see `tools/build_bitstream.py`),
so UART baud rate, I2S sample rate, SPI clock, `millis()`/`micros()`, and
the SDRAM/WS2812 timing derived from `CLK_FREQ` in `top.v` all stay
consistent with whichever frequency is selected.

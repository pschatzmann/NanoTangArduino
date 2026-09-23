# Hardware test status

What has been verified on a real board, what hasn't yet, and the bugs
that only showed up there.

Tested on a Sipeed Tang Nano 20K (GW2AR-LV18QN88C8/I7, onboard BL616
debugger firmware 2025030317) in September 2026, with the default Tools
options (27MHz, Boot Mode: SRAM) and yosys 0.33, nextpnr-himbaechel
0.11.1 and apicula 0.33.

## Verified on the board

| Feature | How it was tested |
|---|---|
| Boot, CPU, C++ startup | Test sketches run `setup()`/`loop()`, including ones with several global constructors |
| Program memory (64KB SRAM) | Hardware self-test reading all 16,384 words of the block RAM |
| `Serial` output | `print()`/`println()` with every argument type (integers, `HEX`/`BIN`/`OCT`, floats, `String`), `printf()` including `%f` |
| `Serial` input | Bursts of up to 128 bytes received completely; `overflow()` stays clear (but see [the USB bridge limitation](KNOWN_LIMITATIONS.md)) |
| `millis()`/`micros()`/`delay()` | Checked against each other over several seconds |
| SDRAM heap | Word, halfword and byte access across all 8MB; a 64KB `malloc` pattern test; `new[]`/`delete[]`; unaligned `memcpy()` |
| SPI and the SD card | `SD.begin()`, writing a 2KB file, reading it back: 0 mismatches |
| I2S audio (onboard MAX98357A) | A clean continuous 440Hz sine at 44.1kHz (written in blocks of 64 frames); 22.05kHz square waves |
| `digitalRead()` and `attachInterrupt()` | The KEY2 button (`BTN1`): reads 1 while pressed, 0 released, one interrupt per change; the reset button restarts the SoC |
| Onboard LEDs | `digitalWrite()` |
| GPIO inputs, pull-ups, `OUTPUT_OPENDRAIN` | An unconnected pin reads HIGH with `INPUT_PULLUP`; open-drain drives LOW and releases HIGH |
| `analogWrite()`/PWM, `analogWriteResolution()`, `pulseIn()` | 1kHz at 25% measured 247/745us high/low with `pulseIn()` on the pin itself; 12-bit 50% measured 500us |
| `tone()` | 2kHz measured 247us half-periods; a 100ms tone stops on time |
| `attachInterrupt()` on a GPIO | 200 rising edges counted from a 1kHz PWM in 200ms |
| `Servo` | `write(90)` measured a 1469us pulse (1472 expected) |
| `TangTimer` | A 10ms periodic callback fired 99 times per second |
| DMA | Blocking SRAM/SDRAM copies and a background SDRAM copy with its completion callback, data verified |
| `Wire` (I2C) | A scan with nothing attached finds nothing and finishes in 35ms (no device tested yet) |
| SDRAM, full 8MB | A pattern over every word: 0 errors |

## Not yet tested on the board

- WS2812: onboard LED and external strips
- `Wire` talking to a real I2C device, and the second SPI/I2C bus
- `SoftwareSerial` (needs a jumper wire), CAN, PWM Audio, I2S input
- The AI accelerator (it builds and packs into a bitstream now, but hasn't run)
- Tools > Boot Mode: Flash and `FLASH_DATA`: not tried, because they
  overwrite what's stored in the board's flash
- The Compressed Instructions, Barrel Shifter and Hardware
  Multiply/Divide options, and the 13.5/54MHz clocks

## Bugs found on the board

All fixed. None of them showed up in simulation or synthesis, because
each depended on how the real chip, the toolchain or the software
actually behave:

1. **Block RAM never returned data.** yosys 0.33 ties each block RAM's
   output clock enable (`OCE`) low; on the real GW2AR-18 the output then
   never updates, so the CPU read garbage and trapped on its first
   instruction. `tools/build_bitstream.py` now drives `OCE` from the read
   enable (newer yosys ties it high itself).
2. **The default build linked a libgcc with multiply/divide
   instructions** (the SDK's top-level `libgcc.a` is built for rv32ima).
   64-bit division and all software floating point trapped on the plain
   RV32I CPU; the first `printf("%lu")` hung.
3. **SDRAM:** a request arriving while a refresh started was silently
   dropped (stale reads, lost writes), and every byte or halfword write
   also overwrote byte 0.
4. **C++ startup:** the constructor loop kept its state in registers a
   constructor may overwrite, so any sketch with several global objects
   (for example anything using `SD`) crashed before `setup()`.
5. **Interrupts were never enabled** before `setup()`, so everything
   interrupt-driven (I2S buffering, timers, `attachInterrupt()`...) was
   dead.
6. **The I2S library was far too slow**: an interrupt and a software
   division per sample, a 64-sample buffer in the slow SDRAM heap. It
   managed about 5,700 samples/s, so a 44.1kHz stream came out silent.
   Now samples go straight into the hardware FIFO when possible, the
   transmit interrupt fires only when the FIFO is half empty, and the
   buffer holds 512 samples in internal SRAM. A 44.1kHz stream written in
   blocks plays cleanly - but see the Serial limitation below.
7. **GPIO pins were output-only.** yosys 0.33 only builds a
   bidirectional pin from the plain `enable ? data : 1'bz` form, and
   `gpio_bank.v` used a nested conditional - so every GPIO got an output
   buffer and could never be read. Reading back a pin's own output still
   worked, which hid it.
8. **DMA hung.** The DMA engine took the bus in the same cycle it
   acknowledged the CPU's START write, so the CPU retried the write after
   the transfer (starting it again), and a late SRAM answer after the
   last access leaked into the CPU's next access.
9. **I2C never worked.** `Wire` updated the drive bits with a
   read-modify-write, but the register reads back pin *levels*: changing
   SDA also drove SCL low. A scan "found" all 126 addresses.

The SPI receive bug (every received byte shifted left by one) was found
in simulation beforehand; the SD card test confirmed the fix on the
board.

## Limitations found on the board

- **Long `Serial` prints during 44.1kHz audio cause clicks** with the
  default CPU settings (27MHz, no Barrel Shifter or Hardware
  Multiply/Divide). The sketch produces samples only slightly faster than
  they're played, so the buffer holds little reserve, and a print of more
  than about 32 characters stalls the CPU on the UART long enough to
  empty the I2S FIFO. Short prints are fine. Use a lower sample rate, the
  54MHz clock, or the CPU options for more headroom.
- The onboard USB bridge loses board-to-PC data during simultaneous
  two-way traffic - see [Known limitations](KNOWN_LIMITATIONS.md).

## Testing on the board yourself

- Load a bitstream into the FPGA's RAM (temporary; a power cycle restores
  what's in the flash): `openFPGALoader -b tangnano20k prog.fs`. If a
  load hangs at "Erase SRAM" (seen after an interrupted load), reset the
  FPGA with `openFPGALoader -b tangnano20k -r` and load again.
- `Serial` is the board's **second** USB serial port (`/dev/ttyUSB1` on
  Linux); the first one is the JTAG/programming interface.
- After the first build for a set of Tools options, test builds take
  seconds - see [Building: build times](BUILDING.md#build-times-and-the-routed-design-cache).

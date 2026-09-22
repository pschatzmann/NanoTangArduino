# NanoTangArduino

An Arduino board-support package for the [Sipeed Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html)
FPGA development board.

The Tang Nano 20K is a bare FPGA (Gowin GW2AR-18), not a microcontroller —
there's no silicon that runs Arduino sketches directly. This package
synthesizes a small RISC-V SoC (PicoRV32 + UART + LEDs + a free-running
timer) onto the FPGA fabric, and provides an Arduino core that targets that
SoC. "Uploading" a sketch means recompiling it for the SoC's CPU, baking the
resulting program into the SoC's block-RAM initialization, and re-running
the FPGA synthesis/place-and-route/pack flow to produce a new bitstream.

**Status: v2 milestone.** Blink + `Serial` (print only) on the 6 onboard
LEDs and the USB-UART, plus stereo I2S audio output to the onboard
MAX98357A amplifier via a new `I2S` object. See [Known limitations](#known-limitations-v1)
for a real, currently-blocking toolchain gap discovered while verifying
this milestone, and [Roadmap](#roadmap) for what's next.

## Architecture

```
sketch.ino ──arduino-cli/IDE──> RISC-V ELF (cores/tangnano20k + api/)
                                      │
                     tools/build_bitstream.py
                                      │
                    elf → bin → SRAM $readmemh init files
                                      │
                 yosys → nextpnr-himbaechel → gowin_pack
                                      │
                                  prog.fs
                                      │
                         tools/upload.py (openFPGALoader)
                                      │
                              Tang Nano 20K
```

- `gateware/` — the PicoRV32-based SoC (forked from
  [grughuhler/picorv32_tang_nano_20k](https://github.com/grughuhler/picorv32_tang_nano_20k),
  BSD-2-Clause), trimmed to LEDs + UART for v1 and extended with a
  free-running `systick` peripheral for `millis()`/`micros()` and an
  `i2s_tx` peripheral driving the onboard MAX98357A amplifier.
- `cores/tangnano20k/` — the Arduino core runtime (startup code, linker
  script, `HardwareSerial`, `TangNanoI2S`, digital I/O, timing), implementing
  the interfaces from [arduino/ArduinoCore-API](https://github.com/arduino/ArduinoCore-API)
  (vendored under `cores/tangnano20k/api/` — see
  [Updating the vendored ArduinoCore-API](#updating-the-vendored-arduinocore-api)).
- `variants/tangnano20k/` — pin definitions.
- `tools/` — the FPGA build (`build_bitstream.py`), SRAM-init generation
  (`gen_mem_init.py`), and upload (`upload.py`) scripts that `platform.txt`
  drives instead of a normal flash-and-run recipe.
- `boards.txt` / `platform.txt` — the Arduino board definition.

### Memory map

| Address        | Peripheral                              |
|----------------|------------------------------------------|
| `0x0000_0000`  | SRAM (32KB: program + data + stack)       |
| `0x8000_0000`  | LEDs, bits `[5:0]`, read/write            |
| `0x8000_0008`  | UART clock divisor register               |
| `0x8000_000C`  | UART data register                        |
| `0x8000_0020`  | `systick` free-running 32-bit up-counter  |
| `0x8000_0040`  | I2S BCLK divisor register (write)         |
| `0x8000_0044`  | I2S data register: `{left16,right16}` (write) |
| `0x8000_0048`  | I2S control register: bit0 = PA_EN (write) |

## Audio (I2S)

`I2S.begin(sampleRate)` enables the MAX98357A (`PA_EN`) and configures the
BCLK divisor for `sampleRate * 32` (16-bit stereo). `I2S.write(left, right)`
(or `I2S.writeMono(sample)`) pushes one stereo sample pair; like `Serial`'s
UART writes, this blocks via hardware bus backpressure rather than a
software timer — the `i2s_tx` peripheral (`gateware/src/i2s_tx.v`) only
asserts bus-ready for a new sample once the previous one has been picked up
by the shifter, which paces output to the configured sample rate
automatically. See `examples/I2SToneTest`. Pin numbers (`PA_EN`=51,
`DIN`=54, `WS`=55, `BCLK`=56) are confirmed against Sipeed's own
[audio example](https://github.com/sipeed/TangNano-20K-example/tree/main/audio).

Not yet verified on real hardware (see the toolchain gap below) — the exact
bit alignment of the I2S frame (`bit_cnt`/`frame_load` logic in `i2s_tx.v`)
follows the Philips/I2S convention but may need a one-`BCLK` tweak once you
can actually hear it.

## Known limitations (v1)

- **A pre-existing toolchain gap blocks full synthesis right now**, found
  while verifying the I2S milestone: with the `yosys` 0.33 build available
  in this environment, `synth_gowin` does not infer real Gowin block RAM for
  `gateware/src/sram8bit.v`'s 32KB SRAM array — it falls back to
  distributed LUT RAM (or worse, plain flip-flops with `-nolutram`),
  ballooning to 100K+ cells for a chip with only ~20K LUT4s. This is
  independent of the I2S peripheral (it reproduces with just the SRAM
  modules alone) and isn't a real Verilog bug — it's a mismatch between
  this yosys version's Gowin BRAM-inference rules and the reference
  project's memory coding style. **Before attempting a real board build,
  install a current, matched toolchain** (the
  [oss-cad-suite](https://github.com/YosysHQ/oss-cad-suite-build) bundle
  pins a yosys/nextpnr-himbaechel pair known to work together) and re-check
  with `yosys -p 'read_verilog gateware/src/sram8bit.v gateware/src/sram.v; synth_gowin -top sram'`
  — the cell count should land in the low thousands, not tens of thousands.
  If it still doesn't infer BRAM, `sram8bit.v`'s coding style will need
  reworking to match whatever inference template that yosys version expects.
- **Uploads are slow.** Every "upload" re-runs the full FPGA flow
  (synthesis → place & route → pack), typically a minute or more, because
  the program lives in block RAM initialized at synthesis time rather than
  in a separate program flash. A flash/XIP boot redesign to avoid this is
  on the [roadmap](#roadmap).
- **`millis()`/`micros()` wrap much sooner than a real Arduino board.**
  `systick` is a raw 20MHz cycle counter, so it wraps roughly every 214
  seconds (~3.5 minutes), versus ~49 days on AVR. Code that compares
  `millis()`/`micros()` with unsigned subtraction (the standard Arduino
  idiom, e.g. `if (millis() - last >= interval)`) is unaffected by wrapping
  at any period.
- **Only 6 "pins" exist**: the onboard LEDs (`pinMode`/`digitalWrite`/
  `digitalRead`, numbered 0-5, `LED_BUILTIN` = 0). There's no general GPIO
  header support, no `analogRead`/`analogWrite`, no interrupts, and `Serial`
  is print/receive only (no flow control, fixed 8N1).
- Only the RV32I base ISA is enabled (no hardware multiply/divide/compressed
  instructions), matching the reference SoC.

## Prerequisites

- **RISC-V compiler**: any bare-metal `rv32i2p0`/`ilp32`-capable GCC. This
  package defaults `compiler.path`/`compiler.prefix` in `platform.txt` to a
  Zephyr SDK toolchain (`riscv64-zephyr-elf-gcc`, which is multilib and
  supports rv32i); override both in a `platform.local.txt` next to
  `platform.txt` if yours lives elsewhere or uses a different prefix (e.g.
  `riscv32-unknown-elf-`).
- **yosys** (Verilog synthesis).
- **nextpnr-himbaechel**, built with the Gowin backend, for place & route.
  Not all yosys/apicula installs include this by default — the easiest path
  is the [YosysHQ oss-cad-suite](https://github.com/YosysHQ/oss-cad-suite-build)
  bundle, which ships yosys + nextpnr-himbaechel + apicula + openFPGALoader
  together. If building nextpnr from source, configure it with `-DARCH=himbaechel`.
- **[Apicula](https://github.com/YosysHQ/apicula)** (`gowin_pack`) for
  producing the final Gowin bitstream.
- **openFPGALoader** for programming the board over USB.
- **Python 3** (used by `tools/*.py`).

## Installing the board package

Arduino-cli/IDE discover third-party hardware under
`<sketchbook>/hardware/<vendor>/<architecture>/`. Symlink (or copy) this
repo into place, e.g.:

```sh
mkdir -p ~/Arduino/hardware/nanotang
ln -s /path/to/NanoTangArduino ~/Arduino/hardware/nanotang/tangnano20k
```

Then the board is available as FQBN `nanotang:tangnano20k:tangnano20k`:

```sh
arduino-cli compile --fqbn nanotang:tangnano20k:tangnano20k examples/Blink
arduino-cli upload  --fqbn nanotang:tangnano20k:tangnano20k -p /dev/ttyUSB1 examples/Blink
```

(`-p` is required by arduino-cli's CLI parsing but unused by the upload
recipe, which always targets the board via `openFPGALoader -b tangnano20k`.)

## One-time board setup

The Tang Nano 20K's onboard clock generator must be configured to output
20MHz on the pin the SoC uses as its system clock, per the upstream
picorv32_tang_nano_20k instructions:

1. Connect the Tang Nano 20K over USB.
2. Open a terminal emulator at 115200 baud (e.g. `picocom`).
3. Press Ctrl-X then Ctrl-C, then Enter — you should see a `TangNano20K` prompt.
4. Run `pll_clk O0=20M -s` (letter O, zero).
5. Run `choose uart` to switch back to the FPGA's own UART.

## Updating the vendored ArduinoCore-API

`ArduinoCore-API/` is a git submodule tracking the upstream repo.
`cores/tangnano20k/api/` is **not** the submodule itself — arduino-cli
recursively compiles every `.c`/`.cpp`/`.S` file under the core directory,
and the submodule's root also carries a Catch2 `test/` tree that isn't
meant to be built into a sketch. `tools/vendor_arduino_api.sh` copies just
the needed subset (all headers, plus only the `.cpp` files this core
actually links: `Common.cpp`, `Print.cpp`, `Stream.cpp` — `String.cpp`,
`IPAddress.cpp`, `CanMsg*.cpp`, and `PluggableUSB.cpp` need malloc/USB
support this bare-metal core doesn't provide yet, so their headers are
copied for API completeness but their implementations are left out).

After updating the submodule:

```sh
cd ArduinoCore-API && git pull origin main && cd ..
git add ArduinoCore-API
./tools/vendor_arduino_api.sh
git add cores/tangnano20k/api
```

## Roadmap

- **Fix Gowin BRAM inference** (see [Known limitations](#known-limitations-v1))
  and get a real bitstream through `nextpnr-himbaechel` + `gowin_pack` —
  the next concrete blocker before anything can run on actual hardware.
- **Verify I2S audio on real hardware** and correct bit-alignment if needed.
- **Flash/XIP boot** — boot from the onboard QSPI flash instead of
  synthesis-time block-RAM initialization, so uploading a new sketch is a
  quick flash write instead of a full FPGA rebuild.
- General GPIO header support beyond the 6 onboard LEDs.
- `analogWrite` (PWM) on the LEDs/GPIO.

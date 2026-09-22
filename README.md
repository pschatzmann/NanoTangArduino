# Arduino Core for Tang Nano 20k

An Arduino board-support package for the [Sipeed Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html) FPGA development board.

<img src="https://wiki.sipeed.com/hardware/zh/tang/tang-nano-20k/assets/nano_20k/tang_nano_20k_3920_top.png" alt="Sipeed Tang Nano 20K" width="300">

*Image credit: [Sipeed](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html).*


The Tang Nano 20K is a bare FPGA (Gowin GW2AR-18), not a microcontroller —
there's no silicon that runs Arduino sketches directly. This package
synthesizes a small RISC-V SoC (PicoRV32 + a handful of peripherals) onto
the FPGA fabric, and provides an Arduino core that targets that SoC.
By default, "uploading" a sketch means recompiling it for the SoC's CPU,
baking the resulting program into the SoC's internal block-RAM
initialization, and re-running the FPGA synthesis/place-and-route/pack
flow to produce a new bitstream. Tools > Boot Mode: Flash boots the
sketch from the onboard SPI flash instead, so uploading is a flash write
rather than a full FPGA rebuild - see
[Peripherals: Flash](docs/PERIPHERALS.md#flash).

**Status.** Implemented:

- `Serial`
- 6 onboard LEDs (`digitalWrite`/`digitalRead`/`analogWrite` PWM)
- General-purpose expansion-header GPIO
- Onboard WS2812 addressable LED
- Stereo I2S audio to the onboard MAX98357A amplifier (transmit), plus
  optional receive/full-duplex against an external I2S microphone
  (Tools > I2S Input)
- SPI and I2C (`Wire`), independently configurable 0/1/2 buses each
  (Tools > SPI Buses / I2C Buses) - a second port lands on GPIO0-3 (SPI2)
  / GPIO4-5 (I2C2)
- Reading/writing files on the onboard microSD card (`SD`)
- On-chip INT8 dot-product AI accelerator
- `String`
- `malloc`/`free`, backed by the board's embedded 8MB SDRAM
- Interrupts (`attachInterrupt()`, `tone()`, a `TangTimer` callback-timer library)
- `SoftwareSerial`, a bit-banged second serial port on any two GPIO pins
- Hardware-accelerated bulk memory copy (`DMA`), including a background/async mode
- Booting the sketch from the onboard SPI flash instead of internal SRAM (Tools > Boot Mode), and flash-mapped constant data (`FLASH_DATA`)
- Hardware multiply/divide (Tools > Hardware Multiply/Divide) - speeds up
  integer math and, indirectly, `float`/`double` math too (see
  [Known limitations](docs/KNOWN_LIMITATIONS.md) - there's no FPU, so
  floating-point is always software-emulated regardless)
- 64KB internal SRAM

See [Known limitations](docs/KNOWN_LIMITATIONS.md) for real gaps found
while building this, and [Roadmap](docs/ROADMAP.md) for what's next.
`gowin_pack` produces a real bitstream for the current design, but
**nothing here has been run on real hardware yet** - everything is
verified via `yosys`/`nextpnr-himbaechel` synthesis and place & route and
`arduino-cli compile`; see `tools/run_tests.sh`.

## Board specifications

Per [Sipeed's official page](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html):

| | |
|---|---|
| FPGA | Gowin **GW2AR-LV18QN88C8/I7** (GW2AR-18C) |
| LUT4 | 20,736 |
| Flip-flops | 15,552 |
| Block SRAM | 828 Kbit across 46 blocks |
| Shadow SRAM | 41,472 bits |
| 18×18 multipliers | 48 |
| PLLs | 2 |
| Embedded SDRAM | 32-bit SDR SDRAM, 64 Mbit (8MB) - this core's heap |
| External flash | 64 Mbit (SPI, bitstream storage) |
| Fixed oscillator | 27MHz crystal |
| Debug/UART/upload | onboard BL616 (USB-JTAG, USB-UART, USB-SPI) |
| Onboard LEDs | 6 regular + 1 WS2812 addressable RGB |
| Onboard buttons | 2 (reset + user key) |
| Storage | 1× microSD (TF) slot |
| Audio | MAX98357A I2S Class-D amplifier |
| Display | 40-pin RGB LCD connector + HDMI |
| Expansion | 34 free GPIO across two 2×20, 2.54mm headers (J5/J6) |
| Board size | 22.55mm × 54.04mm |

This package uses the fixed 27MHz oscillator (via an on-chip PLL, see
[Clock architecture](docs/PERIPHERALS.md#clock-architecture)), the
embedded SDRAM (heap), the microSD slot, the MAX98357A audio path, the
onboard LEDs/buttons, the WS2812, and the GPIO headers - see
[Peripherals](docs/PERIPHERALS.md) for what's implemented against each.
The onboard BL616's UART bridge carries `Serial` back to your computer
over the same USB cable (FPGA pins 69/70, confirmed against
[Sipeed's official schematic](https://dl.sipeed.com/shareURL/TANG/Nano_20K/2_Schematic)
and cross-checked against [nand2mario/nestang](https://github.com/nand2mario/nestang)'s
identical pin choice) - see
[Known limitations](docs/KNOWN_LIMITATIONS.md) for which USB port that
actually is. The BL616's JTAG/debug-probe function, HDMI, and RGB LCD
connector are not used by this core.

## Quick start

**Boards Manager** (once a release is published — see
[Releasing](docs/RELEASING.md)): add
`https://raw.githubusercontent.com/pschatzmann/arduino-tangnano20k/main/package_nanotang_index.json`
under Additional Boards Manager URLs, then install `nanotang:tangnano20k`
— this also installs a working RISC-V compiler automatically (Linux
x86_64, macOS Intel/Apple Silicon, or Windows 64-bit).

**Manual** (for development, or before a release exists):

```sh
mkdir -p ~/Arduino/hardware/nanotang
ln -s /path/to/arduino-tangnano20k ~/Arduino/hardware/nanotang/tangnano20k

arduino-cli compile --fqbn nanotang:tangnano20k:tangnano20k libraries/Core/examples/Blink
arduino-cli upload  --fqbn nanotang:tangnano20k:tangnano20k -p /dev/ttyUSB1 libraries/Core/examples/Blink
```

See [Building, installing, and verifying](docs/BUILDING.md) for
prerequisites, Tools menu options, and how to run the verification suite.

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — repo layout and the SoC's memory map.
- [Peripherals](docs/PERIPHERALS.md) — what each API does and how it maps
  to gateware/pins: digital I/O & PWM, general GPIO, I2S audio, SPI/I2C/SD
  card, heap/`malloc`, the AI accelerator, and clocking.
- [Building, installing, and verifying](docs/BUILDING.md) — prerequisites,
  installing the board package, Tools menu options, and `tools/run_tests.sh`.
- [Known limitations](docs/KNOWN_LIMITATIONS.md) — real, currently-blocking
  gaps (read this before attempting a real board build).
- [Licensing](docs/LICENSING.md) — this repo mixes permissive, GPLv3, and
  Apache-2.0 code; it matters which files you're looking at.
- [Updating the vendored ArduinoCore-API](docs/UPDATING_ARDUINOCORE_API.md)
- [Releasing](docs/RELEASING.md) — cutting a Boards Manager release.
- [Roadmap](docs/ROADMAP.md)

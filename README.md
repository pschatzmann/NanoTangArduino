# Arduino Core for Tang Nano 20k

An Arduino board-support package for the [Sipeed Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html) FPGA development board.

<img src="https://wiki.sipeed.com/hardware/zh/tang/tang-nano-20k/assets/nano_20k/tang_nano_20k_3920_top.png" alt="Sipeed Tang Nano 20K" width="300">

*Image credit: [Sipeed](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html).*

The Tang Nano 20K is a bare FPGA (Gowin GW2AR-18), not a microcontroller.
This package synthesizes a small RISC-V SoC (PicoRV32 + peripherals) onto
the FPGA and provides an Arduino core that targets it. Uploading a sketch
compiles it, bakes it into the SoC's block RAM and rebuilds the FPGA
bitstream (or, with Tools > Boot Mode: Flash, writes it to the onboard
SPI flash).

## Features

- [`Serial`, `printf`](docs/PERIPHERALS.md#serial-and-printf) and [`SoftwareSerial`](docs/PERIPHERALS.md#software-serial)
- [Onboard LEDs, GPIO, PWM](docs/PERIPHERALS.md#digital-io-and-pwm), `tone()`, `Servo`
- [Onboard WS2812 and external NeoPixel strips](docs/PERIPHERALS.md#ws2812-led)
- [I2S audio](docs/PERIPHERALS.md#audio-i2s) (onboard MAX98357A, optional microphone input) and [PWM audio](docs/PERIPHERALS.md#audio-pwm)
- [SPI, I2C (`Wire`) and the microSD card (`SD`)](docs/PERIPHERALS.md#spi-i2c-wire-and-the-sd-card)
- [CAN bus](docs/PERIPHERALS.md#can) with the standard `HardwareCAN` API
- [8MB SDRAM heap](docs/PERIPHERALS.md#heap--malloc) for `malloc`/`new`/`String`
- [INT8 dot-product AI accelerator](docs/PERIPHERALS.md#ai-accelerator)
- [Interrupts and `TangTimer`](docs/PERIPHERALS.md#interrupts)
- [DMA](docs/PERIPHERALS.md#dma) memory copy, blocking or in the background
- [Booting from flash and `FLASH_DATA`](docs/PERIPHERALS.md#flash)
- [CPU options](docs/PERIPHERALS.md#cpu-features): compressed instructions,
  barrel shifter, hardware multiply/divide, clock speed

Most of this has been [tested on a real board](docs/HARDWARE_STATUS.md);
the rest is verified in simulation and by the build test suite. See
[Known limitations](docs/KNOWN_LIMITATIONS.md) and the
[Roadmap](docs/ROADMAP.md).

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
| Embedded SDRAM | 32-bit SDR SDRAM, 64 Mbit (8MB) |
| External flash | 64 Mbit (SPI, bitstream storage) |
| Fixed oscillator | 27MHz crystal |
| Debug/UART/upload | onboard BL616 (USB-JTAG, USB-UART, USB-SPI) |
| Onboard LEDs | 6 regular + 1 WS2812 addressable RGB |
| Onboard buttons | 2 (reset + user key) |
| Storage | 1× microSD (TF) slot |
| Audio | MAX98357A I2S Class-D amplifier |
| Display | 40-pin RGB LCD connector + HDMI (not used by this core) |
| Expansion | 34 free GPIO across two 2×20, 2.54mm headers (J5/J6) |
| Board size | 22.55mm × 54.04mm |

## Quick start

In the Arduino IDE, add
`https://raw.githubusercontent.com/pschatzmann/arduino-tangnano20k/main/package_nanotang_index.json`
under Additional Boards Manager URLs and install `nanotang:tangnano20k`.
This also installs the RISC-V compiler. The FPGA toolchain and
alternatives (arduino-cli, manual install for development) are covered in
[Building, installing, and verifying](docs/BUILDING.md).

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — repo layout, memory map, gateware notes
- [Peripherals](docs/PERIPHERALS.md) — each API and how it maps to gateware and pins
- [Building, installing, and verifying](docs/BUILDING.md) — prerequisites, Tools menus, tests
- [Hardware test status](docs/HARDWARE_STATUS.md)
- [Known limitations](docs/KNOWN_LIMITATIONS.md)
- [Licensing](docs/LICENSING.md) — permissive, GPLv3 and Apache-2.0 code are mixed
- [Updating the vendored ArduinoCore-API](docs/UPDATING_ARDUINOCORE_API.md)
- [Releasing](docs/RELEASING.md)
- [Roadmap](docs/ROADMAP.md)

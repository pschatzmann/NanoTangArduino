# Architecture

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
  [grughuhler/picorv32_tang_nano_20k](https://github.com/grughuhler/picorv32_tang_nano_20k)),
  extended with: a free-running `systick` peripheral (`millis()`/
  `micros()`), `i2s` (MAX98357A audio, plus an optional receive path for
  an external I2S microphone), `pwm6` (`analogWrite()` on the
  LEDs), `spi_master` and `od_gpio2` (bit-banged I2C), `gpio_bank`
  (general-purpose expansion-header GPIO), `ws2812b`/`ws2812b_tgt` (the
  onboard addressable RGB LED), `extirq` (pin-change source for
  `attachInterrupt()` — see [Interrupts](PERIPHERALS.md#interrupts)),
  `dma_engine` (the SoC's second bus master, see
  [DMA](PERIPHERALS.md#dma)),
  `qspi_flash` (the onboard SPI flash - boot mode and constant data, see
  [Flash](PERIPHERALS.md#flash)),
  `ai_accel_bus`/`dot_product_engine` (the
  optional [AI accelerator](PERIPHERALS.md#ai-accelerator)), and
  `sdram`/`sdram_bus` (the embedded 8MB heap) plus the
  `Gowin_rPLL_sys` PLL that clocks it all from the board's fixed 27MHz
  oscillator.
- `cores/tangnano20k/` — the Arduino core runtime: startup code, linker
  script, `HardwareSerial`, digital/analog I/O, timing, `malloc`. This is
  what every sketch links against; kept deliberately minimal given the
  64KB internal SRAM budget. Implements the interfaces from
  [arduino/ArduinoCore-API](https://github.com/arduino/ArduinoCore-API)
  (vendored under `cores/tangnano20k/api/` — see
  [Updating the vendored ArduinoCore-API](UPDATING_ARDUINOCORE_API.md)).
- `libraries/` — bundled, opt-in libraries (`SPI`, `Wire`, `I2S`, `SD`,
  `AIAccelerator`, `WS2812`, `TangTimer`, `DMA`, `SoftwareSerial`), the
  same pattern real Arduino cores (AVR, ESP32, ...) use: a sketch only
  links one in if it does `#include <SPI.h>` / `#include <Wire.h>` /
  `#include <I2S.h>` / `#include <SD.h>` / `#include <AIAccelerator.h>` /
  `#include <TangTimer.h>` / `#include <DMA.h>` /
  `#include <SoftwareSerial.h>`, same as on any other board - keeping
  `Blink` and similar sketches from linking in
  SPI/I2C/I2S/etc. code they never call.
- `variants/tangnano20k/` — pin definitions.
- `tools/` — the FPGA build (`build_bitstream.py`), SRAM-init generation
  (`gen_mem_init.py`), upload (`upload.py`), ArduinoCore-API vendoring
  (`vendor_arduino_api.sh`), and verification (`run_tests.sh`) scripts.
- `boards.txt` / `platform.txt` — the Arduino board definition.

## Memory map

| Address                     | Peripheral                                        |
|------------------------------|---------------------------------------------------|
| `0x0000_0000`                | Internal SRAM (64KB: program + data + stack)       |
| `0x8000_0000`                | LEDs, bits `[5:0]`, read/write                     |
| `0x8000_0008`                | UART clock divisor register                        |
| `0x8000_000C`                | UART data register                                 |
| `0x8000_0020`                | `systick` free-running 32-bit up-counter           |
| `0x8000_0040`                | I2S BCLK divisor register (write)                  |
| `0x8000_0044`                | I2S transmit data register: `{left16,right16}` (write) |
| `0x8000_0048`                | I2S control register: bit0 = PA_EN (write)         |
| `0x8000_004C`                | I2S receive data register: `{left16,right16}` (read, blocks - Tools > I2S Input only) |
| `0x8000_0050`                | KEY_S2 button, bit0, read-only                     |
| `0x8000_0060`-`0x8000_0074`  | PWM duty/enable, one reg per LED channel 0-5       |
| `0x8000_0080`                | SPI SCLK divisor register (write)                  |
| `0x8000_0084`                | SPI CS register: bit0 = asserted (write)           |
| `0x8000_0088`                | SPI data register (read/write)                     |
| `0x8000_0090`                | I2C open-drain SDA/SCL: write=drive low, read=level|
| `0x8000_00A0`                | SPI2 SCLK divisor register (write) - Tools > Extra SPI/I2C only |
| `0x8000_00A4`                | SPI2 CS register: bit0 = asserted (write) - Tools > Extra SPI/I2C only |
| `0x8000_00A8`                | SPI2 data register (read/write) - Tools > Extra SPI/I2C only |
| `0x8000_00B0`                | I2C2 open-drain SDA/SCL - Tools > Extra SPI/I2C only |
| `0x8000_0100`                | GPIO direction register (bits [20:0], 1=output)    |
| `0x8000_0104`                | GPIO output register (bits [20:0])                 |
| `0x8000_0108`                | GPIO input register (bits [20:0], read-only)       |
| `0x8000_0110`                | WS2812 LED: write `{G[7:0],R[7:0],B[7:0]}` (write, blocks until accepted) |
| `0x8000_0120`                | External-interrupt ENABLE register (bits [21:0], see [Peripherals](PERIPHERALS.md#interrupts)) |
| `0x8000_0124`                | External-interrupt STATUS register (read-clears)   |
| `0x8000_0128`                | External-interrupt LEVEL register (read-only)      |
| `0x8000_0130`-`0x8000_013C`  | DMA SRC/DST/LEN/START registers (see [Peripherals](PERIPHERALS.md#dma)) |
| `0x8000_0140`-`0x8000_015C`  | AI accelerator registers (see [Peripherals](PERIPHERALS.md#ai-accelerator)) |
| `0x8000_0160`                | I2S IRQ_ENABLE: bit0=TX room, bit1=RX data (read/write, see [Peripherals](PERIPHERALS.md#audio-i2s)) |
| `0x8000_0164`                | I2S STATUS: bits[4:0]=TX FIFO free slots, bits[9:5]=RX FIFO count (read-only) |
| `0x1000_0000`-`0x107f_ffff`  | Embedded SDRAM, 8MB (heap - see [Peripherals](PERIPHERALS.md#heap--malloc)) |
| `0x2000_0000`-`0x207f_ffff`  | Onboard SPI flash, memory-mapped read-only (boot/constant data - see [Peripherals](PERIPHERALS.md#flash)) |

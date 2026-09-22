# Building, installing, and verifying

## Prerequisites

- **RISC-V compiler**: any bare-metal `rv32i2p0`/`ilp32`-capable GCC.
  Installing via [Boards Manager](#installing-via-boards-manager) gets you
  one automatically (a Zephyr SDK `riscv64-zephyr-elf-gcc`, which is
  multilib and supports rv32i) for Linux x86_64, macOS Intel/Apple
  Silicon, or Windows 64-bit - see [Releasing](RELEASING.md) for how those
  archives are produced. Installing manually (below), you
  need one yourself; override `compiler.path`/`compiler.prefix` in a
  `platform.local.txt` next to `platform.txt` if yours lives elsewhere or
  uses a different prefix (e.g. `riscv32-unknown-elf-`).
- **yosys** (Verilog synthesis) — see the BRAM-inference caveat in
  [Known limitations](KNOWN_LIMITATIONS.md) about version matching.
- **nextpnr-himbaechel**, built with the Gowin backend, for place & route.
  Not all yosys/apicula installs include this by default — the easiest path
  is the [YosysHQ oss-cad-suite](https://github.com/YosysHQ/oss-cad-suite-build)
  bundle, which ships yosys + nextpnr-himbaechel + apicula + openFPGALoader
  together. If building nextpnr from source, configure it with `-DARCH=himbaechel`.
- **[Apicula](https://github.com/YosysHQ/apicula)** (`gowin_pack`) for
  producing the final Gowin bitstream.
- **openFPGALoader** for programming the board over USB.
- **Python 3** (used by `tools/*.py`) and **bash** (`tools/run_tests.sh`).

## Installing via Boards Manager

Once a release is published (see [Releasing](RELEASING.md)), add this URL
under Arduino IDE's Preferences > "Additional Boards Manager URLs" (or
`arduino-cli`'s `--additional-urls`):

```
https://raw.githubusercontent.com/pschatzmann/arduino-tangnano20k/main/package_nanotang_index.json
```

Then install `nanotang:tangnano20k` from Boards Manager (IDE) or:

```sh
arduino-cli core update-index --additional-urls <url above>
arduino-cli core install nanotang:tangnano20k --additional-urls <url above>
```

This installs the board files *and* a working RISC-V compiler (Linux
x86_64, macOS Intel/Apple Silicon, or Windows 64-bit) with no other manual
steps - skip ahead to [Tools menus](#tools-menus) below.

## Installing manually (for development, or before a release exists)

Arduino-cli/IDE discover third-party hardware under
`<sketchbook>/hardware/<vendor>/<architecture>/`. Symlink (or copy) this
repo into place, e.g.:

```sh
mkdir -p ~/Arduino/hardware/nanotang
ln -s /path/to/arduino-tangnano20k ~/Arduino/hardware/nanotang/tangnano20k
```

Then the board is available as FQBN `nanotang:tangnano20k:tangnano20k`:

```sh
arduino-cli compile --fqbn nanotang:tangnano20k:tangnano20k examples/Blink
arduino-cli upload  --fqbn nanotang:tangnano20k:tangnano20k -p /dev/ttyUSB1 examples/Blink
```

(`-p` is required by arduino-cli's CLI parsing but unused by the upload
recipe, which always targets the board via `openFPGALoader -b tangnano20k`.)

## Tools menus

`boards.txt` exposes several Tools menus (in the IDE) / FQBN suffixes (on
the CLI). Combine as many as needed, e.g.:

```sh
arduino-cli compile --fqbn nanotang:tangnano20k:tangnano20k:optimize=fastest,sd_card=enabled examples/SDReadWrite
```

### Optimize

Controls the compiler's optimization level - not just a speed/size
tradeoff here, since the whole program has to fit in 64KB of internal SRAM:

| Option | Flags | FQBN suffix |
|---|---|---|
| Small (default) | `-Os` | `:optimize=small` |
| Fast | `-O2` | `:optimize=fast` |
| Fastest | `-O3` | `:optimize=fastest` |
| Debug | `-Og -g` | `:optimize=debug` |

`-g` debug info isn't part of what `tools/build_bitstream.py` bakes into
SRAM (it lives outside the `.elf`'s loadable sections), so Debug doesn't
cost SRAM budget - only `-O2`/`-O3`'s larger code does.

### AI Accelerator

Controls whether `gateware/src/ai_accel_bus.v` (see
[AI accelerator](PERIPHERALS.md#ai-accelerator)) is synthesized into the
bitstream at all - **disabled by default**. Unlike a software library,
gateware isn't free just because a sketch doesn't call it: everything in
`top.v` gets built into every bitstream, and this accelerator's 9
memories + 128 multiply lanes are a real LUT/BRAM cost whether or not a
sketch uses it.

| Option | FQBN suffix |
|---|---|
| Disabled (default) | `:ai_accel=disabled` |
| Enabled | `:ai_accel=enabled` |

### SD Card

Controls whether `libraries/SD/src/SD.h` compiles at all - **disabled by
default**, for a different reason than AI Accelerator: `libraries/SD` is
GPLv3 (see [Licensing](LICENSING.md)), and compiling it in makes your
sketch's binary a GPLv3 derivative. Requiring this explicit menu choice,
not just an `#include <SD.h>`, means that only happens when you've
actually chosen it - enabling it doesn't change the gateware/bitstream at
all.

| Option | FQBN suffix |
|---|---|
| Disabled (default) | `:sd_card=disabled` |
| Enabled (GPLv3) | `:sd_card=enabled` |

### C++ Exceptions

Passes `-fexceptions` instead of the default `-fno-exceptions`. **Disabled
by default, and not a "just flip it on" toggle even when enabled**: this
core is `-nostdlib` with no libsupc++/libstdc++, so `__cxa_throw`,
`_Unwind_Resume`, and `__gxx_personality_v0` are still unresolved unless
you bring your own freestanding C++ runtime support. This menu exists as a
starting point for that, not a working `throw`/`catch` out of the box.

| Option | FQBN suffix |
|---|---|
| Disabled (default) | `:exceptions=disabled` |
| Enabled | `:exceptions=enabled` |

### Boot Mode

See [Peripherals: Flash](PERIPHERALS.md#flash). **SRAM (default)** keeps
the sketch baked directly into internal SRAM, resynthesizing on every
upload. **Flash** boots a fixed stub that copies the sketch from the
onboard SPI flash instead, so `tools/upload.py` writes to flash rather
than reprogramming the whole bitstream.

| Option | FQBN suffix |
|---|---|
| SRAM (default) | `:boot_mode=sram` |
| Flash | `:boot_mode=flash` |

### SPI Buses / I2C Buses

See [Peripherals: SPI, I2C (Wire), and the SD card](PERIPHERALS.md#a-second-spi--i2c-port).
Independent menus, each defaulting to **One** - the original,
always-present primary port. **None** removes that port's gateware
entirely (saves LUTs; `SPI`/`Wire`, and anything built on them like `SD`,
silently read back 0/no-op instead of hanging). **Two** adds a second,
independent port (`SPI2` on GPIO0-3, `Wire2` on GPIO4-5), removing those
pins from the general-purpose GPIO pool.

| Option | FQBN suffix |
|---|---|
| None | `:spi_buses=none` / `:i2c_buses=none` |
| One (default) | `:spi_buses=one` / `:i2c_buses=one` |
| Two | `:spi_buses=two` / `:i2c_buses=two` |

### Hardware Multiply/Divide

See [Peripherals: CPU features](PERIPHERALS.md#cpu-features).
**Disabled by default** - enabling it switches the compiler to
`-march=rv32im_zicsr_zifencei` and picorv32 to real hardware
multiply/divide, together. Never mix a binary built with one setting
against a bitstream built with the other.

| Option | FQBN suffix |
|---|---|
| Disabled (default) | `:hw_muldiv=disabled` |
| Enabled | `:hw_muldiv=enabled` |

### I2S Input

See [Peripherals: Audio (I2S)](PERIPHERALS.md#audio-i2s). **Disabled by
default** - enabling it wires `GPIO6` to the I2S peripheral's receive
input for an external microphone, removing that pin from the
general-purpose GPIO pool.

| Option | FQBN suffix |
|---|---|
| Disabled (default) | `:i2s_rx=disabled` |
| Enabled | `:i2s_rx=enabled` |

## Verifying changes

```sh
tools/run_tests.sh          # yosys hierarchy check + compile every example
tools/run_tests.sh --full   # also run one standalone full synth_gowin pass on the gateware (slow, ~1-2 min)
```

Every example compile goes through the full FPGA flow (synthesis, place &
route, and pack), the same as an actual upload in the default SRAM boot
mode - with a full nextpnr-himbaechel install, running the whole suite
against every example can take a long time (each example's place & route
alone can run several minutes). This is the extent of verification
possible without the physical board: it confirms the gateware elaborates/
synthesizes, every example compiles and links, and (when nextpnr-himbaechel
succeeds) that a real bitstream is produced - but it cannot confirm a
bitstream programs correctly or that anything actually works once running.

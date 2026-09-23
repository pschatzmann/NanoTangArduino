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
- **yosys** (Verilog synthesis). Tested with 0.33, what Linux
  distributions ship; its Gowin block-RAM mapping has a bug that
  `tools/build_bitstream.py` corrects automatically (see
  [Known limitations](KNOWN_LIMITATIONS.md)). Newer versions work too.
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
arduino-cli compile --fqbn nanotang:tangnano20k:tangnano20k libraries/Core/examples/Blink
arduino-cli upload  --fqbn nanotang:tangnano20k:tangnano20k -p /dev/ttyUSB1 libraries/Core/examples/Blink
```

(`-p` is required by arduino-cli's CLI parsing but unused by the upload
recipe, which always targets the board via `openFPGALoader -b tangnano20k`.)

## Tools menus

`boards.txt` exposes several Tools menus (in the IDE) / FQBN suffixes (on
the CLI). Combine as many as needed, e.g.:

```sh
arduino-cli compile --fqbn nanotang:tangnano20k:tangnano20k:optimize=fastest,sd_card=enabled libraries/SD/examples/SDReadWrite
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
the sketch baked directly into internal SRAM; after the first build for a
set of Tools options, a new sketch only takes seconds to build (see
[Build times](#build-times-and-the-routed-design-cache)). **Flash** boots a fixed stub that copies the sketch from the
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

### PWM Audio

See [Peripherals: Audio (PWM)](PERIPHERALS.md#audio-pwm). **Disabled by
default** - enabling it synthesizes the PWM audio peripheral onto
`GPIO16` (left) and `GPIO17` (right), removing both pins from the
general-purpose GPIO pool.

| Option | FQBN suffix |
|---|---|
| Disabled (default) | `:pwm_audio=disabled` |
| Enabled | `:pwm_audio=enabled` |

### Flash Cache

See [Peripherals: Flash](PERIPHERALS.md#flash). **Disabled by default** -
enabling it adds a 512-byte read cache in front of the onboard flash
(faster `FLASH_DATA`/`PROGMEM` reads and flash boot) at a cost of ~1,700
LUT4s.

| Option | FQBN suffix |
|---|---|
| Disabled (default) | `:flash_cache=disabled` |
| Enabled | `:flash_cache=enabled` |

### Compressed Instructions

See [Peripherals: CPU features](PERIPHERALS.md#cpu-features). **Disabled
by default** - enabling it builds the CPU with the RISC-V "C" extension
and compiles with a matching `-march`, for about 18% smaller code at the
cost of some LUTs.

| Option | FQBN suffix |
|---|---|
| Disabled (default) | `:compressed=disabled` |
| Enabled | `:compressed=enabled` |

### Barrel Shifter

See [Peripherals: CPU features](PERIPHERALS.md#cpu-features). **Disabled
by default** - enabling it makes every shift single-cycle, for a few
hundred LUTs. Gateware only; the compiler flags don't change.

| Option | FQBN suffix |
|---|---|
| Disabled (default) | `:barrel_shifter=disabled` |
| Enabled | `:barrel_shifter=enabled` |

### CAN

See [Peripherals: CAN](PERIPHERALS.md#can). **Disabled by default** -
enabling it synthesizes the CAN controller for `libraries/CAN`. Its pins
are chosen at run time, so it claims no GPIO pin up front.

| Option | FQBN suffix |
|---|---|
| Disabled (default) | `:can=disabled` |
| Enabled | `:can=enabled` |

## Build times and the routed-design cache

With the default Tools > Boot Mode: SRAM, the sketch's program is baked
into the FPGA's block RAM, so every upload is a new bitstream. But for a
given set of Tools options the placed-and-routed design is the same for
every sketch - only the RAM contents differ. So `tools/build_bitstream.py`
caches the routed design:

- The **first build** for a combination of Tools options runs the full
  flow (synthesis, place & route, pack): typically 15-25 minutes.
- **Every later build** with the same options only writes the new program
  into the cached design and packs it: about **6 seconds** in total.

The cache lives in `~/.cache/nanotang/routed/`, a few MB per option
combination. Its key covers the gateware sources, the pin constraints,
the Tools options, this package's version (so a new release always
rebuilds), `build_bitstream.py` itself, and the yosys, nextpnr and
apicula versions; deleting the directory is always safe. Set
`NANOTANG_NO_ROUTED_CACHE=1` to force the full flow. Tools > Boot Mode:
Flash has its own cache of the core bitstream, keyed the same way.

Full builds write several hundred MB of intermediate files to the
temporary directory. If `/tmp` is on a small partition, point `TMPDIR`
somewhere with room, e.g. `TMPDIR=~/tmp arduino-cli compile ...`.

## FPGA resource usage

How much of the GW2AR-18's logic each Tools option costs, from place &
route. Each row is the default configuration (one SPI bus, one I2C bus,
27MHz, SRAM boot) with that one option added:

| Configuration | LUT4 (of 20,736) | vs. default | Max clock after routing |
|---|---|---|---|
| Minimal (Tools > SPI Buses / I2C Buses: None) | 10,327 (50%) | -426 | 79.8 MHz |
| **Default** | **10,753 (52%)** | - | 74.3 MHz |
| + Barrel Shifter | 10,678 | ~0 | not measured |
| + SPI Buses: Two | 11,173 | +420 | 71.9 MHz |
| + I2C Buses: Two | 11,284 | +531 | 73.7 MHz |
| + Compressed Instructions | 11,403 | +650 | 66.8 MHz |
| + Hardware Multiply/Divide | 11,476 | +723 | not measured |
| + PWM Audio | 11,775 | +1,022 | 71.6 MHz |
| + I2S Input | 11,924 | +1,171 | 74.4 MHz |
| + Flash Cache | 12,983 | +2,230 | not measured |
| + CAN | 13,225 | +2,472 | 75.6 MHz |
| + AI Accelerator | 14,306 (69%) | +3,553 | 68.8 MHz |

Notes:

- The costs add up roughly when options are combined, so most
  combinations fit, but everything at once would not.
- Other resources: the default design uses 32 of the 46 block RAMs (the
  64KB internal SRAM) and about 3,500 of 15,552 flip-flops. The AI
  accelerator adds 9 block RAMs and 32 of the 96 MULT9X9 DSP blocks.
  Hardware Multiply/Divide uses DSP blocks too.
- Differences below about 300 LUT4s are within run-to-run variation of the
  synthesis and placement tools, which is why the Barrel Shifter (a few
  hundred LUTs in synthesis) shows up as roughly zero here.
- Tools > Boot Mode: Flash showed no measurable difference in synthesis.
- Every configuration whose routing was measured runs well above the
  54MHz Overclocked setting. For Hardware Multiply/Divide, nextpnr's
  estimate before routing was 54.4MHz - right at that limit - so check
  timing before combining it with Overclocked.
- Measured on 2026-09-23 with yosys 0.33, nextpnr-himbaechel 0.11.1 and
  apicula 0.33. `tools/run_tests.sh --utilization` prints these figures
  for the option combinations it builds.

## Verifying changes

```sh
tools/run_tests.sh                 # yosys check + tools/sim tests + compile every example,
                                   # then the FPGA flow once per Tools option combination
tools/run_tests.sh --compile-only  # skip the FPGA flow - a couple of minutes in total
tools/run_tests.sh --utilization   # also build the CPU options no example uses (LUT figures)
tools/run_tests.sh --full          # also run one standalone synth_gowin pass on the gateware
```

Every example is compiled and linked against this checkout (a temporary
arduino-cli config points at it, so an installed Boards Manager release
can't be picked up instead). The FPGA flow only depends on the Tools
options, not on the sketch, so it runs once per distinct option
combination the examples use, and prints nextpnr's device utilization for
each.

`tools/sim/run_sims.sh` (also run on its own in seconds) simulates the
Arduino-core gateware with iverilog - systick counters, UART FIFOs,
GPIO/LED set/clear registers, SPI in all four modes against a
spec-following slave model, WS2812 strip streaming - and tests the core's
`printf` family and `mem*()` functions against glibc on the host. Needs
`iverilog` and a host `gcc`; each part is skipped with a warning if the
tool is missing.

Each FPGA build (synthesis, place & route, and pack) is the same as an
actual upload in the default SRAM boot mode, and place & route alone can
take 20 minutes or more, so a full run takes hours. This confirms the
gateware elaborates and synthesizes, every example compiles and links,
and a real bitstream is produced - but not that everything works on the
chip: several real bugs only showed up there (see
[Hardware test status](HARDWARE_STATUS.md)).

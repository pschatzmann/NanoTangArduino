# Licensing

This repo mixes licenses, and it matters which files you're looking at:

- Everything **except** `gateware/src/sdram.v` is permissively licensed
  (ISC for `picorv32.v`; BSD-2-Clause for most of the rest of `gateware/`,
  forked from grughuhler/picorv32_tang_nano_20k; the core/software side has
  no license restriction beyond ArduinoCore-API's own LGPL-2.1+ terms for
  the files vendored under `cores/tangnano20k/api/`).
- `gateware/src/sdram.v` (the embedded-SDRAM controller, vendored from
  Sipeed's own `nestang` example, by nand2mario) is **GPLv3**. Because it's
  synthesized into the same bitstream as the rest of `gateware/`, that
  makes the **gateware as a whole a GPLv3 derivative work** — a deliberate
  choice to reuse a controller already proven on this exact chip rather
  than write an untested one from scratch. This doesn't affect your
  `.ino` sketches; it's about the FPGA bitstream/gateware sources
  specifically.
- `libraries/SD/` (vendored, unmodified except two deliberate patches - see
  [Peripherals: SD card](PERIPHERALS.md#sd-card)) is also **GPLv3**
  (`arduino-libraries/SD`, by Arduino/SparkFun/William Greiman - see
  `libraries/SD/LICENSE.txt`). This one **does** reach your sketch: any
  `.ino` that does `#include <SD.h>` and gets compiled produces a
  GPLv3-derivative binary, same as it always has on every other Arduino
  board that ships this exact library - not a new situation this repo
  introduces. One of the two patches requires you to explicitly select
  **Tools > SD Card: Enabled (GPLv3)** before `SD.h` will even compile, so
  this only happens when you've actually chosen it.
- `gateware/src/{dot_product_engine,dot_product_lane_array,int8_mac_lane,
  byte_interleave_ram}.v` and `libraries/AIAccelerator/` (the
  [AI accelerator](PERIPHERALS.md#ai-accelerator)) are vendored/adapted
  from the standalone [NanoTangAI](https://github.com/pschatzmann/NanoTangAI)
  project (same author as this repo) and are **Apache-2.0**.
- The `riscv-zephyr-elf` compiler bundled as a [Boards Manager tool
  dependency](RELEASING.md) is an unmodified re-host of the [Zephyr
  Project](https://github.com/zephyrproject-rtos/sdk-ng)'s own public SDK
  build (GCC/binutils, **GPL**) - redistributing an unmodified GPL-licensed
  compiler *binary* is standard practice (every third-party Arduino core
  that bundles its own compiler does the same, e.g. ESP32's toolchain
  distributions) and isn't a licensing complication like the gateware
  entries above: it's a tool that compiles your sketch, not code linked
  into it, so it has no bearing on your sketch's own license.

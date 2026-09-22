# Known limitations

- **`Serial` likely needs a different USB port selected than the one used
  for uploading.** The onboard BL616 exposes both a JTAG/programming
  interface and a UART bridge over the same USB cable (confirmed against
  [Sipeed's official schematic](https://dl.sipeed.com/shareURL/TANG/Nano_20K/2_Schematic):
  FPGA pin 69 (`uart_tx`) → `BL616_UART_RX`, pin 70 (`uart_rx`) ←
  `BL616_UART_TX` - the same pins
  [nand2mario/nestang](https://github.com/nand2mario/nestang) uses for
  its own console UART), which on most hosts enumerate as two separate
  serial devices (e.g. two `/dev/ttyACM*`/`/dev/ttyUSB*` entries on
  Linux, two COM ports on Windows) - `tools/upload.py` targets the
  programming one, and the Arduino Serial Monitor needs to be pointed at
  the *other* one to see `Serial.print()`/`println()` output. Which of
  the two is which isn't yet confirmed on real hardware - if the first
  one you try shows nothing, try the other.
- **`gateware/src/sram8bit.v`'s memory needs an explicit `(* ram_style =
  "block" *)` attribute** to map onto real Gowin BSRAM; without it, yosys
  defaults to a small LUT-based distributed-RAM primitive that doesn't
  scale to this array's size. With the attribute present (as it is in this
  file), the internal SRAM synthesizes and places cleanly, and
  `gowin_pack` produces a real `.fs` bitstream for the current design.
- **The embedded SDRAM's pins auto-place correctly as long as
  `gateware/src/top.v`'s SDRAM port names match an exact convention**
  (`O_sdram_clk`, `O_sdram_cke`, `O_sdram_cs_n`, `O_sdram_cas_n`,
  `O_sdram_ras_n`, `O_sdram_wen_n`, `O_sdram_dqm[3:0]`,
  `O_sdram_addr[10:0]`, `O_sdram_ba[1:0]`, `IO_sdram_dq[31:0]`) - the
  GW2AR-18's embedded SiP SDRAM isn't constrained via `.cst` at all;
  `nextpnr-himbaechel`'s Gowin backend (Project Apicula) auto-places it
  via a chip-database lookup keyed on these exact top-level port names
  (see [YosysHQ/nextpnr#1370](https://github.com/YosysHQ/nextpnr/pull/1370)
  "apicula: add support for magic sip pins"). Renaming these ports breaks
  place & route with `ERROR: Unconstrained IO:...`.
- **Uploads are slow in the default (SRAM) boot mode.** Every "upload"
  re-runs the full FPGA flow (synthesis → place & route → pack), typically
  several minutes, because the program lives in block RAM initialized at
  synthesis time rather than in a separate program flash. Tools > Boot
  Mode: Flash (see [Peripherals](PERIPHERALS.md#flash)) avoids this: the
  fixed core-only SRAM image (`.text.irq` + `.text.boot`) is identical
  across sketch compiles, so `build_bitstream.py` caches the resulting
  `.fs` at `~/.cache/nanotang/bitstreams/` and reuses it on every compile
  after the first, skipping synthesis/place-and-route/pack entirely.
  `irq_vec.S` calls the sketch's interrupt dispatcher *indirectly*,
  through a fixed pointer slot (`irq_dispatch_ptr`, written by
  `startup.S`) rather than a direct `jal`/`call`, so this file's own bytes
  stay independent of where the dispatcher happens to link for a given
  sketch - a direct call's machine code would otherwise encode that
  link-time distance, breaking the "identical core image" property this
  caching depends on.
- **`millis()`/`micros()` wrap much sooner than a real Arduino board.**
  `systick` is a raw cycle counter at whatever the Tools > Clock Speed menu
  selects (27MHz by default), so it wraps roughly every 160 seconds at
  27MHz (faster at Overclocked, slower at Low Power), versus ~49 days on
  AVR. Code that compares
  `millis()`/`micros()` with unsigned subtraction (the standard Arduino
  idiom, e.g. `if (millis() - last >= interval)`) is unaffected by wrapping
  at any period.
- **No FPU.** picorv32 has no floating-point extension option at all - every
  `float`/`double` operation compiles to a call into libgcc's software
  floating-point routines (`__adddf3`, `__muldf3`, `__divdf3`, etc.), each
  costing many dozens of cycles. Tools > Hardware Multiply/Divide (see
  [Peripherals](PERIPHERALS.md#cpu-features)) speeds these routines up
  significantly (they're internally built from integer multiplies/shifts),
  but doesn't eliminate the software emulation itself - there's no hardware
  path to real single-cycle float math on this core. Prefer fixed-point
  (integer-scaled) arithmetic in hot loops, or the AI accelerator's INT8
  path where applicable.
- The RV32I base ISA has no compressed-instruction support
  (`COMPRESSED_ISA(0)`), matching the reference SoC.
- **DMA's async/background mode only reaches the embedded SDRAM heap, and
  can't be extended to the internal SRAM** (see [DMA](PERIPHERALS.md#dma)).
  This needs true dual-port BRAM (the CPU's existing port plus an
  independent DMA port on the same array), but this toolchain's BRAM
  inference only supports dual-port memories where each port is
  single-purpose (fixed read-only or fixed write-only) - never a port that
  flexibly reads or writes depending on the access, which is what both the
  CPU's own port and a general-purpose DMA port need; yosys reports `ERROR:
  no valid mapping found for memory` for that combination regardless of
  how the Verilog is written. The blocking DMA
  mode (`dmaCopyWords()`/`dmaCopy()`) has no such restriction, but stalls
  the CPU (including instruction fetch - picorv32 has no separate
  instruction bus) for the whole transfer.
- No CAN or USB.
- **Nothing here has been run on real hardware.** Everything is verified
  only via `yosys` elaboration/synthesis and `arduino-cli compile`; see
  `tools/run_tests.sh`.

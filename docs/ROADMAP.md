# Roadmap

- **Test what's still untested on real hardware** - see
  [Hardware test status](HARDWARE_STATUS.md#not-yet-tested-on-the-board).
- **Math library functions** (`sin()`, `sqrt()`, ...) - see
  [Known limitations](KNOWN_LIMITATIONS.md).
- **Verify the I2S frame's exact bit alignment** against the MAX98357A
  with a logic analyzer - audio plays correctly by ear, but the
  alignment hasn't been measured.
- **Check `tools/run_tests.sh`'s fast builds against full builds**:
  compare the bitstream a cached (routed-design) build produces with a
  full synthesis/place & route of the same sketch.
- **Try a newer BL616 debugger firmware** to see whether it fixes the
  board-to-PC data loss during two-way traffic (see
  [Known limitations](KNOWN_LIMITATIONS.md)).
- **More I2S headroom at 44.1kHz**: the ring-buffer path still costs
  about as much CPU time as the sample period allows at 27MHz; a DMA feed
  from memory, or a cheaper interrupt path, would let long `Serial` prints
  coexist with audio.
- **Slim down the CAN controller** (about 2,500 LUT4s after the first
  round of optimization).
- **True XIP** (executing directly from flash, not just copying the
  program to SRAM at boot) needs an instruction cache to avoid a severe
  per-fetch latency penalty (picorv32 has no instruction cache and no
  separate instruction bus). Tools > Boot Mode: ... + SDRAM already runs code from
  SDRAM without a cache; an instruction cache would speed up both.
- **SPI Client API** Add a SPI Client API so that we can implement devices

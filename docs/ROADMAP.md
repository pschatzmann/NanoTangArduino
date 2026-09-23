# Roadmap

- **Test the remaining peripherals on real hardware** - see the list in
  [Hardware test status](HARDWARE_STATUS.md): GPIO/PWM, interrupts and
  timers, WS2812, I2C, SoftwareSerial, DMA, CAN, PWM Audio, the AI
  accelerator, Flash boot, and the CPU/clock options.
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
- **Slim down the CAN controller** (about 2,200 LUT4s after the first
  round of optimization).
- **True XIP** (executing directly from flash, not just copying the
  program to SRAM at boot) needs an instruction cache to avoid a severe
  per-fetch latency penalty (picorv32 has no instruction cache and no
  separate instruction bus).

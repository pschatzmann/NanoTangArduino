# Roadmap

- **Program the bitstream onto real hardware** — this is the first point
  anything in this repo can be verified outside of `yosys`/`arduino-cli`.
- **Verify I2S audio bit-alignment** and the embedded SDRAM's actual
  timing/refresh behavior once real hardware is available — both were
  built against documented specs/vendored reference designs but never
  exercised against the physical chips.
- **True XIP** (executing directly from flash, not just copying the
  program to SRAM at boot) needs an instruction cache to avoid a severe
  per-fetch latency penalty (picorv32 has no instruction cache and no
  separate instruction bus).

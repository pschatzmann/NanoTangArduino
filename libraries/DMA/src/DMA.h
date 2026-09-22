#pragma once

/* Hardware-accelerated bulk memory copy, backed by gateware/src/dma_engine.v
 * (the SoC's second bus master - see docs/PERIPHERALS.md "DMA"). Useful for
 * large copies within/between the internal SRAM and the embedded 8MB SDRAM
 * heap (e.g. audio buffers, AI accelerator weight/activation staging) - a
 * plain software loop is fine for small copies.
 *
 * The CPU (including instruction fetch, since picorv32 has no separate
 * instruction bus) is stalled by hardware for the whole transfer and
 * resumes automatically the instruction after dmaCopy()/dmaCopyWords()
 * returns - there's nothing to poll or wait for, and no interrupt is
 * involved. Source and destination regions must not overlap (undefined
 * which bytes win, same as memcpy()).
 */

#include <stddef.h>
#include <stdint.h>

// Copies `wordCount` 32-bit words from `src` to `dst`. Both must be
// 4-byte-aligned addresses within the SoC's memory map (internal SRAM or
// the embedded SDRAM) - not a peripheral register.
void dmaCopyWords(volatile void *dst, const volatile void *src, uint32_t wordCount);

// memcpy()-style convenience wrapper: copies `byteCount` bytes, byte-copying
// any unaligned leading/trailing bytes in software and using the DMA engine
// for the word-aligned middle portion.
void dmaCopy(void *dst, const void *src, size_t byteCount);

// Starts a copy in the background and returns immediately - loop() keeps
// running (including on real interrupts, timers, tone(), etc.) while the
// copy happens, using a dedicated hardware path that never touches the
// CPU's own bus at all (unlike dmaCopyWords() above, which stalls the CPU
// for the transfer's duration). `callback` runs from interrupt context
// when the copy finishes - same caveats as attachInterrupt(): keep it
// short, and any shared state it touches from loop() should be `volatile`.
//
// Only one background transfer can be in flight at a time (starting a new
// one while another is running is refused, returning false), and both
// `dst` and `src` must lie entirely within the embedded SDRAM heap
// (TANGNANO20K_SDRAM_BASE, TANGNANO20K_SDRAM_SIZE) - this path has no
// route to the internal SRAM. Use dmaCopyWords()/dmaCopy() for anything
// involving SRAM.
bool dmaCopyWordsAsync(void *dst, const void *src, uint32_t wordCount, void (*callback)(void));

// True while a dmaCopyWordsAsync() transfer is still in flight. Avoid
// polling this from a tight loop if you're also using the callback - both
// read the same hardware completion flag, so whichever reads it first
// clears it for the other (see docs/PERIPHERALS.md "DMA").
bool dmaAsyncBusy(void);

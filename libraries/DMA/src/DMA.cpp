#include "DMA.h"
#include "tangnano20k_soc.h"

extern "C" void tangnano20k_dma_set_async_callback(void (*callback)(void));

static inline bool inSdramRange(const volatile void *p, size_t byteCount)
{
  uintptr_t addr = (uintptr_t)p;
  return addr >= TANGNANO20K_SDRAM_BASE &&
         (addr - TANGNANO20K_SDRAM_BASE) + byteCount <= TANGNANO20K_SDRAM_SIZE;
}

void dmaCopyWords(volatile void *dst, const volatile void *src, uint32_t wordCount)
{
  if (wordCount == 0)
    return;

  TANGNANO20K_DMA_SRC_REG = (uint32_t)(uintptr_t)src;
  TANGNANO20K_DMA_DST_REG = (uint32_t)(uintptr_t)dst;
  TANGNANO20K_DMA_LEN_REG = wordCount;
  TANGNANO20K_DMA_START_REG = 1; // Any write starts it; the CPU's next bus
                                 // access simply stalls until it's done.
}

void dmaCopy(void *dst, const void *src, size_t byteCount)
{
  uintptr_t s = (uintptr_t)src;
  uintptr_t d = (uintptr_t)dst;

  // Byte-copy any unaligned prefix (rare in practice - buffers this core
  // cares about, e.g. audio/AI accelerator staging, are word-aligned).
  while (byteCount > 0 && ((s & 3) || (d & 3))) {
    *(uint8_t *)d = *(const uint8_t *)s;
    s++;
    d++;
    byteCount--;
  }

  uint32_t words = (uint32_t)(byteCount / 4);
  if (words > 0) {
    dmaCopyWords((void *)d, (const void *)s, words);
    s += (size_t)words * 4;
    d += (size_t)words * 4;
    byteCount -= (size_t)words * 4;
  }

  while (byteCount > 0) {
    *(uint8_t *)d = *(const uint8_t *)s;
    s++;
    d++;
    byteCount--;
  }
}

bool dmaCopyWordsAsync(void *dst, const void *src, uint32_t wordCount, void (*callback)(void))
{
  if (wordCount == 0)
    return false;
  if (!inSdramRange(dst, (size_t)wordCount * 4) || !inSdramRange(src, (size_t)wordCount * 4))
    return false; // Async DMA only reaches the SDRAM heap - see DMA.h.
  if (TANGNANO20K_DMA_START_REG & TANGNANO20K_DMA_STATUS_ASYNC_BUSY)
    return false; // Only one background transfer at a time.

  tangnano20k_dma_set_async_callback(callback);

  TANGNANO20K_DMA_SRC_REG = (uint32_t)(uintptr_t)src;
  TANGNANO20K_DMA_DST_REG = (uint32_t)(uintptr_t)dst;
  TANGNANO20K_DMA_LEN_REG = wordCount;
  TANGNANO20K_DMA_START_REG = TANGNANO20K_DMA_START_GO | TANGNANO20K_DMA_START_ASYNC;
  return true;
}

bool dmaAsyncBusy(void)
{
  return (TANGNANO20K_DMA_START_REG & TANGNANO20K_DMA_STATUS_ASYNC_BUSY) != 0;
}

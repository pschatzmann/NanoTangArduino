#include "Arduino.h"

/* millis()/micros() read dedicated hardware counters (gateware/src/
 * systick.v) that wrap at the full 2^32, the same as on any other Arduino
 * board (~49 days / ~71 minutes), so the standard `millis() - last >=
 * interval` idiom is correct across the wrap - and no software division
 * is needed per call. */

unsigned long micros(void)
{
  return TANGNANO20K_MICROS_REG;
}

unsigned long millis(void)
{
  return TANGNANO20K_MILLIS_REG;
}

void delay(unsigned long ms)
{
  unsigned long start = millis();
  while ((millis() - start) < ms) {
    yield();
  }
}

/* Cycle-accurate rather than micros()-based, so short delays (bit-banged
 * protocols like Wire) aren't quantized to whole microseconds. F_CPU is a
 * multiple of 500kHz on every Tools > Clock Speed option (13.5/27/54MHz),
 * which keeps the conversion exact and division-free. Chunked so
 * `us * cycles` can't overflow 32 bits. */
void delayMicroseconds(unsigned int us)
{
  static_assert(F_CPU % 500000UL == 0, "delayMicroseconds() needs F_CPU to be a multiple of 500kHz");
  const unsigned int kChunkUs = 1000000U;
  while (us > kChunkUs) {
    delayMicroseconds(kChunkUs);
    us -= kChunkUs;
  }

  uint32_t ticks = ((uint32_t)us * (uint32_t)(F_CPU / 500000UL)) >> 1;
  uint32_t start = TANGNANO20K_SYSTICK_REG;
  while ((uint32_t)(TANGNANO20K_SYSTICK_REG - start) < ticks) {
  }
}

#include "Arduino.h"

/* pulseIn() times the pulse itself against the cycle counter (sub-
 * microsecond resolution, measures pulses up to 2^32 cycles, ~159s at
 * 27MHz) and the timeout against the microsecond counter. Neither needs
 * interrupts disabled, so pulseInLong() is the same function here. */

static inline uint32_t cyclesToMicros(uint32_t cycles)
{
  // F_CPU is a multiple of 500kHz on every Tools > Clock Speed option.
  return (uint32_t)(((uint64_t)cycles * 2U) / (F_CPU / 500000UL));
}

extern "C" unsigned long pulseIn(pin_size_t pin, uint8_t state, unsigned long timeout)
{
  PinStatus level = state ? HIGH : LOW;
  uint32_t startUs = micros();

  // Let any pulse already in progress finish, then wait for the next one.
  while (digitalRead(pin) == level) {
    if (micros() - startUs >= timeout)
      return 0;
  }
  while (digitalRead(pin) != level) {
    if (micros() - startUs >= timeout)
      return 0;
  }

  uint32_t pulseStart = TANGNANO20K_SYSTICK_REG;
  while (digitalRead(pin) == level) {
    if (micros() - startUs >= timeout)
      return 0;
  }
  return cyclesToMicros(TANGNANO20K_SYSTICK_REG - pulseStart);
}

extern "C" unsigned long pulseInLong(pin_size_t pin, uint8_t state, unsigned long timeout)
{
  return pulseIn(pin, state, timeout);
}

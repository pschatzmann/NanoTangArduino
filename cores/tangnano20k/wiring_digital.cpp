#include "Arduino.h"

/* v1 "pins" are the 6 onboard LEDs (numbered 0..5), memory-mapped as a
 * single 6-bit read/write register. There is no general-purpose GPIO
 * header support yet - see README roadmap. */

void pinMode(pin_size_t pinNumber, PinMode mode)
{
  /* The LED register is output-only in hardware; accept any mode without
   * error so sketches written for real Arduino boards still compile. */
  (void)pinNumber;
  (void)mode;
}

void digitalWrite(pin_size_t pinNumber, PinStatus status)
{
  if (pinNumber >= TANGNANO20K_NUM_LEDS)
    return;

  uint32_t mask = 1UL << pinNumber;
  if (status == HIGH)
    TANGNANO20K_LED_REG = TANGNANO20K_LED_REG | mask;
  else
    TANGNANO20K_LED_REG = TANGNANO20K_LED_REG & ~mask;
}

PinStatus digitalRead(pin_size_t pinNumber)
{
  if (pinNumber >= TANGNANO20K_NUM_LEDS)
    return LOW;

  return (TANGNANO20K_LED_REG & (1UL << pinNumber)) ? HIGH : LOW;
}

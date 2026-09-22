#include "Arduino.h"

/* analogWrite() is real 8-bit PWM (gateware/src/pwm6.v) on the 6 onboard
 * LED pins - writing switches that LED from tang_leds' plain digital
 * register to the PWM channel; pinMode()/digitalWrite() switch it back
 * (see wiring_digital.cpp). Arduino's analogWrite() takes a 0-255 value;
 * this board's PWM is already 8-bit, so no scaling is needed. */
void analogWrite(pin_size_t pinNumber, int value)
{
  if (pinNumber >= TANGNANO20K_NUM_LEDS)
    return;

  if (value < 0)
    value = 0;
  if (value > 255)
    value = 255;

  TANGNANO20K_PWM_REG(pinNumber) = TANGNANO20K_PWM_ENABLE | (uint32_t)value;
}

/* The Tang Nano 20K has no ADC wired to any pin - there is no way to
 * implement analogRead() on this hardware. This stub exists only so
 * sketches that call it still link; it always returns 0. */
int analogRead(pin_size_t pinNumber)
{
  (void)pinNumber;
  return 0;
}

void analogReference(uint8_t mode)
{
  (void)mode;
}

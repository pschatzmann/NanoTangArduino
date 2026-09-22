#include "Arduino.h"

/* analogWrite() is real hardware PWM (gateware/src/pwm_bank.v) with a
 * per-pin frequency (analogWriteFrequency()):
 *
 * - LED pins 0-5 each have a dedicated channel (0-5). Writing switches
 *   that LED from tang_leds' plain digital register to its PWM channel;
 *   pinMode()/digitalWrite() switch it back (see wiring_digital.cpp).
 * - GPIO0-GPIO20 share a pool of TANGNANO20K_PWM_GPIO_CHANNELS channels
 *   (6-9), assigned on the first analogWrite() to a pin and released by
 *   pinMode()/digitalWrite() on it. While assigned, the channel overrides
 *   that pin as a PWM-driven output. With the pool exhausted, analogWrite()
 *   falls back to what AVR Arduinos do on non-PWM pins: HIGH for values
 *   >= 128, LOW below.
 *
 * Values are Arduino's usual 0-255, scaled onto the channel's period, so
 * 0 is always low and 255 always high at any frequency. */

#define LED_PINS  TANGNANO20K_PWM_LED_CHANNELS
#define PWM_PINS  (LED_PINS + TANGNANO20K_GPIO_COUNT)
#define NO_CHANNEL 0xFF

/* Per-pin state, indexed by pwmIndex(): LEDs 0-5, then GPIO0-GPIO20. */
static uint32_t pinFrequency[PWM_PINS];  // 0 = default (F_CPU/256)
static uint8_t pinValue[PWM_PINS];       // last analogWrite() value
static uint8_t pinChannel[PWM_PINS] = {
  0, 1, 2, 3, 4, 5, // LEDs: fixed channels
  NO_CHANNEL, NO_CHANNEL, NO_CHANNEL, NO_CHANNEL, NO_CHANNEL, NO_CHANNEL, NO_CHANNEL,
  NO_CHANNEL, NO_CHANNEL, NO_CHANNEL, NO_CHANNEL, NO_CHANNEL, NO_CHANNEL, NO_CHANNEL,
  NO_CHANNEL, NO_CHANNEL, NO_CHANNEL, NO_CHANNEL, NO_CHANNEL, NO_CHANNEL, NO_CHANNEL,
};
static bool ledPwmActive[LED_PINS];
static bool poolChannelUsed[TANGNANO20K_PWM_GPIO_CHANNELS];

/* Maps an Arduino pin number to an index into the tables above, or -1 if
 * the pin has no PWM support. */
static int pwmIndex(pin_size_t pin)
{
  if (pin < LED_PINS)
    return pin;
  if (pin >= TANGNANO20K_PIN_GPIO_BASE && pin < TANGNANO20K_PIN_GPIO_BASE + TANGNANO20K_GPIO_COUNT)
    return LED_PINS + (pin - TANGNANO20K_PIN_GPIO_BASE);
  return -1;
}

static bool isActive(int idx)
{
  if (idx < LED_PINS)
    return ledPwmActive[idx];
  return pinChannel[idx] != NO_CHANNEL;
}

/* Programs channel `ch` for pin index `idx` from its stored frequency and
 * value: splits F_CPU/frequency clock cycles per PWM period into the
 * smallest prescaler that lets the period fit in 16 bits (maximizing
 * resolution), then scales the 0-255 value onto that period. */
static void programChannel(uint8_t ch, int idx)
{
  uint32_t cycles = pinFrequency[idx] ? (uint32_t)(F_CPU / pinFrequency[idx]) : 256;
  if (cycles < 2)
    cycles = 2; // F_CPU/2 is the fastest a counter can toggle.

  uint32_t prescale = (cycles - 1) >> 16;
  if (prescale > 255)
    prescale = 255; // Slowest possible - about F_CPU / 2^24.
  uint32_t period = cycles / (prescale + 1);
  if (period > 65536)
    period = 65536;
  period -= 1;

  uint32_t gpio = (idx >= LED_PINS) ? (uint32_t)(idx - LED_PINS) : 0;
  uint32_t duty = ((uint32_t)pinValue[idx] * (period + 1) + 127) / 255;

  TANGNANO20K_PWM_CFG_REG(ch) = TANGNANO20K_PWM_CFG(period, prescale, gpio);
  TANGNANO20K_PWM_DUTY_REG(ch) = TANGNANO20K_PWM_ENABLE | duty;
}

void analogWrite(pin_size_t pinNumber, int value)
{
  int idx = pwmIndex(pinNumber);
  if (idx < 0)
    return;

  if (value < 0)
    value = 0;
  if (value > 255)
    value = 255;
  pinValue[idx] = (uint8_t)value;

  if (idx < LED_PINS) {
    ledPwmActive[idx] = true;
  } else if (pinChannel[idx] == NO_CHANNEL) {
    for (uint8_t i = 0; i < TANGNANO20K_PWM_GPIO_CHANNELS; i++) {
      if (!poolChannelUsed[i]) {
        poolChannelUsed[i] = true;
        pinChannel[idx] = LED_PINS + i;
        break;
      }
    }
    if (pinChannel[idx] == NO_CHANNEL) {
      // Pool exhausted - plain digital fallback.
      uint32_t mask = 1UL << (idx - LED_PINS);
      TANGNANO20K_GPIO_DIR_REG = TANGNANO20K_GPIO_DIR_REG | mask;
      if (value >= 128)
        TANGNANO20K_GPIO_OUT_REG = TANGNANO20K_GPIO_OUT_REG | mask;
      else
        TANGNANO20K_GPIO_OUT_REG = TANGNANO20K_GPIO_OUT_REG & ~mask;
      return;
    }
  }

  programChannel(pinChannel[idx], idx);
}

void analogWriteFrequency(pin_size_t pin, uint32_t frequency)
{
  int idx = pwmIndex(pin);
  if (idx < 0)
    return;
  pinFrequency[idx] = frequency;
  if (isActive(idx))
    programChannel(pinChannel[idx], idx);
}

void tangnano20k_pwm_release(pin_size_t pin)
{
  int idx = pwmIndex(pin);
  if (idx < 0 || !isActive(idx))
    return;

  uint8_t ch = pinChannel[idx];
  TANGNANO20K_PWM_DUTY_REG(ch) = 0;
  if (idx < LED_PINS) {
    ledPwmActive[idx] = false;
  } else {
    poolChannelUsed[ch - LED_PINS] = false;
    pinChannel[idx] = NO_CHANNEL;
  }
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

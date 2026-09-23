#include "Arduino.h"

/* analogWrite() is real hardware PWM (gateware/src/pwm_bank.v) with a
 * per-pin frequency (analogWriteFrequency()). The 6 onboard LEDs (pins
 * 0-5) and GPIO0-GPIO20 are treated alike: they share a pool of
 * TANGNANO20K_PWM_CHANNELS channels, one assigned on the first
 * analogWrite() to a pin and released by pinMode()/digitalWrite() on it
 * (see wiring_digital.cpp), matching real-Arduino behavior where those
 * calls stop the PWM. While assigned, the channel overrides the pin: an
 * LED shows PWM instead of its plain on/off register, a GPIO pin becomes
 * a PWM-driven output. With the pool exhausted, analogWrite() falls back
 * to what AVR Arduinos do on non-PWM pins: HIGH for values >= 128, LOW
 * below.
 *
 * Values are Arduino's usual 0-255 by default, or 0..2^bits-1 after
 * analogWriteResolution(bits) (1-16 bits), scaled onto the channel's
 * period, so 0 is always low and the maximum always high at any
 * frequency. Internally every pin's duty is kept at 16-bit resolution.
 *
 * The channel tables are also updated from interrupt context (tone()'s
 * duration timer releases its channel), so allocation and release run
 * inside a critical section. */

#define PWM_PINS   (TANGNANO20K_NUM_LEDS + TANGNANO20K_GPIO_COUNT)
#define NO_CHANNEL 0xFF

/* Per-pin state, indexed by pwmIndex(): LEDs 0-5, then GPIO0-GPIO20 -
 * the same numbering as pwm_bank.v's CFG target field. */
static uint32_t pinFrequency[PWM_PINS]; // 0 = default (F_CPU/256)
static uint16_t pinDuty[PWM_PINS];      // last duty, 0 (low) - 65535 (high)
static uint8_t pinChannel[PWM_PINS];    // channel+1, 0 = not in PWM mode
static bool channelUsed[TANGNANO20K_PWM_CHANNELS];
static uint8_t writeResolution = 8;

/* Maps an Arduino pin number to an index into the tables above, or -1 if
 * the pin has no PWM support. */
static int pwmIndex(pin_size_t pin)
{
  if (pin < TANGNANO20K_NUM_LEDS)
    return pin;
  if (pin >= TANGNANO20K_PIN_GPIO_BASE && pin < TANGNANO20K_PIN_GPIO_BASE + TANGNANO20K_GPIO_COUNT)
    return TANGNANO20K_NUM_LEDS + (pin - TANGNANO20K_PIN_GPIO_BASE);
  return -1;
}

/* pinChannel[] starts zero-filled (.bss), so "no channel" is stored as
 * channel+1 internally - these two keep that detail in one place. */
static uint8_t channelOf(int idx)
{
  return pinChannel[idx] ? (uint8_t)(pinChannel[idx] - 1) : NO_CHANNEL;
}

static void setChannel(int idx, uint8_t ch)
{
  pinChannel[idx] = (ch == NO_CHANNEL) ? 0 : (uint8_t)(ch + 1);
}

/* Programs channel `ch` for pin index `idx` from its stored frequency and
 * duty: splits F_CPU/frequency clock cycles per PWM period into the
 * smallest prescaler that lets the period fit in 16 bits (maximizing
 * resolution), then scales the 16-bit duty onto that period. */
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

  // Fits 32 bits: at most 65535 * 65536 + 32767.
  uint32_t duty = ((uint32_t)pinDuty[idx] * (period + 1) + 32767) / 65535;

  TANGNANO20K_PWM_CFG_REG(ch) = TANGNANO20K_PWM_CFG(period, prescale, idx);
  TANGNANO20K_PWM_DUTY_REG(ch) = TANGNANO20K_PWM_ENABLE | duty;
}

/* Pool-exhausted fallback: plain on/off through the pin's digital
 * register (which the PWM override would otherwise mask). */
static void writeDigitalFallback(int idx, bool high)
{
  if (idx < TANGNANO20K_NUM_LEDS) {
    uint32_t mask = 1UL << idx;
    if (high)
      TANGNANO20K_LED_SET_REG = mask;
    else
      TANGNANO20K_LED_CLR_REG = mask;
    return;
  }
  uint32_t mask = 1UL << (idx - TANGNANO20K_NUM_LEDS);
  TANGNANO20K_GPIO_DIR_SET_REG = mask;
  if (high)
    TANGNANO20K_GPIO_OUT_SET_REG = mask;
  else
    TANGNANO20K_GPIO_OUT_CLR_REG = mask;
}

/* Starts (or updates) PWM on pin index `idx` at its stored frequency and
 * the given 16-bit duty. Returns false if no channel was free, after
 * falling back to plain on/off. */
static bool startPwm(int idx, uint16_t duty)
{
  uint32_t irqState = tangnano20k_irq_save();
  pinDuty[idx] = duty;

  uint8_t ch = channelOf(idx);
  if (ch == NO_CHANNEL) {
    for (uint8_t i = 0; i < TANGNANO20K_PWM_CHANNELS; i++) {
      if (!channelUsed[i]) {
        channelUsed[i] = true;
        ch = i;
        setChannel(idx, ch);
        break;
      }
    }
  }

  if (ch == NO_CHANNEL)
    writeDigitalFallback(idx, duty >= 32768);
  else
    programChannel(ch, idx);
  tangnano20k_irq_restore(irqState);
  return ch != NO_CHANNEL;
}

void analogWrite(pin_size_t pinNumber, int value)
{
  int idx = pwmIndex(pinNumber);
  if (idx < 0)
    return;

  uint32_t maxValue = (1UL << writeResolution) - 1;
  if (value < 0)
    value = 0;
  if ((uint32_t)value > maxValue)
    value = (int)maxValue;
  startPwm(idx, (uint16_t)(((uint32_t)value * 65535UL + maxValue / 2) / maxValue));
}

void analogWriteResolution(int bits)
{
  if (bits < 1)
    bits = 1;
  if (bits > 16)
    bits = 16;
  writeResolution = (uint8_t)bits;
}

void analogReadResolution(int bits)
{
  (void)bits; // No ADC - see analogRead() below.
}

bool tangnano20k_pwm_start(pin_size_t pin, uint32_t frequency, uint16_t duty)
{
  int idx = pwmIndex(pin);
  if (idx < 0 || frequency == 0)
    return false;
  pinFrequency[idx] = frequency;
  if (startPwm(idx, duty))
    return true;
  pinFrequency[idx] = 0;
  return false;
}

void analogWriteFrequency(pin_size_t pin, uint32_t frequency)
{
  int idx = pwmIndex(pin);
  if (idx < 0)
    return;
  uint32_t irqState = tangnano20k_irq_save();
  pinFrequency[idx] = frequency;
  uint8_t ch = channelOf(idx);
  if (ch != NO_CHANNEL)
    programChannel(ch, idx);
  tangnano20k_irq_restore(irqState);
}

void tangnano20k_pwm_release(pin_size_t pin)
{
  int idx = pwmIndex(pin);
  if (idx < 0)
    return;
  uint32_t irqState = tangnano20k_irq_save();
  uint8_t ch = channelOf(idx);
  if (ch != NO_CHANNEL) {
    TANGNANO20K_PWM_DUTY_REG(ch) = 0;
    channelUsed[ch] = false;
    setChannel(idx, NO_CHANNEL);
  }
  tangnano20k_irq_restore(irqState);
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

#include "Arduino.h"

/* v1 "pins": 0-5 are the 6 onboard LEDs (memory-mapped as a single 6-bit
 * read/write register, individually switchable into PWM mode by
 * analogWrite() - see wiring_analog.cpp); pin 6 (TANGNANO20K_PIN_KEY2) is
 * the board's second button, read-only; pin 10 (TANGNANO20K_PIN_SD_CS,
 * aka SS) is a virtual pin toggling the SPI peripheral's hardware chip
 * select, so the unmodified libraries/SD library's plain digitalWrite()
 * calls work (see pins_arduino.h); pins 14-34 (GPIO0-GPIO20) are real
 * general-purpose I/O on the expansion header, with real pinMode()
 * support unlike the pins above.
 *
 * All register updates are single writes to SET/CLR registers rather than
 * read-modify-writes, so digitalWrite() from an interrupt handler (tone(),
 * a TangTimer callback, ...) can't undo a concurrent one from loop().
 *
 * Every GPIO pin has a weak pull-up (fixed at synthesis - see
 * gateware/picorv32_20k.cst), so INPUT and INPUT_PULLUP behave the same
 * and INPUT_PULLDOWN isn't available. OUTPUT_OPENDRAIN is emulated on top
 * of it: LOW drives the pin low, HIGH releases it (switches it to an
 * input), letting the pull-up or another device set the level. */

/* GPIO pins currently in OUTPUT_OPENDRAIN mode, one bit per GPIOn. */
static volatile uint32_t openDrainPins;

static inline bool isExpansionGpio(pin_size_t pinNumber)
{
  return pinNumber >= TANGNANO20K_PIN_GPIO_BASE &&
         pinNumber < TANGNANO20K_PIN_GPIO_BASE + TANGNANO20K_GPIO_COUNT;
}

void pinMode(pin_size_t pinNumber, PinMode mode)
{
  tangnano20k_pwm_release(pinNumber); // Leaving PWM mode, see below.

  if (isExpansionGpio(pinNumber)) {
    uint32_t mask = 1UL << (pinNumber - TANGNANO20K_PIN_GPIO_BASE);
    if (mode == OUTPUT_OPENDRAIN) {
      // Starts released (HIGH); the output latch stays 0 so that
      // digitalWrite(LOW) only has to switch the direction.
      TANGNANO20K_GPIO_DIR_CLR_REG = mask;
      TANGNANO20K_GPIO_OUT_CLR_REG = mask;
      openDrainPins |= mask;
      return;
    }
    openDrainPins &= ~mask;
    if (mode == OUTPUT)
      TANGNANO20K_GPIO_DIR_SET_REG = mask;
    else
      TANGNANO20K_GPIO_DIR_CLR_REG = mask;
    return;
  }

  /* The LED register is output-only in hardware and KEY2 is input-only;
   * accept any mode without error so sketches written for real Arduino
   * boards still compile. (PWM was already stopped above, since on a real
   * Arduino calling pinMode()/digitalWrite() after analogWrite() stops
   * the PWM.) */
  (void)mode;
}

void digitalWrite(pin_size_t pinNumber, PinStatus status)
{
  tangnano20k_pwm_release(pinNumber); // Leaving PWM mode, see pinMode() above.

  if (isExpansionGpio(pinNumber)) {
    uint32_t mask = 1UL << (pinNumber - TANGNANO20K_PIN_GPIO_BASE);
    if (openDrainPins & mask) {
      if (status == HIGH)
        TANGNANO20K_GPIO_DIR_CLR_REG = mask; // Release.
      else
        TANGNANO20K_GPIO_DIR_SET_REG = mask; // Drive the latched 0.
    } else if (status == HIGH) {
      TANGNANO20K_GPIO_OUT_SET_REG = mask;
    } else {
      TANGNANO20K_GPIO_OUT_CLR_REG = mask;
    }
    return;
  }

  if (pinNumber == TANGNANO20K_PIN_SD_CS) {
    // SD-card chip select is active low.
    TANGNANO20K_SPI_CS_REG = (status == LOW) ? TANGNANO20K_SPI_CS_ASSERT : 0;
    return;
  }

  if (pinNumber >= TANGNANO20K_NUM_LEDS)
    return;

  uint32_t mask = 1UL << pinNumber;
  if (status == HIGH)
    TANGNANO20K_LED_SET_REG = mask;
  else
    TANGNANO20K_LED_CLR_REG = mask;
}

PinStatus digitalRead(pin_size_t pinNumber)
{
  if (isExpansionGpio(pinNumber)) {
    uint32_t mask = 1UL << (pinNumber - TANGNANO20K_PIN_GPIO_BASE);
    return (TANGNANO20K_GPIO_IN_REG & mask) ? HIGH : LOW;
  }

  if (pinNumber < TANGNANO20K_NUM_LEDS)
    return (TANGNANO20K_LED_REG & (1UL << pinNumber)) ? HIGH : LOW;

  if (pinNumber == TANGNANO20K_PIN_KEY2)
    return (TANGNANO20K_KEY2_REG & 1UL) ? HIGH : LOW;

  if (pinNumber == TANGNANO20K_PIN_SD_CS)
    return (TANGNANO20K_SPI_CS_REG & TANGNANO20K_SPI_CS_ASSERT) ? LOW : HIGH;

  return LOW;
}

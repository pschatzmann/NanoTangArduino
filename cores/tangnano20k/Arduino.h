#pragma once

#include <stdint.h>
#include "api/ArduinoAPI.h"
#include "api/HardwareSerial.h"
#include "HardwareSerial.h"
#include "tangnano20k_soc.h"
#include "pins_arduino.h"

/* SPI, Wire (I2C), and I2S are bundled libraries (libraries/SPI,
 * libraries/Wire, libraries/I2S), not part of the core - a sketch that
 * wants them does `#include <SPI.h>` / `#include <Wire.h>` / `#include
 * <I2STangNano.h>` itself, same as on any other Arduino board. This keeps a
 * sketch that doesn't use them (e.g. Blink) from linking in code it never
 * calls, which matters on this board's 64KB internal SRAM budget. */

using namespace arduino;

/* Global Serial instance, defined in HardwareSerial.cpp - declared with
 * its concrete type so board-specific extras like Serial.overflow() are
 * reachable (and calls needn't go through the vtable). */
extern tangnano20k::HardwareSerial Serial;

/* ArduinoCore-API's Common.h deliberately leaves these two undeclared
 * ("interrupts() / noInterrupts() must be defined by the core") since
 * their implementation is inherently core-specific - see wiring_irq.cpp,
 * which masks/unmasks all of picorv32's maskable IRQ lines via its
 * `maskirq` instruction. */
void interrupts(void);
void noInterrupts(void);

/* Nesting-safe critical section for core/library code: disables all
 * maskable IRQs and returns the previous mask, which
 * tangnano20k_irq_restore() puts back - so a library call made inside a
 * sketch's own noInterrupts() section doesn't re-enable interrupts behind
 * its back, as a plain noInterrupts()/interrupts() pair would.
 *
 *   uint32_t irqState = tangnano20k_irq_save();
 *   ...
 *   tangnano20k_irq_restore(irqState); */
extern "C" uint32_t tangnano20k_set_irq_mask(uint32_t mask);
static inline uint32_t tangnano20k_irq_save(void) { return tangnano20k_set_irq_mask(0xFFFFFFFFUL); }
static inline void tangnano20k_irq_restore(uint32_t state) { tangnano20k_set_irq_mask(state); }

/* Sets the PWM frequency analogWrite() uses on `pin` (an LED pin 0-5 or
 * GPIO0-GPIO20), taking effect immediately if the pin is already in PWM
 * mode. 0 restores the default (F_CPU/256, ~105kHz at 27MHz). Each pin's
 * frequency is independent. Resolution is log2(F_CPU/frequency) bits -
 * frequencies above F_CPU/256 trade away some of analogWrite()'s 0-255
 * steps; the maximum is F_CPU/2, the minimum about F_CPU/2^24. See
 * wiring_analog.cpp and docs/PERIPHERALS.md "Digital I/O and PWM". */
void analogWriteFrequency(pin_size_t pin, uint32_t frequency);

/* Sets the number of bits analogWrite() values have (1-16, default 8 -
 * i.e. 0-255). Higher resolutions are exact only when the pin's PWM
 * period has that many steps: F_CPU/frequency >= 2^bits (e.g. 16 bits
 * needs a frequency of at most F_CPU/65536, ~412Hz at 27MHz). */
void analogWriteResolution(int bits);

/* Accepted for portability; there's no ADC (see analogRead()). */
void analogReadResolution(int bits);

/* Internal (tone(), libraries/Servo): starts PWM on `pin` at `frequency`
 * with a 16-bit duty (0 = always low, 65535 = always high), independent
 * of analogWriteResolution(). Returns false if the pin can't do PWM or no
 * channel is free. digitalWrite()/pinMode() on the pin stop it again. */
bool tangnano20k_pwm_start(pin_size_t pin, uint32_t frequency, uint16_t duty);

/* Internal: stops PWM on `pin` (called by pinMode()/digitalWrite(), which
 * switch a pin back to plain digital mode, as on a real Arduino). */
void tangnano20k_pwm_release(pin_size_t pin);

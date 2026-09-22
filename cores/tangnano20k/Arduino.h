#pragma once

#include <stdint.h>
#include "api/ArduinoAPI.h"
#include "api/HardwareSerial.h"
#include "tangnano20k_soc.h"
#include "pins_arduino.h"

/* SPI, Wire (I2C), and I2S are bundled libraries (libraries/SPI,
 * libraries/Wire, libraries/I2S), not part of the core - a sketch that
 * wants them does `#include <SPI.h>` / `#include <Wire.h>` / `#include
 * <I2S.h>` itself, same as on any other Arduino board. This keeps a
 * sketch that doesn't use them (e.g. Blink) from linking in code it never
 * calls, which matters on this board's 64KB internal SRAM budget. */

using namespace arduino;

/* Global Serial instance, defined in HardwareSerial.cpp */
extern arduino::HardwareSerial &Serial;

/* ArduinoCore-API's Common.h deliberately leaves these two undeclared
 * ("interrupts() / noInterrupts() must be defined by the core") since
 * their implementation is inherently core-specific - see wiring_irq.cpp,
 * which masks/unmasks all of picorv32's maskable IRQ lines via its
 * `maskirq` instruction. */
void interrupts(void);
void noInterrupts(void);

/* Sets the PWM frequency analogWrite() uses on `pin` (an LED pin 0-5 or
 * GPIO0-GPIO20), taking effect immediately if the pin is already in PWM
 * mode. 0 restores the default (F_CPU/256, ~105kHz at 27MHz). Each pin's
 * frequency is independent. Resolution is log2(F_CPU/frequency) bits -
 * frequencies above F_CPU/256 trade away some of analogWrite()'s 0-255
 * steps; the maximum is F_CPU/2, the minimum about F_CPU/2^24. See
 * wiring_analog.cpp and docs/PERIPHERALS.md "Digital I/O and PWM". */
void analogWriteFrequency(pin_size_t pin, uint32_t frequency);

/* Internal: stops PWM on `pin` (called by pinMode()/digitalWrite(), which
 * switch a pin back to plain digital mode, as on a real Arduino). */
void tangnano20k_pwm_release(pin_size_t pin);

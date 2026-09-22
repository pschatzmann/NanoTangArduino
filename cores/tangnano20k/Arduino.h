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

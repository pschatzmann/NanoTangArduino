#pragma once

/* `#include <avr/pgmspace.h>`, as AVR-era sketches and libraries do.
 * Forwards to ArduinoCore-API's compatibility header (the same one
 * String.h uses on non-AVR cores), then to tangnano20k_soc.h, which
 * redefines its empty PROGMEM as FLASH_DATA - so PROGMEM data lands in
 * flash here too, even in a library that never includes Arduino.h. See
 * docs/PERIPHERALS.md "Constant data". */
#include "../api/deprecated-avr-comp/avr/pgmspace.h"
#include "../tangnano20k_soc.h"

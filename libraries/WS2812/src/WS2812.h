#pragma once

#include <Arduino.h>

/* Drives the onboard WS2812 addressable RGB LED (physical FPGA pin 79)
 * via a real hardware shift-timer (gateware/src/ws2812b.v/ws2812b_tgt.v,
 * vendored unmodified from grughuhler/picorv32_tang_nano_20k), not
 * software bit-banging - WS2812's protocol needs ~400ns-precision pulses,
 * well beyond what's reliably achievable in C at this core's ~26.845MHz.
 *
 * write() blocks (via bus backpressure, not a software poll loop) until
 * the peripheral can accept the next pixel - see docs/PERIPHERALS.md
 * "WS2812 LED".
 */
class WS2812Class
{
public:
  void begin(void) {}

  void write(uint8_t r, uint8_t g, uint8_t b)
  {
    uint32_t grb = ((uint32_t)g << 16) | ((uint32_t)r << 8) | b;
    TANGNANO20K_WS2812_REG = grb;
  }
};

extern WS2812Class WS2812;

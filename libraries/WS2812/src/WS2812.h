#pragma once

#include <Arduino.h>

/* WS2812/WS2812B ("NeoPixel") LEDs through the hardware driver in
 * gateware/src/ws2812_strip.v - a real shift-timer, not software
 * bit-banging, since WS2812's protocol needs ~400ns-precision pulses,
 * well beyond what's reliably achievable in C at this core's clock.
 *
 * `WS2812` (global instance) drives the onboard RGB LED (physical FPGA
 * pin 79). `WS2812Strip` drives a strip of any length on any GPIO pin
 * (or the onboard pin), with an Adafruit_NeoPixel-style API. There is one
 * hardware driver: show() routes it to its own strip's pin each time, so
 * several strips work, just not simultaneously. See docs/PERIPHERALS.md
 * "WS2812 LED". */

class WS2812Class
{
public:
  void begin(void) {}

  // Sets the onboard LED. Waits for any frame still being sent first.
  void write(uint8_t r, uint8_t g, uint8_t b);
};

extern WS2812Class WS2812;

// Pass as the pin to WS2812Strip to drive the onboard LED's pin.
#define WS2812_ONBOARD 0xFF

class WS2812Strip
{
public:
  WS2812Strip(uint16_t numPixels, uint8_t pin = WS2812_ONBOARD);
  ~WS2812Strip();

  // Allocates the pixel buffer (on the SDRAM heap). Returns false if the
  // allocation failed or the pin isn't WS2812_ONBOARD or GPIO0-GPIO20.
  bool begin(void);

  /* Sends the buffer to the strip. Interrupts are disabled while the
   * pixels stream out (~30us per pixel): a pause of more than ~50us in
   * the middle would latch a partial frame. Waits for the previous
   * frame's latch time first, so back-to-back show() calls are safe. */
  void show(void);

  void setPixelColor(uint16_t n, uint8_t r, uint8_t g, uint8_t b);
  void setPixelColor(uint16_t n, uint32_t color); // 0x00RRGGBB
  uint32_t getPixelColor(uint16_t n) const;
  void fill(uint32_t color = 0, uint16_t first = 0, uint16_t count = 0);
  void clear(void) { fill(0); }

  // 0-255, applied when sending - the stored colors keep full precision.
  void setBrightness(uint8_t brightness) { brightness_ = brightness; }
  uint8_t getBrightness(void) const { return brightness_; }

  uint16_t numPixels(void) const { return numPixels_; }

  static uint32_t Color(uint8_t r, uint8_t g, uint8_t b)
  {
    return ((uint32_t)r << 16) | ((uint32_t)g << 8) | b;
  }

  // Hue 0-65535 around the color wheel, as in Adafruit_NeoPixel.
  static uint32_t ColorHSV(uint16_t hue, uint8_t sat = 255, uint8_t val = 255);

private:
  uint16_t numPixels_;
  uint8_t pin_;
  uint8_t brightness_ = 255;
  uint32_t *pixels_ = nullptr; // 0x00RRGGBB per pixel
};

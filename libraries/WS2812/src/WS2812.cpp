#include "WS2812.h"
#include <stdlib.h>

WS2812Class WS2812;

static void waitIdle(void)
{
  while (TANGNANO20K_WS2812_REG & TANGNANO20K_WS2812_BUSY) {
  }
}

void WS2812Class::write(uint8_t r, uint8_t g, uint8_t b)
{
  waitIdle();
  TANGNANO20K_WS2812_CFG_REG = 0; // Onboard pin only.
  TANGNANO20K_WS2812_REG = ((uint32_t)g << 16) | ((uint32_t)r << 8) | b;
}

WS2812Strip::WS2812Strip(uint16_t numPixels, uint8_t pin) : numPixels_(numPixels), pin_(pin) {}

WS2812Strip::~WS2812Strip()
{
  free(pixels_);
}

bool WS2812Strip::begin(void)
{
  bool gpio = pin_ >= TANGNANO20K_PIN_GPIO_BASE && pin_ < TANGNANO20K_PIN_GPIO_BASE + TANGNANO20K_GPIO_COUNT;
  if (pin_ != WS2812_ONBOARD && !gpio)
    return false;
  if (!pixels_)
    pixels_ = (uint32_t *)calloc(numPixels_ ? numPixels_ : 1, sizeof(uint32_t));
  return pixels_ != nullptr;
}

void WS2812Strip::show(void)
{
  if (!pixels_)
    return;

  waitIdle();
  if (pin_ == WS2812_ONBOARD)
    TANGNANO20K_WS2812_CFG_REG = 0;
  else
    TANGNANO20K_WS2812_CFG_REG = TANGNANO20K_WS2812_CFG_GPIO(pin_ - TANGNANO20K_PIN_GPIO_BASE) |
                                 TANGNANO20K_WS2812_CFG_GPIO_EN | TANGNANO20K_WS2812_CFG_ONBOARD_OFF;

  // brightness 255 -> scale 256, so full brightness leaves values unchanged.
  uint32_t scale = (uint32_t)brightness_ + 1;
  uint32_t irqState = tangnano20k_irq_save();
  for (uint16_t i = 0; i < numPixels_; i++) {
    uint32_t c = pixels_[i];
    uint32_t r = (((c >> 16) & 0xFF) * scale) >> 8;
    uint32_t g = (((c >> 8) & 0xFF) * scale) >> 8;
    uint32_t b = ((c & 0xFF) * scale) >> 8;
    TANGNANO20K_WS2812_REG = (g << 16) | (r << 8) | b; // Stalls while one is queued.
  }
  tangnano20k_irq_restore(irqState);
}

void WS2812Strip::setPixelColor(uint16_t n, uint8_t r, uint8_t g, uint8_t b)
{
  setPixelColor(n, Color(r, g, b));
}

void WS2812Strip::setPixelColor(uint16_t n, uint32_t color)
{
  if (pixels_ && n < numPixels_)
    pixels_[n] = color & 0xFFFFFFUL;
}

uint32_t WS2812Strip::getPixelColor(uint16_t n) const
{
  return (pixels_ && n < numPixels_) ? pixels_[n] : 0;
}

void WS2812Strip::fill(uint32_t color, uint16_t first, uint16_t count)
{
  if (!pixels_ || first >= numPixels_)
    return;
  uint16_t end = (count == 0 || count > numPixels_ - first) ? numPixels_ : first + count;
  for (uint16_t i = first; i < end; i++)
    pixels_[i] = color & 0xFFFFFFUL;
}

uint32_t WS2812Strip::ColorHSV(uint16_t hue, uint8_t sat, uint8_t val)
{
  // Six 60-degree sectors of the wheel, each 65536/6 wide.
  uint32_t sector = ((uint32_t)hue * 6) >> 16;          // 0-5
  uint32_t frac = (((uint32_t)hue * 6) & 0xFFFF) >> 8; // 0-255 within the sector
  uint32_t r, g, b;
  switch (sector) {
  case 0: r = 255; g = frac; b = 0; break;
  case 1: r = 255 - frac; g = 255; b = 0; break;
  case 2: r = 0; g = 255; b = frac; break;
  case 3: r = 0; g = 255 - frac; b = 255; break;
  case 4: r = frac; g = 0; b = 255; break;
  default: r = 255; g = 0; b = 255 - frac; break;
  }

  // Saturation blends toward white, value scales the result.
  uint32_t s = (uint32_t)sat + 1, v = (uint32_t)val + 1;
  uint32_t white = 255 - sat;
  r = (((r * s) >> 8) + white) * v >> 8;
  g = (((g * s) >> 8) + white) * v >> 8;
  b = (((b * s) >> 8) + white) * v >> 8;
  return Color((uint8_t)r, (uint8_t)g, (uint8_t)b);
}

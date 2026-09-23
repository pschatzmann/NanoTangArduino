/* A moving rainbow on an external WS2812 strip. Wire the strip's data
 * input to GPIO0 (FPGA pin 73), power it from its own 5V supply with a
 * common ground, and set NUM_PIXELS to your strip's length. */

#include <WS2812.h>

#define NUM_PIXELS 30

WS2812Strip strip(NUM_PIXELS, GPIO0);

void setup()
{
  Serial.begin(115200);
  if (!strip.begin())
    Serial.println("WS2812Strip: begin() failed");
  strip.setBrightness(40);
}

void loop()
{
  static uint16_t firstHue = 0;
  for (uint16_t i = 0; i < strip.numPixels(); i++)
    strip.setPixelColor(i, WS2812Strip::ColorHSV(firstHue + i * 65536UL / strip.numPixels()));
  strip.show();
  firstHue += 256;
  delay(20);
}

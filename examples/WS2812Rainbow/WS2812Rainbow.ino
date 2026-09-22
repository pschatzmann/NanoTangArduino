/* Cycles the onboard WS2812 addressable RGB LED through red, green, blue. */

#include <WS2812.h>

void setup() {
  WS2812.begin();
}

void loop() {
  WS2812.write(32, 0, 0); // red
  delay(500);
  WS2812.write(0, 32, 0); // green
  delay(500);
  WS2812.write(0, 0, 32); // blue
  delay(500);
}

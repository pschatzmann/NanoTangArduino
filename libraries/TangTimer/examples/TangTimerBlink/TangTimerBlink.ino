/* Blinks LED0 from a repeating TangTimer callback instead of delay(),
 * leaving loop() free to do other work. */

#include <TangTimer.h>

TangTimer blinker;
volatile bool ledState = false;

void toggleLed() {
  ledState = !ledState;
}

void setup() {
  pinMode(LED0, OUTPUT);
  blinker.begin(toggleLed, 500000UL /* 500ms */, true /* repeat */);
}

void loop() {
  digitalWrite(LED0, ledState ? HIGH : LOW);
}

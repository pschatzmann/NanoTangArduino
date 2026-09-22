/* analogWrite() with a per-pin frequency: dims LED0 at the default
 * (~105kHz), blinks LED1 visibly at 2Hz with a 25% duty cycle, and drives
 * a hobby servo on GPIO0 at the standard 50Hz - see docs/PERIPHERALS.md
 * "Digital I/O and PWM".
 */

void setup() {
  analogWrite(LED0, 32);            // default frequency

  analogWriteFrequency(LED1, 2);    // slow enough to see
  analogWrite(LED1, 64);            // 25% on

  analogWriteFrequency(GPIO0, 50);  // servo frame rate: 20ms
}

void loop() {
  // Servo pulse 1ms..2ms out of 20ms = 5%..10% duty = 13..26 of 255.
  for (int v = 13; v <= 26; v++) {
    analogWrite(GPIO0, v);
    delay(100);
  }
  for (int v = 26; v >= 13; v--) {
    analogWrite(GPIO0, v);
    delay(100);
  }
}

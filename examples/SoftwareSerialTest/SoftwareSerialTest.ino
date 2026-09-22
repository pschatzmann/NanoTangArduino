/* Loops back a second, bit-banged serial port on two GPIO pins - wire
 * GPIO0 (TX) to GPIO1 (RX) with a jumper to see it echo what it sends.
 * See docs/PERIPHERALS.md "Software Serial". Also prints over the
 * regular hardware Serial so you can watch it work over USB. */

#include <SoftwareSerial.h>

SoftwareSerial softSerial(/*rx=*/GPIO1, /*tx=*/GPIO0);

void setup() {
  Serial.begin(115200);
  softSerial.begin(9600);
}

void loop() {
  static unsigned long lastSend = 0;
  static char nextChar = 'A';

  if (millis() - lastSend >= 500) {
    lastSend = millis();
    softSerial.write(nextChar);
    Serial.print("sent: ");
    Serial.println(nextChar);
    nextChar = (nextChar == 'Z') ? 'A' : nextChar + 1;
  }

  if (softSerial.available()) {
    Serial.print("received: ");
    Serial.println((char)softSerial.read());
  }

  if (softSerial.overflow()) {
    Serial.println("softSerial: receive buffer overflowed");
  }
}

/* Blinks GPIO0 (expansion header pin, physical FPGA pin 73) and echoes
 * GPIO1's level back on GPIO2, to demonstrate general-purpose digital I/O
 * on the J5/J6 expansion header. See docs/PERIPHERALS.md "General GPIO" for the full
 * pin table (physical pin numbers and which pins double as the optional
 * LCD/HDMI-EDID connectors). */

void setup() {
  pinMode(GPIO0, OUTPUT);
  pinMode(GPIO1, INPUT);
  pinMode(GPIO2, OUTPUT);
}

void loop() {
  digitalWrite(GPIO0, HIGH);
  digitalWrite(GPIO2, digitalRead(GPIO1));
  delay(500);

  digitalWrite(GPIO0, LOW);
  digitalWrite(GPIO2, digitalRead(GPIO1));
  delay(500);
}

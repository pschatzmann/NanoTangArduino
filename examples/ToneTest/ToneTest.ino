/* Drives a square wave on GPIO0 with tone()/noTone() - connect a piezo
 * speaker between GPIO0 and GND. Uses picorv32's built-in timer interrupt
 * to toggle the pin; see docs/PERIPHERALS.md "Interrupts". */

void setup() {
}

void loop() {
  tone(GPIO0, 440, 500); // A4 for 500ms
  delay(1000);
  tone(GPIO0, 880, 500); // A5 for 500ms
  delay(1000);
}

/* Lights LED1 while the board's second button (KEY_S2 / BTN1) is held. */

void setup() {
  pinMode(LED1, OUTPUT);
  // BTN1 needs no pinMode() call - it's a fixed input (see wiring_digital.cpp).
}

void loop() {
  digitalWrite(LED1, digitalRead(BTN1));
}

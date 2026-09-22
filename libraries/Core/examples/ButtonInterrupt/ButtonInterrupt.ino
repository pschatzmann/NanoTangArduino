/* Toggles LED1 from an attachInterrupt() callback on BTN1, instead of
 * polling digitalRead() in loop() like the Button example does. */

volatile bool ledState = false;

void onButtonChange() {
  ledState = !ledState;
}

void setup() {
  pinMode(LED1, OUTPUT);
  attachInterrupt(digitalPinToInterrupt(BTN1), onButtonChange, CHANGE);
}

void loop() {
  digitalWrite(LED1, ledState ? HIGH : LOW);
}

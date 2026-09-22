/* Fades LED0 up and down using analogWrite() (PWM). */

int brightness = 0;
int step = 5;

void setup() {
  pinMode(LED0, OUTPUT);
}

void loop() {
  analogWrite(LED0, brightness);

  brightness += step;
  if (brightness <= 0 || brightness >= 255)
    step = -step;

  delay(15);
}

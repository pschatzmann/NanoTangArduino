void setup() {
  Serial.begin(115200);
  Serial.println("Hello from Tang Nano 20K!");
}

void loop() {
  Serial.print("millis: ");
  Serial.println(millis());
  delay(1000);
}

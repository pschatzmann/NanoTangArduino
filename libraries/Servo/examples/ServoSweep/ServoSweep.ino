/* Sweeps a servo on GPIO0 back and forth between 0 and 180 degrees.
 * Wire the servo's signal line to GPIO0 (FPGA pin 73), and power it from
 * its own 5V supply with a common ground. */

#include <Servo.h>

Servo servo;

void setup()
{
  Serial.begin(115200);
  servo.attach(GPIO0);
  if (!servo.attached())
    Serial.println("No free PWM channel for the servo");
}

void loop()
{
  for (int angle = 0; angle <= 180; angle++) {
    servo.write(angle);
    delay(15);
  }
  for (int angle = 180; angle >= 0; angle--) {
    servo.write(angle);
    delay(15);
  }
}

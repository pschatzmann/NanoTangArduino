/* Classic I2C bus scanner: probes every 7-bit address and reports which
 * ones ACK.
 *
 * I2C shares the onboard microSD slot's bus pins (see
 * gateware/src/od_gpio2.v and docs/PERIPHERALS.md) - don't run this with a microSD
 * card inserted. Wire an I2C device to those same pins to try it:
 * SDA=85, SCL=80 (physical FPGA pin numbers; see
 * gateware/picorv32_20k.cst). This is a bit-banged master - don't expect
 * high speed, but a few hundred kHz is fine for most sensors. */

#include <Wire.h>

void setup() {
  Serial.begin(115200);
  Wire.begin();
  Wire.setClock(100000);
}

void loop() {
  Serial.println("Scanning I2C bus...");

  int found = 0;
  for (uint8_t address = 1; address < 127; address++) {
    Wire.beginTransmission(address);
    uint8_t status = Wire.endTransmission();
    if (status == 0) {
      Serial.print("  Found device at 0x");
      Serial.println(address, HEX);
      found++;
    }
  }

  if (found == 0)
    Serial.println("  No devices found");

  delay(5000);
}

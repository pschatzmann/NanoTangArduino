/* Exercises the second SPI/I2C port on GPIO0-5 - requires selecting
 * Tools > Extra SPI/I2C: Enabled (disabled by default). SPI (the first
 * port) keeps working normally on the microSD slot bus pins; SPI2/Wire2
 * are independent, simultaneous ports on GPIO0-5 - see
 * docs/PERIPHERALS.md "SPI, I2C (Wire), and the SD card". */

#include <SPI.h>
#include <Wire.h>

void setup() {
  SPI2.begin();
  SPI2.beginTransaction(SPISettings(1000000, MSBFIRST, SPI_MODE0));
  SPI2.transfer(0xAA);
  SPI2.endTransaction();

  Wire2.begin();
  Wire2.beginTransmission(0x50);
  Wire2.write((uint8_t)0x00);
  Wire2.endTransmission();
}

void loop() {
}

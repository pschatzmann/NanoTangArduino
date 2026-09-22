/* Sends a byte over SPI once a second and prints back whatever the slave
 * shifted in return.
 *
 * SPI shares the onboard microSD slot's bus pins (see
 * gateware/src/spi_master.v and docs/PERIPHERALS.md) - don't run this with a microSD
 * card inserted. Wire an SPI peripheral to those same pins to try it:
 * SCLK=83, MOSI=82, MISO=84, CS=81 (physical FPGA pin numbers; see
 * gateware/picorv32_20k.cst). Only SPI mode 0, MSB-first is supported. */

#include <SPI.h>

void setup() {
  Serial.begin(115200);
  SPI.begin();
}

void loop() {
  SPI.beginTransaction(SPISettings(1000000, MSBFIRST, SPI_MODE0));
  uint8_t reply = SPI.transfer(0xFF);
  SPI.endTransaction();

  Serial.print("SPI reply: 0x");
  Serial.println(reply, HEX);

  delay(1000);
}

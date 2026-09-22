/* Reads and writes a file on the onboard microSD card slot.
 *
 * The SD library uses the onboard microSD slot's bus pins in SPI mode
 * (see libraries/SD, libraries/SPI, and docs/PERIPHERALS.md "SD card") - it's mutually
 * exclusive with using those same pins for a general-purpose SPI or I2C
 * device (libraries/SPI, libraries/Wire used for anything else). */

#include <SPI.h>
#include <SD.h>

void setup() {
  Serial.begin(115200);

  if (!SD.begin(SS)) {
    Serial.println("SD.begin() failed - is a card inserted?");
    return;
  }

  File f = SD.open("test.txt", FILE_WRITE);
  if (f) {
    f.println("Hello from Tang Nano 20K!");
    f.close();
  }

  f = SD.open("test.txt");
  if (f) {
    while (f.available())
      Serial.write(f.read());
    f.close();
  }
}

void loop() {
}

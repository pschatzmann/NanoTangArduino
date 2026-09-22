/* Exercises malloc()/free() backed by the onboard 8MB embedded SDRAM (see
 * cores/tangnano20k/tangnano20k_malloc.c and docs/PERIPHERALS.md "Heap / malloc"). */

#include <stdlib.h>

void setup() {
  Serial.begin(115200);
}

void loop() {
  size_t size = 1024;
  uint8_t *buf = (uint8_t *)malloc(size);

  if (buf == NULL) {
    Serial.println("malloc failed!");
  } else {
    for (size_t i = 0; i < size; i++)
      buf[i] = (uint8_t)i;

    uint32_t checksum = 0;
    for (size_t i = 0; i < size; i++)
      checksum += buf[i];

    Serial.print("allocated ");
    Serial.print(size);
    Serial.print(" bytes at 0x");
    Serial.print((unsigned long)buf, HEX);
    Serial.print(", checksum=");
    Serial.println(checksum);

    free(buf);
  }

  delay(1000);
}

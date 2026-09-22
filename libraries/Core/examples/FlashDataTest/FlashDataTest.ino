/* Stores a big constant table in the onboard SPI flash instead of the
 * 32KB internal SRAM, using FLASH_DATA - reads happen through ordinary
 * array syntax. Verifies the first/last few entries and lights LED0 solid
 * on success (blinks fast on a mismatch).
 *
 * Requires the FLASH_DATA payload to actually be written to the board's
 * flash - see docs/PERIPHERALS.md "Flash" (tools/upload.py writes it
 * automatically as part of a normal upload, in either Boot Mode). */

#define TABLE_LEN 4096

const uint32_t bigTable[TABLE_LEN] FLASH_DATA = {
// A small generated pattern is enough to prove flash-mapped reads work;
// this array is populated below in setup() logic instead of a literal
// list for brevity - see the loop initializing `expected` for the values
// actually compared against.
#define V(i) ((uint32_t)(i) * 2654435761u)
#define V4(i) V(i), V(i + 1), V(i + 2), V(i + 3)
#define V16(i) V4(i), V4(i + 4), V4(i + 8), V4(i + 12)
#define V64(i) V16(i), V16(i + 16), V16(i + 32), V16(i + 48)
#define V256(i) V64(i), V64(i + 64), V64(i + 128), V64(i + 192)
#define V1024(i) V256(i), V256(i + 256), V256(i + 512), V256(i + 768)
  V1024(0), V1024(1024), V1024(2048), V1024(3072)
};

void setup() {
  pinMode(LED0, OUTPUT);

  bool ok = true;
  for (uint32_t i = 0; i < TABLE_LEN; i++) {
    uint32_t expected = (uint32_t)i * 2654435761u;
    if (bigTable[i] != expected) {
      ok = false;
      break;
    }
  }

  digitalWrite(LED0, ok ? HIGH : LOW);
  while (!ok) {
    digitalWrite(LED0, !digitalRead(LED0));
    delay(100);
  }
}

void loop() {
}

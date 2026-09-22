/* Fills a source buffer in the SDRAM heap, DMA-copies it to a second
 * buffer, then verifies every word round-tripped correctly - LED0 lights
 * solid on success, blinks fast on a mismatch. */

#include <DMA.h>

#define WORD_COUNT 4096

uint32_t *src;
uint32_t *dst;

void setup() {
  pinMode(LED0, OUTPUT);

  src = (uint32_t *)malloc(WORD_COUNT * sizeof(uint32_t));
  dst = (uint32_t *)malloc(WORD_COUNT * sizeof(uint32_t));

  for (uint32_t i = 0; i < WORD_COUNT; i++)
    src[i] = i * 2654435761u; // Knuth multiplicative hash, just needs variety.

  dmaCopyWords(dst, src, WORD_COUNT);

  bool ok = true;
  for (uint32_t i = 0; i < WORD_COUNT; i++) {
    if (dst[i] != src[i]) {
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

/* Starts a large background DMA copy within the SDRAM heap and keeps
 * blinking LED0 the whole time via loop() - proving the CPU isn't stalled
 * the way it is with dmaCopyWords(). LED1 lights once the callback fires. */

#include <DMA.h>

#define WORD_COUNT (256 * 1024) // 1MB, large enough to take a while

uint32_t *src;
uint32_t *dst;
volatile bool copyDone = false;

void onCopyDone() {
  copyDone = true;
}

void setup() {
  pinMode(LED0, OUTPUT);
  pinMode(LED1, OUTPUT);

  src = (uint32_t *)malloc(WORD_COUNT * sizeof(uint32_t));
  dst = (uint32_t *)malloc(WORD_COUNT * sizeof(uint32_t));

  for (uint32_t i = 0; i < WORD_COUNT; i++)
    src[i] = i;

  dmaCopyWordsAsync(dst, src, WORD_COUNT, onCopyDone);
}

void loop() {
  // Keeps blinking at a steady rate throughout the background copy -
  // if this were dmaCopyWords() instead, the board would appear frozen
  // (no blinking) until the whole transfer finished.
  digitalWrite(LED0, !digitalRead(LED0));
  delay(100);

  digitalWrite(LED1, copyDone ? HIGH : LOW);
}

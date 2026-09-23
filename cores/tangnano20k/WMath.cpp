#include "Arduino.h"

/* random()/randomSeed(): there's no libc random() on this -nostdlib core,
 * so this is a small xorshift32 generator. Like on AVR, the sequence is
 * the same on every boot unless the sketch calls randomSeed(). */

static uint32_t randomState = 2463534242UL;

static uint32_t nextRandom(void)
{
  uint32_t x = randomState;
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  randomState = x;
  return x;
}

void randomSeed(unsigned long seed)
{
  if (seed != 0)
    randomState = seed; // xorshift's state must never be 0.
}

long random(long howbig)
{
  if (howbig <= 0)
    return 0;
  return (long)(nextRandom() % (uint32_t)howbig);
}

long random(long howsmall, long howbig)
{
  if (howsmall >= howbig)
    return howsmall;
  uint32_t diff = (uint32_t)howbig - (uint32_t)howsmall;
  return (long)((uint32_t)howsmall + nextRandom() % diff);
}

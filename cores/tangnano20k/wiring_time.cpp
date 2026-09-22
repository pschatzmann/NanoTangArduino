#include "Arduino.h"

/* TANGNANO20K_SYSTICK_REG is a 32-bit free-running counter incrementing
 * once per system clock cycle (20MHz). It wraps roughly every 214s, much
 * sooner than the ~49 day wrap of a typical Arduino board's millis() -
 * see README for details. Code that compares millis()/micros() with
 * unsigned subtraction (the standard Arduino idiom) is unaffected. */

unsigned long micros(void)
{
  return TANGNANO20K_SYSTICK_REG / (TANGNANO20K_CLK_FREQ / 1000000UL);
}

unsigned long millis(void)
{
  return TANGNANO20K_SYSTICK_REG / (TANGNANO20K_CLK_FREQ / 1000UL);
}

void delay(unsigned long ms)
{
  unsigned long start = millis();
  while ((millis() - start) < ms) {
  }
}

void delayMicroseconds(unsigned int us)
{
  unsigned long start = micros();
  while ((unsigned long)(micros() - start) < us) {
  }
}

#include "Arduino.h"

void init(void)
{
  TANGNANO20K_LED_REG = 0;

  /* picorv32 comes out of reset with every interrupt masked. As on other
   * Arduino cores, interrupts are enabled before setup() runs - every
   * peripheral's own interrupt stays off until its library turns it on,
   * so this alone fires nothing. (Previously nothing unmasked them here:
   * they only came on as a side effect of a library calling
   * interrupts(), and once the libraries' critical sections were made to
   * restore the previous state instead, no interrupt ever fired - found
   * on real hardware, where I2S.write() blocked forever.) */
  interrupts();
}

void initVariant(void)
{
}

int main(void)
{
  init();
  initVariant();

  setup();
  for (;;) {
    loop();
    if (serialEventRun)
      serialEventRun();
  }

  return 0;
}

#include "Arduino.h"

void init(void)
{
  TANGNANO20K_LED_REG = 0;
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

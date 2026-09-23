#include "Arduino.h"

extern "C" uint8_t shiftIn(pin_size_t dataPin, pin_size_t clockPin, BitOrder bitOrder)
{
  uint8_t value = 0;
  for (uint8_t i = 0; i < 8; i++) {
    digitalWrite(clockPin, HIGH);
    if (bitOrder == LSBFIRST)
      value |= (digitalRead(dataPin) == HIGH ? 1 : 0) << i;
    else
      value |= (digitalRead(dataPin) == HIGH ? 1 : 0) << (7 - i);
    digitalWrite(clockPin, LOW);
  }
  return value;
}

extern "C" void shiftOut(pin_size_t dataPin, pin_size_t clockPin, BitOrder bitOrder, uint8_t val)
{
  for (uint8_t i = 0; i < 8; i++) {
    bool bit = (bitOrder == LSBFIRST) ? (val & (1U << i)) : (val & (1U << (7 - i)));
    digitalWrite(dataPin, bit ? HIGH : LOW);
    digitalWrite(clockPin, HIGH);
    digitalWrite(clockPin, LOW);
  }
}

#pragma once

#include "api/HardwareSerial.h"

namespace tangnano20k {

class HardwareSerial : public arduino::HardwareSerial
{
public:
  void begin(unsigned long baudrate) override;
  void begin(unsigned long baudrate, uint16_t config) override;
  void end() override;

  int available(void) override;
  int peek(void) override;
  int read(void) override;
  void flush(void) override;
  size_t write(uint8_t c) override;
  using Print::write;

  operator bool() override { return true; }

private:
  void refillRxCache(void);

  bool rxHasByte = false;
  uint8_t rxByte = 0;
};

} // namespace tangnano20k

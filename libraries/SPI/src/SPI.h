#pragma once

#include <Arduino.h>
#include "api/HardwareSPI.h"

/* SPI master (see gateware/src/spi_master.v). Only mode 0, MSB-first is
 * supported in hardware; the requested SPIMode/BitOrder in SPISettings are
 * otherwise ignored. There is a single fixed CS line (asserted for the
 * duration of a transaction, i.e. between beginTransaction()/
 * endTransaction()) rather than a general-purpose CS pin - only one SPI
 * device can be wired up at a time per port.
 *
 * `SPI` (this file's global instance) uses the onboard microSD slot's bus
 * pins - mutually exclusive with using the microSD slot, and present by
 * default but removable (Tools > SPI Buses: None) to save LUTs. `SPI2`
 * (this file's second global instance, only present when Tools > SPI
 * Buses: Two is selected) uses GPIO0-3 instead - see
 * docs/PERIPHERALS.md. */
class TangNanoSPIClass : public arduino::HardwareSPI
{
public:
  TangNanoSPIClass(volatile uint32_t &divReg, volatile uint32_t &csReg, volatile uint32_t &datReg)
    : divReg_(divReg), csReg_(csReg), datReg_(datReg) {}

  uint8_t transfer(uint8_t data) override;
  uint16_t transfer16(uint16_t data) override;
  void transfer(void *buf, size_t count) override;

  void usingInterrupt(int interruptNumber) override { (void)interruptNumber; }
  void notUsingInterrupt(int interruptNumber) override { (void)interruptNumber; }
  void beginTransaction(arduino::SPISettings settings) override;
  void endTransaction(void) override;

  void attachInterrupt() override {}
  void detachInterrupt() override {}

  void begin() override;
  void end() override;

private:
  volatile uint32_t &divReg_;
  volatile uint32_t &csReg_;
  volatile uint32_t &datReg_;
};

extern TangNanoSPIClass SPI;
extern TangNanoSPIClass SPI2; // Only usable when Tools > SPI Buses: Two is selected - see docs/PERIPHERALS.md.

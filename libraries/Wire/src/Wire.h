#pragma once

#include <Arduino.h>
#include "api/HardwareI2C.h"

/* I2C master, bit-banged in software over an open-drain SDA/SCL pair (see
 * gateware/src/od_gpio2.v). Master mode only (no slave/onReceive/onRequest
 * support). Buffers are fixed-size (32 bytes, no dynamic allocation is
 * available on this bare-metal core).
 *
 * `Wire` (this file's global instance) uses the onboard microSD slot's two
 * remaining bus lines - mutually exclusive with using the microSD slot,
 * and present by default but removable (Tools > I2C Buses: None) to save
 * LUTs. `Wire2` (libraries/Wire's second global instance, only present
 * when Tools > I2C Buses: Two is selected) uses GPIO4/GPIO5 instead - see
 * docs/PERIPHERALS.md.
 *
 * A slave holding SCL low (clock stretching) is waited for, but only up
 * to the timeout (25ms by default, AVR's setWireTimeout() API): after
 * that the transfer is abandoned, both lines released, the timeout flag
 * set, and endTransmission() returns 5 / requestFrom() 0 - so a missing
 * pull-up or a stuck device can't hang the sketch. */
class TwoWire : public arduino::HardwareI2C
{
public:
  explicit TwoWire(volatile uint32_t &reg) : reg_(reg) {}

  void begin() override;
  void begin(uint8_t address) override;
  void end() override;

  void setClock(uint32_t freq) override;

  void beginTransmission(uint8_t address) override;
  uint8_t endTransmission(bool stopBit) override;
  uint8_t endTransmission(void) override { return endTransmission(true); }

  size_t requestFrom(uint8_t address, size_t len, bool stopBit) override;
  size_t requestFrom(uint8_t address, size_t len) override { return requestFrom(address, len, true); }

  void onReceive(void (*)(int)) override {}
  void onRequest(void (*)(void)) override {}

  // timeout_us == 0 waits forever. reset_with_timeout is accepted for
  // AVR compatibility; the bus is always released after a timeout.
  void setWireTimeout(uint32_t timeout_us = 25000, bool reset_with_timeout = false);
  bool getWireTimeoutFlag(void) const { return timeoutFlag_; }
  void clearWireTimeoutFlag(void) { timeoutFlag_ = false; }

  int available(void) override;
  int peek(void) override;
  int read(void) override;
  void flush(void) override {}
  size_t write(uint8_t c) override;
  using Print::write;

private:
  static const size_t kBufferSize = 32;

  volatile uint32_t &reg_;

  void i2cStart(void);
  void i2cStop(void);
  bool i2cWriteByte(uint8_t b);
  uint8_t i2cReadByte(bool ack);
  void sdaLow(void);
  void sdaRelease(void);
  void sclLow(void);
  void sclRelease(void);
  bool sdaRead(void);
  void halfPeriodDelay(void);
  bool abandonIfTimedOut(void);

  uint8_t txBuffer[kBufferSize];
  size_t txLength = 0;
  uint8_t txAddress = 0;

  uint8_t rxBuffer[kBufferSize];
  size_t rxLength = 0;
  size_t rxIndex = 0;

  uint32_t halfPeriodCycles = F_CPU / 200000UL; // ~100kHz default
  uint32_t timeoutUs_ = 25000;
  bool aborted_ = false;     // Current transfer hit the timeout.
  bool timeoutFlag_ = false; // Sticky, for getWireTimeoutFlag().
};

extern TwoWire Wire;
extern TwoWire Wire2; // Only usable when Tools > I2C Buses: Two is selected - see docs/PERIPHERALS.md.

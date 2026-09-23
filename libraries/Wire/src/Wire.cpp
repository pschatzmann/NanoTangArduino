#include "Wire.h"

void TwoWire::sdaLow(void)
{
  reg_ = TANGNANO20K_I2C_SDA_LOW | (reg_ & TANGNANO20K_I2C_SCL_LOW);
}

void TwoWire::sdaRelease(void)
{
  reg_ = reg_ & TANGNANO20K_I2C_SCL_LOW;
}

void TwoWire::sclLow(void)
{
  reg_ = TANGNANO20K_I2C_SCL_LOW | (reg_ & TANGNANO20K_I2C_SDA_LOW);
}

void TwoWire::sclRelease(void)
{
  reg_ = reg_ & TANGNANO20K_I2C_SDA_LOW;
  /* Clock stretching: a slave may hold SCL low; wait for it to actually
   * read back high before proceeding - up to the timeout. Once a transfer
   * has timed out, later steps skip the wait so it unwinds quickly. */
  if (aborted_)
    return;
  uint32_t start = micros();
  while (!(reg_ & TANGNANO20K_I2C_SCL_LOW)) {
    if (timeoutUs_ != 0 && micros() - start >= timeoutUs_) {
      aborted_ = true;
      timeoutFlag_ = true;
      return;
    }
  }
}

/* Called at the end of a transfer: if it timed out, releases both lines
 * and reports it. */
bool TwoWire::abandonIfTimedOut(void)
{
  if (!aborted_)
    return false;
  reg_ = 0;
  aborted_ = false;
  return true;
}

bool TwoWire::sdaRead(void)
{
  return (reg_ & TANGNANO20K_I2C_SDA_LOW) != 0;
}

/* Timed against the cycle counter rather than whole microseconds, so
 * 400kHz (a 1.25us half period) is reachable. The bit-banging code
 * around each delay adds some cycles, so the bus runs a little slower
 * than requested, never faster. */
void TwoWire::halfPeriodDelay(void)
{
  uint32_t start = TANGNANO20K_SYSTICK_REG;
  while ((uint32_t)(TANGNANO20K_SYSTICK_REG - start) < halfPeriodCycles) {
  }
}

void TwoWire::i2cStart(void)
{
  sdaRelease();
  sclRelease();
  halfPeriodDelay();
  sdaLow();
  halfPeriodDelay();
  sclLow();
  halfPeriodDelay();
}

void TwoWire::i2cStop(void)
{
  sdaLow();
  halfPeriodDelay();
  sclRelease();
  halfPeriodDelay();
  sdaRelease();
  halfPeriodDelay();
}

bool TwoWire::i2cWriteByte(uint8_t b)
{
  for (int i = 7; i >= 0; i--) {
    if (b & (1 << i))
      sdaRelease();
    else
      sdaLow();
    halfPeriodDelay();
    sclRelease();
    halfPeriodDelay();
    sclLow();
  }

  sdaRelease();
  halfPeriodDelay();
  sclRelease();
  halfPeriodDelay();
  bool ack = !sdaRead(); // ACK = slave pulls SDA low.
  sclLow();
  return ack;
}

uint8_t TwoWire::i2cReadByte(bool ack)
{
  uint8_t value = 0;
  sdaRelease();

  for (int i = 0; i < 8; i++) {
    halfPeriodDelay();
    sclRelease();
    value = (value << 1) | (sdaRead() ? 1 : 0);
    halfPeriodDelay();
    sclLow();
  }

  if (ack)
    sdaLow();
  else
    sdaRelease();
  halfPeriodDelay();
  sclRelease();
  halfPeriodDelay();
  sclLow();
  sdaRelease();

  return value;
}

void TwoWire::begin(void)
{
  reg_ = 0; // Release both lines (idle high via pull-ups).
}

void TwoWire::begin(uint8_t /*address*/)
{
  begin(); // Slave mode is not supported; the address is ignored.
}

void TwoWire::end(void)
{
  reg_ = 0;
}

void TwoWire::setClock(uint32_t freq)
{
  if (freq == 0)
    freq = 100000UL;
  halfPeriodCycles = (F_CPU + 2UL * freq - 1) / (2UL * freq);
}

void TwoWire::setWireTimeout(uint32_t timeout_us, bool reset_with_timeout)
{
  (void)reset_with_timeout;
  timeoutUs_ = timeout_us;
}

void TwoWire::beginTransmission(uint8_t address)
{
  txAddress = address;
  txLength = 0;
}

uint8_t TwoWire::endTransmission(bool stopBit)
{
  uint8_t result = 0;
  i2cStart();
  if (!i2cWriteByte((uint8_t)(txAddress << 1))) {
    result = 2; // NACK on address.
  } else {
    for (size_t i = 0; i < txLength; i++) {
      if (!i2cWriteByte(txBuffer[i])) {
        result = 3; // NACK on data.
        break;
      }
    }
  }

  if (stopBit || result != 0)
    i2cStop();
  if (abandonIfTimedOut())
    return 5; // Timeout (AVR Wire's code).
  return result;
}

size_t TwoWire::requestFrom(uint8_t address, size_t len, bool stopBit)
{
  if (len > kBufferSize)
    len = kBufferSize;

  rxLength = 0;
  rxIndex = 0;

  i2cStart();
  if (!i2cWriteByte((uint8_t)((address << 1) | 1))) {
    i2cStop();
    abandonIfTimedOut();
    return 0;
  }

  for (size_t i = 0; i < len; i++)
    rxBuffer[i] = i2cReadByte(i != (len - 1));

  if (stopBit)
    i2cStop();
  if (abandonIfTimedOut())
    return 0;

  rxLength = len;
  return len;
}

int TwoWire::available(void)
{
  return (int)(rxLength - rxIndex);
}

int TwoWire::peek(void)
{
  if (rxIndex >= rxLength)
    return -1;
  return rxBuffer[rxIndex];
}

int TwoWire::read(void)
{
  if (rxIndex >= rxLength)
    return -1;
  return rxBuffer[rxIndex++];
}

size_t TwoWire::write(uint8_t c)
{
  if (txLength >= kBufferSize)
    return 0;
  txBuffer[txLength++] = c;
  return 1;
}

TwoWire Wire(TANGNANO20K_I2C_REG);
TwoWire Wire2(TANGNANO20K_I2C2_REG);

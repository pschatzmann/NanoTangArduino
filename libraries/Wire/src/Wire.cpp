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
   * read back high before proceeding. */
  while (!(reg_ & TANGNANO20K_I2C_SCL_LOW)) {
  }
}

bool TwoWire::sdaRead(void)
{
  return (reg_ & TANGNANO20K_I2C_SDA_LOW) != 0;
}

void TwoWire::halfPeriodDelay(void)
{
  delayMicroseconds(halfPeriodUs);
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
  halfPeriodUs = (unsigned int)(1000000UL / (2UL * freq));
  if (halfPeriodUs == 0)
    halfPeriodUs = 1;
}

void TwoWire::beginTransmission(uint8_t address)
{
  txAddress = address;
  txLength = 0;
}

uint8_t TwoWire::endTransmission(bool stopBit)
{
  i2cStart();
  if (!i2cWriteByte((uint8_t)(txAddress << 1))) {
    if (stopBit)
      i2cStop();
    return 2; // NACK on address.
  }

  for (size_t i = 0; i < txLength; i++) {
    if (!i2cWriteByte(txBuffer[i])) {
      if (stopBit)
        i2cStop();
      return 3; // NACK on data.
    }
  }

  if (stopBit)
    i2cStop();
  return 0;
}

size_t TwoWire::requestFrom(uint8_t address, size_t len, bool stopBit)
{
  if (len > kBufferSize)
    len = kBufferSize;

  i2cStart();
  if (!i2cWriteByte((uint8_t)((address << 1) | 1))) {
    i2cStop();
    rxLength = 0;
    rxIndex = 0;
    return 0;
  }

  for (size_t i = 0; i < len; i++)
    rxBuffer[i] = i2cReadByte(i != (len - 1));

  if (stopBit)
    i2cStop();

  rxLength = len;
  rxIndex = 0;
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

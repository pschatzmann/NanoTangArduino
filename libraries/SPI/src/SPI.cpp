#include "SPI.h"
#include "tangnano20k_soc.h"

void TangNanoSPIClass::begin(void)
{
  csReg_ = 0;
  divReg_ = TANGNANO20K_CLK_FREQ / (2UL * 1000000UL); // 1MHz default
}

void TangNanoSPIClass::end(void)
{
  csReg_ = 0;
}

void TangNanoSPIClass::beginTransaction(arduino::SPISettings settings)
{
  unsigned long clockHz = settings.getClockFreq();
  if (clockHz == 0)
    clockHz = 1000000UL;

  unsigned long divisor = TANGNANO20K_CLK_FREQ / (2UL * clockHz);
  divReg_ = divisor;
  csReg_ = TANGNANO20K_SPI_CS_ASSERT;
}

void TangNanoSPIClass::endTransaction(void)
{
  csReg_ = 0;
}

uint8_t TangNanoSPIClass::transfer(uint8_t data)
{
  datReg_ = data;      // Starts the transfer.
  return (uint8_t)datReg_; // Blocks until done, returns RX byte.
}

uint16_t TangNanoSPIClass::transfer16(uint16_t data)
{
  uint8_t hi = transfer((uint8_t)(data >> 8));
  uint8_t lo = transfer((uint8_t)(data & 0xFF));
  return ((uint16_t)hi << 8) | lo;
}

void TangNanoSPIClass::transfer(void *buf, size_t count)
{
  uint8_t *p = (uint8_t *)buf;
  for (size_t i = 0; i < count; i++)
    p[i] = transfer(p[i]);
}

TangNanoSPIClass SPI(TANGNANO20K_SPI_DIV_REG, TANGNANO20K_SPI_CS_REG, TANGNANO20K_SPI_DAT_REG);
TangNanoSPIClass SPI2(TANGNANO20K_SPI2_DIV_REG, TANGNANO20K_SPI2_CS_REG, TANGNANO20K_SPI2_DAT_REG);

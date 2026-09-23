#include "SPI.h"
#include "tangnano20k_soc.h"

/* The hardware toggles SCLK every (divisor+1) clocks, i.e. SCLK =
 * F_CPU / (2 * (divisor+1)); round the divisor up so the result never
 * exceeds the requested clock. */
static uint32_t clockDivisor(unsigned long clockHz)
{
  if (clockHz == 0)
    clockHz = 1000000UL;
  uint32_t halfPeriods = (TANGNANO20K_CLK_FREQ + 2UL * clockHz - 1) / (2UL * clockHz);
  return halfPeriods > 0 ? halfPeriods - 1 : 0;
}

void TangNanoSPIClass::begin(void)
{
  csReg_ = 0;
  cfgReg_ = 0; // Mode 0, MSB first.
  divReg_ = clockDivisor(1000000UL); // 1MHz default
}

void TangNanoSPIClass::end(void)
{
  csReg_ = 0;
}

void TangNanoSPIClass::beginTransaction(arduino::SPISettings settings)
{
  divReg_ = clockDivisor(settings.getClockFreq());
  // SPI_MODE0-3 are CPOL<<1 | CPHA, matching the register's low bits.
  cfgReg_ = ((uint32_t)settings.getDataMode() & 3UL) |
            (settings.getBitOrder() == LSBFIRST ? TANGNANO20K_SPI_CFG_LSB_FIRST : 0);
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

TangNanoSPIClass SPI(TANGNANO20K_SPI_DIV_REG, TANGNANO20K_SPI_CS_REG, TANGNANO20K_SPI_DAT_REG,
                     TANGNANO20K_SPI_CFG_REG);
TangNanoSPIClass SPI2(TANGNANO20K_SPI2_DIV_REG, TANGNANO20K_SPI2_CS_REG, TANGNANO20K_SPI2_DAT_REG,
                      TANGNANO20K_SPI2_CFG_REG);

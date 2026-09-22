#include "TangNanoI2S.h"
#include "tangnano20k_soc.h"

namespace tangnano20k {

void TangNanoI2S::begin(unsigned long sampleRate)
{
  unsigned long bclk = sampleRate * 32UL;
  unsigned long divisor = TANGNANO20K_CLK_FREQ / (2UL * bclk);
  if (divisor > 0)
    divisor -= 1;

  TANGNANO20K_I2S_DIV_REG = divisor;
  TANGNANO20K_I2S_CTRL_REG = TANGNANO20K_I2S_CTRL_PA_EN;
}

void TangNanoI2S::end(void)
{
  TANGNANO20K_I2S_CTRL_REG = 0;
}

void TangNanoI2S::write(int16_t left, int16_t right)
{
  uint32_t sample = ((uint32_t)(uint16_t)left << 16) | (uint16_t)right;
  TANGNANO20K_I2S_DAT_REG = sample;
}

} // namespace tangnano20k

tangnano20k::TangNanoI2S I2S;

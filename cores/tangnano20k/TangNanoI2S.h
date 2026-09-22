#pragma once

#include <stdint.h>

namespace tangnano20k {

/* Stereo I2S output to the onboard MAX98357A amplifier, driven by the
 * gateware's i2s_tx peripheral (see gateware/src/i2s_tx.v). Only 16-bit
 * samples are supported (that's what the MAX98357A expects over I2S). */
class TangNanoI2S
{
public:
  /* Enables the amplifier (PA_EN) and configures the BCLK divisor for
   * sampleRate: bclk runs at sampleRate * 32 (16 bits x 2 channels). */
  void begin(unsigned long sampleRate);

  /* Disables the amplifier. */
  void end(void);

  /* Blocking: stalls (via bus backpressure in i2s_tx, not a software
   * spin-loop) until the peripheral is ready for the next sample, which
   * naturally paces writes to the configured sample rate. */
  void write(int16_t left, int16_t right);

  void writeMono(int16_t sample) { write(sample, sample); }
};

} // namespace tangnano20k

extern tangnano20k::TangNanoI2S I2S;

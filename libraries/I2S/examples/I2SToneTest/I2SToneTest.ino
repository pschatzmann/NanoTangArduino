/* Plays a square-wave tone through the onboard MAX98357A amplifier. */

#include <I2STangNano.h>

const unsigned long sampleRate = 44100;
const unsigned long toneHz = 440;
const int16_t amplitude = 8000;

void setup() {
  I2SConfig config = I2S.defaultConfig(I2S_MODE_OUTPUT);
  config.sampleRate = sampleRate;
  I2S.begin(config);
}

void loop() {
  static unsigned long sample = 0;
  unsigned long samplesPerHalfCycle = sampleRate / (2 * toneHz);
  int16_t value = ((sample / samplesPerHalfCycle) % 2 == 0) ? amplitude : -amplitude;

  int16_t frame[2] = {value, value}; // left, right
  I2S.write((uint8_t *)frame, sizeof(frame));
  sample++;
}

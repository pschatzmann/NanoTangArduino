/* Plays a square-wave tone through the onboard MAX98357A amplifier. */

const unsigned long sampleRate = 16000;
const unsigned long toneHz = 440;
const int16_t amplitude = 8000;

void setup() {
  I2S.begin(sampleRate);
}

void loop() {
  static unsigned long sample = 0;
  unsigned long samplesPerHalfCycle = sampleRate / (2 * toneHz);
  int16_t value = ((sample / samplesPerHalfCycle) % 2 == 0) ? amplitude : -amplitude;

  I2S.write(value, value);
  sample++;
}

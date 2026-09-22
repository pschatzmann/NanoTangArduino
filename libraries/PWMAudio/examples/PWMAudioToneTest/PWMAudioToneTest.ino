/* Plays a square-wave tone as PWM audio on GPIO16 (left) and GPIO17
 * (right). Needs Tools > PWM Audio: Enabled, and an RC low-pass filter
 * (e.g. 1k + 10nF) or an amplifier between the pins and a speaker - see
 * docs/PERIPHERALS.md "Audio (PWM)".
 */

#include <PWMAudio.h>

const unsigned long sampleRate = 44100;
const unsigned long toneHz = 440;
const int16_t amplitude = 8000;

void setup() {
  PWMAudioConfig config = PWMAudio.defaultConfig();
  config.sampleRate = sampleRate;
  config.pwmRate = 50000;
  if (!PWMAudio.begin(config)) {
    Serial.begin(115200);
    Serial.println("PWMAudio: bitstream built without Tools > PWM Audio");
    while (true) {
    }
  }
}

void loop() {
  static unsigned long sample = 0;
  unsigned long samplesPerHalfCycle = sampleRate / (2 * toneHz);
  int16_t value = ((sample / samplesPerHalfCycle) % 2 == 0) ? amplitude : -amplitude;

  int16_t frame[2] = {value, value}; // left, right
  PWMAudio.write((uint8_t *)frame, sizeof(frame));
  sample++;
}

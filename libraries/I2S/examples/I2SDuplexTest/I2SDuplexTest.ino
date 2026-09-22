/* Full-duplex I2S: passes an external microphone's input straight back
 * out to the onboard MAX98357A amplifier, one captured frame at a time.
 * Needs Tools > I2S Input: Enabled (wires GPIO6 to the microphone's
 * data-out line) - see docs/PERIPHERALS.md "Audio (I2S)". Without a
 * microphone wired (or with I2S Input left disabled), captured samples
 * are just silence, so the amplifier stays quiet - this still exercises
 * the write()/read() Stream pairing and the background FIFO/interrupt
 * buffering (see docs/PERIPHERALS.md "Buffering and interrupts").
 */

#include <I2S.h>

const unsigned long sampleRate = 16000;

void setup() {
  I2S.begin(sampleRate, I2S_MODE_DUPLEX);
}

void loop() {
  if (I2S.available() >= 4) {
    uint8_t frame[4]; // {left16, right16}, little-endian
    I2S.readBytes(frame, sizeof(frame));
    I2S.write(frame, sizeof(frame));
  }
}

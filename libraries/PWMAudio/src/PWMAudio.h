#pragma once

#include <Arduino.h>

/* The PWM audio gateware only exists in the bitstream when Tools > PWM
 * Audio is enabled - it claims GPIO16/GPIO17, a synthesis-time decision
 * no runtime call can change. Fail at compile time rather than letting a
 * sketch silently play nothing (TANGNANO20K_PWM_AUDIO is set by
 * platform.txt - see docs/ARCHITECTURE.md "Preprocessor defines"). */
#if defined(TANGNANO20K_PWM_AUDIO) && !TANGNANO20K_PWM_AUDIO
#error "PWMAudio needs Tools > PWM Audio: Enabled - see docs/PERIPHERALS.md \"Audio (PWM)\""
#endif

/* begin()'s settings - see PWMAudioClass::defaultConfig() and begin().
 *
 * `sampleRate` (default 44100) is how many samples per second the
 * hardware pops off its FIFO - paced by gateware/src/pwm_audio.v's own
 * divider, so the actual rate is CLK_FREQ / round-down(CLK_FREQ /
 * sampleRate). `channels` is 1 (mono) or 2 (stereo, the default); with
 * 1, each sample drives both outputs. `pwmRate` (default 50000) is the
 * PWM carrier frequency in Hz: higher is easier to filter out, lower
 * gives more amplitude resolution (log2(CLK_FREQ / pwmRate) bits - about
 * 9 bits at the defaults and 27MHz). Keep it comfortably above the
 * highest audio frequency you care about. `ringSamples` (default 64)
 * sets the depth of the software ring buffer in front of the hardware
 * FIFO - see PWMAudioClass below; each sample costs 4 bytes,
 * heap-allocated (this core's heap is the embedded 8MB SDRAM - see
 * docs/PERIPHERALS.md#heap--malloc). */
struct PWMAudioConfig
{
  unsigned long sampleRate = 44100;
  uint8_t channels = 2;
  unsigned long pwmRate = 50000;
  uint16_t ringSamples = 64;
};

/* Stereo (or mono) PWM audio on GPIO16 (left) and GPIO17 (right), driven
 * by the gateware's pwm_audio peripheral (see gateware/src/pwm_audio.v).
 * Each pin carries a `pwmRate` square wave whose duty cycle follows the
 * signal - add an RC low-pass filter (or feed an amplifier/small speaker
 * that filters it for you) to hear it. See docs/PERIPHERALS.md "Audio
 * (PWM)".
 *
 * Same Stream-based API as libraries/I2S's output side: write(uint8_t)
 * (plus Print's bulk write(const uint8_t*, size_t)) takes raw
 * little-endian signed 16-bit PCM, channels interleaved left-then-right.
 * Scaling each sample onto the PWM period happens in gateware, so no
 * per-sample math runs on the CPU. Output is backed by a
 * `ringSamples`-deep software ring buffer that a background interrupt
 * drains into the hardware FIFO (see serviceIrq()), so write() only
 * blocks once you're that far ahead of the hardware. read()/peek()
 * always return -1 and available() 0 - there's no input side. */
class PWMAudioClass : public arduino::Stream
{
public:
  /* A default-initialized PWMAudioConfig - fill in whatever differs and
   * pass it to begin(). */
  PWMAudioConfig defaultConfig(void) const { return PWMAudioConfig(); }

  /* (Re)starts with the configuration last passed to begin(const
   * PWMAudioConfig &) - or PWMAudioConfig's defaults if there was none.
   * Returns false if the bitstream has no PWM audio peripheral (Tools >
   * PWM Audio disabled when it was built). Output starts at silence (50%
   * duty) until the first write(). If the ring buffer allocation fails
   * (e.g. an unreasonably large `ringSamples`), begin() falls back to the
   * smallest usable ring (1 sample) rather than leaving a null buffer;
   * check `ringSamples()` afterwards if this matters to your sketch. */
  bool begin(void);

  /* Applies `config` - see PWMAudioConfig for what each field does. */
  bool begin(const PWMAudioConfig &config)
  {
    config_ = config;
    return begin();
  }

  /* The configuration actually in effect - begin()'s `config`, with
   * `channels` normalized to 1 or 2 and `ringSamples` reflecting any
   * allocation fallback. */
  const PWMAudioConfig &config(void) const { return config_; }

  /* The ring buffer depth actually in effect. */
  uint16_t ringSamples(void) const { return ringCapacity_; }

  /* Stops the PWM outputs (both pins low) and the background interrupt,
   * discarding anything still queued. */
  void end(void);

  /* Stream/Print interface - see the class comment above. */
  size_t write(uint8_t byte) override;
  using Print::write;
  int availableForWrite(void) override;
  int available(void) override { return 0; }
  int read(void) override { return -1; }
  int peek(void) override { return -1; }
  void flush(void) override;

  /* Called only from the IRQ dispatcher (see wiring_irq.cpp's
   * tangnano20k_pwm_audio_set_irq_callback, registered by begin())
   * whenever pwm_audio.v's FIFO drops to half full - not meant to be
   * called directly by sketches. Public only because it has to be
   * reachable from a plain C callback. Drains the software ring buffer
   * into the hardware FIFO as far as both sides allow, and disables the
   * interrupt once the ring buffer is empty (re-armed by write()) so a
   * permanently low FIFO doesn't turn into an interrupt storm. */
  void serviceIrq(void);

private:
  /* Requested settings until begin() normalizes them - see config(). */
  PWMAudioConfig config_;
  bool started_ = false;

  /* Software ring buffer, one {left16,right16} sample per slot - same
   * design and locking rules as libraries/I2S's transmit ring. */
  uint16_t ringCapacity_ = 0;
  volatile uint32_t *ring_ = nullptr;
  volatile uint16_t ringHead_ = 0; // next slot write(uint8_t) will fill
  volatile uint16_t ringTail_ = 0; // next slot serviceIrq() will drain
  volatile uint16_t ringCount_ = 0;

  /* write(uint8_t)'s partial-frame accumulator (up to 2 channels x 16
   * bits). */
  uint8_t frame_[4];
  uint8_t frameLen_ = 0;

  void ringPush(uint32_t sample);
  bool allocateRing(uint16_t samples);
};

extern PWMAudioClass PWMAudio;

#pragma once

#include <Arduino.h>

/* Which direction(s) begin() sets up in software - see I2SClass below.
 * This does NOT decide whether the receive pin physically exists: an
 * external microphone's data line only reaches the FPGA at all when
 * Tools > I2S Input is enabled (see docs/PERIPHERALS.md "Audio (I2S)"),
 * because claiming GPIO6 for it is a synthesis-time decision (it removes
 * that pin from the general-purpose GPIO pool in the bitstream itself) -
 * nothing a runtime parameter can change. Passing I2S_MODE_INPUT/DUPLEX
 * without that menu enabled still works, it just reads back silence. */
enum I2SMode
{
  I2S_MODE_OUTPUT,
  I2S_MODE_INPUT,
  I2S_MODE_DUPLEX
};

/* Sample width for write(uint8_t)/read()/peek()/available() - the
 * gateware's i2s.v peripheral itself only ever moves 16-bit samples
 * (that's what the MAX98357A expects over I2S); anything else is
 * converted to/from 16-bit in software, the same way a WAV file's bit
 * depth is just an encoding of the underlying amplitude. 16/24/32-bit
 * samples are signed, matching standard PCM; 8-bit comes in both
 * flavors since real-world 8-bit PCM sources go either way - I2S_BITS_8
 * is signed (consistent with the wider widths), I2S_BITS_8_UNSIGNED is
 * unsigned and centered at 128 (the conventional 8-bit WAV encoding).
 * I2S_BITS_8_UNSIGNED's value is arbitrary (not a real bit count) - it
 * only needs to differ from I2S_BITS_8's. */
enum I2SBitsPerSample
{
  I2S_BITS_8          = 8,
  I2S_BITS_8_UNSIGNED = 9,
  I2S_BITS_16         = 16,
  I2S_BITS_24         = 24,
  I2S_BITS_32         = 32
};

/* begin()'s settings - see I2SClass::defaultConfig() and begin().
 *
 * `sampleRate` sets the shared BCLK: bclk runs at sampleRate * 32
 * (16 bits x 2 channels, regardless of `channels`/`bits` below - both
 * only affect write()/read()'s byte framing/conversion, not the hardware
 * timing). `mode` selects whether begin() enables the amplifier (PA_EN) -
 * I2S_MODE_INPUT leaves it disabled, OUTPUT/DUPLEX enable it - and
 * whether the receive-side background interrupt is armed (INPUT/DUPLEX
 * only; see the I2SClass comment below and serviceIrq()). `channels` is
 * 1 (mono) or 2 (stereo, the default); with 1, writes duplicate the
 * single sample onto both hardware channels, and reads only expose the
 * left channel. `bits` (8/16/24/32, default 16) is write()/read()'s
 * sample width - see I2SBitsPerSample. `ringSamples` (default 512) sets
 * the depth of each direction's software ring buffer - see the I2SClass
 * comment below; each sample costs 4 bytes, heap-allocated (this core's
 * heap is the embedded 8MB SDRAM - see docs/PERIPHERALS.md#heap--malloc). */
/* Rings up to this many samples per direction use fast internal-SRAM
 * buffers (4KB in total at the default, only in sketches using I2S);
 * larger ones come from the SDRAM heap, which is much slower - see
 * I2S.cpp's allocateRings(). */
#ifndef I2S_SRAM_RING_SAMPLES
#define I2S_SRAM_RING_SAMPLES 512
#endif

struct I2SConfig
{
  unsigned long sampleRate = 44100;
  I2SMode mode = I2S_MODE_OUTPUT;
  uint8_t channels = 2;
  I2SBitsPerSample bits = I2S_BITS_16;
  uint16_t ringSamples = I2S_SRAM_RING_SAMPLES; // ~11.6ms at 44.1kHz of slack
};

/* Stereo (or mono) I2S to the onboard MAX98357A amplifier (transmit,
 * always available) and, optionally, an external I2S microphone (receive
 * - see Tools > I2S Input), driven by the gateware's i2s peripheral (see
 * gateware/src/i2s.v).
 *
 * Transmit and receive share one BCLK/WS generator - once begin() is
 * called, both run continuously and simultaneously regardless of `mode`;
 * `mode` only controls PA_EN, whether the RX interrupt is armed, and
 * available()'s contract below - not what the hardware actually does. A
 * sketch that calls both write() and read() around the same loop is
 * running full duplex whether or not I2S_MODE_DUPLEX was passed - there's
 * no separate hardware mode to switch into.
 *
 * One API: `I2SClass` is an `arduino::Stream` - write(uint8_t)/read()/
 * peek()/available() are the only way in or out, working on raw
 * little-endian PCM bytes at the configured `bits` depth (see I2SConfig),
 * channels interleaved left-then-right, converting to/from the
 * hardware's native 16-bit samples internally. This is backed by its
 * own `ringSamples`-deep (see I2SConfig) software ring buffer per
 * direction, heap-allocated, that a background interrupt drains/fills
 * against i2s.v's own hardware FIFO - see serviceIrq() - so write() only
 * blocks once you're `ringSamples` samples ahead of hardware, and
 * read()/available() are genuinely non-blocking, reporting exactly what
 * has already been captured. I2S
 * output/input can be wired directly into or out of any other
 * Stream-based code this way (e.g. playing a PCM WAV file's bytes
 * straight through, or piping a captured sample straight back out - see
 * examples/I2SDuplexTest). For a single int16_t sample pair, write it as
 * bytes: `int16_t frame[2] = {left, right}; I2S.write((uint8_t*)frame,
 * sizeof(frame));` (Print::write(const uint8_t*, size_t), inherited via
 * `using Print::write` below). */
class I2SClass : public arduino::Stream
{
public:
  /* A default-initialized I2SConfig for `mode` - fill in whatever
   * differs (typically `sampleRate`) and pass it to begin(). */
  I2SConfig defaultConfig(I2SMode mode = I2S_MODE_OUTPUT) const
  {
    I2SConfig config;
    config.mode = mode;
    return config;
  }

  /* (Re)starts with the configuration last passed to begin(const
   * I2SConfig &) - or I2SConfig's defaults if there was none. */
  void begin(void);

  /* Applies `config` - see I2SConfig for what each field does. If the
   * ring buffer allocation fails (e.g. an unreasonably large
   * `ringSamples`), begin() falls back to the smallest usable ring (1
   * sample) rather than leaving a null buffer; check `ringSamples()`
   * afterwards if this matters to your sketch. Calling begin() again
   * reallocates the rings only if `ringSamples` actually changed from
   * the previous call. */
  void begin(const I2SConfig &config)
  {
    config_ = config;
    begin();
  }

  /* The configuration actually in effect - begin()'s `config`, with
   * `channels`/`bits` normalized to supported values and `ringSamples`
   * reflecting any allocation fallback. */
  const I2SConfig &config(void) const { return config_; }

  /* The ring buffer depth actually in effect - see I2SConfig's
   * `ringSamples` and begin()'s note about allocation fallback. */
  uint16_t ringSamples(void) const { return ringCapacity_; }

  /* Disables the amplifier and the background interrupt. Does not stop
   * the shared BCLK/WS generator. */
  void end(void);

  /* Stream/Print interface - see the class comment above. */
  size_t write(uint8_t byte) override;
  size_t write(const uint8_t *buffer, size_t size) override;
  using Print::write;
  // Samples (frames) that can be written without blocking: free space in
  // the software ring buffer.
  int availableForWrite(void) override { return (int)(ringCapacity_ - txRingCount_); }
  int available(void) override;
  int read(void) override;
  int peek(void) override;
  void flush(void) override;

  /* Called only from the IRQ dispatcher (see wiring_irq.cpp's
   * tangnano20k_i2s_set_irq_callback, registered by begin()) whenever
   * i2s.v's TX-room/RX-data condition fires (see gateware/src/i2s.v) -
   * not meant to be called directly by sketches. Public only because it
   * has to be reachable from a plain C callback. Drains the software TX
   * ring buffer into the hardware FIFO, and/or fills the software RX
   * ring buffer from the hardware FIFO, as far as both sides allow;
   * disables the TX interrupt once the ring buffer is empty (nothing
   * left to push) and the RX interrupt once the ring buffer is full
   * (nowhere left to put a capture) - re-armed by write(uint8_t)/read()
   * respectively - so an always-true "FIFO has room"/"FIFO has data"
   * hardware condition doesn't turn into a permanent interrupt storm. */
  void serviceIrq(void);

private:
  /* Effective settings - see config(). `ringSamples` stays 0 until the
   * first begin() allocates the rings. */
  I2SConfig config_ = {44800, I2S_MODE_OUTPUT, 2, I2S_BITS_16, 64};
  uint8_t bytesPerSample_ = 2;

  /* Software ring buffers, one hardware-format {left16,right16} sample
   * per slot, heap-allocated in begin() to `ringCapacity_` entries each -
   * see serviceIrq() and the class comment above. `volatile` because
   * both the ISR (serviceIrq()) and mainline code (write(uint8_t)/
   * read()) touch these; every multi-step update is wrapped in
   * noInterrupts()/interrupts() (matching this core's existing
   * convention, e.g. attachInterrupt()'s slot updates) since picorv32
   * itself already serializes against re-entrant IRQs (interrupts stay
   * masked until retirq), so only mainline-vs-ISR races need guarding. */
  uint16_t ringCapacity_ = 0; // slots actually allocated, independent of config_
  volatile uint32_t *txRing_ = nullptr;
  // Ring index + 1, wrapping - a compare instead of `% ringCapacity_`,
  // which is a slow library call without hardware divide.
  uint16_t nextIndex(uint16_t i) const { return (uint16_t)(i + 1 == ringCapacity_ ? 0 : i + 1); }

  // i2s.v's IRQ_ENABLE register reads back as 0, so bits are changed via
  // this copy - a read-modify-write of the register itself cleared the
  // other direction's bit.
  void setIrqEnable(uint32_t bits) { irqEnable_ = bits; TANGNANO20K_I2S_IRQEN_REG = bits; }
  volatile uint32_t irqEnable_ = 0;

  volatile uint16_t txRingHead_ = 0; // next slot write(uint8_t) will fill
  volatile uint16_t txRingTail_ = 0; // next slot serviceIrq() will drain
  volatile uint16_t txRingCount_ = 0;

  volatile uint32_t *rxRing_ = nullptr;
  volatile uint16_t rxRingHead_ = 0; // next slot serviceIrq() will fill
  volatile uint16_t rxRingTail_ = 0; // next slot read() will drain
  volatile uint16_t rxRingCount_ = 0;

  /* write(uint8_t)'s partial-sample accumulator: bytes are queued here
   * until a full frame (channels_ * bytesPerSample_ bytes) is ready,
   * then decoded and pushed onto txRing_ in one go. Sized for the widest
   * supported frame (2 channels x 32 bits). */
  uint8_t txFrame_[8];
  uint8_t txFrameLen_ = 0;

  /* read()/peek()/available()'s captured-frame cache: refilled a whole
   * frame (channels_ * bytesPerSample_ bytes) at a time by popping
   * rxRing_, encoded to the configured `bits`, then served out one byte
   * at a time without touching the ring buffer again until the cache is
   * exhausted. */
  uint8_t rxFrame_[8];
  uint8_t rxFrameLen_ = 0;
  uint8_t rxFramePos_ = 0;

  void txRingPush(uint32_t sample);
  bool rxRingPop(uint32_t *sample);
  bool refillRxFrame(void);
  int16_t decodeSample(const uint8_t *bytes) const;
  void encodeSample(int16_t sample, uint8_t *bytes) const;
  bool allocateRings(uint16_t samples);
};

extern I2SClass I2S;

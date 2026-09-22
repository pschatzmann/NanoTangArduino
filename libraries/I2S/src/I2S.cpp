#include "I2S.h"
#include "tangnano20k_soc.h"
#include <stdlib.h>

/* Registered with the core's IRQ dispatcher (see wiring_irq.cpp) rather
 * than called directly - I2S is an opt-in library, not part of the
 * always-linked core, so the core can't call into it by name. Mirrors
 * the DMA async-completion callback's registration pattern exactly. */
extern "C" void tangnano20k_i2s_set_irq_callback(void (*callback)(void));

static void i2sServiceIrqTrampoline(void)
{
  I2S.serviceIrq();
}

/* Allocates fresh txRing_/rxRing_ buffers of `samples` entries each,
 * freeing whatever was there before only once the new allocation has
 * actually succeeded (so a failed resize leaves the previous, working
 * buffers in place rather than leaking a null pointer). Returns false
 * if either allocation fails. */
bool I2SClass::allocateRings(uint16_t samples)
{
  uint32_t *newTx = (uint32_t *)malloc((size_t)samples * sizeof(uint32_t));
  uint32_t *newRx = (uint32_t *)malloc((size_t)samples * sizeof(uint32_t));
  if (!newTx || !newRx)
  {
    free(newTx);
    free(newRx);
    return false;
  }
  free((void *)txRing_);
  free((void *)rxRing_);
  txRing_ = newTx;
  rxRing_ = newRx;
  ringCapacity_ = samples;
  return true;
}

void I2SClass::begin()
{
  config_.channels = (config_.channels >= 2) ? 2 : 1;
  switch (config_.bits)
  {
    case I2S_BITS_8:
      config_.bits = I2S_BITS_8;
      bytesPerSample_ = 1;
      break;
    case I2S_BITS_8_UNSIGNED:
      config_.bits = I2S_BITS_8_UNSIGNED;
      bytesPerSample_ = 1;
      break;
    case I2S_BITS_24:
      config_.bits = I2S_BITS_24;
      bytesPerSample_ = 3;
      break;
    case I2S_BITS_32:
      config_.bits = I2S_BITS_32;
      bytesPerSample_ = 4;
      break;
    case I2S_BITS_16:
    default:
      config_.bits = I2S_BITS_16;
      bytesPerSample_ = 2;
      break;
  }
  txFrameLen_ = 0;
  rxFrameLen_ = 0;
  rxFramePos_ = 0;

  uint16_t ringSamples = config_.ringSamples;
  if (ringSamples == 0)
    ringSamples = 1; // A zero-deep ring can never hold a sample.
  if (ringSamples != ringCapacity_)
  {
    if (!allocateRings(ringSamples) && txRing_ == nullptr)
      allocateRings(1); // First-ever begin() with an unreasonable size - fall back rather than leaving null buffers.
  }
  config_.ringSamples = ringCapacity_;

  noInterrupts();
  txRingHead_ = 0;
  txRingTail_ = 0;
  txRingCount_ = 0;
  rxRingHead_ = 0;
  rxRingTail_ = 0;
  rxRingCount_ = 0;
  interrupts();

  unsigned long bclk = config_.sampleRate * 32UL;
  unsigned long divisor = TANGNANO20K_CLK_FREQ / (2UL * bclk);
  if (divisor > 0)
    divisor -= 1;

  TANGNANO20K_I2S_DIV_REG = divisor;
  /* PA_EN only matters for output/duplex - leaving the amplifier off in
   * pure INPUT mode saves power and avoids driving it with whatever
   * stale sample is sitting in the transmit shifter. */
  TANGNANO20K_I2S_CTRL_REG = (config_.mode != I2S_MODE_INPUT) ? TANGNANO20K_I2S_CTRL_PA_EN : 0;

  tangnano20k_i2s_set_irq_callback(i2sServiceIrqTrampoline);

  /* The TX interrupt is armed lazily by txRingPush() only while there's
   * something queued (see serviceIrq()'s header comment for why). RX
   * should start flowing into the ring buffer immediately whenever this
   * sketch might call read() - there's no "idle" concept for capture the
   * way there is for playback. */
  TANGNANO20K_I2S_IRQEN_REG = (config_.mode != I2S_MODE_OUTPUT) ? TANGNANO20K_I2S_IRQEN_RX : 0;
}

void I2SClass::end(void)
{
  TANGNANO20K_I2S_CTRL_REG = 0;
  TANGNANO20K_I2S_IRQEN_REG = 0;
}

/* Converts `bytesPerSample_` little-endian bytes at the configured
 * `config_.bits` depth into the hardware's native signed 16-bit range.
 * I2S_BITS_8_UNSIGNED is the one exception to "signed" (centered at 128,
 * as in a conventional 8-bit WAV file) - every other width, including
 * I2S_BITS_8, is signed. Narrower-than-16 widens by padding low bits
 * with zero (shifting up); wider-than-16 truncates by dropping low bits
 * (shifting down) - the same lossy-but-standard approach any PCM
 * bit-depth converter uses. */
int16_t I2SClass::decodeSample(const uint8_t *bytes) const
{
  switch (config_.bits)
  {
    case I2S_BITS_8:
      return (int16_t)(((int8_t)bytes[0]) << 8);
    case I2S_BITS_8_UNSIGNED:
    {
      int16_t centered = (int16_t)bytes[0] - 128;
      return (int16_t)(centered << 8);
    }
    case I2S_BITS_24:
    {
      int32_t raw = (int32_t)bytes[0] | ((int32_t)bytes[1] << 8) | ((int32_t)bytes[2] << 16);
      if (raw & 0x00800000L)
        raw |= (int32_t)0xFF000000L; // sign-extend 24 -> 32
      return (int16_t)(raw >> 8);
    }
    case I2S_BITS_32:
    {
      uint32_t raw = (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
                     ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
      return (int16_t)(((int32_t)raw) >> 16);
    }
    case I2S_BITS_16:
    default:
      return (int16_t)((uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8));
  }
}

/* The inverse of decodeSample(): widens/narrows a native 16-bit hardware
 * sample out to `bytesPerSample_` little-endian bytes at the configured
 * `config_.bits` depth. */
void I2SClass::encodeSample(int16_t sample, uint8_t *bytes) const
{
  switch (config_.bits)
  {
    case I2S_BITS_8:
      bytes[0] = (uint8_t)(sample >> 8);
      break;
    case I2S_BITS_8_UNSIGNED:
      bytes[0] = (uint8_t)((int16_t)(sample >> 8) + 128);
      break;
    case I2S_BITS_24:
    {
      int32_t widened = ((int32_t)sample) << 8;
      bytes[0] = (uint8_t)(widened & 0xFF);
      bytes[1] = (uint8_t)((widened >> 8) & 0xFF);
      bytes[2] = (uint8_t)((widened >> 16) & 0xFF);
      break;
    }
    case I2S_BITS_32:
    {
      int32_t widened = ((int32_t)sample) << 16;
      bytes[0] = (uint8_t)(widened & 0xFF);
      bytes[1] = (uint8_t)((widened >> 8) & 0xFF);
      bytes[2] = (uint8_t)((widened >> 16) & 0xFF);
      bytes[3] = (uint8_t)((widened >> 24) & 0xFF);
      break;
    }
    case I2S_BITS_16:
    default:
      bytes[0] = (uint8_t)(sample & 0xFF);
      bytes[1] = (uint8_t)((sample >> 8) & 0xFF);
      break;
  }
}

/* Pushes one hardware-format sample onto the software TX ring buffer,
 * (re-)arming the TX interrupt so serviceIrq() drains it into the
 * hardware FIFO in the background. Blocks (spinning with interrupts
 * enabled, so serviceIrq() can actually run and make room) only once the
 * ring buffer itself is full - ringCapacity_ samples ahead of hardware,
 * versus i2s.v's own much shallower hardware FIFO alone. */
void I2SClass::txRingPush(uint32_t sample)
{
  while (true)
  {
    noInterrupts();
    bool hasRoom = (txRingCount_ < ringCapacity_);
    if (hasRoom)
    {
      txRing_[txRingHead_] = sample;
      txRingHead_ = (uint16_t)((txRingHead_ + 1) % ringCapacity_);
      txRingCount_++;
      TANGNANO20K_I2S_IRQEN_REG = TANGNANO20K_I2S_IRQEN_REG | TANGNANO20K_I2S_IRQEN_TX;
    }
    interrupts();
    if (hasRoom)
      return;
    // Ring is full - spin until serviceIrq() (background IRQ) drains it.
  }
}

/* Pops one hardware-format sample off the software RX ring buffer if one
 * is available (non-blocking - see read()/available(), which only call
 * this once they already know the ring buffer isn't empty; getting into
 * that check-then-pop scheme without a race requires interrupts to stay
 * disabled between them, which read()/peek()/available() below do by
 * simply never yielding between the check and this call). Re-arms the
 * RX interrupt if popping freed room in a ring buffer that had been
 * full (serviceIrq() disables it in that case - see there for why). */
bool I2SClass::rxRingPop(uint32_t *sample)
{
  noInterrupts();
  bool hasData = (rxRingCount_ > 0);
  bool wasFull = (rxRingCount_ == ringCapacity_);
  if (hasData)
  {
    *sample = rxRing_[rxRingTail_];
    rxRingTail_ = (uint16_t)((rxRingTail_ + 1) % ringCapacity_);
    rxRingCount_--;
  }
  interrupts();

  if (hasData && wasFull)
  {
    noInterrupts();
    TANGNANO20K_I2S_IRQEN_REG = TANGNANO20K_I2S_IRQEN_REG | TANGNANO20K_I2S_IRQEN_RX;
    interrupts();
  }
  return hasData;
}

void I2SClass::serviceIrq(void)
{
  uint32_t status = TANGNANO20K_I2S_STATUS_REG;
  uint32_t txFree = TANGNANO20K_I2S_STATUS_TX_FREE(status);
  uint32_t rxCount = TANGNANO20K_I2S_STATUS_RX_COUNT(status);

  while (txFree > 0 && txRingCount_ > 0)
  {
    TANGNANO20K_I2S_DAT_REG = txRing_[txRingTail_];
    txRingTail_ = (uint16_t)((txRingTail_ + 1) % ringCapacity_);
    txRingCount_--;
    txFree--;
  }
  if (txRingCount_ == 0)
    TANGNANO20K_I2S_IRQEN_REG = TANGNANO20K_I2S_IRQEN_REG & ~TANGNANO20K_I2S_IRQEN_TX;

  while (rxCount > 0 && rxRingCount_ < ringCapacity_)
  {
    rxRing_[rxRingHead_] = TANGNANO20K_I2S_DAT_RX_REG;
    rxRingHead_ = (uint16_t)((rxRingHead_ + 1) % ringCapacity_);
    rxRingCount_++;
    rxCount--;
  }
  if (rxRingCount_ == ringCapacity_)
    TANGNANO20K_I2S_IRQEN_REG = TANGNANO20K_I2S_IRQEN_REG & ~TANGNANO20K_I2S_IRQEN_RX;
}

size_t I2SClass::write(uint8_t byte)
{
  size_t frameBytes = config_.channels * bytesPerSample_;
  txFrame_[txFrameLen_++] = byte;
  if (txFrameLen_ == frameBytes)
  {
    int16_t left = decodeSample(&txFrame_[0]);
    int16_t right = (config_.channels == 2) ? decodeSample(&txFrame_[bytesPerSample_]) : left;
    uint32_t sample = ((uint32_t)(uint16_t)left << 16) | (uint16_t)right;
    txRingPush(sample);
    txFrameLen_ = 0;
  }
  return 1;
}

bool I2SClass::refillRxFrame(void)
{
  uint32_t sample;
  if (!rxRingPop(&sample))
    return false;

  int16_t left = (int16_t)(sample >> 16);
  int16_t right = (int16_t)(sample & 0xFFFF);

  encodeSample(left, &rxFrame_[0]);
  if (config_.channels == 2)
  {
    encodeSample(right, &rxFrame_[bytesPerSample_]);
    rxFrameLen_ = (uint8_t)(bytesPerSample_ * 2);
  }
  else
  {
    rxFrameLen_ = bytesPerSample_;
  }
  rxFramePos_ = 0;
  return true;
}

int I2SClass::available(void)
{
  /* Genuinely non-blocking now that a real background-filled ring buffer
   * backs this: whatever's left in the cached frame plus whatever full
   * frames are already queued in rxRing_, with nothing left to guess at
   * (unlike the direct sample-level read(), which still blocks on
   * i2s.v's own hardware FIFO - see the class comment). */
  if (config_.mode == I2S_MODE_OUTPUT)
    return 0;
  return (int)(rxFrameLen_ - rxFramePos_) + (int)rxRingCount_ * (int)(config_.channels * bytesPerSample_);
}

int I2SClass::read(void)
{
  if (config_.mode == I2S_MODE_OUTPUT)
    return -1;
  if (rxFramePos_ >= rxFrameLen_)
  {
    if (!refillRxFrame())
      return -1; // Nothing captured yet - non-blocking.
  }
  return rxFrame_[rxFramePos_++];
}

int I2SClass::peek(void)
{
  if (config_.mode == I2S_MODE_OUTPUT)
    return -1;
  if (rxFramePos_ >= rxFrameLen_)
  {
    if (!refillRxFrame())
      return -1;
  }
  return rxFrame_[rxFramePos_];
}

void I2SClass::flush(void)
{
  // Waits for serviceIrq() to drain the software ring buffer into
  // hardware - not for i2s.v's own (much shallower) FIFO/shifter to
  // finish physically transmitting, matching this project's other
  // blocking peripherals, which only guarantee the software-visible
  // buffer is empty, not that the last bit has left the pin.
  while (txRingCount_ > 0)
  {
  }
}

I2SClass I2S;

#include "PWMAudio.h"
#include "tangnano20k_soc.h"
#include <stdlib.h>

/* Registered with the core's IRQ dispatcher (see wiring_irq.cpp) rather
 * than called directly - same reasoning as libraries/I2S. */
extern "C" void tangnano20k_pwm_audio_set_irq_callback(void (*callback)(void));

static void pwmAudioServiceIrqTrampoline(void)
{
  PWMAudio.serviceIrq();
}

/* Allocates a fresh ring_ of `samples` entries, freeing the old one only
 * once the new allocation has actually succeeded. */
bool PWMAudioClass::allocateRing(uint16_t samples)
{
  uint32_t *newRing = (uint32_t *)malloc((size_t)samples * sizeof(uint32_t));
  if (!newRing)
    return false;
  free((void *)ring_);
  ring_ = newRing;
  ringCapacity_ = samples;
  return true;
}

/* Rounded-down CLK_FREQ / rate - 1, clamped to [1, max]; a zero rate
 * falls back to `fallback`. */
static uint32_t clockDivider(unsigned long rate, unsigned long fallback, uint32_t max)
{
  if (rate == 0)
    rate = fallback;
  unsigned long cycles = TANGNANO20K_CLK_FREQ / rate;
  if (cycles < 2)
    cycles = 2;
  if (cycles - 1 > max)
    return max;
  return (uint32_t)(cycles - 1);
}

bool PWMAudioClass::begin(void)
{
  if (!(TANGNANO20K_PWM_AUDIO_CTRL_REG & TANGNANO20K_PWM_AUDIO_STATUS_PRESENT))
    return false; // Bitstream built without Tools > PWM Audio.

  // Quiesce first, so the ISR can't touch the ring while it's resized.
  TANGNANO20K_PWM_AUDIO_CTRL_REG = TANGNANO20K_PWM_AUDIO_CTRL_FLUSH;

  config_.channels = (config_.channels >= 2) ? 2 : 1;
  frameLen_ = 0;

  uint16_t ringSamples = config_.ringSamples;
  if (ringSamples == 0)
    ringSamples = 1; // A zero-deep ring can never hold a sample.
  if (ringSamples != ringCapacity_)
  {
    if (!allocateRing(ringSamples) && ring_ == nullptr)
      allocateRing(1); // First-ever begin() with an unreasonable size - fall back rather than leaving a null buffer.
  }
  config_.ringSamples = ringCapacity_;

  noInterrupts();
  ringHead_ = 0;
  ringTail_ = 0;
  ringCount_ = 0;
  interrupts();

  // Writing PERIOD also resets both outputs to 50% duty (silence).
  TANGNANO20K_PWM_AUDIO_PERIOD_REG = clockDivider(config_.pwmRate, 50000, 0xFFFF);
  TANGNANO20K_PWM_AUDIO_DIV_REG = clockDivider(config_.sampleRate, 44100, 0xFFFFFF);

  tangnano20k_pwm_audio_set_irq_callback(pwmAudioServiceIrqTrampoline);

  /* The refill interrupt is armed lazily by ringPush() only while there's
   * something queued (see serviceIrq()). */
  TANGNANO20K_PWM_AUDIO_CTRL_REG = TANGNANO20K_PWM_AUDIO_CTRL_ENABLE;
  started_ = true;
  return true;
}

void PWMAudioClass::end(void)
{
  if (!started_)
    return;
  TANGNANO20K_PWM_AUDIO_CTRL_REG = TANGNANO20K_PWM_AUDIO_CTRL_FLUSH;
  noInterrupts();
  ringHead_ = 0;
  ringTail_ = 0;
  ringCount_ = 0;
  interrupts();
  frameLen_ = 0;
  started_ = false;
}

/* Pushes one {left16,right16} sample onto the ring buffer, (re-)arming
 * the refill interrupt so serviceIrq() drains it into the hardware FIFO
 * in the background. Blocks (with interrupts enabled, so serviceIrq()
 * can make room) only once the ring buffer itself is full. */
void PWMAudioClass::ringPush(uint32_t sample)
{
  while (true)
  {
    noInterrupts();
    bool hasRoom = (ringCount_ < ringCapacity_);
    if (hasRoom)
    {
      ring_[ringHead_] = sample;
      ringHead_ = (uint16_t)((ringHead_ + 1) % ringCapacity_);
      ringCount_++;
      TANGNANO20K_PWM_AUDIO_CTRL_REG = TANGNANO20K_PWM_AUDIO_CTRL_ENABLE | TANGNANO20K_PWM_AUDIO_CTRL_IRQEN;
    }
    interrupts();
    if (hasRoom)
      return;
    // Ring is full - spin until serviceIrq() (background IRQ) drains it.
  }
}

void PWMAudioClass::serviceIrq(void)
{
  uint32_t fifoFree = TANGNANO20K_PWM_AUDIO_STATUS_FREE(TANGNANO20K_PWM_AUDIO_CTRL_REG);

  while (fifoFree > 0 && ringCount_ > 0)
  {
    TANGNANO20K_PWM_AUDIO_DAT_REG = ring_[ringTail_];
    ringTail_ = (uint16_t)((ringTail_ + 1) % ringCapacity_);
    ringCount_--;
    fifoFree--;
  }
  if (ringCount_ == 0)
    TANGNANO20K_PWM_AUDIO_CTRL_REG = TANGNANO20K_PWM_AUDIO_CTRL_ENABLE;
}

size_t PWMAudioClass::write(uint8_t byte)
{
  if (!started_)
    return 0;
  frame_[frameLen_++] = byte;
  if (frameLen_ == config_.channels * 2)
  {
    uint16_t left = (uint16_t)(frame_[0] | (frame_[1] << 8));
    uint16_t right = (config_.channels == 2) ? (uint16_t)(frame_[2] | (frame_[3] << 8)) : left;
    ringPush(((uint32_t)left << 16) | right);
    frameLen_ = 0;
  }
  return 1;
}

int PWMAudioClass::availableForWrite(void)
{
  if (!started_)
    return 0;
  int room = (int)(ringCapacity_ - ringCount_) * config_.channels * 2 - frameLen_;
  return room > 0 ? room : 0;
}

void PWMAudioClass::flush(void)
{
  // Waits for serviceIrq() to drain the software ring buffer into
  // hardware - same guarantee as I2SClass::flush().
  while (started_ && ringCount_ > 0)
  {
  }
}

PWMAudioClass PWMAudio;

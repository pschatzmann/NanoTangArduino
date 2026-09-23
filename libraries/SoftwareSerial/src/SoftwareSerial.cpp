#include "SoftwareSerial.h"
#include "tangnano20k_soc.h"

// Wrap-safe: compares as a signed difference, same idiom as
// wiring_irq.cpp's rearmHardwareTimer()/toneToggle() deadline handling.
static inline void waitUntilTick(uint32_t target)
{
  while ((int32_t)(TANGNANO20K_SYSTICK_REG - target) < 0)
  {
  }
}

static void softwareSerialIsrTrampoline(void *param)
{
  ((SoftwareSerial *)param)->handleStartBit();
}

SoftwareSerial::SoftwareSerial(uint8_t rxPin, uint8_t txPin, bool invert)
  : rxPin_(rxPin), txPin_(txPin), invert_(invert)
{
}

void SoftwareSerial::begin(unsigned long baud)
{
  bitTicks_ = TANGNANO20K_CLK_FREQ / baud;

  pinMode(txPin_, OUTPUT);
  digitalWrite(txPin_, invert_ ? LOW : HIGH); // idle level

  pinMode(rxPin_, INPUT);

  rxHead_ = 0;
  rxTail_ = 0;
  rxCount_ = 0;
  overflow_ = false;

  listen();
}

void SoftwareSerial::end(void)
{
  stopListening();
}

bool SoftwareSerial::listen(void)
{
  attachInterruptParam(digitalPinToInterrupt(rxPin_), softwareSerialIsrTrampoline,
                        invert_ ? RISING : FALLING, this);
  listening_ = true;
  return true;
}

void SoftwareSerial::stopListening(void)
{
  detachInterrupt(digitalPinToInterrupt(rxPin_));
  listening_ = false;
}

bool SoftwareSerial::overflow(void)
{
  bool result = overflow_;
  overflow_ = false;
  return result;
}

size_t SoftwareSerial::write(uint8_t byte)
{
  uint32_t irqState = tangnano20k_irq_save();

  uint32_t next = TANGNANO20K_SYSTICK_REG;

  digitalWrite(txPin_, invert_ ? HIGH : LOW); // start bit
  next += bitTicks_;
  waitUntilTick(next);

  uint8_t v = byte;
  for (uint8_t i = 0; i < 8; i++)
  {
    bool bitVal = (v & 0x01) != 0;
    digitalWrite(txPin_, (bitVal != invert_) ? HIGH : LOW);
    v >>= 1;
    next += bitTicks_;
    waitUntilTick(next);
  }

  digitalWrite(txPin_, invert_ ? LOW : HIGH); // stop bit
  next += bitTicks_;
  waitUntilTick(next);

  tangnano20k_irq_restore(irqState);
  return 1;
}

int SoftwareSerial::available(void)
{
  return rxCount_;
}

int SoftwareSerial::read(void)
{
  if (rxCount_ == 0)
    return -1;

  uint32_t irqState = tangnano20k_irq_save();
  uint8_t b = rxBuffer_[rxTail_];
  rxTail_ = (uint8_t)((rxTail_ + 1) % RX_BUFFER_SIZE);
  rxCount_--;
  tangnano20k_irq_restore(irqState);
  return b;
}

int SoftwareSerial::peek(void)
{
  if (rxCount_ == 0)
    return -1;
  return rxBuffer_[rxTail_];
}

void SoftwareSerial::handleStartBit(void)
{
  /* Already several cycles late by the time this runs (extirq -> IRQ
   * entry -> dispatch overhead), which is why the first sample point is
   * anchored to *now* plus 1.5 bit periods (centering in the middle of
   * data bit 0) rather than assuming the edge just happened this
   * instant - the same reasoning as I2S's receive-capture timing. */
  uint32_t next = TANGNANO20K_SYSTICK_REG + bitTicks_ + bitTicks_ / 2;
  uint8_t value = 0;

  for (uint8_t i = 0; i < 8; i++)
  {
    waitUntilTick(next);
    bool high = digitalRead(rxPin_) == HIGH;
    if (invert_)
      high = !high;
    if (high)
      value |= (uint8_t)(1U << i);
    next += bitTicks_;
  }
  // Stop bit not verified - matches this project's other best-effort peripherals.

  if (rxCount_ < RX_BUFFER_SIZE)
  {
    rxBuffer_[rxHead_] = value;
    rxHead_ = (uint8_t)((rxHead_ + 1) % RX_BUFFER_SIZE);
    rxCount_++;
  }
  else
  {
    overflow_ = true;
  }
}

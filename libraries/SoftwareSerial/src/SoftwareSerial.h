#pragma once

#include <Arduino.h>

/* Bit-banged software UART on any two GPIO pins - for a second/third
 * serial port beyond the hardware `Serial`, when you don't need it fast.
 * 8N1 framing only (8 data bits, no parity, one stop bit), no hardware
 * flow control. See docs/PERIPHERALS.md "Software Serial".
 *
 * Transmit is blocking: bit-banged against the free-running systick
 * counter (`TANGNANO20K_SYSTICK_REG`), with interrupts disabled for the
 * whole byte to keep bit timing jitter-free - the same "blocks, no
 * software buffering" tradeoff as every other blocking peripheral in
 * this project.
 *
 * Receive is interrupt-driven: begin() uses attachInterrupt() (see
 * gateware/src/extirq.v) to catch the start bit's edge; the ISR then
 * busy-waits to sample the remaining bits and buffers the completed byte
 * - so available()/read() are non-blocking. Because sampling happens
 * *inside* that interrupt handler, receiving one byte blocks every other
 * interrupt (timers, tone(), other attachInterrupt() callbacks, DMA
 * completion, I2S's own background buffering, another SoftwareSerial
 * instance's start-bit edge...) for roughly one byte period - keep baud
 * rates modest (9600 is a safe default) and avoid overlapping traffic
 * across multiple simultaneous SoftwareSerial instances if you can help
 * it. Unlike the classic Arduino SoftwareSerial, there's no shared
 * "listening" hardware to arbitrate between instances - each gets its
 * own attachInterrupt() slot (one per GPIO pin already), so multiple
 * instances can each buffer independently; listen()/stopListening() here
 * just pause/resume this instance's own interrupt, for API familiarity.
 */
class SoftwareSerial : public arduino::Stream
{
public:
  SoftwareSerial(uint8_t rxPin, uint8_t txPin, bool invert = false);

  void begin(unsigned long baud);
  void end(void);

  bool listen(void);
  void stopListening(void);
  bool isListening(void) const { return listening_; }

  // Returns whether the receive buffer has dropped a byte since the last
  // call (and clears the flag) - the receive buffer is small (see
  // RX_BUFFER_SIZE) and there's no flow control to slow a sender down.
  bool overflow(void);

  size_t write(uint8_t byte) override;
  using Print::write;
  int available(void) override;
  int read(void) override;
  int peek(void) override;
  void flush(void) override {}

  /* Called only from the ISR trampoline registered with
   * attachInterruptParam() by listen() - not meant to be called directly
   * by sketches. Public only because it has to be reachable from a plain
   * C-style callback. Samples the 8 data bits following the start-bit
   * edge that triggered this call and buffers the resulting byte. */
  void handleStartBit(void);

private:
  static const uint8_t RX_BUFFER_SIZE = 16;

  uint8_t rxPin_;
  uint8_t txPin_;
  bool invert_;
  bool listening_ = false;
  uint32_t bitTicks_ = 0;

  volatile uint8_t rxBuffer_[RX_BUFFER_SIZE];
  volatile uint8_t rxHead_ = 0; // next slot handleStartBit() will fill
  volatile uint8_t rxTail_ = 0; // next slot read()/peek() will drain
  volatile uint8_t rxCount_ = 0;
  volatile bool overflow_ = false;
};

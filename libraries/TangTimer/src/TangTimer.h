#pragma once

/* Calls a callback after a delay, either once or repeatedly, driven by
 * picorv32's built-in countdown timer via an interrupt (see
 * cores/tangnano20k/wiring_irq.cpp and docs/PERIPHERALS.md "Interrupts").
 * The callback runs in interrupt context, same caveats as attachInterrupt():
 * keep it short, and any shared state it touches from loop() should be
 * `volatile`.
 *
 * Up to 5 concurrent TangTimer instances are supported (a 6th slot is
 * reserved internally for tone()) - see TANGNANO20K_SW_TIMER_COUNT.
 */

#include <stdint.h>

class TangTimer {
public:
  TangTimer() : _handle(-1) {}
  ~TangTimer() { end(); }

  // Returns false if no free timer slot is available.
  bool begin(void (*callback)(void), uint32_t interval_us, bool repeat = false);

  void end();

  bool isRunning() const { return _handle >= 0; }

private:
  int _handle;
};

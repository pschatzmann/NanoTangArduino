#pragma once

#include <Arduino.h>

/* Standard Arduino Servo API on this core's hardware PWM (see
 * cores/tangnano20k/wiring_analog.cpp): each attached servo claims one of
 * the TANGNANO20K_PWM_CHANNELS channels shared with analogWrite() and
 * tone(), running a 50Hz frame with ~0.33us pulse resolution at 27MHz -
 * no interrupts involved, unlike the AVR library. As there, attach()
 * returns INVALID_SERVO when it fails - here when no PWM channel is free
 * or the pin can't do PWM (the LEDs and GPIO0-GPIO20 can); attached()
 * is the simplest check. */

#define MIN_PULSE_WIDTH     544  // shortest pulse sent to a servo, us
#define MAX_PULSE_WIDTH     2400 // longest pulse sent to a servo, us
#define DEFAULT_PULSE_WIDTH 1500 // pulse when attached, us
#define REFRESH_INTERVAL    20000 // frame length, us (50Hz)
#define MAX_SERVOS          TANGNANO20K_PWM_CHANNELS
#define INVALID_SERVO       255

class Servo
{
public:
  // Returns a servo index (0..MAX_SERVOS-1) on success, INVALID_SERVO on failure.
  uint8_t attach(int pin);
  uint8_t attach(int pin, int min, int max);
  void detach(void);

  // Values below MIN_PULSE_WIDTH are angles (0-180), others microseconds.
  void write(int value);
  void writeMicroseconds(int value);

  int read(void);             // current angle, 0-180
  int readMicroseconds(void); // current pulse width
  bool attached(void) const { return pin_ != INVALID_SERVO; }

private:
  void update(void);

  static uint8_t attachedCount;

  uint8_t pin_ = INVALID_SERVO;
  uint8_t index_ = INVALID_SERVO;
  uint16_t min_ = MIN_PULSE_WIDTH;
  uint16_t max_ = MAX_PULSE_WIDTH;
  uint16_t pulseUs_ = DEFAULT_PULSE_WIDTH;
};

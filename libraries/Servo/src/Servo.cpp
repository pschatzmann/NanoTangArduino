#include "Servo.h"

uint8_t Servo::attachedCount = 0;

uint8_t Servo::attach(int pin)
{
  return attach(pin, MIN_PULSE_WIDTH, MAX_PULSE_WIDTH);
}

uint8_t Servo::attach(int pin, int min, int max)
{
  if (attached())
    detach();
  if (pin < 0 || pin >= NUM_DIGITAL_PINS || min >= max)
    return INVALID_SERVO;

  min_ = (uint16_t)min;
  max_ = (uint16_t)max;
  pin_ = (uint8_t)pin;
  if (pulseUs_ < min_ || pulseUs_ > max_)
    pulseUs_ = DEFAULT_PULSE_WIDTH;
  update();
  if (!attached())
    return INVALID_SERVO;
  index_ = attachedCount++ % MAX_SERVOS;
  return index_;
}

void Servo::detach(void)
{
  if (!attached())
    return;
  digitalWrite(pin_, LOW); // Stops the PWM channel and frees it.
  pin_ = INVALID_SERVO;
  index_ = INVALID_SERVO;
  if (attachedCount > 0)
    attachedCount--;
}

void Servo::write(int value)
{
  if (value < MIN_PULSE_WIDTH) {
    if (value < 0)
      value = 0;
    if (value > 180)
      value = 180;
    value = map(value, 0, 180, min_, max_);
  }
  writeMicroseconds(value);
}

void Servo::writeMicroseconds(int value)
{
  if (value < min_)
    value = min_;
  if (value > max_)
    value = max_;
  pulseUs_ = (uint16_t)value;
  if (attached())
    update();
}

int Servo::read(void)
{
  return map(pulseUs_, min_, max_, 0, 180);
}

int Servo::readMicroseconds(void)
{
  return pulseUs_;
}

void Servo::update(void)
{
  uint16_t duty = (uint16_t)(((uint32_t)pulseUs_ * 65535UL + REFRESH_INTERVAL / 2) / REFRESH_INTERVAL);
  if (!tangnano20k_pwm_start(pin_, 1000000UL / REFRESH_INTERVAL, duty)) {
    // No free channel (or no PWM on this pin): leave it plain LOW.
    digitalWrite(pin_, LOW);
    pin_ = INVALID_SERVO;
  }
}

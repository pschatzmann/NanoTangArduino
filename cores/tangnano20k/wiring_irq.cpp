#include "Arduino.h"
#include "tangnano20k_timer.h"

/* Interrupt support: picorv32 is built with ENABLE_IRQ(1),
 * ENABLE_IRQ_QREGS(0) (see gateware/src/top.v). irq[0] is its own built-in
 * countdown timer, irq[1]/irq[2] are ebreak/bus-error (unused here),
 * irq[3] is gateware/src/extirq.v, a pin-change source for
 * attachInterrupt() covering the 21 GPIO pins plus KEY_S2 (BTN1), irq[4]
 * is dma_engine.v's async-copy completion, irq[5] is i2s.v's FIFO
 * refill/drain source (see the I2S callback below), irq[6] is
 * pwm_audio.v's FIFO refill source (Tools > PWM Audio only), and irq[7]
 * is can_ctrl.v's receive FIFO (Tools > CAN only). See
 * cores/tangnano20k/irq_vec.S for the entry trampoline and
 * docs/PERIPHERALS.md "Interrupts" for the full picture.
 *
 * Software timers (tone() and libraries/TangTimer) share one engine here,
 * scheduled by absolute deadline against the free-running systick counter
 * and driven by picorv32's one-shot countdown timer armed to the nearest
 * deadline - see tangnano20k_timer.h.
 */

extern "C" void tangnano20k_set_timer(uint32_t ticks);

void interrupts(void)
{
  tangnano20k_set_irq_mask(0x00000000UL);
}

void noInterrupts(void)
{
  tangnano20k_set_irq_mask(0xFFFFFFFFUL);
}

/* --- attachInterrupt() / detachInterrupt() ------------------------------ */

struct ExtIrqSlot {
  bool active;
  bool hasParam;
  PinStatus mode;
  union {
    voidFuncPtr plain;
    voidFuncPtrParam withParam;
  } callback;
  void *param;
};

static ExtIrqSlot extIrqSlots[TANGNANO20K_GPIO_COUNT + 1]; // +1 for BTN1

static inline int pinToExtIrqBit(pin_size_t pin)
{
  if (pin >= TANGNANO20K_PIN_GPIO_BASE && pin < TANGNANO20K_PIN_GPIO_BASE + TANGNANO20K_GPIO_COUNT)
    return (int)(pin - TANGNANO20K_PIN_GPIO_BASE);
  if (pin == TANGNANO20K_PIN_KEY2)
    return TANGNANO20K_EXTIRQ_KEY2_BIT;
  return -1;
}

void attachInterrupt(pin_size_t interruptNumber, voidFuncPtr callback, PinStatus mode)
{
  int bit = pinToExtIrqBit(interruptNumber);
  if (bit < 0)
    return;

  uint32_t irqState = tangnano20k_irq_save();
  extIrqSlots[bit].active = true;
  extIrqSlots[bit].hasParam = false;
  extIrqSlots[bit].mode = mode;
  extIrqSlots[bit].callback.plain = callback;
  TANGNANO20K_EXTIRQ_ENABLE_REG = TANGNANO20K_EXTIRQ_ENABLE_REG | (1UL << bit);
  (void)TANGNANO20K_EXTIRQ_STATUS_REG; // Discard any change latched before enabling.
  tangnano20k_irq_restore(irqState);
}

void attachInterruptParam(pin_size_t interruptNumber, voidFuncPtrParam callback, PinStatus mode, void *param)
{
  int bit = pinToExtIrqBit(interruptNumber);
  if (bit < 0)
    return;

  uint32_t irqState = tangnano20k_irq_save();
  extIrqSlots[bit].active = true;
  extIrqSlots[bit].hasParam = true;
  extIrqSlots[bit].mode = mode;
  extIrqSlots[bit].callback.withParam = callback;
  extIrqSlots[bit].param = param;
  TANGNANO20K_EXTIRQ_ENABLE_REG = TANGNANO20K_EXTIRQ_ENABLE_REG | (1UL << bit);
  (void)TANGNANO20K_EXTIRQ_STATUS_REG;
  tangnano20k_irq_restore(irqState);
}

void detachInterrupt(pin_size_t interruptNumber)
{
  int bit = pinToExtIrqBit(interruptNumber);
  if (bit < 0)
    return;

  uint32_t irqState = tangnano20k_irq_save();
  extIrqSlots[bit].active = false;
  TANGNANO20K_EXTIRQ_ENABLE_REG = TANGNANO20K_EXTIRQ_ENABLE_REG & ~(1UL << bit);
  tangnano20k_irq_restore(irqState);
}

/* --- Software timer engine (tone() + libraries/TangTimer) --------------- */

struct SwTimer {
  bool active;
  bool inUse; // Slot allocated (TangTimer), distinct from `active` (running).
  bool repeat;
  void (*callback)(void);
  uint32_t interval_ticks;
  uint32_t deadline_ticks; // Absolute TANGNANO20K_SYSTICK_REG value.
};

static SwTimer swTimers[TANGNANO20K_SW_TIMER_COUNT];

// Re-arms picorv32's one-shot timer for the nearest active deadline.
// Must be called with interrupts already disabled.
static void rearmHardwareTimer(void)
{
  bool any = false;
  uint32_t now = TANGNANO20K_SYSTICK_REG;
  uint32_t bestDelta = 0xFFFFFFFFUL;

  for (int i = 0; i < TANGNANO20K_SW_TIMER_COUNT; i++) {
    if (!swTimers[i].active)
      continue;
    uint32_t delta = swTimers[i].deadline_ticks - now; // wraps correctly if already due
    if ((int32_t)delta < 0)
      delta = 1; // Already due - fire as soon as possible.
    if (!any || delta < bestDelta) {
      bestDelta = delta;
      any = true;
    }
  }

  tangnano20k_set_timer(any ? bestDelta : 0);
}

int tangnano20k_sw_timer_alloc(void)
{
  uint32_t irqState = tangnano20k_irq_save();
  int handle = -1;
  for (int i = TANGNANO20K_SW_TIMER_TONE + 1; i < TANGNANO20K_SW_TIMER_COUNT; i++) {
    if (!swTimers[i].inUse) {
      swTimers[i].inUse = true;
      handle = i;
      break;
    }
  }
  tangnano20k_irq_restore(irqState);
  return handle;
}

void tangnano20k_sw_timer_release(int handle)
{
  if (handle < 0 || handle >= TANGNANO20K_SW_TIMER_COUNT)
    return;
  uint32_t irqState = tangnano20k_irq_save();
  swTimers[handle].active = false;
  swTimers[handle].inUse = false;
  rearmHardwareTimer();
  tangnano20k_irq_restore(irqState);
}

bool tangnano20k_sw_timer_start(int handle, void (*callback)(void), uint32_t interval_ticks, bool repeat)
{
  if (handle < 0 || handle >= TANGNANO20K_SW_TIMER_COUNT || interval_ticks == 0)
    return false;

  uint32_t irqState = tangnano20k_irq_save();
  swTimers[handle].callback = callback;
  swTimers[handle].interval_ticks = interval_ticks;
  swTimers[handle].deadline_ticks = TANGNANO20K_SYSTICK_REG + interval_ticks;
  swTimers[handle].repeat = repeat;
  swTimers[handle].active = true;
  rearmHardwareTimer();
  tangnano20k_irq_restore(irqState);
  return true;
}

void tangnano20k_sw_timer_stop(int handle)
{
  if (handle < 0 || handle >= TANGNANO20K_SW_TIMER_COUNT)
    return;
  uint32_t irqState = tangnano20k_irq_save();
  swTimers[handle].active = false;
  rearmHardwareTimer();
  tangnano20k_irq_restore(irqState);
}

/* --- tone() / noTone() --------------------------------------------------- */

/* tone() plays from a PWM channel (tangnano20k_pwm_start(), see
 * wiring_analog.cpp): a hardware 50% square wave with no CPU cost, the
 * software timer only ending it after `duration`. Only when all PWM
 * channels are busy does it fall back to toggling the pin from the
 * timer interrupt, twice per cycle. As on AVR, one tone plays at a time:
 * a new tone() replaces the current one. */

#define NO_TONE_PIN 0xFF

static pin_size_t toneActivePin = NO_TONE_PIN;
static uint32_t toneRemainingHalfPeriods; // Fallback only; 0 == until noTone().

static void toneEnd(void)
{
  if (toneActivePin != NO_TONE_PIN)
    digitalWrite(toneActivePin, LOW); // Also releases the PWM channel.
  toneActivePin = NO_TONE_PIN;
}

static void toneToggle(void)
{
  static PinStatus toneLevel = LOW;
  toneLevel = (toneLevel == LOW) ? HIGH : LOW;
  digitalWrite(toneActivePin, toneLevel);

  if (toneRemainingHalfPeriods > 0) {
    if (--toneRemainingHalfPeriods == 0) {
      tangnano20k_sw_timer_stop(TANGNANO20K_SW_TIMER_TONE);
      toneEnd();
    }
  }
}

void tone(uint8_t pin, unsigned int frequency, unsigned long duration)
{
  if (frequency == 0) {
    noTone(pin);
    return;
  }

  tangnano20k_sw_timer_stop(TANGNANO20K_SW_TIMER_TONE);
  if (toneActivePin != NO_TONE_PIN && toneActivePin != pin)
    toneEnd();
  toneActivePin = pin;

  if (tangnano20k_pwm_start(pin, frequency, 32768)) { // 50% duty
    if (duration > 0) {
      uint64_t ticks = (uint64_t)duration * (TANGNANO20K_CLK_FREQ / 1000UL);
      if (ticks > 0x7FFFFFFFULL)
        ticks = 0x7FFFFFFFULL; // The timer engine's limit (~79s at 27MHz).
      tangnano20k_sw_timer_start(TANGNANO20K_SW_TIMER_TONE, toneEnd, (uint32_t)ticks, false);
    }
    return;
  }

  // Fallback: toggle the pin from the timer interrupt.
  pinMode(pin, OUTPUT);

  // Toggling twice per cycle -> half-period interval.
  uint32_t halfPeriodTicks = TANGNANO20K_CLK_FREQ / (2UL * frequency);
  if (halfPeriodTicks == 0)
    halfPeriodTicks = 1;

  toneRemainingHalfPeriods = (duration == 0) ? 0 : (uint32_t)((duration * (unsigned long)frequency * 2UL) / 1000UL);

  tangnano20k_sw_timer_start(TANGNANO20K_SW_TIMER_TONE, toneToggle, halfPeriodTicks, true);
}

void noTone(uint8_t pin)
{
  tangnano20k_sw_timer_stop(TANGNANO20K_SW_TIMER_TONE);
  digitalWrite(pin, LOW);
  if (pin == toneActivePin)
    toneActivePin = NO_TONE_PIN;
}

/* --- Async DMA completion callback --------------------------------------- */

static void (*dmaAsyncDoneCallback)(void) = nullptr;

extern "C" void tangnano20k_dma_set_async_callback(void (*callback)(void))
{
  dmaAsyncDoneCallback = callback;
}

/* --- I2S FIFO refill/drain callback --------------------------------------- */

/* Same registration pattern as the DMA callback above, for the same
 * reason: I2S is an opt-in library (libraries/I2S), not part of the
 * always-linked core, so this file can't call directly into it - a
 * sketch that never #includes I2S.h must still link cleanly. */
static void (*i2sIrqCallback)(void) = nullptr;

extern "C" void tangnano20k_i2s_set_irq_callback(void (*callback)(void))
{
  i2sIrqCallback = callback;
}

/* --- PWM audio FIFO refill callback -------------------------------------- */

/* Same pattern as the I2S callback above, for libraries/PWMAudio. */
static void (*pwmAudioIrqCallback)(void) = nullptr;

extern "C" void tangnano20k_pwm_audio_set_irq_callback(void (*callback)(void))
{
  pwmAudioIrqCallback = callback;
}

/* --- CAN receive callback ------------------------------------------------ */

/* Same pattern again, for libraries/CAN (irq[7], Tools > CAN only). */
static void (*canIrqCallback)(void) = nullptr;

extern "C" void tangnano20k_can_set_irq_callback(void (*callback)(void))
{
  canIrqCallback = callback;
}

/* --- IRQ dispatcher, called from irq_vec.S ------------------------------- */

extern "C" void tangnano20k_irq_dispatch(uint32_t *regs, uint32_t irqs)
{
  (void)regs;

  if (irqs & (1UL << 0)) {
    uint32_t now = TANGNANO20K_SYSTICK_REG;
    for (int i = 0; i < TANGNANO20K_SW_TIMER_COUNT; i++) {
      if (!swTimers[i].active)
        continue;
      if ((int32_t)(now - swTimers[i].deadline_ticks) < 0)
        continue; // Not due yet.

      void (*cb)(void) = swTimers[i].callback;
      if (swTimers[i].repeat)
        swTimers[i].deadline_ticks += swTimers[i].interval_ticks;
      else
        swTimers[i].active = false;

      if (cb)
        cb();
    }
    rearmHardwareTimer();
  }

  if (irqs & (1UL << 3)) {
    uint32_t changed = TANGNANO20K_EXTIRQ_STATUS_REG; // Read clears pending flags.
    uint32_t level = TANGNANO20K_EXTIRQ_LEVEL_REG;

    for (int bit = 0; bit <= TANGNANO20K_EXTIRQ_KEY2_BIT; bit++) {
      if (!(changed & (1UL << bit)))
        continue;
      ExtIrqSlot &slot = extIrqSlots[bit];
      if (!slot.active)
        continue;

      bool high = (level & (1UL << bit)) != 0;
      bool fire = (slot.mode == CHANGE) ||
                  (slot.mode == RISING && high) ||
                  (slot.mode == FALLING && !high);
      if (!fire)
        continue;

      if (slot.hasParam)
        slot.callback.withParam(slot.param);
      else
        slot.callback.plain();
    }
  }

  if (irqs & (1UL << 4)) {
    uint32_t status = TANGNANO20K_DMA_START_REG; // Read clears ASYNC_DONE.
    if ((status & TANGNANO20K_DMA_STATUS_ASYNC_DONE) && dmaAsyncDoneCallback)
      dmaAsyncDoneCallback();
  }

  if (irqs & (1UL << 5)) {
    if (i2sIrqCallback)
      i2sIrqCallback();
  }

  if (irqs & (1UL << 6)) {
    if (pwmAudioIrqCallback)
      pwmAudioIrqCallback();
  }

  if (irqs & (1UL << 7)) {
    if (canIrqCallback)
      canIrqCallback();
  }
}

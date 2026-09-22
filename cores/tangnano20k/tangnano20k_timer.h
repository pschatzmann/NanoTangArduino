#pragma once

/* Internal software-timer engine shared by tone()/noTone() (wiring_irq.cpp)
 * and the bundled libraries/TangTimer library. Not part of the Arduino API
 * - sketches use tone() or TangTimer, not this directly.
 *
 * Timers are scheduled by absolute deadline against TANGNANO20K_SYSTICK_REG
 * (a free-running counter never touched by picorv32's separate one-shot
 * IRQ countdown register), so there's no need to ever "peek" the
 * decrementing hardware timer - only the nearest deadline is armed into it
 * at a time, and it is safe against drift because a reload always adds the
 * interval to the *missed* deadline, not to "now".
 */

#include <stdint.h>

extern "C" {

/* Allocates a free software timer slot for libraries/TangTimer, excluding
 * the one reserved for tone(). Returns -1 if all slots are in use. */
int tangnano20k_sw_timer_alloc(void);

/* Releases a slot previously returned by tangnano20k_sw_timer_alloc(). */
void tangnano20k_sw_timer_release(int handle);

/* Starts (or restarts, if already active) software timer slot `handle`
 * (0..TANGNANO20K_SW_TIMER_COUNT-1) to call `callback` after
 * `interval_ticks` systick ticks, repeating every `interval_ticks` ticks if
 * `repeat` is true. Returns false if `handle` is out of range. */
bool tangnano20k_sw_timer_start(int handle, void (*callback)(void), uint32_t interval_ticks, bool repeat);

/* Stops software timer slot `handle`, if active. */
void tangnano20k_sw_timer_stop(int handle);

}

#define TANGNANO20K_SW_TIMER_COUNT 6

/* Fixed slot reserved for tone()/noTone(); the rest are available to
 * libraries/TangTimer. */
#define TANGNANO20K_SW_TIMER_TONE 0

#include "TangTimer.h"
#include "tangnano20k_soc.h"
#include "tangnano20k_timer.h"

bool TangTimer::begin(void (*callback)(void), uint32_t interval_us, bool repeat)
{
  if (_handle < 0) {
    _handle = tangnano20k_sw_timer_alloc();
    if (_handle < 0)
      return false; // All slots in use.
  }

  uint32_t ticks = (uint32_t)(((uint64_t)interval_us * TANGNANO20K_CLK_FREQ) / 1000000ULL);
  if (ticks == 0)
    ticks = 1;

  if (!tangnano20k_sw_timer_start(_handle, callback, ticks, repeat)) {
    tangnano20k_sw_timer_release(_handle);
    _handle = -1;
    return false;
  }
  return true;
}

void TangTimer::end()
{
  if (_handle < 0)
    return;
  tangnano20k_sw_timer_release(_handle);
  _handle = -1;
}

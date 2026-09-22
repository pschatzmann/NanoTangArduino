/* Minimal C++ runtime support for -nostdlib. Nothing on this bare-metal
 * core actually calls `delete` or destroys a static object, but any class
 * with a virtual destructor (e.g. arduino::HardwareSPI) still emits a
 * deleting destructor that references operator delete, and a global
 * object with a non-trivial destructor registers itself with
 * __cxa_atexit - both need *something* to link against even though they
 * are never exercised at runtime. */

#include <stddef.h>

extern "C" void *__dso_handle;
void *__dso_handle = nullptr;

extern "C" int __cxa_atexit(void (*)(void *), void *, void *)
{
  return 0;
}

void operator delete(void *)
{
}

void operator delete(void *, unsigned int)
{
}

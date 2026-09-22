/* Minimal freestanding libc replacements. The core is built with
 * -nostdlib (there is no libc for this bare SoC), but the vendored
 * ArduinoCore-API sources call a handful of ordinary string functions. */

#include <stddef.h>

size_t strlen(const char *s)
{
  const char *p = s;
  while (*p)
    p++;
  return (size_t)(p - s);
}

void *memcpy(void *dst, const void *src, size_t n)
{
  unsigned char *d = (unsigned char *)dst;
  const unsigned char *s = (const unsigned char *)src;
  while (n--)
    *d++ = *s++;
  return dst;
}

void *memset(void *dst, int c, size_t n)
{
  unsigned char *d = (unsigned char *)dst;
  while (n--)
    *d++ = (unsigned char)c;
  return dst;
}

void *memmove(void *dst, const void *src, size_t n)
{
  unsigned char *d = (unsigned char *)dst;
  const unsigned char *s = (const unsigned char *)src;
  if (d < s) {
    while (n--)
      *d++ = *s++;
  } else {
    d += n;
    s += n;
    while (n--)
      *--d = *--s;
  }
  return dst;
}

int strcmp(const char *a, const char *b)
{
  while (*a && (*a == *b)) {
    a++;
    b++;
  }
  return (unsigned char)*a - (unsigned char)*b;
}

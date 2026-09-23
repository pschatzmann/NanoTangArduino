/* Minimal freestanding libc replacements. The core is built with
 * -nostdlib (there is no libc for this bare SoC), but the vendored
 * ArduinoCore-API sources (String.cpp in particular) call a number of
 * ordinary libc string/ctype/stdlib functions. */

#include <stddef.h>
#include <stdint.h>

/* Not <ctype.h>: this toolchain's version defines isspace/tolower/toupper
 * as macros in C mode, which would conflict with defining them as real
 * functions below (String.cpp, compiled as C++, sees them as plain extern
 * function declarations instead and links against these). */
int isspace(int c);
int tolower(int c);
int toupper(int c);

size_t strlen(const char *s)
{
  const char *p = s;
  while (*p)
    p++;
  return (size_t)(p - s);
}

/* memcpy()/memset()/memmove() move whole 32-bit words when source and
 * destination share the same alignment, ~4x fewer bus transactions than
 * byte loops (it matters most on the SDRAM heap). NO_LIBCALL stops GCC
 * from recognizing these loops as memcpy()/memset() and turning them
 * back into calls to themselves. */
#define NO_LIBCALL __attribute__((optimize("no-tree-loop-distribute-patterns")))
#define WORD_ALIGNED(p) (((uintptr_t)(p) & 3U) == 0)

NO_LIBCALL void *memcpy(void *dst, const void *src, size_t n)
{
  unsigned char *d = (unsigned char *)dst;
  const unsigned char *s = (const unsigned char *)src;

  if ((((uintptr_t)d ^ (uintptr_t)s) & 3U) == 0) {
    while (n && !WORD_ALIGNED(d)) {
      *d++ = *s++;
      n--;
    }
    uint32_t *dw = (uint32_t *)d;
    const uint32_t *sw = (const uint32_t *)s;
    for (; n >= 16; n -= 16) {
      dw[0] = sw[0];
      dw[1] = sw[1];
      dw[2] = sw[2];
      dw[3] = sw[3];
      dw += 4;
      sw += 4;
    }
    for (; n >= 4; n -= 4)
      *dw++ = *sw++;
    d = (unsigned char *)dw;
    s = (const unsigned char *)sw;
  }

  while (n--)
    *d++ = *s++;
  return dst;
}

NO_LIBCALL void *memset(void *dst, int c, size_t n)
{
  unsigned char *d = (unsigned char *)dst;
  unsigned char b = (unsigned char)c;

  while (n && !WORD_ALIGNED(d)) {
    *d++ = b;
    n--;
  }
  uint32_t pattern = b * 0x01010101UL;
  uint32_t *dw = (uint32_t *)d;
  for (; n >= 16; n -= 16) {
    dw[0] = pattern;
    dw[1] = pattern;
    dw[2] = pattern;
    dw[3] = pattern;
    dw += 4;
  }
  for (; n >= 4; n -= 4)
    *dw++ = pattern;
  d = (unsigned char *)dw;

  while (n--)
    *d++ = b;
  return dst;
}

NO_LIBCALL void *memmove(void *dst, const void *src, size_t n)
{
  unsigned char *d = (unsigned char *)dst;
  const unsigned char *s = (const unsigned char *)src;

  // Copying forwards is safe unless dst starts inside [src, src+n).
  if (d <= s || d >= s + n)
    return memcpy(dst, src, n);

  d += n;
  s += n;
  if ((((uintptr_t)d ^ (uintptr_t)s) & 3U) == 0) {
    while (n && !WORD_ALIGNED(d)) {
      *--d = *--s;
      n--;
    }
    uint32_t *dw = (uint32_t *)d;
    const uint32_t *sw = (const uint32_t *)s;
    for (; n >= 4; n -= 4)
      *--dw = *--sw;
    d = (unsigned char *)dw;
    s = (const unsigned char *)sw;
  }
  while (n--)
    *--d = *--s;
  return dst;
}

int memcmp(const void *a, const void *b, size_t n)
{
  const unsigned char *pa = (const unsigned char *)a;
  const unsigned char *pb = (const unsigned char *)b;
  while (n--) {
    if (*pa != *pb)
      return (int)*pa - (int)*pb;
    pa++;
    pb++;
  }
  return 0;
}

int strcmp(const char *a, const char *b)
{
  while (*a && (*a == *b)) {
    a++;
    b++;
  }
  return (unsigned char)*a - (unsigned char)*b;
}

int strncmp(const char *a, const char *b, size_t n)
{
  while (n && *a && (*a == *b)) {
    a++;
    b++;
    n--;
  }
  if (n == 0)
    return 0;
  return (unsigned char)*a - (unsigned char)*b;
}

char *strcpy(char *dst, const char *src)
{
  char *d = dst;
  while ((*d++ = *src++)) {
  }
  return dst;
}

char *strncpy(char *dst, const char *src, size_t n)
{
  size_t i;
  for (i = 0; i < n && src[i]; i++)
    dst[i] = src[i];
  for (; i < n; i++)
    dst[i] = '\0';
  return dst;
}

char *strchr(const char *s, int c)
{
  while (*s) {
    if (*s == (char)c)
      return (char *)s;
    s++;
  }
  return (c == 0) ? (char *)s : NULL;
}

char *strrchr(const char *s, int c)
{
  const char *last = (c == 0) ? s : NULL;
  while (*s) {
    if (*s == (char)c)
      last = s;
    s++;
  }
  return (char *)last;
}

char *strstr(const char *haystack, const char *needle)
{
  if (!*needle)
    return (char *)haystack;
  for (; *haystack; haystack++) {
    const char *h = haystack;
    const char *n = needle;
    while (*h && *n && *h == *n) {
      h++;
      n++;
    }
    if (!*n)
      return (char *)haystack;
  }
  return NULL;
}

int isspace(int c)
{
  return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r';
}

int tolower(int c)
{
  return (c >= 'A' && c <= 'Z') ? c + ('a' - 'A') : c;
}

int toupper(int c)
{
  return (c >= 'a' && c <= 'z') ? c - ('a' - 'A') : c;
}

double atof(const char *s)
{
  while (isspace((unsigned char)*s))
    s++;

  double sign = 1.0;
  if (*s == '-') {
    sign = -1.0;
    s++;
  } else if (*s == '+') {
    s++;
  }

  double result = 0.0;
  while (*s >= '0' && *s <= '9')
    result = result * 10.0 + (double)(*s++ - '0');

  if (*s == '.') {
    s++;
    double frac = 0.1;
    while (*s >= '0' && *s <= '9') {
      result += (double)(*s++ - '0') * frac;
      frac *= 0.1;
    }
  }

  return sign * result;
}

long atol(const char *s)
{
  while (isspace((unsigned char)*s))
    s++;

  long sign = 1;
  if (*s == '-') {
    sign = -1;
    s++;
  } else if (*s == '+') {
    s++;
  }

  long result = 0;
  while (*s >= '0' && *s <= '9')
    result = result * 10 + (*s++ - '0');

  return sign * result;
}

int atoi(const char *s)
{
  return (int)atol(s);
}

/* strtol()/strtoul(): base 0 (auto-detect 0x/0 prefixes) or 2-36. No
 * errno on this libc-less core - out-of-range values saturate to
 * LONG_MIN/LONG_MAX/ULONG_MAX as the standard specifies. */
static unsigned long parse_unsigned(const char *s, char **endptr, int base, int *negative, int *overflow)
{
  const char *start = s;
  while (isspace((unsigned char)*s))
    s++;

  *negative = 0;
  if (*s == '-') {
    *negative = 1;
    s++;
  } else if (*s == '+') {
    s++;
  }

  if ((base == 0 || base == 16) && s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
    s += 2;
    base = 16;
  } else if (base == 0) {
    base = (s[0] == '0') ? 8 : 10;
  }

  unsigned long result = 0;
  int any = 0;
  *overflow = 0;
  for (;; s++) {
    int digit;
    if (*s >= '0' && *s <= '9')
      digit = *s - '0';
    else if (*s >= 'a' && *s <= 'z')
      digit = *s - 'a' + 10;
    else if (*s >= 'A' && *s <= 'Z')
      digit = *s - 'A' + 10;
    else
      break;
    if (digit >= base)
      break;
    any = 1;
    if (result > (~0UL - (unsigned long)digit) / (unsigned long)base)
      *overflow = 1;
    else
      result = result * (unsigned long)base + (unsigned long)digit;
  }

  if (endptr)
    *endptr = (char *)(any ? s : start);
  return result;
}

long strtol(const char *s, char **endptr, int base)
{
  int negative, overflow;
  unsigned long mag = parse_unsigned(s, endptr, base, &negative, &overflow);
  if (negative) {
    if (overflow || mag > 0x80000000UL)
      return (long)0x80000000UL;
    return (long)(0UL - mag);
  }
  if (overflow || mag > 0x7FFFFFFFUL)
    return 0x7FFFFFFFL;
  return (long)mag;
}

unsigned long strtoul(const char *s, char **endptr, int base)
{
  int negative, overflow;
  unsigned long mag = parse_unsigned(s, endptr, base, &negative, &overflow);
  if (overflow)
    return ~0UL;
  return negative ? 0UL - mag : mag;
}

int abs(int v)
{
  return v < 0 ? -v : v;
}

long labs(long v)
{
  return v < 0 ? -v : v;
}

char *strcat(char *dst, const char *src)
{
  strcpy(dst + strlen(dst), src);
  return dst;
}

char *strncat(char *dst, const char *src, size_t n)
{
  char *d = dst + strlen(dst);
  while (n-- && *src)
    *d++ = *src++;
  *d = '\0';
  return dst;
}

void *memchr(const void *s, int c, size_t n)
{
  const unsigned char *p = (const unsigned char *)s;
  while (n--) {
    if (*p == (unsigned char)c)
      return (void *)p;
    p++;
  }
  return NULL;
}

int strcasecmp(const char *a, const char *b)
{
  while (*a && tolower((unsigned char)*a) == tolower((unsigned char)*b)) {
    a++;
    b++;
  }
  return tolower((unsigned char)*a) - tolower((unsigned char)*b);
}

int strncasecmp(const char *a, const char *b, size_t n)
{
  while (n && *a && tolower((unsigned char)*a) == tolower((unsigned char)*b)) {
    a++;
    b++;
    n--;
  }
  if (n == 0)
    return 0;
  return tolower((unsigned char)*a) - tolower((unsigned char)*b);
}

static char *tangnano20k_utoa(unsigned long value, char *str, int base)
{
  static const char digits[] = "0123456789abcdefghijklmnopqrstuvwxyz";
  char *p = str;

  do {
    unsigned long rem = value % (unsigned long)base;
    value /= (unsigned long)base;
    *p++ = digits[rem];
  } while (value);

  *p = '\0';

  for (char *lo = str, *hi = p - 1; lo < hi; lo++, hi--) {
    char tmp = *lo;
    *lo = *hi;
    *hi = tmp;
  }

  return str;
}

char *utoa(unsigned int value, char *str, int base)
{
  return tangnano20k_utoa(value, str, base);
}

char *ultoa(unsigned long value, char *str, int base)
{
  return tangnano20k_utoa(value, str, base);
}

char *itoa(int value, char *str, int base)
{
  if (base == 10 && value < 0) {
    str[0] = '-';
    tangnano20k_utoa((unsigned long)(-(long)value), str + 1, base);
    return str;
  }
  return tangnano20k_utoa((unsigned long)(unsigned int)value, str, base);
}

char *ltoa(long value, char *str, int base)
{
  if (base == 10 && value < 0) {
    str[0] = '-';
    tangnano20k_utoa((unsigned long)(-value), str + 1, base);
    return str;
  }
  return tangnano20k_utoa((unsigned long)value, str, base);
}

/* avr-libc-style: formats val with `prec` digits after the decimal point
 * into sout, right-justified to `width` characters if positive (negative
 * width/left-justify, as real avr-libc supports, isn't implemented - not
 * needed by ArduinoCore-API's String(float) constructor, the only caller
 * here). */
char *dtostrf(double val, signed char width, unsigned char prec, char *sout)
{
  char *dst = sout;

  if (val < 0) {
    *dst++ = '-';
    val = -val;
  }

  double rounding = 0.5;
  for (unsigned char i = 0; i < prec; i++)
    rounding /= 10.0;
  val += rounding;

  unsigned long intPart = (unsigned long)val;
  double fracPart = val - (double)intPart;

  char intBuf[12];
  int ii = 0;
  if (intPart == 0) {
    intBuf[ii++] = '0';
  } else {
    while (intPart > 0) {
      intBuf[ii++] = (char)('0' + (intPart % 10));
      intPart /= 10;
    }
  }
  while (ii > 0)
    *dst++ = intBuf[--ii];

  if (prec > 0) {
    *dst++ = '.';
    for (unsigned char i = 0; i < prec; i++) {
      fracPart *= 10.0;
      int digit = (int)fracPart;
      *dst++ = (char)('0' + digit);
      fracPart -= digit;
    }
  }
  *dst = '\0';

  int len = (int)(dst - sout);
  if (width > 0 && len < width) {
    int padCount = width - len;
    for (int i = len; i >= 0; i--)
      sout[i + padCount] = sout[i];
    for (int i = 0; i < padCount; i++)
      sout[i] = ' ';
  }

  return sout;
}

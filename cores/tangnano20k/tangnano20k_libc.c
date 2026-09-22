/* Minimal freestanding libc replacements. The core is built with
 * -nostdlib (there is no libc for this bare SoC), but the vendored
 * ArduinoCore-API sources (String.cpp in particular) call a number of
 * ordinary libc string/ctype/stdlib functions. */

#include <stddef.h>

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

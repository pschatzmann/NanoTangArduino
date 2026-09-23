/* Compact printf family for this -nostdlib core: vsnprintf()/snprintf()/
 * vsprintf()/sprintf() into a buffer, and printf()/vprintf()/puts() to
 * Serial (through putchar(), defined in HardwareSerial.cpp).
 *
 * Supported: flags `-` `+` ` ` `#` `0`, width and precision (including
 * `*`), length modifiers hh/h/l/ll/z/j/t, conversions %d %i %u %o %x %X
 * %c %s %p %% and floating point %f %F %e %E %g %G. Floating point is
 * software-emulated on this core (no FPU), so %f etc. are comparatively
 * slow; they're only linked into sketches that use this family at all.
 * Not supported: %n, %a, wide characters. Differences from glibc: exact
 * halfway values round up rather than to even (%.0f of 0.5 is "1"), and
 * %f of magnitudes >= 2^64 prints in %e notation. */

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

int putchar(int c);

typedef struct {
  char *buf;
  size_t size;
  size_t len;       // characters produced so far, including any not stored
  int toPutchar;    // 1: send to putchar() instead of buf
} printf_sink_t;

static void emit(printf_sink_t *s, char c)
{
  if (s->toPutchar)
    putchar((unsigned char)c);
  else if (s->len + 1 < s->size)
    s->buf[s->len] = c;
  s->len++;
}

static void emitRepeat(printf_sink_t *s, char c, int count)
{
  while (count-- > 0)
    emit(s, c);
}

#define FLAG_LEFT  (1U << 0)
#define FLAG_PLUS  (1U << 1)
#define FLAG_SPACE (1U << 2)
#define FLAG_ALT   (1U << 3)
#define FLAG_ZERO  (1U << 4)
#define FLAG_UPPER (1U << 5)

/* Emits `body` (bodyLen chars) with an optional sign/prefix, padded to
 * `width` - the one place padding rules live, for integers and floats. */
static void emitPadded(printf_sink_t *s, const char *prefix, const char *body, int bodyLen,
                       int zeroes, int width, unsigned flags)
{
  int prefixLen = 0;
  while (prefix[prefixLen])
    prefixLen++;

  int total = prefixLen + zeroes + bodyLen;
  int pad = width > total ? width - total : 0;

  if ((flags & FLAG_ZERO) && !(flags & FLAG_LEFT)) {
    zeroes += pad;
    pad = 0;
  }
  if (!(flags & FLAG_LEFT))
    emitRepeat(s, ' ', pad);
  for (int i = 0; i < prefixLen; i++)
    emit(s, prefix[i]);
  emitRepeat(s, '0', zeroes);
  for (int i = 0; i < bodyLen; i++)
    emit(s, body[i]);
  if (flags & FLAG_LEFT)
    emitRepeat(s, ' ', pad);
}

static void formatInteger(printf_sink_t *s, uint64_t value, int negative, unsigned base,
                          int width, int precision, unsigned flags)
{
  const char *digits = (flags & FLAG_UPPER) ? "0123456789ABCDEF" : "0123456789abcdef";
  char tmp[24];
  int n = 0;

  // Precision 0 with value 0 prints no digits at all (C standard).
  if (!(value == 0 && precision == 0)) {
    do {
      tmp[n++] = digits[value % base];
      value /= base;
    } while (value);
  }

  char body[24];
  for (int i = 0; i < n; i++)
    body[i] = tmp[n - 1 - i];

  int zeroes = (precision > n) ? precision - n : 0;
  if (precision >= 0)
    flags &= ~FLAG_ZERO; // An explicit precision overrides the 0 flag.

  const char *prefix = "";
  if (base == 10) {
    if (negative)
      prefix = "-";
    else if (flags & FLAG_PLUS)
      prefix = "+";
    else if (flags & FLAG_SPACE)
      prefix = " ";
  } else if ((flags & FLAG_ALT) && n > 0) {
    if (base == 16)
      prefix = (flags & FLAG_UPPER) ? "0X" : "0x";
    else if (base == 8 && zeroes == 0 && body[0] != '0')
      prefix = "0";
  }

  emitPadded(s, prefix, body, n, zeroes, width, flags);
}

/* Appends the decimal digits of `value` (< 2^64) to out; returns count. */
static int appendUnsigned(char *out, uint64_t value)
{
  char tmp[21];
  int n = 0;
  do {
    tmp[n++] = (char)('0' + value % 10);
    value /= 10;
  } while (value);
  for (int i = 0; i < n; i++)
    out[i] = tmp[n - 1 - i];
  return n;
}

#define FLOAT_BUF 64

/* %f body: `prec` fractional digits. Values too large for a uint64 integer
 * part return -1 so the caller falls back to %e. */
static int formatFixed(char *out, double v, int prec, int keepPoint)
{
  double rounding = 0.5;
  for (int i = 0; i < prec; i++)
    rounding /= 10.0;
  v += rounding;
  if (v >= 18446744073709551615.0)
    return -1;

  uint64_t intPart = (uint64_t)v;
  double frac = v - (double)intPart;
  int n = appendUnsigned(out, intPart);

  if (prec > 0 || keepPoint)
    out[n++] = '.';
  for (int i = 0; i < prec && n < FLOAT_BUF - 1; i++) {
    frac *= 10.0;
    int digit = (int)frac;
    if (digit > 9)
      digit = 9;
    out[n++] = (char)('0' + digit);
    frac -= digit;
  }
  return n;
}

/* Splits v (> 0) into mantissa in [1,10) and a decimal exponent. */
static double normalize(double v, int *exp10)
{
  int e = 0;
  if (v != 0.0) {
    while (v >= 10.0) {
      v /= 10.0;
      e++;
    }
    while (v < 1.0) {
      v *= 10.0;
      e--;
    }
  }
  *exp10 = e;
  return v;
}

static int formatExponent(char *out, double v, int prec, int keepPoint, int upper)
{
  int e;
  double m = normalize(v, &e);

  double rounding = 0.5;
  for (int i = 0; i < prec; i++)
    rounding /= 10.0;
  if (m + rounding >= 10.0) { // Rounding carries into a new digit (9.99 -> 1.00e+1).
    m /= 10.0;
    e++;
  }

  int n = formatFixed(out, m, prec, keepPoint);
  out[n++] = upper ? 'E' : 'e';
  out[n++] = e < 0 ? '-' : '+';
  if (e < 0)
    e = -e;
  if (e < 10)
    out[n++] = '0';
  n += appendUnsigned(out + n, (uint64_t)e);
  return n;
}

/* %g: strips trailing zeros (and a bare trailing point) unless '#'. */
static int stripZeros(char *out, int n)
{
  int point = -1;
  int expPos = n;
  for (int i = 0; i < n; i++) {
    if (out[i] == '.')
      point = i;
    if (out[i] == 'e' || out[i] == 'E') {
      expPos = i;
      break;
    }
  }
  if (point < 0)
    return n;

  int end = expPos;
  while (end > point + 1 && out[end - 1] == '0')
    end--;
  if (end == point + 1)
    end = point;

  int removed = expPos - end;
  for (int i = expPos; i < n; i++)
    out[i - removed] = out[i];
  return n - removed;
}

static void formatFloat(printf_sink_t *s, double v, char conv, int width, int prec, unsigned flags)
{
  int upper = (conv == 'F' || conv == 'E' || conv == 'G');
  int negative = (v < 0.0) || (v == 0.0 && 1.0 / v < 0.0);
  if (negative)
    v = -v;

  const char *prefix = negative ? "-" : (flags & FLAG_PLUS) ? "+" : (flags & FLAG_SPACE) ? " " : "";
  char body[FLOAT_BUF];
  int n;

  if (v != v) { // NaN
    flags &= ~FLAG_ZERO;
    emitPadded(s, prefix, upper ? "NAN" : "nan", 3, 0, width, flags);
    return;
  }
  if (v > 1.7976931348623157e308) { // Infinity
    flags &= ~FLAG_ZERO;
    emitPadded(s, prefix, upper ? "INF" : "inf", 3, 0, width, flags);
    return;
  }

  if (prec < 0)
    prec = 6;
  if (prec > 30)
    prec = 30; // Keeps every body inside FLOAT_BUF.
  int keepPoint = (flags & FLAG_ALT) != 0;

  if (conv == 'g' || conv == 'G') {
    if (prec == 0)
      prec = 1;
    int e;
    normalize(v, &e);
    // Rounding to `prec` significant digits can bump the exponent (9.99 -> 10.0).
    double rounded = v;
    double scale = 0.5;
    for (int i = 1; i < prec; i++)
      scale /= 10.0;
    for (int i = 0; i < e; i++)
      scale *= 10.0;
    for (int i = 0; i > e; i--)
      scale /= 10.0;
    rounded += scale;
    normalize(rounded, &e);

    if (e < -4 || e >= prec)
      n = formatExponent(body, v, prec - 1, keepPoint, upper);
    else
      n = formatFixed(body, v, prec - 1 - e, keepPoint);
    if (!keepPoint)
      n = stripZeros(body, n);
  } else if (conv == 'e' || conv == 'E') {
    n = formatExponent(body, v, prec, keepPoint, upper);
  } else {
    n = formatFixed(body, v, prec, keepPoint);
    if (n < 0)
      n = formatExponent(body, v, prec, keepPoint, upper);
  }

  emitPadded(s, prefix, body, n, 0, width, flags);
}

static int format(printf_sink_t *s, const char *fmt, va_list ap)
{
  while (*fmt) {
    if (*fmt != '%') {
      emit(s, *fmt++);
      continue;
    }
    fmt++;

    unsigned flags = 0;
    for (;; fmt++) {
      if (*fmt == '-')
        flags |= FLAG_LEFT;
      else if (*fmt == '+')
        flags |= FLAG_PLUS;
      else if (*fmt == ' ')
        flags |= FLAG_SPACE;
      else if (*fmt == '#')
        flags |= FLAG_ALT;
      else if (*fmt == '0')
        flags |= FLAG_ZERO;
      else
        break;
    }

    int width = 0;
    if (*fmt == '*') {
      width = va_arg(ap, int);
      if (width < 0) {
        flags |= FLAG_LEFT;
        width = -width;
      }
      fmt++;
    } else {
      while (*fmt >= '0' && *fmt <= '9')
        width = width * 10 + (*fmt++ - '0');
    }

    int precision = -1;
    if (*fmt == '.') {
      fmt++;
      precision = 0;
      if (*fmt == '*') {
        precision = va_arg(ap, int);
        if (precision < 0)
          precision = -1;
        fmt++;
      } else {
        while (*fmt >= '0' && *fmt <= '9')
          precision = precision * 10 + (*fmt++ - '0');
      }
    }

    // 0 = int, 1 = long/size_t/ptrdiff_t (32-bit here), 2 = long long/intmax_t.
    int length = 0;
    int narrow = 0; // 1 = short, 2 = char
    if (*fmt == 'h') {
      fmt++;
      narrow = 1;
      if (*fmt == 'h') {
        fmt++;
        narrow = 2;
      }
    } else if (*fmt == 'l') {
      fmt++;
      length = 1;
      if (*fmt == 'l') {
        fmt++;
        length = 2;
      }
    } else if (*fmt == 'j') {
      fmt++;
      length = 2;
    } else if (*fmt == 'z' || *fmt == 't') {
      fmt++;
      length = 1;
    }

    char conv = *fmt;
    if (!conv)
      break;
    fmt++;

    switch (conv) {
    case 'd':
    case 'i': {
      int64_t v = (length == 2) ? va_arg(ap, long long) : (length == 1) ? va_arg(ap, long) : va_arg(ap, int);
      if (narrow == 1)
        v = (short)v;
      else if (narrow == 2)
        v = (signed char)v;
      uint64_t mag = v < 0 ? (uint64_t)0 - (uint64_t)v : (uint64_t)v;
      formatInteger(s, mag, v < 0, 10, width, precision, flags);
      break;
    }
    case 'u':
    case 'o':
    case 'x':
    case 'X': {
      uint64_t v = (length == 2) ? va_arg(ap, unsigned long long)
                   : (length == 1) ? va_arg(ap, unsigned long) : va_arg(ap, unsigned int);
      if (narrow == 1)
        v = (unsigned short)v;
      else if (narrow == 2)
        v = (unsigned char)v;
      unsigned base = (conv == 'u') ? 10 : (conv == 'o') ? 8 : 16;
      if (conv == 'X')
        flags |= FLAG_UPPER;
      formatInteger(s, v, 0, base, width, precision, flags & ~(FLAG_PLUS | FLAG_SPACE));
      break;
    }
    case 'p': {
      uintptr_t v = (uintptr_t)va_arg(ap, void *);
      formatInteger(s, v, 0, 16, width, 8, FLAG_ALT | (flags & FLAG_LEFT));
      break;
    }
    case 'c': {
      char c = (char)va_arg(ap, int);
      emitPadded(s, "", &c, 1, 0, width, flags & FLAG_LEFT);
      break;
    }
    case 's': {
      const char *str = va_arg(ap, const char *);
      if (!str)
        str = "(null)";
      int n = 0;
      while (str[n] && (precision < 0 || n < precision))
        n++;
      emitPadded(s, "", str, n, 0, width, flags & FLAG_LEFT);
      break;
    }
    case 'f':
    case 'F':
    case 'e':
    case 'E':
    case 'g':
    case 'G':
      formatFloat(s, va_arg(ap, double), conv, width, precision, flags);
      break;
    case '%':
      emit(s, '%');
      break;
    default:
      // Unknown conversion: print it verbatim so the mistake is visible.
      emit(s, '%');
      emit(s, conv);
      break;
    }
  }
  return (int)s->len;
}

int vsnprintf(char *buf, size_t size, const char *fmt, va_list ap)
{
  printf_sink_t s = {buf, size, 0, 0};
  int n = format(&s, fmt, ap);
  if (size > 0)
    buf[(s.len < size) ? s.len : size - 1] = '\0';
  return n;
}

int snprintf(char *buf, size_t size, const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  int n = vsnprintf(buf, size, fmt, ap);
  va_end(ap);
  return n;
}

int vsprintf(char *buf, const char *fmt, va_list ap)
{
  return vsnprintf(buf, 0x7FFFFFFF, fmt, ap); // Unbounded, as sprintf() is.
}

int sprintf(char *buf, const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  int n = vsprintf(buf, fmt, ap);
  va_end(ap);
  return n;
}

int vprintf(const char *fmt, va_list ap)
{
  printf_sink_t s = {NULL, 0, 0, 1};
  return format(&s, fmt, ap);
}

int printf(const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  int n = vprintf(fmt, ap);
  va_end(ap);
  return n;
}

/* GCC rewrites printf("text\n") into puts("text"), so this must exist. */
int puts(const char *str)
{
  while (*str)
    putchar((unsigned char)*str++);
  putchar('\n');
  return 1;
}

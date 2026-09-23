#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <math.h>
int t_snprintf(char *buf, size_t size, const char *fmt, ...);
int t_putchar(int c) { return c; }
static int fails, total;
#define CHECK(...) do { char a[256], b[256]; snprintf(a, sizeof a, __VA_ARGS__); t_snprintf(b, sizeof b, __VA_ARGS__); total++; \
  if (strcmp(a, b)) { fails++; printf("MISMATCH %-22s glibc=[%s] ours=[%s]\n", #__VA_ARGS__, a, b); } } while (0)
/* Deliberate, documented differences from glibc (see the header of
 * cores/tangnano20k/tangnano20k_printf.c): check our own output instead. */
#define CHECK_OURS(want, ...) do { char b[256]; t_snprintf(b, sizeof b, __VA_ARGS__); total++; \
  if (strcmp(b, want)) { fails++; printf("MISMATCH %-22s want=[%s] ours=[%s]\n", #__VA_ARGS__, want, b); } } while (0)
int main(void) {
  CHECK("%d", 0); CHECK("%d", -123); CHECK("%5d|%-5d|%05d", 42, 42, 42); CHECK("%+d % d", 5, 5);
  CHECK("%u", 4294967295u); CHECK("%x %X %#x %#o %o", 255, 255, 255, 8, 8); CHECK("%08x", 0xbeef);
  CHECK("%lld %llu", -9223372036854775807LL - 1, 18446744073709551615ULL); CHECK("%hhd %hd", 300, 70000);
  CHECK("%.3d|%.0d|%5.3d", 7, 0, 7); CHECK("%c|%3c|%-3c|", 'a', 'b', 'c'); CHECK("%s|%.2s|%5s|%-5s|", "hello", "hello", "ab", "ab");
  CHECK("%%"); CHECK("%*d|%-*d|%.*f", 5, 1, 5, 2, 2, 3.14159); CHECK("%zu %ld", (size_t)12, -5L);
  CHECK("%f", 0.0); CHECK("%f", 3.14159265); CHECK("%.2f", 2.675); CHECK_OURS("1", "%.0f", 0.5); /* rounds half up, glibc rounds to even */ CHECK("%.0f", 1.5); CHECK("%#.0f", 3.0);
  CHECK("%8.3f|%-8.3f|%08.3f", -1.5, 1.5, -1.5); CHECK("%+.1f", 9.96); CHECK("%f", -0.0); CHECK("%f", 1e10); CHECK("%.10f", 1.0/3);
  CHECK("%e", 12345.678); CHECK("%.2e", 9.999); CHECK("%E", 0.000123); CHECK("%e", 0.0); CHECK("%.0e", 5.5); CHECK("%e", 1e-300);
  CHECK("%g", 0.0001); CHECK("%g", 0.00001); CHECK("%g", 123456.0); CHECK("%g", 1234567.0); CHECK("%g", 100.0); CHECK("%.3g", 9.999);
  CHECK("%g", 1.5); CHECK("%G", 1e-10); CHECK("%#g", 1.0); CHECK("%.0g", 0.5); CHECK("%10.4g|", 3.14159);
  CHECK("%f %F %e", INFINITY, -INFINITY, NAN); CHECK("%5.1f|", NAN);
  CHECK_OURS("1.000000e+20", "%f", 1e20); /* >= 2^64 falls back to %e */ CHECK("%.1f", 123456789.25);
  { char small[5]; int n = t_snprintf(small, sizeof small, "%s", "abcdefgh"); total++;
    if (n != 8 || strcmp(small, "abcd")) { fails++; printf("truncation: n=%d buf=[%s]\n", n, small); } }
  printf("%d/%d printf checks pass (glibc-identical except 2 documented cases)\n", total - fails, total);
  return fails != 0;
}

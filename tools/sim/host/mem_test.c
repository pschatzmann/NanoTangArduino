#include <stdio.h>
#include <string.h>
#include <stdlib.h>
void *t_memcpy(void *, const void *, size_t); void *t_memset(void *, int, size_t); void *t_memmove(void *, const void *, size_t);
int main(void) {
  static unsigned char a[512], b[512], src[512];
  int fails = 0, runs = 0;
  srand(1);
  for (int iter = 0; iter < 200000; iter++) {
    for (int i = 0; i < 512; i++) { src[i] = rand(); a[i] = b[i] = rand(); }
    size_t n = rand() % 200, so = rand() % 64, d = rand() % 64;
    int op = rand() % 3; runs++;
    if (op == 0) { memcpy(a + d, src + so, n); t_memcpy(b + d, src + so, n); }
    else if (op == 1) { int c = rand(); memset(a + d, c, n); t_memset(b + d, c, n); }
    else { size_t s2 = rand() % 64; memmove(a + d, a + s2, n); t_memmove(b + d, b + s2, n); }
    if (memcmp(a, b, 512)) { if (fails++ < 5) printf("mismatch op=%d n=%zu d=%zu\n", op, n, d); }
  }
  printf("%d/%d mem tests match glibc\n", runs - fails, runs);
  return fails != 0;
}

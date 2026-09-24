/* Exercises Tools > Boot Mode: SRAM + SDRAM (or Flash + SDRAM) - see
 * cores/tangnano20k/link_cmd_sdram.ld and docs/PERIPHERALS.md "Code in
 * SDRAM"). Select that menu option before uploading: the upload then
 * also writes the SDRAM code image to the flash data partition.
 *
 * Runs the same loop once from SDRAM (SDRAM_CODE) and once from the
 * internal SRAM (SRAM_CODE), checks both give the same result, prints
 * how much slower the SDRAM copy runs, and checks that the heap starts
 * after the code image. */

extern "C" char __sdram_img_start[], __sdram_img_end[];

SDRAM_CODE uint32_t sumFromSdram(uint32_t n)
{
  uint32_t s = 0;
  for (uint32_t i = 0; i < n; i++) {
    s += i * 3 + 1;
    asm volatile("" : "+r"(s)); // Keep the loop: no closed-form rewrite.
  }
  return s;
}

SRAM_CODE uint32_t sumFromSram(uint32_t n)
{
  uint32_t s = 0;
  for (uint32_t i = 0; i < n; i++) {
    s += i * 3 + 1;
    asm volatile("" : "+r"(s));
  }
  return s;
}

static bool inSdram(const void *p)
{
  return (uintptr_t)p >= TANGNANO20K_SDRAM_BASE &&
         (uintptr_t)p < TANGNANO20K_SDRAM_BASE + TANGNANO20K_SDRAM_SIZE;
}

void setup()
{
  Serial.begin(115200);
}

void loop()
{
  const uint32_t n = 100000;
  bool ok = true;

  Serial.print("code image: 0x");
  Serial.print((unsigned long)__sdram_img_start, HEX);
  Serial.print(" - 0x");
  Serial.print((unsigned long)__sdram_img_end, HEX);
  Serial.print(" (");
  Serial.print((unsigned long)(__sdram_img_end - __sdram_img_start));
  Serial.println(" bytes)");

  if (!inSdram((const void *)&sumFromSdram) || inSdram((const void *)&sumFromSram)) {
    Serial.println("FAIL: functions not where expected - is Tools > Boot Mode set to a + SDRAM entry?");
    ok = false;
  }

  uint32_t t0 = micros();
  uint32_t a = sumFromSdram(n);
  uint32_t t1 = micros();
  uint32_t b = sumFromSram(n);
  uint32_t t2 = micros();

  Serial.print("SDRAM: ");
  Serial.print(t1 - t0);
  Serial.print("us, SRAM: ");
  Serial.print(t2 - t1);
  Serial.print("us, ratio x");
  Serial.println((float)(t1 - t0) / (float)(t2 - t1), 1);
  if (a != b) {
    Serial.println("FAIL: results differ");
    ok = false;
  }

  void *p = malloc(16);
  if (p == NULL || (char *)p < __sdram_img_end) {
    Serial.println("FAIL: heap overlaps the code image");
    ok = false;
  }
  free(p);

  Serial.println(ok ? "PASS" : "FAIL");
  delay(2000);
}

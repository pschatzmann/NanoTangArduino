/* Loads a small INT8 weight tile and activation window into the on-chip
 * AI accelerator, computes the dot products, and prints them - a smoke
 * test for gateware/src/ai_accel_bus.v (dot_product_engine.v, integrated
 * from the standalone NanoTangAI project). See docs/PERIPHERALS.md "AI accelerator".
 *
 * Shape: 1 row, k=2 taps, cinPadded=16 (the minimum - one LANES-wide
 * chunk per tap).
 */

#include <AIAccelerator.h>

const uint8_t kRows = 1;
const uint8_t kTaps = 2;
const uint16_t kCinPadded = 16;

int8_t weights[kRows * kTaps * kCinPadded];
int8_t activation[kTaps * kCinPadded];
int32_t results[kRows * kTaps];

void setup() {
  Serial.begin(115200);
  AIAccelerator.begin();

  for (size_t i = 0; i < sizeof(weights); i++)
    weights[i] = 1;
  for (size_t i = 0; i < sizeof(activation); i++)
    activation[i] = 2;

  AIAccelerator.config(kCinPadded, kTaps, kRows);
  AIAccelerator.loadWeights(weights, sizeof(weights));
}

void loop() {
  AIAccelerator.compute(activation, sizeof(activation));
  AIAccelerator.getResults(results, kRows, kTaps);

  // Expect cinPadded * 1 * 2 = 32 for each tap (all-ones weights times
  // all-twos activation, summed over 16 lanes).
  for (uint8_t tap = 0; tap < kTaps; tap++) {
    Serial.print("tap ");
    Serial.print(tap);
    Serial.print(": ");
    Serial.println(results[tap]);
  }

  delay(1000);
}

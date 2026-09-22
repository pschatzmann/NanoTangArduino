/* Two independent AIAccelerator instances, each with its own weight
 * tile, sharing the one physical engine (see docs/PERIPHERALS.md "AI
 * accelerator" > "Multiple instances"). Each instance's compute() fully
 * finishes (it blocks until its own result is ready) before the other
 * instance's compute() runs - the required ordering when time-slicing a
 * single physical engine across instances.
 *
 * Shape for both: 1 row, k=1 tap, cinPadded=16 (the minimum).
 */

#include <AIAccelerator.h>

const uint8_t kRows = 1;
const uint8_t kTaps = 1;
const uint16_t kCinPadded = 16;

AIAccelerator instanceA(kCinPadded, kTaps, kRows);
AIAccelerator instanceB(kCinPadded, kTaps, kRows);

int8_t weightsA[kRows * kTaps * kCinPadded];
int8_t weightsB[kRows * kTaps * kCinPadded];
int8_t activation[kTaps * kCinPadded];

void setup() {
  Serial.begin(115200);
  instanceA.begin();
  instanceB.begin();

  for (size_t i = 0; i < sizeof(weightsA); i++)
    weightsA[i] = 1; // instanceA: all-ones weights
  for (size_t i = 0; i < sizeof(weightsB); i++)
    weightsB[i] = 3; // instanceB: all-threes weights
  for (size_t i = 0; i < sizeof(activation); i++)
    activation[i] = 2; // shared activation window, all-twos

  instanceA.loadWeights(weightsA, sizeof(weightsA));
  instanceB.loadWeights(weightsB, sizeof(weightsB));
}

void loop() {
  int32_t *resultsA = instanceA.compute(activation, sizeof(activation));
  int32_t *resultsB = instanceB.compute(activation, sizeof(activation));

  // Expect cinPadded * weight * activation = 16 * 1 * 2 = 32 for A,
  // 16 * 3 * 2 = 96 for B - proving each instance's own weights survive
  // the engine being shared with the other.
  Serial.print("A: ");
  Serial.print(resultsA[0]);
  Serial.print("  B: ");
  Serial.println(resultsB[0]);

  delay(1000);
}

/* Sends a frame every second in internal loopback mode and prints what
 * comes back - a self-test that needs no transceiver or bus.
 * Needs Tools > CAN: Enabled. */

#include <CAN.h>

void setup()
{
  Serial.begin(115200);
  CAN.setLoopback(true);
  if (!CAN.begin(CanBitRate::BR_500k))
    Serial.println("CAN.begin() failed - is Tools > CAN enabled?");
}

void loop()
{
  static uint8_t counter = 0;
  uint8_t data[] = {0xCA, 0xFE, counter++};
  int rc = CAN.write(CanMsg(CanStandardId(0x123), sizeof(data), data));
  if (rc < 0)
    Serial.println("CAN.write() failed: " + String(rc));

  delay(10);
  while (CAN.available())
    Serial.println(CAN.read()); // CanMsg prints itself: [id] (len) : data
  delay(990);
}

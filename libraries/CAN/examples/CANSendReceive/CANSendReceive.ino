/* Sends a counter every 500ms and prints every frame received from other
 * nodes. Wire an SN65HVD230 (or similar 3.3V) transceiver: its D (TXD)
 * pin to GPIO18 (FPGA pin 71), R (RXD) to GPIO11 (pin 76), CANH/CANL to
 * the bus, which needs 120 ohm termination at both ends.
 * Needs Tools > CAN: Enabled. */

#include <CAN.h>

void setup()
{
  Serial.begin(115200);
  // CAN.setPins(GPIO18, GPIO11); // the defaults - change to use others
  if (!CAN.begin(CanBitRate::BR_500k))
    Serial.println("CAN.begin() failed - is Tools > CAN enabled?");
}

void loop()
{
  static unsigned long last = 0;
  static uint32_t counter = 0;

  if (millis() - last >= 500) {
    last = millis();
    uint8_t data[4];
    memcpy(data, &counter, sizeof(counter));
    counter++;
    int rc = CAN.write(CanMsg(CanStandardId(0x100), sizeof(data), data));
    if (rc < 0)
      printf("write failed (%d), TEC=%u REC=%u%s\n", rc, CAN.txErrorCount(), CAN.rxErrorCount(),
             CAN.isBusOff() ? " bus off" : CAN.isErrorPassive() ? " error passive" : "");
  }

  while (CAN.available())
    Serial.println(CAN.read());
}

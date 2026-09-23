#pragma once

#include <Arduino.h>
#include "api/HardwareCAN.h"

/* CAN bus through the gateware CAN 2.0A/B controller
 * (gateware/src/can_ctrl.v) - needs Tools > CAN: Enabled, and an external
 * 3.3V CAN transceiver (e.g. SN65HVD230) on two GPIO pins, GPIO18 (TX)
 * and GPIO11 (RX) by default. Implements Arduino's standard HardwareCAN
 * API (begin/end/write/available/read with CanMsg), as on the UNO R4:
 *
 *   CAN.begin(CanBitRate::BR_500k);
 *   uint8_t data[] = {1, 2, 3};
 *   CAN.write(CanMsg(CanStandardId(0x123), sizeof(data), data));
 *   if (CAN.available()) { CanMsg msg = CAN.read(); ... }
 *
 * Received frames are moved from the controller's 8-frame FIFO into a
 * 32-frame software buffer by an interrupt, so loop() doesn't have to
 * keep up with every frame on a busy bus. Remote frames are delivered
 * too (CanMsg can't mark them, so they arrive with their DLC and zeroed
 * data). See docs/PERIPHERALS.md "CAN". */
class TangNanoCAN : public arduino::HardwareCAN
{
public:
  // Returns false if Tools > CAN is disabled or the bit rate can't be made
  // exactly from the system clock (1 Mbit/s needs 27 or 54MHz).
  bool begin(CanBitRate const can_bitrate) override;
  void end() override;

  /* Queues a frame. The controller holds one outgoing frame; if the
   * previous one is still waiting for the bus, this waits up to about
   * three frame times for it. Returns 1 when queued, -1 if the previous
   * frame is still pending (e.g. nobody acknowledges it), -2 if the
   * controller is bus off, -3 if begin() hasn't succeeded. Transmission
   * then happens in the background, with automatic retries. */
  int write(CanMsg const &msg) override;

  size_t available() override;
  CanMsg read() override;

  // Call before begin(): TX/RX pins (GPIO0-GPIO20) and internal loopback
  // (TX connected to RX inside the FPGA, pins left alone, own frames
  // acknowledged and received - for testing without a transceiver).
  void setPins(pin_size_t txPin, pin_size_t rxPin);
  void setLoopback(bool enabled) { loopback_ = enabled; }

  // Error state per ISO 11898-1.
  uint8_t txErrorCount(void);
  uint8_t rxErrorCount(void);
  bool isErrorPassive(void);
  bool isBusOff(void);

  // Whether received frames were dropped (hardware or software buffer
  // full) since the last call; clears the flag.
  bool overflow(void);

  // Called from the receive interrupt; not for sketches.
  void serviceIrq(void);

private:
  uint32_t ctrlValue(void) const;
  uint32_t readStatus(void);

  arduino::CanMsgRingbuffer rx_;
  pin_size_t txPin_ = GPIO18;
  pin_size_t rxPin_ = GPIO11;
  bool loopback_ = false;
  bool started_ = false;
  bool overflow_ = false;
  uint32_t frameUs_ = 0; // Longest frame time at the current bit rate.
};

extern TangNanoCAN CAN;

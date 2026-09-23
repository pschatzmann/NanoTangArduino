#include "CAN.h"

TangNanoCAN CAN;

extern "C" void tangnano20k_can_set_irq_callback(void (*callback)(void));

static void canServiceIrqTrampoline(void)
{
  CAN.serviceIrq();
}

uint32_t TangNanoCAN::ctrlValue(void) const
{
  return TANGNANO20K_CAN_CTRL_ENABLE | TANGNANO20K_CAN_CTRL_RX_IRQ |
         (loopback_ ? TANGNANO20K_CAN_CTRL_LOOPBACK : 0) |
         TANGNANO20K_CAN_CTRL_TX_PIN(txPin_ - TANGNANO20K_PIN_GPIO_BASE) |
         TANGNANO20K_CAN_CTRL_RX_PIN(rxPin_ - TANGNANO20K_PIN_GPIO_BASE);
}

/* STATUS reads clear the hardware's sticky overflow bit, so it's latched
 * here whichever call happened to read it. */
uint32_t TangNanoCAN::readStatus(void)
{
  uint32_t status = TANGNANO20K_CAN_CTRL_REG;
  if (status & TANGNANO20K_CAN_STATUS_RX_OVERFLOW)
    overflow_ = true;
  return status;
}

void TangNanoCAN::setPins(pin_size_t txPin, pin_size_t rxPin)
{
  txPin_ = txPin;
  rxPin_ = rxPin;
}

bool TangNanoCAN::begin(CanBitRate const can_bitrate)
{
  end();
  if (!(TANGNANO20K_CAN_CTRL_REG & TANGNANO20K_CAN_STATUS_PRESENT))
    return false; // Tools > CAN is disabled.
  bool pinsOk = txPin_ >= TANGNANO20K_PIN_GPIO_BASE && rxPin_ >= TANGNANO20K_PIN_GPIO_BASE &&
                txPin_ < NUM_DIGITAL_PINS && rxPin_ < NUM_DIGITAL_PINS;
  if (!pinsOk)
    return false;

  /* Find the smallest prescaler giving a whole number of 8-49 time quanta
   * per bit, then place the sample point at ~80% (TSEG2 = 20%, at least 2
   * tq) with SJW = min(4, TSEG2). */
  uint32_t rate = (uint32_t)can_bitrate;
  uint32_t brp = 0, tq = 0;
  for (uint32_t b = 1; b <= 256; b++) {
    if (F_CPU % (rate * b) != 0)
      continue;
    uint32_t n = F_CPU / (rate * b);
    if (n < 8)
      break;
    if (n <= 49) {
      brp = b;
      tq = n;
      break;
    }
  }
  if (brp == 0)
    return false;
  uint32_t tseg2 = (tq * 2 + 5) / 10;
  if (tseg2 < 2)
    tseg2 = 2;
  uint32_t tseg1 = tq - 1 - tseg2;
  if (tseg1 > 32) {
    tseg1 = 32;
    tseg2 = tq - 1 - tseg1;
  }
  uint32_t sjw = tseg2 < 4 ? tseg2 : 4;
  TANGNANO20K_CAN_TIMING_REG = (brp - 1) | ((tseg1 - 1) << 8) | ((tseg2 - 1) << 16) | ((sjw - 1) << 24);

  // A stuffed extended frame with 8 data bytes plus IFS: at most ~160 bits.
  frameUs_ = (160UL * 1000000UL) / rate;

  uint32_t irqState = tangnano20k_irq_save();
  while (!rx_.isEmpty())
    rx_.dequeue();
  tangnano20k_irq_restore(irqState);
  overflow_ = false;

  tangnano20k_can_set_irq_callback(canServiceIrqTrampoline);
  TANGNANO20K_CAN_CTRL_REG = ctrlValue();
  started_ = true;
  return true;
}

void TangNanoCAN::end(void)
{
  if (TANGNANO20K_CAN_CTRL_REG & TANGNANO20K_CAN_STATUS_PRESENT)
    TANGNANO20K_CAN_CTRL_REG = 0;
  started_ = false;
}

int TangNanoCAN::write(CanMsg const &msg)
{
  if (!started_)
    return -3;

  uint32_t start = micros();
  uint32_t status;
  while ((status = readStatus()) & TANGNANO20K_CAN_STATUS_TX_PENDING) {
    if (status & TANGNANO20K_CAN_STATUS_BUS_OFF)
      return -2;
    if (micros() - start >= 3 * frameUs_)
      return -1;
  }
  if (status & TANGNANO20K_CAN_STATUS_BUS_OFF)
    return -2;

  uint32_t id = msg.isExtendedId() ? (msg.getExtendedId() | TANGNANO20K_CAN_ID_EXTENDED)
                                   : msg.getStandardId();
  uint8_t bytes[8] = {0};
  memcpy(bytes, msg.data, msg.data_length);
  TANGNANO20K_CAN_ID_REG = id;
  TANGNANO20K_CAN_DATA0_REG = (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
                              ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
  TANGNANO20K_CAN_DATA1_REG = (uint32_t)bytes[4] | ((uint32_t)bytes[5] << 8) |
                              ((uint32_t)bytes[6] << 16) | ((uint32_t)bytes[7] << 24);
  TANGNANO20K_CAN_CMD_REG = TANGNANO20K_CAN_CMD_SEND | msg.data_length;
  return 1;
}

/* Moves every frame from the controller's FIFO into rx_. Runs from the
 * receive interrupt (irq[7]); interrupts are already off there. */
void TangNanoCAN::serviceIrq(void)
{
  while (readStatus() & TANGNANO20K_CAN_STATUS_RX_READY) {
    uint32_t id = TANGNANO20K_CAN_ID_REG;
    uint32_t d0 = TANGNANO20K_CAN_DATA0_REG;
    uint32_t d1 = TANGNANO20K_CAN_DATA1_REG;
    uint8_t dlc = (uint8_t)(TANGNANO20K_CAN_CMD_REG & 0xF);
    TANGNANO20K_CAN_POP_REG = 0;

    uint8_t len = dlc > 8 ? 8 : dlc;
    uint8_t bytes[8];
    for (int i = 0; i < 4; i++) {
      bytes[i] = (uint8_t)(d0 >> (8 * i));
      bytes[i + 4] = (uint8_t)(d1 >> (8 * i));
    }
    if (id & TANGNANO20K_CAN_ID_REMOTE)
      memset(bytes, 0, sizeof(bytes));
    uint32_t canId = (id & TANGNANO20K_CAN_ID_EXTENDED) ? CanExtendedId(id & CanMsg::CAN_EFF_MASK)
                                                        : CanStandardId(id & CanMsg::CAN_SFF_MASK);
    if (rx_.isFull())
      overflow_ = true;
    else
      rx_.enqueue(CanMsg(canId, len, bytes));
  }
}

size_t TangNanoCAN::available(void)
{
  uint32_t irqState = tangnano20k_irq_save();
  size_t n = rx_.available();
  tangnano20k_irq_restore(irqState);
  return n;
}

CanMsg TangNanoCAN::read(void)
{
  uint32_t irqState = tangnano20k_irq_save();
  CanMsg msg = rx_.dequeue();
  tangnano20k_irq_restore(irqState);
  return msg;
}

uint8_t TangNanoCAN::txErrorCount(void)
{
  return (uint8_t)(TANGNANO20K_CAN_POP_REG & 0xFF);
}

uint8_t TangNanoCAN::rxErrorCount(void)
{
  return (uint8_t)((TANGNANO20K_CAN_POP_REG >> 8) & 0xFF);
}

bool TangNanoCAN::isErrorPassive(void)
{
  return (readStatus() & TANGNANO20K_CAN_STATUS_PASSIVE) != 0;
}

bool TangNanoCAN::isBusOff(void)
{
  return (readStatus() & TANGNANO20K_CAN_STATUS_BUS_OFF) != 0;
}

bool TangNanoCAN::overflow(void)
{
  readStatus();
  bool result = overflow_;
  overflow_ = false;
  return result;
}

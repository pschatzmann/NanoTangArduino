#include "HardwareSerial.h"
#include "tangnano20k_soc.h"

namespace tangnano20k {

void HardwareSerial::begin(unsigned long baudrate)
{
  TANGNANO20K_UART_DIV_REG = TANGNANO20K_CLK_FREQ / baudrate;
}

void HardwareSerial::begin(unsigned long baudrate, uint16_t /*config*/)
{
  /* Only 8N1 is supported by the simpleuart peripheral; config is ignored. */
  begin(baudrate);
}

void HardwareSerial::end()
{
}

void HardwareSerial::refillRxCache(void)
{
  if (rxHasByte)
    return;

  uint32_t v = TANGNANO20K_UART_DAT_REG;
  if (v != 0xFFFFFFFFUL) {
    rxByte = (uint8_t)v;
    rxHasByte = true;
  }
}

int HardwareSerial::available(void)
{
  refillRxCache();
  return rxHasByte ? 1 : 0;
}

int HardwareSerial::peek(void)
{
  refillRxCache();
  return rxHasByte ? rxByte : -1;
}

int HardwareSerial::read(void)
{
  refillRxCache();
  if (!rxHasByte)
    return -1;

  rxHasByte = false;
  return rxByte;
}

void HardwareSerial::flush(void)
{
  /* Writes stall the CPU in hardware until the UART is ready for the next
   * byte (see gateware/src/uart_wrap.v), so there is no software buffer to
   * drain here. */
}

size_t HardwareSerial::write(uint8_t c)
{
  TANGNANO20K_UART_DAT_REG = c;
  return 1;
}

} // namespace tangnano20k

static tangnano20k::HardwareSerial tangnano20kSerial;
arduino::HardwareSerial &Serial = tangnano20kSerial;

#pragma once

/* Memory map of the arduino-tangnano20k PicoRV32 SoC. Must match
 * gateware/src/top.v and gateware/src/sys_parameters.v. */

#include <stdint.h>

/* Must match gateware/src/sys_parameters.v's CLK_FREQ, derived from the
 * board's fixed 27MHz oscillator via Gowin_rPLL_sys - see top.v. Getting
 * this wrong silently skews every timing derived from it: UART baud rate,
 * I2S sample rate, SPI clock, and millis()/micros(). Driven by the Tools >
 * Clock Speed board menu via F_CPU (see platform.txt/boards.txt), which
 * sets build.f_cpu and build.clk_freq_hz from the same menu choice in
 * lockstep - so this always matches whatever clk_freq_hz was actually
 * synthesized into the gateware. */
#define TANGNANO20K_CLK_FREQ F_CPU

#define TANGNANO20K_LED_REG      (*(volatile uint32_t *)0x80000000UL)
#define TANGNANO20K_UART_DIV_REG (*(volatile uint32_t *)0x80000008UL)
#define TANGNANO20K_UART_DAT_REG (*(volatile uint32_t *)0x8000000CUL)
#define TANGNANO20K_SYSTICK_REG  (*(volatile uint32_t *)0x80000020UL)
#define TANGNANO20K_I2S_DIV_REG    (*(volatile uint32_t *)0x80000040UL)
#define TANGNANO20K_I2S_DAT_REG    (*(volatile uint32_t *)0x80000044UL)
#define TANGNANO20K_I2S_CTRL_REG   (*(volatile uint32_t *)0x80000048UL)
#define TANGNANO20K_I2S_DAT_RX_REG (*(volatile uint32_t *)0x8000004CUL)
/* Separate 16-byte address window from the four registers above - see
 * gateware/src/i2s.v's header comment for why. */
#define TANGNANO20K_I2S_IRQEN_REG  (*(volatile uint32_t *)0x80000160UL)
#define TANGNANO20K_I2S_STATUS_REG (*(volatile uint32_t *)0x80000164UL)
/* gateware/src/pwm_audio.v - Tools > PWM Audio only; see libraries/PWMAudio. */
#define TANGNANO20K_PWM_AUDIO_PERIOD_REG (*(volatile uint32_t *)0x80000170UL)
#define TANGNANO20K_PWM_AUDIO_DIV_REG    (*(volatile uint32_t *)0x80000174UL)
#define TANGNANO20K_PWM_AUDIO_DAT_REG    (*(volatile uint32_t *)0x80000178UL)
#define TANGNANO20K_PWM_AUDIO_CTRL_REG   (*(volatile uint32_t *)0x8000017CUL)
#define TANGNANO20K_KEY2_REG     (*(volatile uint32_t *)0x80000050UL)
/* gateware/src/pwm_bank.v: a DUTY/CFG register pair per channel -
 * channels 0-5 are LEDs 0-5, channels 6-9 are a pool assignable to any
 * GPIO pin. See wiring_analog.cpp. */
#define TANGNANO20K_PWM_DUTY_REG(ch) (*(volatile uint32_t *)(0x80000180UL + 8UL * (ch)))
#define TANGNANO20K_PWM_CFG_REG(ch)  (*(volatile uint32_t *)(0x80000184UL + 8UL * (ch)))
#define TANGNANO20K_SPI_DIV_REG  (*(volatile uint32_t *)0x80000080UL)
#define TANGNANO20K_SPI_CS_REG   (*(volatile uint32_t *)0x80000084UL)
#define TANGNANO20K_SPI_DAT_REG  (*(volatile uint32_t *)0x80000088UL)
#define TANGNANO20K_I2C_REG      (*(volatile uint32_t *)0x80000090UL)

/* Second SPI/I2C port (Tools > SPI Buses / I2C Buses: Two, not the
 * default) - same register layout as the first, on GPIO0-3 (SPI2)/GPIO4-5
 * (I2C2) instead of the microSD slot's bus pins. See docs/PERIPHERALS.md. */
#define TANGNANO20K_SPI2_DIV_REG (*(volatile uint32_t *)0x800000A0UL)
#define TANGNANO20K_SPI2_CS_REG  (*(volatile uint32_t *)0x800000A4UL)
#define TANGNANO20K_SPI2_DAT_REG (*(volatile uint32_t *)0x800000A8UL)
#define TANGNANO20K_I2C2_REG     (*(volatile uint32_t *)0x800000B0UL)
#define TANGNANO20K_GPIO_DIR_REG (*(volatile uint32_t *)0x80000100UL)
#define TANGNANO20K_GPIO_OUT_REG (*(volatile uint32_t *)0x80000104UL)
#define TANGNANO20K_GPIO_IN_REG  (*(volatile uint32_t *)0x80000108UL)
#define TANGNANO20K_WS2812_REG   (*(volatile uint32_t *)0x80000110UL)

#define TANGNANO20K_AI_CFG_REG         (*(volatile uint32_t *)0x80000140UL)
#define TANGNANO20K_AI_WEIGHT_SEL_REG  (*(volatile uint32_t *)0x80000144UL)
#define TANGNANO20K_AI_WEIGHT_DATA_REG (*(volatile uint32_t *)0x80000148UL)
#define TANGNANO20K_AI_ACT_RESET_REG   (*(volatile uint32_t *)0x8000014CUL)
#define TANGNANO20K_AI_ACT_DATA_REG    (*(volatile uint32_t *)0x80000150UL)
#define TANGNANO20K_AI_START_REG       (*(volatile uint32_t *)0x80000154UL)
#define TANGNANO20K_AI_RESULT_ADDR_REG (*(volatile uint32_t *)0x80000158UL)
#define TANGNANO20K_AI_RESULT_DATA_REG (*(volatile uint32_t *)0x8000015CUL)

/* extirq peripheral (gateware/src/extirq.v): watches the 21 GPIO pins plus
 * KEY_S2 (bit 21) for level changes and drives picorv32's irq[3]. Bit
 * layout matches TANGNANO20K_GPIO_* pin numbering, offset by the pin's
 * expansion-header index (0-20); bit 21 is KEY_S2. See wiring_irq.cpp. */
#define TANGNANO20K_EXTIRQ_ENABLE_REG (*(volatile uint32_t *)0x80000120UL)
#define TANGNANO20K_EXTIRQ_STATUS_REG (*(volatile uint32_t *)0x80000124UL)
#define TANGNANO20K_EXTIRQ_LEVEL_REG  (*(volatile uint32_t *)0x80000128UL)
#define TANGNANO20K_EXTIRQ_KEY2_BIT   21

/* dma_engine.v: word-at-a-time bulk memory copy, the SoC's second bus
 * master (see gateware/src/top.v's arbiter and docs/PERIPHERALS.md
 * "DMA"). Writing DMA_START begins a transfer if DMA_LEN != 0; the CPU's
 * own bus (including instruction fetch) simply stalls for the transfer's
 * duration and resumes automatically once it completes - there's nothing
 * to poll or wait for in software. Addresses and length are in WORDS, not
 * bytes. See libraries/DMA. */
#define TANGNANO20K_DMA_SRC_REG   (*(volatile uint32_t *)0x80000130UL)
#define TANGNANO20K_DMA_DST_REG   (*(volatile uint32_t *)0x80000134UL)
#define TANGNANO20K_DMA_LEN_REG   (*(volatile uint32_t *)0x80000138UL)
#define TANGNANO20K_DMA_START_REG (*(volatile uint32_t *)0x8000013CUL)

/* START register write bits. */
#define TANGNANO20K_DMA_START_GO    (1UL << 0)
#define TANGNANO20K_DMA_START_ASYNC (1UL << 1)
/* STATUS (same address, read) bits. */
#define TANGNANO20K_DMA_STATUS_BUSY       (1UL << 0)
#define TANGNANO20K_DMA_STATUS_ASYNC_BUSY (1UL << 1)
#define TANGNANO20K_DMA_STATUS_ASYNC_DONE (1UL << 2)

/* Async DMA (gateware/src/dma_engine.v's dedicated port into sdram_bus.v)
 * only reaches the embedded SDRAM heap - see docs/PERIPHERALS.md "DMA". */
#define TANGNANO20K_SDRAM_BASE 0x10000000UL
#define TANGNANO20K_SDRAM_SIZE (8UL * 1024UL * 1024UL)

/* gateware/src/qspi_flash.v: the onboard SPI NOR flash, memory-mapped
 * read-only at TANGNANO20K_FLASH_WINDOW_BASE (a raw window - `addr` is a
 * byte offset within the flash chip, matching the SDRAM window's
 * convention). See docs/PERIPHERALS.md "Flash". The offset macros
 * themselves live in flash_layout.h, shared as-is with boot.S (assembly
 * files can't parse this header's C casts/<stdint.h>). */
#include "flash_layout.h"

/* C-only convenience pointer for FLASH_DATA-attributed const arrays'
 * base address (see below) - not used from boot.S, fine to use the
 * suffixed/cast form here. */
#define TANGNANO20K_FLASH_DATA_BASE \
  ((const void *)(TANGNANO20K_FLASH_WINDOW_BASE + TANGNANO20K_FLASH_DATA_OFFSET))

/* Attribute for big constant arrays that should live in flash instead of
 * the 64KB internal SRAM - see docs/PERIPHERALS.md "Flash". Reads happen
 * transparently through ordinary pointer/array syntax; no special API
 * needed. Independent of Tools > Boot Mode - available even in the
 * default SRAM boot mode. */
#define FLASH_DATA __attribute__((section(".flash_data")))

#define TANGNANO20K_I2S_CTRL_PA_EN (1UL << 0)
#define TANGNANO20K_I2S_IRQEN_TX   (1UL << 0) // TX FIFO has room
#define TANGNANO20K_I2S_IRQEN_RX   (1UL << 1) // RX FIFO has a sample
#define TANGNANO20K_I2S_STATUS_TX_FREE(status)  ((status) & 0x1FUL)
#define TANGNANO20K_I2S_STATUS_RX_COUNT(status) (((status) >> 5) & 0x1FUL)
#define TANGNANO20K_PWM_ENABLE     (1UL << 31) // DUTY register
#define TANGNANO20K_PWM_CFG(period, prescale, gpio) \
  ((uint32_t)(period) | ((uint32_t)(prescale) << 16) | ((uint32_t)(gpio) << 24))
#define TANGNANO20K_PWM_LED_CHANNELS  6
#define TANGNANO20K_PWM_GPIO_CHANNELS 4
/* PWM audio CTRL register: write bits. */
#define TANGNANO20K_PWM_AUDIO_CTRL_ENABLE (1UL << 0)
#define TANGNANO20K_PWM_AUDIO_CTRL_IRQEN  (1UL << 1) // FIFO at most half full
#define TANGNANO20K_PWM_AUDIO_CTRL_FLUSH  (1UL << 2)
/* PWM audio CTRL register: read bits. */
#define TANGNANO20K_PWM_AUDIO_STATUS_FREE(status) ((status) & 0x1FUL)
#define TANGNANO20K_PWM_AUDIO_STATUS_PRESENT      (1UL << 31)
#define TANGNANO20K_SPI_CS_ASSERT  (1UL << 0)
#define TANGNANO20K_I2C_SDA_LOW    (1UL << 0)
#define TANGNANO20K_I2C_SCL_LOW    (1UL << 1)

#define TANGNANO20K_NUM_LEDS 6
#define TANGNANO20K_GPIO_COUNT 21

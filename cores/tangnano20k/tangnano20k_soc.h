#pragma once

/* Memory map of the NanoTangArduino PicoRV32 SoC. Must match
 * gateware/src/top.v and gateware/src/sys_parameters.v. */

#include <stdint.h>

#define TANGNANO20K_CLK_FREQ 20000000UL

#define TANGNANO20K_LED_REG      (*(volatile uint32_t *)0x80000000UL)
#define TANGNANO20K_UART_DIV_REG (*(volatile uint32_t *)0x80000008UL)
#define TANGNANO20K_UART_DAT_REG (*(volatile uint32_t *)0x8000000CUL)
#define TANGNANO20K_SYSTICK_REG  (*(volatile uint32_t *)0x80000020UL)
#define TANGNANO20K_I2S_DIV_REG  (*(volatile uint32_t *)0x80000040UL)
#define TANGNANO20K_I2S_DAT_REG  (*(volatile uint32_t *)0x80000044UL)
#define TANGNANO20K_I2S_CTRL_REG (*(volatile uint32_t *)0x80000048UL)

#define TANGNANO20K_I2S_CTRL_PA_EN (1UL << 0)

#define TANGNANO20K_NUM_LEDS 6

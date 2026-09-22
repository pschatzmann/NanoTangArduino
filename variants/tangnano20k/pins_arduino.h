#pragma once

/* Pins 0-5 are the 6 onboard LEDs (support digitalWrite/digitalRead/
 * analogWrite). Pin 6 is the board's second button (KEY_S2), digitalRead
 * only. General GPIO header support is a future milestone - see docs/ROADMAP.md
 * roadmap. */

#define LED_BUILTIN 0
#define TANGNANO20K_PIN_KEY2 6

static const uint8_t LED0 = 0;
static const uint8_t LED1 = 1;
static const uint8_t LED2 = 2;
static const uint8_t LED3 = 3;
static const uint8_t LED4 = 4;
static const uint8_t LED5 = 5;
static const uint8_t BTN1 = TANGNANO20K_PIN_KEY2;

/* Virtual pins for the libraries/SD library (a real GPIO header doesn't
 * exist on this board - see docs/KNOWN_LIMITATIONS.md). SPI's hardware
 * chip-select is otherwise controlled internally by the SPI peripheral,
 * not via a free GPIO pin, so wiring_digital.cpp's digitalWrite()
 * special-cases pin SS to toggle it - this lets the unmodified,
 * vendored SD library's plain pinMode()/digitalWrite() calls on "SS"
 * work as it expects. MOSI/MISO/SCK are never actually driven through
 * digitalWrite() by the SD library when built against a real SPI class
 * (only SOFTWARE_SPI mode would, which this core doesn't use) - they
 * only need to exist as distinct pin numbers for it to compile. */
#define TANGNANO20K_PIN_SD_CS 10
static const uint8_t SS = TANGNANO20K_PIN_SD_CS;
static const uint8_t MOSI = 11;
static const uint8_t MISO = 12;
static const uint8_t SCK = 13;

/* General GPIO: 21 of the J5/J6 expansion header's 34 free I/O pins (per
 * the official Tang Nano 20K Datasheet v1.3 pinout table), numbered
 * 14-34. The other 13 header pins are the same physical nets as the LEDs
 * (0-5), I2S, I2C, and WS2812 above - this board ties those header
 * positions directly to those onboard functions, so they're reached
 * through those APIs, not through GPIOx. Unlike LEDs/BTN1,
 * pinMode(INPUT/OUTPUT) is real here (see wiring_digital.cpp). Several
 * double as the optional RGB LCD FPC connector or the HDMI EDID I2C bus
 * when those are in use - see docs/PERIPHERALS.md "General GPIO" for the
 * full table including physical FPGA pin numbers and shared-function
 * labels. */
#define TANGNANO20K_PIN_GPIO_BASE 14

static const uint8_t GPIO0 = TANGNANO20K_PIN_GPIO_BASE + 0;
static const uint8_t GPIO1 = TANGNANO20K_PIN_GPIO_BASE + 1;
static const uint8_t GPIO2 = TANGNANO20K_PIN_GPIO_BASE + 2;
static const uint8_t GPIO3 = TANGNANO20K_PIN_GPIO_BASE + 3;
static const uint8_t GPIO4 = TANGNANO20K_PIN_GPIO_BASE + 4;
static const uint8_t GPIO5 = TANGNANO20K_PIN_GPIO_BASE + 5;
static const uint8_t GPIO6 = TANGNANO20K_PIN_GPIO_BASE + 6;
static const uint8_t GPIO7 = TANGNANO20K_PIN_GPIO_BASE + 7;
static const uint8_t GPIO8 = TANGNANO20K_PIN_GPIO_BASE + 8;
static const uint8_t GPIO9 = TANGNANO20K_PIN_GPIO_BASE + 9;
static const uint8_t GPIO10 = TANGNANO20K_PIN_GPIO_BASE + 10;
static const uint8_t GPIO11 = TANGNANO20K_PIN_GPIO_BASE + 11;
static const uint8_t GPIO12 = TANGNANO20K_PIN_GPIO_BASE + 12;
static const uint8_t GPIO13 = TANGNANO20K_PIN_GPIO_BASE + 13;
static const uint8_t GPIO14 = TANGNANO20K_PIN_GPIO_BASE + 14;
static const uint8_t GPIO15 = TANGNANO20K_PIN_GPIO_BASE + 15;
static const uint8_t GPIO16 = TANGNANO20K_PIN_GPIO_BASE + 16;
static const uint8_t GPIO17 = TANGNANO20K_PIN_GPIO_BASE + 17;
static const uint8_t GPIO18 = TANGNANO20K_PIN_GPIO_BASE + 18;
static const uint8_t GPIO19 = TANGNANO20K_PIN_GPIO_BASE + 19;
static const uint8_t GPIO20 = TANGNANO20K_PIN_GPIO_BASE + 20;

/* attachInterrupt() takes a pin number directly on this core (like SAMD/
 * ESP32), not an old-style "interrupt number" - see wiring_irq.cpp. Only
 * the 21 GPIO pins and BTN1 support it; digitalPinToInterrupt() on any
 * other pin is harmless (attachInterrupt() silently ignores it). */
#define digitalPinToInterrupt(p) (p)

#pragma once

/* Pins 0-5 are the 6 onboard LEDs (support digitalWrite/digitalRead/
 * analogWrite). Pin 6 is the board's second button (KEY_S2), digitalRead
 * only. Pins 10-13 are virtual SPI pins (see below), and pins 14-34 are
 * the expansion header's general-purpose GPIO0-GPIO20. */

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
#define PIN_SPI_SS   SS
#define PIN_SPI_MOSI MOSI
#define PIN_SPI_MISO MISO
#define PIN_SPI_SCK  SCK

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

/* Board-level counts and capability checks that portable libraries test
 * for. Pin numbers run 0-34 (with 7-9 unused); there is no ADC. */
#define NUM_DIGITAL_PINS  (TANGNANO20K_PIN_GPIO_BASE + 21)
#define NUM_ANALOG_INPUTS 0
#define digitalPinHasPWM(p) \
  ((p) < 6 || ((p) >= TANGNANO20K_PIN_GPIO_BASE && (p) < NUM_DIGITAL_PINS))

/* Compile-time lookups between a GPIOx constant and the physical FPGA pin
 * number printed in the official Tang Nano 20K Datasheet v1.3 pinout
 * table (same numbers as docs/PERIPHERALS.md "General GPIO"), in both
 * directions. Both are ternary chains rather than real tables: with a
 * compile-time constant argument each folds down to a single constant,
 * same as any other macro, with no flash/runtime cost. Only defined for
 * the 21 GPIOx pins - LEDs/BTN1/SS/MOSI/MISO/SCK aren't real header pins
 * in this sense (see their own comments above).
 *
 * TANGNANO20K_PHYSICAL_PIN(GPIOn) -> physical pin, e.g.
 * TANGNANO20K_PHYSICAL_PIN(GPIO3) == 77. Any other GPIOn argument yields
 * 0. Useful for cross-checking code against the datasheet/schematic. */
#define TANGNANO20K_PHYSICAL_PIN(pin) \
  ((pin) == GPIO0  ? 73 : \
   (pin) == GPIO1  ? 74 : \
   (pin) == GPIO2  ? 75 : \
   (pin) == GPIO3  ? 77 : \
   (pin) == GPIO4  ? 27 : \
   (pin) == GPIO5  ? 28 : \
   (pin) == GPIO6  ? 25 : \
   (pin) == GPIO7  ? 26 : \
   (pin) == GPIO8  ? 29 : \
   (pin) == GPIO9  ? 30 : \
   (pin) == GPIO10 ? 31 : \
   (pin) == GPIO11 ? 76 : \
   (pin) == GPIO12 ? 42 : \
   (pin) == GPIO13 ? 41 : \
   (pin) == GPIO14 ? 48 : \
   (pin) == GPIO15 ? 49 : \
   (pin) == GPIO16 ? 86 : \
   (pin) == GPIO17 ? 72 : \
   (pin) == GPIO18 ? 71 : \
   (pin) == GPIO19 ? 53 : \
   (pin) == GPIO20 ? 52 : \
   0)

/* TANGNANO20K_GPIO_FOR_PIN(physPin) -> GPIOn, the inverse of
 * TANGNANO20K_PHYSICAL_PIN() above, e.g. TANGNANO20K_GPIO_FOR_PIN(77) ==
 * GPIO3 - useful when wiring against the datasheet/schematic and you know
 * the physical pin but want the GPIOx name to pass to
 * pinMode()/digitalWrite(). Any other physPin argument (including the
 * LED/I2S/I2C/etc. pins' own physical numbers, which aren't reachable as
 * GPIOx at all) yields 0xFF. */
#define TANGNANO20K_GPIO_FOR_PIN(physPin) \
  ((physPin) == 73 ? GPIO0  : \
   (physPin) == 74 ? GPIO1  : \
   (physPin) == 75 ? GPIO2  : \
   (physPin) == 77 ? GPIO3  : \
   (physPin) == 27 ? GPIO4  : \
   (physPin) == 28 ? GPIO5  : \
   (physPin) == 25 ? GPIO6  : \
   (physPin) == 26 ? GPIO7  : \
   (physPin) == 29 ? GPIO8  : \
   (physPin) == 30 ? GPIO9  : \
   (physPin) == 31 ? GPIO10 : \
   (physPin) == 76 ? GPIO11 : \
   (physPin) == 42 ? GPIO12 : \
   (physPin) == 41 ? GPIO13 : \
   (physPin) == 48 ? GPIO14 : \
   (physPin) == 49 ? GPIO15 : \
   (physPin) == 86 ? GPIO16 : \
   (physPin) == 72 ? GPIO17 : \
   (physPin) == 71 ? GPIO18 : \
   (physPin) == 53 ? GPIO19 : \
   (physPin) == 52 ? GPIO20 : \
   0xFF)

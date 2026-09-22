/* Flash memory layout, shared between C (tangnano20k_soc.h) and assembly
 * (boot.S) - kept in its own header, with no C-cast macros or standard
 * headers pulled in, because assembly files preprocess through cpp but
 * can't parse arbitrary C syntax (unlike a plain `#define NAME <number>`).
 * Kept in sync with tools/upload.py. See docs/PERIPHERALS.md "Flash".
 */
#pragma once

#define TANGNANO20K_FLASH_WINDOW_BASE      0x20000000
#define TANGNANO20K_FLASH_BITSTREAM_OFFSET 0x000000
#define TANGNANO20K_FLASH_PROGRAM_OFFSET   0x100000
#define TANGNANO20K_FLASH_DATA_OFFSET      0x110000

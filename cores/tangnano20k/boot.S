/* Fixed boot stub for Tools > Boot Mode: Flash (BOOT_FROM_FLASH) - see
 * gateware/src/top.v's PROGADDR_RESET `ifdef and docs/PERIPHERALS.md
 * "Flash". Baked into SRAM at a fixed address (0x380, see link_cmd.ld) as
 * part of the *core* - never part of a per-sketch compile. It copies the
 * sketch's actual program from a fixed flash offset into SRAM at 0x400
 * (exactly where startup.S's _start already runs from in the default
 * SRAM-boot mode too - nothing about the sketch's own linking changes),
 * then jumps there. Hand-written, no stack/C runtime needed - runs before
 * .bss is even cleared (startup.S does that immediately after, once
 * running from 0x400).
 *
 * Flash layout (kept in sync with tools/upload.py and
 * tangnano20k_soc.h's TANGNANO20K_FLASH_*_OFFSET macros): a 4-byte
 * little-endian program size at TANGNANO20K_FLASH_PROGRAM_OFFSET,
 * immediately followed by the program bytes themselves.
 */

#include "flash_layout.h"

	.section .text.boot
	.global _boot
	.balign 4
_boot:
	li   t0, TANGNANO20K_FLASH_WINDOW_BASE + TANGNANO20K_FLASH_PROGRAM_OFFSET
	lw   t1, 0(t0)          /* t1 = program size in bytes */
	addi t0, t0, 4          /* t0 = first program byte's flash address */
	li   t2, 0x400          /* t2 = SRAM destination address */
	add  t1, t1, t2         /* t1 = destination end address (dest + size) */

copy_loop:
	bge  t2, t1, copy_done
	lw   t3, 0(t0)
	sw   t3, 0(t2)
	addi t0, t0, 4
	addi t2, t2, 4
	j    copy_loop

copy_done:
	li   t0, 0x400
	jr   t0

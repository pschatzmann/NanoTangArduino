/* Thin C-callable wrappers around picorv32's custom-0 IRQ instructions
 * (see picorv32_custom_ops.S). Kept out of C/C++ entirely since there's no
 * portable way to emit raw custom-0 opcodes from inline asm on this
 * toolchain's assembler without the same risk irq_vec.S already avoided:
 * hand-deriving encodings. These reuse the same vendored, proven macros.
 */

#include "picorv32_custom_ops.S"

	.text

	/* uint32_t tangnano20k_set_irq_mask(uint32_t mask) - sets picorv32's
	 * maskable-IRQ mask to `mask` (1 bit = that IRQ line disabled),
	 * returns the previous mask. Used by interrupts()/noInterrupts(). */
	.global tangnano20k_set_irq_mask
tangnano20k_set_irq_mask:
	picorv32_maskirq_insn(a0, a0)
	ret

	/* void tangnano20k_set_timer(uint32_t ticks) - (re)arms picorv32's
	 * built-in one-shot countdown timer. ticks==0 disables it. Fires
	 * irq[0] (irq_timer) when the countdown reaches zero. */
	.global tangnano20k_set_timer
tangnano20k_set_timer:
	picorv32_timer_insn(zero, a0)
	ret

/* picorv32 interrupt entry point (PROGADDR_IRQ = 0x000, see link_cmd.ld
 * and top.v). Adapted from YosysHQ/picorv32's firmware/start.S
 * (public domain), the non-ENABLE_IRQ_QREGS register save/restore
 * sequence - this core uses ENABLE_IRQ_QREGS=0 (see gateware/src/top.v),
 * so x3 (gp) is picorv32's hardware-provided saved return PC on
 * interrupt entry and must be left untouched until the final `retirq`,
 * and x4 (tp) is the pending-IRQ bitmask, both picorv32 side effects of
 * entering interrupt state - see docs/PERIPHERALS.md "Interrupts".
 *
 * Calls tangnano20k_irq_dispatch(uint32_t *regs, uint32_t irqs) (see
 * wiring_irq.cpp) with regs[0] = the interrupted PC (a copy of x3) and
 * regs[1..31] = x1..x31 (x3 itself is not included; it's still live).
 * Called *indirectly* through the fixed irq_dispatch_ptr slot (0x280,
 * see link_cmd.ld) rather than a direct jal/call - a direct call's
 * machine code encodes the link-time PC-relative distance to
 * tangnano20k_irq_dispatch, which moves with every sketch, which would
 * make this file's own bytes sketch-dependent despite being part of the
 * fixed core image Tools > Boot Mode: Flash caches across sketches (see
 * build_bitstream.py). startup.S writes the real address into that slot
 * once, before interrupts can ever be unmasked.
 *
 * The register-save addresses below are hardcoded literal offsets from
 * `zero` (0x200+n*4), matching the official reference's own non-QREGS
 * design (it hardcodes 0x200 too, not derived from the irq_regs symbol) -
 * NOT a symbol-relative `la`/`addi` sequence, since every general-purpose
 * register is live at IRQ entry and there's no free one to hold a base
 * pointer before the first save. This means link_cmd.ld's `.text.irq`
 * output section MUST reserve at least up through 0x200 (it has a linker
 * ASSERT enforcing this) and `irq_regs` MUST be placed at exactly 0x200 -
 * this project previously had a real bug here (a hardcoded 0x100 assuming
 * `.text.irq` fit in 256 bytes, when RISC-V linker relaxation shrinks the
 * assembled code to a size the linker only knows after the fact, and the
 * real size didn't fit - silently corrupting the tail of this very
 * function's own code on every interrupt). 0x200 matches the same literal
 * the official reference uses, which already accounts for this.
 */

#include "picorv32_custom_ops.S"

	.section .text.irq
	.global irq_vec
	.balign 16
irq_vec:
	sw gp,   0*4+0x200(zero)  /* regs[0] = interrupted PC (copy of gp/x3) */
	sw x1,   1*4+0x200(zero)
	sw x2,   2*4+0x200(zero)
	/* x3 (gp) intentionally not saved to slot 3 - it must stay live for retirq */
	sw x4,   4*4+0x200(zero)
	sw x5,   5*4+0x200(zero)
	sw x6,   6*4+0x200(zero)
	sw x7,   7*4+0x200(zero)
	sw x8,   8*4+0x200(zero)
	sw x9,   9*4+0x200(zero)
	sw x10, 10*4+0x200(zero)
	sw x11, 11*4+0x200(zero)
	sw x12, 12*4+0x200(zero)
	sw x13, 13*4+0x200(zero)
	sw x14, 14*4+0x200(zero)
	sw x15, 15*4+0x200(zero)
	sw x16, 16*4+0x200(zero)
	sw x17, 17*4+0x200(zero)
	sw x18, 18*4+0x200(zero)
	sw x19, 19*4+0x200(zero)
	sw x20, 20*4+0x200(zero)
	sw x21, 21*4+0x200(zero)
	sw x22, 22*4+0x200(zero)
	sw x23, 23*4+0x200(zero)
	sw x24, 24*4+0x200(zero)
	sw x25, 25*4+0x200(zero)
	sw x26, 26*4+0x200(zero)
	sw x27, 27*4+0x200(zero)
	sw x28, 28*4+0x200(zero)
	sw x29, 29*4+0x200(zero)
	sw x30, 30*4+0x200(zero)
	sw x31, 31*4+0x200(zero)

	lui sp, %hi(irq_stack)
	addi sp, sp, %lo(irq_stack)

	lui a0, %hi(irq_regs)
	addi a0, a0, %lo(irq_regs)
	addi a1, tp, 0          /* a1 = pending IRQ bitmask (live in tp/x4) */

	lw a2, 0x280(zero)      /* a2 = irq_dispatch_ptr's value (see link_cmd.ld/startup.S) */
	jalr ra, a2, 0

	lw gp,   0*4+0x200(zero)  /* restore gp/x3's saved-PC copy back into x3 */
	lw x1,   1*4+0x200(zero)
	lw x2,   2*4+0x200(zero)
	lw x4,   4*4+0x200(zero)
	lw x5,   5*4+0x200(zero)
	lw x6,   6*4+0x200(zero)
	lw x7,   7*4+0x200(zero)
	lw x8,   8*4+0x200(zero)
	lw x9,   9*4+0x200(zero)
	lw x10, 10*4+0x200(zero)
	lw x11, 11*4+0x200(zero)
	lw x12, 12*4+0x200(zero)
	lw x13, 13*4+0x200(zero)
	lw x14, 14*4+0x200(zero)
	lw x15, 15*4+0x200(zero)
	lw x16, 16*4+0x200(zero)
	lw x17, 17*4+0x200(zero)
	lw x18, 18*4+0x200(zero)
	lw x19, 19*4+0x200(zero)
	lw x20, 20*4+0x200(zero)
	lw x21, 21*4+0x200(zero)
	lw x22, 22*4+0x200(zero)
	lw x23, 23*4+0x200(zero)
	lw x24, 24*4+0x200(zero)
	lw x25, 25*4+0x200(zero)
	lw x26, 26*4+0x200(zero)
	lw x27, 27*4+0x200(zero)
	lw x28, 28*4+0x200(zero)
	lw x29, 29*4+0x200(zero)
	lw x30, 30*4+0x200(zero)
	lw x31, 31*4+0x200(zero)

	picorv32_retirq_insn()

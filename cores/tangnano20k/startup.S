/* Startup for the arduino-tangnano20k PicoRV32 core.
 * Unlike the reference project's startup.s, this clears .bss and runs
 * C++ global constructors before calling main(), since the Arduino core
 * relies on global objects (e.g. the Serial instance).
 */

.section .text.start
.global _start
_start:
	la   sp, __stack_top

	/* Clear .bss */
	la   a0, __bss_start
	la   a1, __bss_end
clear_bss:
	bge  a0, a1, clear_bss_done
	sw   zero, 0(a0)
	addi a0, a0, 4
	j    clear_bss
clear_bss_done:

	/* Write this sketch's tangnano20k_irq_dispatch address into the fixed
	 * irq_dispatch_ptr slot irq_vec.S calls through indirectly (see that
	 * file and link_cmd.ld) - must happen before interrupts can ever be
	 * unmasked, so before ctors run. */
	la   a0, tangnano20k_irq_dispatch
	sw   a0, 0x280(zero)

	/* Run global constructors (C++ static init). The loop state lives in
	 * s0/s1, which the calling convention preserves across calls - an
	 * earlier version used a0/a1, which any constructor may clobber, so
	 * with more than one constructor the loop jumped to garbage before
	 * main() (found on real hardware: any sketch using SD hung). */
	la   s0, __init_array_start
	la   s1, __init_array_end
run_ctors:
	bgeu s0, s1, run_ctors_done
	lw   a2, 0(s0)
	jalr ra, a2, 0
	addi s0, s0, 4
	j    run_ctors
run_ctors_done:

	call main

hang:
	j    hang

/* Startup for the arduino-tangnano20k PicoRV32 core.
 * Unlike the reference project's startup.s, this clears .bss and runs
 * C++ global constructors before calling main(), since the Arduino core
 * relies on global objects (e.g. the Serial instance).
 */

.section .text.start
.global _start
_start:
	la   sp, __stack_top

	/* Tools > Boot Mode: ... + SDRAM (link_cmd_sdram.ld) - copy the
	 * code/constants image from the flash data partition into SDRAM
	 * before anything can call into it (constructors may live there).
	 * Empty (start == end) with the default link_cmd.ld. */
	la   a0, __sdram_img_start
	la   a1, __sdram_img_end
	beq  a0, a1, sdram_copy_done
	/* sdram.v ignores requests during its 200us power-on delay instead
	 * of stalling them, so first wait for the free-running micros
	 * counter (systick.v, reset together with the CPU) to pass that. */
	li   t0, 0x80000024
	li   t1, 300
wait_sdram:
	lw   t2, 0(t0)
	bltu t2, t1, wait_sdram
	la   a2, __sdram_img_load
copy_sdram:
	lw   t0, 0(a2)
	sw   t0, 0(a0)
	addi a0, a0, 4
	addi a2, a2, 4
	bltu a0, a1, copy_sdram
sdram_copy_done:

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

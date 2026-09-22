/* Linker script for the NanoTangArduino PicoRV32 SoC.
 * Must match gateware/src/sys_parameters.v (SRAM_ADDR_WIDTH=13 -> 32KB). */
MEMORY
{
  SRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 32K
}

ENTRY(_start)

SECTIONS
{
  .text : {
    *(.text.start)
    *(.text .text.*)
  } > SRAM

  .rodata : {
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
  } > SRAM

  .init_array : {
    __init_array_start = .;
    KEEP(*(.init_array))
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
    __init_array_end = .;
  } > SRAM

  .data : {
    *(.data .data.*)
    *(.sdata .sdata.*)
  } > SRAM

  .bss (NOLOAD) : {
    __bss_start = .;
    *(.bss .bss.*)
    *(.sbss .sbss.*)
    *(COMMON)
    __bss_end = .;
  } > SRAM

  . = ALIGN(16);
  __heap_start = .;
  __stack_top = ORIGIN(SRAM) + LENGTH(SRAM);

  _end = .;
}

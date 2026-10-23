/* =============================================================================
 * MiniSoC-32 Linker Script
 * IROM: 0x0000_0000  4 KB   (text + rodata)
 * DRAM: 0x0001_0000  4 KB   (data + bss + stack)
 * ============================================================================= */

MEMORY {
    IROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    DRAM (rwx) : ORIGIN = 0x00010000, LENGTH = 1K
}

ENTRY(_start)

SECTIONS {
    .text : {
        KEEP(*(.text.startup))
        *(.text .text.*)
        *(.rodata .rodata.*)
        . = ALIGN(4);
        _etext = .;
    } > IROM

    .data : AT(_etext) {
        _sdata = .;
        *(.data .data.*)
        . = ALIGN(4);
        _edata = .;
    } > DRAM

    .bss : {
        _sbss = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > DRAM

    /* Stack grows downward from top of DRAM */
    _stack_top = ORIGIN(DRAM) + LENGTH(DRAM);
}

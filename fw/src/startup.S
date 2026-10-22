/* =============================================================================
 * MiniSoC-32 — startup.S
 * Reset vector at 0x0000_0000.  Performs:
 *   1. Set stack pointer to top of DRAM
 *   2. Copy .data from ROM to RAM
 *   3. Zero .bss
 *   4. Set mtvec to interrupt handler
 *   5. Call main()
 *   6. Spin forever on return
 * ============================================================================= */
    .section .text.startup
    .global  _start
    .type    _start, @function

_start:
    /* ---- 1. Stack pointer ---- */
    la   sp, _stack_top

    /* ---- 2. Copy .data section (LMA → VMA) ---- */
    la   a0, _etext          /* source (LMA) */
    la   a1, _sdata          /* dest   (VMA) */
    la   a2, _edata
.Lcopy_data:
    bge  a1, a2, .Lzero_bss
    lw   t0, 0(a0)
    sw   t0, 0(a1)
    addi a0, a0, 4
    addi a1, a1, 4
    j    .Lcopy_data

    /* ---- 3. Zero .bss ---- */
.Lzero_bss:
    la   a0, _sbss
    la   a1, _ebss
.Lzero_loop:
    bge  a0, a1, .Lmain
    sw   zero, 0(a0)
    addi a0, a0, 4
    j    .Lzero_loop

    /* ---- 4. Set mtvec (trap vector) ---- */
.Lmain:
    la   t0, _isr_entry
    csrw mtvec, t0

    /* ---- 5. Call main ---- */
    call main

    /* ---- 6. Spin forever ---- */
.Lhalt:
    j    .Lhalt

/* -----------------------------------------------------------------------
 * Interrupt/exception entry point.
 * Minimal: save ra, call isr_handler, restore ra, mret.
 * ----------------------------------------------------------------------- */
    .global _isr_entry
    .align  4
_isr_entry:
    addi sp, sp, -64
    sw   ra,  0(sp)
    sw   t0,  4(sp)
    sw   t1,  8(sp)
    sw   t2, 12(sp)
    sw   a0, 16(sp)
    sw   a1, 20(sp)
    sw   a2, 24(sp)
    sw   a3, 28(sp)
    sw   a4, 32(sp)
    sw   a5, 36(sp)
    sw   a6, 40(sp)
    sw   a7, 44(sp)
    sw   t3, 48(sp)
    sw   t4, 52(sp)
    sw   t5, 56(sp)
    sw   t6, 60(sp)

    call isr_handler      /* defined in main.c */

    lw   ra,  0(sp)
    lw   t0,  4(sp)
    lw   t1,  8(sp)
    lw   t2, 12(sp)
    lw   a0, 16(sp)
    lw   a1, 20(sp)
    lw   a2, 24(sp)
    lw   a3, 28(sp)
    lw   a4, 32(sp)
    lw   a5, 36(sp)
    lw   a6, 40(sp)
    lw   a7, 44(sp)
    lw   t3, 48(sp)
    lw   t4, 52(sp)
    lw   t5, 56(sp)
    lw   t6, 60(sp)
    addi sp, sp,  64
    mret

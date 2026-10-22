/* =============================================================================
 * MiniSoC-32 — System Test Firmware (sys_test.S)
 * Exercises UART, SPI, GPIO, and Timer Interrupt via Wishbone interconnect.
 * ============================================================================= */
    .section .text.startup
    .global _start
    .type _start, @function

_start:
    /* Stack pointer init */
    li   sp, 0x00011000

    /* Set trap vector */
    la   t0, _isr
    csrw mtvec, t0

    /* -------------------------------------------------------------------------
     * 1. Test GPIO: DIR=0xF0 (high 4 out, low 4 in), OUT=0x50
     * ------------------------------------------------------------------------- */
    li   s0, 0x00040000        /* GPIO_BASE */
    li   t1, 0xF0
    sw   t1, 0(s0)             /* GPIO_DIR */
    li   t1, 0x50
    sw   t1, 4(s0)             /* GPIO_OUT */

    /* Wait a moment and read GPIO_IN (testbench drives 0x0A on low nibble) */
    li   t3, 0x0A
.Lwait_gpio:
    lw   t2, 8(s0)             /* GPIO_IN */
    andi t2, t2, 0x0F
    bne  t2, t3, .Lwait_gpio

    /* -------------------------------------------------------------------------
     * 2. Test UART: send character 'A' (0x41)
     * ------------------------------------------------------------------------- */
    li   s1, 0x00020000        /* UART_BASE */
    li   t1, 2
    sw   t1, 12(s1)            /* UART_CTRL (baud_div = 2 for fast sim) */
    li   t1, 0x41              /* 'A' */
    sw   t1, 0(s1)             /* UART_TXD */

    /* -------------------------------------------------------------------------
     * 3. Test SPI: send 0xA5, expect 0x5A from slave
     * ------------------------------------------------------------------------- */
    li   s2, 0x00030000        /* SPI_BASE */
    li   t1, 2
    sw   t1, 12(s2)            /* SPI_CTRL (clk_div = 2) */
    li   t1, 0xFE
    sw   t1, 16(s2)            /* SPI_CS (active low CS[0]) */
    li   t1, 0xA5
    sw   t1, 0(s2)             /* SPI_TXD (start transfer) */

.Lwait_spi:
    lw   t1, 8(s2)             /* SPI_STAT */
    andi t1, t1, 1             /* idle bit */
    beqz t1, .Lwait_spi

    li   t1, 0xFF
    sw   t1, 16(s2)            /* deassert CS */
    lw   t2, 4(s2)             /* SPI_RXD */
    li   t3, 0x5A
    bne  t2, t3, _fail

    /* -------------------------------------------------------------------------
     * 4. Test Timer IRQ: set CMP=20, enable timer & interrupt
     * ------------------------------------------------------------------------- */
    li   s3, 0x00050000        /* TIMER_BASE */
    li   s4, 0                 /* IRQ flag in s4 */
    li   t1, 0
    sw   t1, 0(s3)             /* TIMER_CNT = 0 */
    li   t1, 20
    sw   t1, 4(s3)             /* TIMER_CMP = 20 */
    li   t1, 7                 /* en + irq_en + reload */
    sw   t1, 8(s3)             /* TIMER_CTRL */

    /* Enable interrupts in CPU */
    li   t1, 0x80              /* MTIE */
    csrw mie, t1
    li   t1, 0x08              /* MIE */
    csrs mstatus, t1

.Lwait_timer:
    beqz s4, .Lwait_timer

    /* Disable timer */
    sw   zero, 8(s3)

    /* -------------------------------------------------------------------------
     * 5. Success! Write 0xCAFEBABE to DRAM[0] and 0xFF to GPIO_OUT
     * ------------------------------------------------------------------------- */
    li   s5, 0x00010000        /* DRAM_BASE */
    li   t0, 0xCAFEBABE
    sw   t0, 0(s5)

    li   t1, 0xFF
    sw   t1, 0(s0)             /* GPIO_DIR = all out */
    sw   t1, 4(s0)             /* GPIO_OUT = 0xFF (signals success to TB) */

.Lhalt:
    j    .Lhalt

_fail:
    li   t1, 0xEE
    sw   t1, 4(s0)             /* GPIO_OUT = 0xEE (fail) */
.Lfail_loop:
    j    .Lfail_loop

/* -------------------------------------------------------------------------
 * Trap handler: clear timer irq, increment s4, MRET
 * ------------------------------------------------------------------------- */
    .align 4
_isr:
    li   t0, 0x00050000
    li   t1, 1
    sw   t1, 12(t0)            /* TIMER_STAT W1C clear */
    addi s4, s4, 1             /* mark irq received */
    mret

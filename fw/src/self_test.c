/* =============================================================================
 * MiniSoC-32 Demo 5: Comprehensive Self-Test
 * Exercises all peripherals: DRAM, GPIO, Timer + IRQ, SPI, UART.
 * Prints PASS upon successful completion.
 * ============================================================================= */
#include "minisoc.h"

volatile uint32_t isr_invocations = 0;

void isr_handler(void) {
    if (TIMER_STAT & TIMER_STAT_IRQ_PEND) {
        timer_clear_irq();
        isr_invocations++;
    }
}

int main(void) {
    int errors = 0;

    /* 1. UART Init */
    uart_init(8);
    uart_puts("\r\n=== MiniSoC-32 System Self-Test ===\r\n");

    /* 2. DRAM read/write test */
    uart_puts("[TEST] DRAM: ");
    volatile uint32_t *dram_ptr = (volatile uint32_t *)0x00010800UL;
    *dram_ptr = 0xCAFEBABE;
    if (*dram_ptr != 0xCAFEBABE) {
        uart_puts("FAIL\r\n");
        errors++;
    } else {
        uart_puts("OK\r\n");
    }

    /* 3. GPIO test */
    uart_puts("[TEST] GPIO: ");
    gpio_set_dir(0xFF);
    gpio_write(0x5A);
    if (gpio_read_out() != 0x5A) {
        uart_puts("FAIL\r\n");
        errors++;
    } else {
        uart_puts("OK\r\n");
    }

    /* 4. Timer & Interrupt test */
    uart_puts("[TEST] Timer IRQ: ");
    timer_init(120, TIMER_CTRL_EN | TIMER_CTRL_IRQ_EN | TIMER_CTRL_RELOAD);
    CSR_WRITE(mie, 1u << 7); /* MTIE */
    irq_enable();

    /* Wait for 2 timer interrupts */
    uint32_t timeout = 5000;
    while (isr_invocations < 2 && --timeout) {}

    irq_disable();
    timer_stop();

    if (isr_invocations < 2) {
        uart_puts("FAIL\r\n");
        errors++;
    } else {
        uart_puts("OK\r\n");
    }

    /* 5. SPI Master test */
    uart_puts("[TEST] SPI Master: ");
    spi_init(2);
    spi_select(0xFE); /* select slave 0 */
    uint8_t spi_rx = spi_transfer(0x55);
    spi_deselect();

    /* Any valid transaction completes with idle flag set */
    if (!(SPI_STAT & SPI_STAT_IDLE)) {
        uart_puts("FAIL\r\n");
        errors++;
    } else {
        uart_puts("OK (rx=0x");
        const char hex[] = "0123456789ABCDEF";
        uart_putc(hex[(spi_rx >> 4) & 0xF]);
        uart_putc(hex[spi_rx & 0xF]);
        uart_puts(")\r\n");
    }

    /* Final Result */
    if (errors == 0) {
        gpio_write(0xFF); /* Signal success on hardware pins */
        uart_puts("\r\n================================\r\n");
        uart_puts("ALL TESTS PASSED\r\n");
        uart_puts("PASS\r\n");
        uart_puts("================================\r\n");
    } else {
        gpio_write(0xEE); /* Signal failure */
        uart_puts("\r\nFAIL: Errors detected in self-test\r\n");
    }

    return 0;
}

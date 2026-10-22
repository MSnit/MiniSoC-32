/* =============================================================================
 * MiniSoC-32 Demo 4: Timer Interrupt Handler Test
 * ============================================================================= */
#include "minisoc.h"

volatile uint32_t irq_count = 0;

void isr_handler(void) {
    if (TIMER_STAT & TIMER_STAT_IRQ_PEND) {
        timer_clear_irq();
        irq_count++;
    }
}

int main(void) {
    uart_init(8);
    uart_puts("Demo 4: Timer IRQ Test\r\n");

    /* Configure timer: auto-reload every 150 cycles, interrupt enabled */
    timer_init(150, TIMER_CTRL_EN | TIMER_CTRL_IRQ_EN | TIMER_CTRL_RELOAD);

    /* Enable machine timer interrupt in CPU CSR */
    CSR_WRITE(mie, 1u << 7); /* MTIE */
    irq_enable();

    /* Wait for 3 interrupts */
    while (irq_count < 3) {}

    /* Disable interrupts */
    irq_disable();
    timer_stop();

    uart_puts("Timer IRQ verified: 3 ticks received!\r\n");
    return 0;
}

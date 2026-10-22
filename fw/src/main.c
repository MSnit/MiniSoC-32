/* =============================================================================
 * MiniSoC-32 — main.c  (example firmware)
 * Exercises all peripherals: GPIO blink, UART print, SPI loopback, Timer IRQ.
 * ============================================================================= */
#include "minisoc.h"

/* ---- UART helper ---------------------------------------------------------- */
static void uart_putc(char c) {
    while (!(UART_STAT & UART_STAT_TX_IDLE)) {}
    UART_TXD = (uint32_t)c;
}

static void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

/* ---- Timer ISR ------------------------------------------------------------ */
volatile uint32_t timer_ticks = 0;

void isr_handler(void) {
    if (TIMER_STAT & TIMER_STAT_IRQ_PEND) {
        TIMER_STAT = TIMER_STAT_IRQ_PEND;   /* clear by writing 1 */
        timer_ticks++;
    }
}

/* ---- Main ----------------------------------------------------------------- */
int main(void) {
    /* Configure UART: baud divisor for 115200 @ 50 MHz → 50e6/(16*115200) ≈ 27 */
    UART_CTRL = 27;

    uart_puts("MiniSoC-32 boot OK\r\n");

    /* GPIO: all outputs, blink pattern */
    GPIO_DIR = 0xFF;
    GPIO_OUT = 0xAA;

    /* Timer: fire every 50 000 cycles (1 ms @ 50 MHz) */
    TIMER_CMP  = 50000 - 1;
    TIMER_CNT  = 0;
    TIMER_CTRL = TIMER_CTRL_EN | TIMER_CTRL_IRQ_EN | TIMER_CTRL_RELOAD;

    /* Enable machine timer interrupt */
    CSR_WRITE(mie, 1u << 7);   /* MTIE */
    irq_enable();

    uint32_t last_tick = 0;
    while (1) {
        if (timer_ticks != last_tick) {
            last_tick = timer_ticks;
            /* Toggle GPIO every tick */
            GPIO_OUT ^= 0xFF;
            if ((timer_ticks & 0xFF) == 0) {
                uart_puts("tick\r\n");
            }
        }
    }
    return 0;
}

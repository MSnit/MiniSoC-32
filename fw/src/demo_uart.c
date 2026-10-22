/* =============================================================================
 * MiniSoC-32 Demo 2: UART "Hello SoC" print plus echo
 * ============================================================================= */
#include "minisoc.h"

void isr_handler(void) {
}

int main(void) {
    /* Initialize UART with fast divisor for testbench */
    uart_init(8);

    uart_puts("Hello SoC\r\n");
    uart_puts("Echo mode active:\r\n");

    /* Echo received characters */
    int count = 0;
    while (count < 5) {
        if (uart_rx_ready()) {
            char c = uart_getc();
            uart_putc('[');
            uart_putc(c);
            uart_putc(']');
            count++;
        }
    }

    uart_puts("\r\nEcho test done\r\n");
    return 0;
}

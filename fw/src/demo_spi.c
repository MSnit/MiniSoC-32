/* =============================================================================
 * MiniSoC-32 Demo 3: SPI read/write to model slave
 * ============================================================================= */
#include "minisoc.h"

void isr_handler(void) {
}

int main(void) {
    uart_init(8);
    uart_puts("Demo 3: SPI Master\r\n");

    /* Initialize SPI: clk_div = 2 */
    spi_init(2);

    /* Assert CS[0] (active low) */
    spi_select(0xFE);

    /* Transfer bytes to slave */
    uint8_t tx_bytes[] = {0xA5, 0x5A, 0x12, 0x34};
    uint8_t rx_bytes[4];

    for (int i = 0; i < 4; i++) {
        rx_bytes[i] = spi_transfer(tx_bytes[i]);
    }

    /* Deassert CS */
    spi_deselect();

    uart_puts("SPI transfer finished: ");
    for (int i = 0; i < 4; i++) {
        uart_putc('0');
        uart_putc('x');
        const char hex[] = "0123456789ABCDEF";
        uart_putc(hex[(rx_bytes[i] >> 4) & 0xF]);
        uart_putc(hex[rx_bytes[i] & 0xF]);
        uart_putc(' ');
    }
    uart_puts("\r\n");

    return 0;
}

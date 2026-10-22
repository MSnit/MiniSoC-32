/* =============================================================================
 * MiniSoC-32 Demo 1: GPIO LED Blink using Timer
 * ============================================================================= */
#include "minisoc.h"

void isr_handler(void) {
    /* Unused in polling blink */
}

int main(void) {
    /* Initialize UART for status */
    uart_init(8);
    uart_puts("Demo 1: GPIO Blink with Timer\r\n");

    /* Configure GPIO: all 8 pins as outputs */
    gpio_set_dir(0xFF);
    gpio_write(0x00);

    /* Configure timer: free running, no IRQ */
    timer_init(0xFFFFFFFF, TIMER_CTRL_EN);

    /* Blink 10 times then exit */
    uint8_t state = 0xAA;
    for (int i = 0; i < 10; i++) {
        gpio_write(state);
        uart_putc('.');
        timer_delay(200); /* 200 cycles per step */
        state = ~state;
    }

    gpio_write(0xFF); /* finish pattern */
    uart_puts("\r\nBlink Complete!\r\n");
    return 0;
}

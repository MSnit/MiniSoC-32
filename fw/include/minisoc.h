/* =============================================================================
 * MiniSoC-32 Firmware — Memory-Mapped Register Definitions & Peripheral Drivers
 * ============================================================================= */
#ifndef MINISOC_H
#define MINISOC_H

#include <stdint.h>

/* ---- Helper macros -------------------------------------------------------- */
#define _REG(addr)        (*(volatile uint32_t *)(addr))
#define _REG8(addr)       (*(volatile uint8_t  *)(addr))

/* ---- UART  (0x0002_0000) -------------------------------------------------- */
#define UART_BASE         0x00020000UL
#define UART_TXD          _REG(UART_BASE + 0x00)   /* W   : transmit byte      */
#define UART_RXD          _REG(UART_BASE + 0x04)   /* R   : receive byte       */
#define UART_STAT         _REG(UART_BASE + 0x08)   /* R   : [1]=tx_idle [0]=rx_ready */
#define UART_CTRL         _REG(UART_BASE + 0x0C)   /* R/W : baud divisor[15:0] */

#define UART_STAT_TX_IDLE (1u << 1)
#define UART_STAT_RX_RDY  (1u << 0)

/* ---- SPI Master (0x0003_0000) --------------------------------------------- */
#define SPI_BASE          0x00030000UL
#define SPI_TXD           _REG(SPI_BASE + 0x00)    /* W   : start transfer     */
#define SPI_RXD           _REG(SPI_BASE + 0x04)    /* R   : received byte      */
#define SPI_STAT          _REG(SPI_BASE + 0x08)    /* R   : [0]=idle           */
#define SPI_CTRL          _REG(SPI_BASE + 0x0C)    /* R/W : clock divider[7:0] */
#define SPI_CS            _REG(SPI_BASE + 0x10)    /* R/W : chip select[7:0]   */

#define SPI_STAT_IDLE     (1u << 0)

/* ---- GPIO   (0x0004_0000) -------------------------------------------------- */
#define GPIO_BASE         0x00040000UL
#define GPIO_DIR          _REG(GPIO_BASE + 0x00)   /* R/W : 1=output, 0=input  */
#define GPIO_OUT          _REG(GPIO_BASE + 0x04)   /* R/W : output data        */
#define GPIO_IN           _REG(GPIO_BASE + 0x08)   /* R   : input pins         */

/* ---- Timer  (0x0005_0000) -------------------------------------------------- */
#define TIMER_BASE        0x00050000UL
#define TIMER_CNT         _REG(TIMER_BASE + 0x00)  /* R/W : counter            */
#define TIMER_CMP         _REG(TIMER_BASE + 0x04)  /* R/W : compare value      */
#define TIMER_CTRL        _REG(TIMER_BASE + 0x08)  /* R/W : [0]=en [1]=irq_en [2]=reload */
#define TIMER_STAT        _REG(TIMER_BASE + 0x0C)  /* R/W1C: [0]=irq_pending   */

#define TIMER_CTRL_EN         (1u << 0)
#define TIMER_CTRL_IRQ_EN     (1u << 1)
#define TIMER_CTRL_RELOAD     (1u << 2)
#define TIMER_STAT_IRQ_PEND   (1u << 0)

/* ---- CSR helpers (inline asm) ---------------------------------------------- */
#define CSR_READ(csr)   ({ uint32_t _v; asm volatile("csrr %0," #csr : "=r"(_v)); _v; })
#define CSR_WRITE(csr, v) asm volatile("csrw " #csr ", %0" :: "r"((uint32_t)(v)))
#define CSR_SET(csr, v)   asm volatile("csrs " #csr ", %0" :: "r"((uint32_t)(v)))
#define CSR_CLR(csr, v)   asm volatile("csrc " #csr ", %0" :: "r"((uint32_t)(v)))

/* Global machine interrupt enable / disable */
#define irq_enable()   CSR_SET(mstatus, 0x8)
#define irq_disable()  CSR_CLR(mstatus, 0x8)

/* ---- Driver Functions ------------------------------------------------------ */

/* UART */
static inline void uart_init(uint16_t baud_div) {
    UART_CTRL = baud_div;
}

static inline void uart_putc(char c) {
    while (!(UART_STAT & UART_STAT_TX_IDLE)) {}
    UART_TXD = (uint32_t)(uint8_t)c;
}

static inline void uart_puts(const char *s) {
    while (*s) {
        uart_putc(*s++);
    }
}

static inline int uart_rx_ready(void) {
    return (UART_STAT & UART_STAT_RX_RDY) != 0;
}

static inline char uart_getc(void) {
    while (!uart_rx_ready()) {}
    return (char)(UART_RXD & 0xFF);
}

/* GPIO */
static inline void gpio_set_dir(uint8_t dir) {
    GPIO_DIR = dir;
}

static inline void gpio_write(uint8_t val) {
    GPIO_OUT = val;
}

static inline uint8_t gpio_read(void) {
    return (uint8_t)(GPIO_IN & 0xFF);
}

static inline uint8_t gpio_read_out(void) {
    return (uint8_t)(GPIO_OUT & 0xFF);
}

/* Timer */
static inline void timer_init(uint32_t cmp, uint32_t ctrl) {
    TIMER_CTRL = 0;
    TIMER_CNT  = 0;
    TIMER_CMP  = cmp;
    TIMER_STAT = TIMER_STAT_IRQ_PEND; /* clear any pending */
    TIMER_CTRL = ctrl;
}

static inline void timer_stop(void) {
    TIMER_CTRL = 0;
}

static inline uint32_t timer_read(void) {
    return TIMER_CNT;
}

static inline void timer_clear_irq(void) {
    TIMER_STAT = TIMER_STAT_IRQ_PEND;
}

/* Delay in timer cycles */
static inline void timer_delay(uint32_t cycles) {
    uint32_t start = TIMER_CNT;
    while ((TIMER_CNT - start) < cycles) {}
}

/* SPI */
static inline void spi_init(uint8_t clk_div) {
    SPI_CTRL = clk_div;
    SPI_CS   = 0xFF; /* all inactive */
}

static inline void spi_select(uint8_t cs_mask) {
    SPI_CS = cs_mask;
}

static inline void spi_deselect(void) {
    SPI_CS = 0xFF;
}

static inline uint8_t spi_transfer(uint8_t data) {
    while (!(SPI_STAT & SPI_STAT_IDLE)) {}
    SPI_TXD = data;
    while (!(SPI_STAT & SPI_STAT_IDLE)) {}
    return (uint8_t)(SPI_RXD & 0xFF);
}

#endif /* MINISOC_H */

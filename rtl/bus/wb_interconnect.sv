// =============================================================================
// Module:      wb_interconnect
// Description: Wishbone B4 address decoder and 1-master / 6-slave interconnect.
//              Decodes on bits [27:12] of the address as per ARCHITECTURE.md.
//              Generates wb_err for unmapped accesses.
// Memory map:
//   0x0000_0000 – 0x0000_0FFF : IROM
//   0x0001_0000 – 0x0001_0FFF : DRAM
//   0x0002_0000 – 0x0002_00FF : UART
//   0x0003_0000 – 0x0003_00FF : SPI
//   0x0004_0000 – 0x0004_00FF : GPIO
//   0x0005_0000 – 0x0005_00FF : TIMER
// =============================================================================
/* verilator lint_off UNUSEDSIGNAL */
module wb_interconnect (
    input  logic        clk,
    input  logic        rst_n,

    // --- Master interface ---
    input  logic [31:0] m_wb_adr,
    input  logic [31:0] m_wb_dat_o,   // master write data
    input  logic        m_wb_we,
    input  logic [3:0]  m_wb_sel,
    input  logic        m_wb_stb,
    input  logic        m_wb_cyc,
    output logic [31:0] m_wb_dat_i,   // master read data
    output logic        m_wb_ack,
    output logic        m_wb_err,

    // --- IROM slave ---
    output logic [31:0] irom_wb_adr,
    output logic [31:0] irom_wb_dat_o,
    output logic        irom_wb_we,
    output logic [3:0]  irom_wb_sel,
    output logic        irom_wb_stb,
    output logic        irom_wb_cyc,
    input  logic [31:0] irom_wb_dat_i,
    input  logic        irom_wb_ack,

    // --- DRAM slave ---
    output logic [31:0] dram_wb_adr,
    output logic [31:0] dram_wb_dat_o,
    output logic        dram_wb_we,
    output logic [3:0]  dram_wb_sel,
    output logic        dram_wb_stb,
    output logic        dram_wb_cyc,
    input  logic [31:0] dram_wb_dat_i,
    input  logic        dram_wb_ack,

    // --- UART slave ---
    output logic [31:0] uart_wb_adr,
    output logic [31:0] uart_wb_dat_o,
    output logic        uart_wb_we,
    output logic [3:0]  uart_wb_sel,
    output logic        uart_wb_stb,
    output logic        uart_wb_cyc,
    input  logic [31:0] uart_wb_dat_i,
    input  logic        uart_wb_ack,

    // --- SPI slave ---
    output logic [31:0] spi_wb_adr,
    output logic [31:0] spi_wb_dat_o,
    output logic        spi_wb_we,
    output logic [3:0]  spi_wb_sel,
    output logic        spi_wb_stb,
    output logic        spi_wb_cyc,
    input  logic [31:0] spi_wb_dat_i,
    input  logic        spi_wb_ack,

    // --- GPIO slave ---
    output logic [31:0] gpio_wb_adr,
    output logic [31:0] gpio_wb_dat_o,
    output logic        gpio_wb_we,
    output logic [3:0]  gpio_wb_sel,
    output logic        gpio_wb_stb,
    output logic        gpio_wb_cyc,
    input  logic [31:0] gpio_wb_dat_i,
    input  logic        gpio_wb_ack,

    // --- TIMER slave ---
    output logic [31:0] timer_wb_adr,
    output logic [31:0] timer_wb_dat_o,
    output logic        timer_wb_we,
    output logic [3:0]  timer_wb_sel,
    output logic        timer_wb_stb,
    output logic        timer_wb_cyc,
    input  logic [31:0] timer_wb_dat_i,
    input  logic        timer_wb_ack
);

    // -------------------------------------------------------------------------
    // Address decode: bits [27:12]
    // -------------------------------------------------------------------------
    logic sel_irom, sel_dram, sel_uart, sel_spi, sel_gpio, sel_timer;
    logic sel_none;

    // Extract region bits [23:16] — one byte selects which peripheral.
    // Memory map uses 0x00XX_0000 addressing so bits [23:16] give the slave index.
    // IROM=0x00, DRAM=0x01, UART=0x02, SPI=0x03, GPIO=0x04, TIMER=0x05
    logic [7:0] region;
    assign region = m_wb_adr[23:16];

    always_comb begin
        sel_irom  = 1'b0;
        sel_dram  = 1'b0;
        sel_uart  = 1'b0;
        sel_spi   = 1'b0;
        sel_gpio  = 1'b0;
        sel_timer = 1'b0;

        case (region)
            8'h00: sel_irom  = 1'b1;
            8'h01: sel_dram  = 1'b1;
            8'h02: sel_uart  = 1'b1;
            8'h03: sel_spi   = 1'b1;
            8'h04: sel_gpio  = 1'b1;
            8'h05: sel_timer = 1'b1;
            default: ; // no slave selected → bus error
        endcase
    end

    assign sel_none = ~(sel_irom | sel_dram | sel_uart | sel_spi | sel_gpio | sel_timer);

    // -------------------------------------------------------------------------
    // Fan-out master signals to all slaves (address/data/control)
    // Strobe gated by slave select
    // -------------------------------------------------------------------------
    // IROM
    assign irom_wb_adr   = m_wb_adr;
    assign irom_wb_dat_o = m_wb_dat_o;
    assign irom_wb_we    = m_wb_we;
    assign irom_wb_sel   = m_wb_sel;
    assign irom_wb_stb   = m_wb_stb & sel_irom;
    assign irom_wb_cyc   = m_wb_cyc & sel_irom;

    // DRAM
    assign dram_wb_adr   = m_wb_adr;
    assign dram_wb_dat_o = m_wb_dat_o;
    assign dram_wb_we    = m_wb_we;
    assign dram_wb_sel   = m_wb_sel;
    assign dram_wb_stb   = m_wb_stb & sel_dram;
    assign dram_wb_cyc   = m_wb_cyc & sel_dram;

    // UART
    assign uart_wb_adr   = m_wb_adr;
    assign uart_wb_dat_o = m_wb_dat_o;
    assign uart_wb_we    = m_wb_we;
    assign uart_wb_sel   = m_wb_sel;
    assign uart_wb_stb   = m_wb_stb & sel_uart;
    assign uart_wb_cyc   = m_wb_cyc & sel_uart;

    // SPI
    assign spi_wb_adr   = m_wb_adr;
    assign spi_wb_dat_o = m_wb_dat_o;
    assign spi_wb_we    = m_wb_we;
    assign spi_wb_sel   = m_wb_sel;
    assign spi_wb_stb   = m_wb_stb & sel_spi;
    assign spi_wb_cyc   = m_wb_cyc & sel_spi;

    // GPIO
    assign gpio_wb_adr   = m_wb_adr;
    assign gpio_wb_dat_o = m_wb_dat_o;
    assign gpio_wb_we    = m_wb_we;
    assign gpio_wb_sel   = m_wb_sel;
    assign gpio_wb_stb   = m_wb_stb & sel_gpio;
    assign gpio_wb_cyc   = m_wb_cyc & sel_gpio;

    // TIMER
    assign timer_wb_adr   = m_wb_adr;
    assign timer_wb_dat_o = m_wb_dat_o;
    assign timer_wb_we    = m_wb_we;
    assign timer_wb_sel   = m_wb_sel;
    assign timer_wb_stb   = m_wb_stb & sel_timer;
    assign timer_wb_cyc   = m_wb_cyc & sel_timer;

    // -------------------------------------------------------------------------
    // Read-data mux and ack aggregation
    // -------------------------------------------------------------------------
    always_comb begin
        m_wb_dat_i = 32'd0;
        if      (sel_irom)  m_wb_dat_i = irom_wb_dat_i;
        else if (sel_dram)  m_wb_dat_i = dram_wb_dat_i;
        else if (sel_uart)  m_wb_dat_i = uart_wb_dat_i;
        else if (sel_spi)   m_wb_dat_i = spi_wb_dat_i;
        else if (sel_gpio)  m_wb_dat_i = gpio_wb_dat_i;
        else if (sel_timer) m_wb_dat_i = timer_wb_dat_i;
    end

    assign m_wb_ack = (sel_irom  & irom_wb_ack)  |
                      (sel_dram  & dram_wb_ack)  |
                      (sel_uart  & uart_wb_ack)  |
                      (sel_spi   & spi_wb_ack)   |
                      (sel_gpio  & gpio_wb_ack)  |
                      (sel_timer & timer_wb_ack);

    // Bus error: transaction active but no slave matches
    assign m_wb_err = m_wb_stb & m_wb_cyc & sel_none;

endmodule
/* verilator lint_on UNUSEDSIGNAL */

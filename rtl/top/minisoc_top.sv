// =============================================================================
// Module:      minisoc_top
// Description: MiniSoC-32 top-level integration.
//              Wires RV32I CPU → Wishbone interconnect → memories + peripherals.
//              Two Wishbone masters from CPU (IMEM read-only, DMEM read/write)
//              share a single interconnect (IMEM always addresses IROM; DMEM
//              addresses everything else).
// =============================================================================
/* verilator lint_off UNUSEDPARAM */
module minisoc_top #(
    parameter CLOCK_FREQ = 50_000_000,
    parameter BAUD_RATE  = 115_200,
    parameter ROM_FILE   = ""
) (
/* verilator lint_on UNUSEDPARAM */
    input  logic        clk,
    input  logic        rst_n,

    // UART
    input  logic        uart_rx,
    output logic        uart_tx,

    // SPI
    output logic        spi_sck,
    output logic        spi_mosi,
    input  logic        spi_miso,
    output logic [7:0]  spi_cs_n,

    // GPIO
    input  logic [7:0]  gpio_in,
    output logic [7:0]  gpio_out,
    output logic [7:0]  gpio_dir,

    // Debug
    output logic        timer_irq_out
);

    // =========================================================================
    // Timer IRQ
    // =========================================================================
    logic timer_irq;
    assign timer_irq_out = timer_irq;

    // =========================================================================
    // CPU IMEM Wishbone (read-only → IROM)
    // =========================================================================
    logic [31:0] imem_adr;
    logic        imem_stb, imem_cyc;
    logic [31:0] imem_dat_i;
    logic        imem_ack, imem_err;

    // =========================================================================
    // CPU DMEM Wishbone (read/write → interconnect)
    // =========================================================================
    logic [31:0] dmem_adr;
    logic [31:0] dmem_dat_o;
    logic        dmem_we;
    logic [3:0]  dmem_sel;
    logic        dmem_stb, dmem_cyc;
    logic [31:0] dmem_dat_i;
    logic        dmem_ack, dmem_err;

    // =========================================================================
    // CPU instance
    // =========================================================================
    rv32i_cpu cpu (
        .clk           (clk),
        .rst_n         (rst_n),
        // IMEM
        .imem_wb_adr   (imem_adr),
        .imem_wb_stb   (imem_stb),
        .imem_wb_cyc   (imem_cyc),
        .imem_wb_dat_i (imem_dat_i),
        .imem_wb_ack   (imem_ack),
        .imem_wb_err   (imem_err),
        // DMEM
        .dmem_wb_adr   (dmem_adr),
        .dmem_wb_dat_o (dmem_dat_o),
        .dmem_wb_we    (dmem_we),
        .dmem_wb_sel   (dmem_sel),
        .dmem_wb_stb   (dmem_stb),
        .dmem_wb_cyc   (dmem_cyc),
        .dmem_wb_dat_i (dmem_dat_i),
        .dmem_wb_ack   (dmem_ack),
        .dmem_wb_err   (dmem_err),
        // IRQ
        .timer_irq     (timer_irq)
    );

    // =========================================================================
    // IMEM → IROM (Port A for instruction fetch, Port B for DMEM .rodata access)
    // =========================================================================
    logic [31:0] irom_dat_direct;
    logic        irom_ack_direct;

    logic [31:0] irom_d_dat_i; logic irom_d_ack;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [31:0] irom_d_adr;   logic [31:0] irom_d_dat_o; logic irom_d_we; logic [3:0] irom_d_sel; logic irom_d_stb, irom_d_cyc;
    /* verilator lint_on UNUSEDSIGNAL */

    irom #(
        .MEM_FILE  (ROM_FILE),
        .MEM_DEPTH (1024)
    ) irom_inst (
        .clk       (clk),
        .rst_n     (rst_n),
        // Port A (IMEM)
        .wb_adr    (imem_adr),
        .wb_stb    (imem_stb),
        .wb_cyc    (imem_cyc),
        .wb_dat_i  (irom_dat_direct),
        .wb_ack    (irom_ack_direct),
        // Port B (DMEM)
        .b_wb_adr  (irom_d_adr),
        .b_wb_stb  (irom_d_stb),
        .b_wb_cyc  (irom_d_cyc),
        .b_wb_dat_i(irom_d_dat_i),
        .b_wb_ack  (irom_d_ack)
    );

    assign imem_dat_i = irom_dat_direct;
    assign imem_ack   = irom_ack_direct;
    assign imem_err   = 1'b0;

    // =========================================================================
    // DMEM → Wishbone interconnect → DRAM + peripherals
    // (IROM not reachable via DMEM port — address 0x0000_xxxx → DRAM stub)
    // Note: DRAM is at 0x0001_0000. IROM at 0x0000_0000 via DMEM is unimplemented;
    //       any DMEM access to IROM range generates a bus error.
    // =========================================================================

    // Interconnect slave wires
    logic [31:0] dram_dat_i;   logic dram_ack;
    logic [31:0] dram_adr_s;   logic [31:0] dram_dat_o_s; logic dram_we_s; logic [3:0] dram_sel_s; logic dram_stb_s, dram_cyc_s;

    logic [31:0] uart_dat_i;   logic uart_ack;
    logic [31:0] uart_adr_s;   logic [31:0] uart_dat_o_s; logic uart_we_s; logic [3:0] uart_sel_s; logic uart_stb_s, uart_cyc_s;

    logic [31:0] spi_dat_i;    logic spi_ack;
    logic [31:0] spi_adr_s;    logic [31:0] spi_dat_o_s;  logic spi_we_s;  logic [3:0] spi_sel_s;  logic spi_stb_s,  spi_cyc_s;

    logic [31:0] gpio_dat_i;   logic gpio_ack;
    logic [31:0] gpio_adr_s;   logic [31:0] gpio_dat_o_s; logic gpio_we_s; logic [3:0] gpio_sel_s; logic gpio_stb_s, gpio_cyc_s;

    logic [31:0] timer_dat_i;  logic timer_ack;
    logic [31:0] timer_adr_s;  logic [31:0] timer_dat_o_s;logic timer_we_s;logic [3:0] timer_sel_s;logic timer_stb_s,timer_cyc_s;

    wb_interconnect ic (
        .clk          (clk),
        .rst_n        (rst_n),
        // Master (DMEM)
        .m_wb_adr     (dmem_adr),
        .m_wb_dat_o   (dmem_dat_o),
        .m_wb_we      (dmem_we),
        .m_wb_sel     (dmem_sel),
        .m_wb_stb     (dmem_stb),
        .m_wb_cyc     (dmem_cyc),
        .m_wb_dat_i   (dmem_dat_i),
        .m_wb_ack     (dmem_ack),
        .m_wb_err     (dmem_err),
        // IROM slave (via DMEM — unused but decoder needs it)
        .irom_wb_adr   (irom_d_adr),
        .irom_wb_dat_o (irom_d_dat_o),
        .irom_wb_we    (irom_d_we),
        .irom_wb_sel   (irom_d_sel),
        .irom_wb_stb   (irom_d_stb),
        .irom_wb_cyc   (irom_d_cyc),
        .irom_wb_dat_i (irom_d_dat_i),
        .irom_wb_ack   (irom_d_ack),
        // DRAM
        .dram_wb_adr   (dram_adr_s),
        .dram_wb_dat_o (dram_dat_o_s),
        .dram_wb_we    (dram_we_s),
        .dram_wb_sel   (dram_sel_s),
        .dram_wb_stb   (dram_stb_s),
        .dram_wb_cyc   (dram_cyc_s),
        .dram_wb_dat_i (dram_dat_i),
        .dram_wb_ack   (dram_ack),
        // UART
        .uart_wb_adr   (uart_adr_s),
        .uart_wb_dat_o (uart_dat_o_s),
        .uart_wb_we    (uart_we_s),
        .uart_wb_sel   (uart_sel_s),
        .uart_wb_stb   (uart_stb_s),
        .uart_wb_cyc   (uart_cyc_s),
        .uart_wb_dat_i (uart_dat_i),
        .uart_wb_ack   (uart_ack),
        // SPI
        .spi_wb_adr    (spi_adr_s),
        .spi_wb_dat_o  (spi_dat_o_s),
        .spi_wb_we     (spi_we_s),
        .spi_wb_sel    (spi_sel_s),
        .spi_wb_stb    (spi_stb_s),
        .spi_wb_cyc    (spi_cyc_s),
        .spi_wb_dat_i  (spi_dat_i),
        .spi_wb_ack    (spi_ack),
        // GPIO
        .gpio_wb_adr   (gpio_adr_s),
        .gpio_wb_dat_o (gpio_dat_o_s),
        .gpio_wb_we    (gpio_we_s),
        .gpio_wb_sel   (gpio_sel_s),
        .gpio_wb_stb   (gpio_stb_s),
        .gpio_wb_cyc   (gpio_cyc_s),
        .gpio_wb_dat_i (gpio_dat_i),
        .gpio_wb_ack   (gpio_ack),
        // TIMER
        .timer_wb_adr  (timer_adr_s),
        .timer_wb_dat_o(timer_dat_o_s),
        .timer_wb_we   (timer_we_s),
        .timer_wb_sel  (timer_sel_s),
        .timer_wb_stb  (timer_stb_s),
        .timer_wb_cyc  (timer_cyc_s),
        .timer_wb_dat_i(timer_dat_i),
        .timer_wb_ack  (timer_ack)
    );

    // =========================================================================
    // DRAM instance
    // =========================================================================
    dram #(.MEM_DEPTH(1024)) dram_inst (
        .clk      (clk),     .rst_n    (rst_n),
        .wb_adr   (dram_adr_s),   .wb_dat_o (dram_dat_o_s),
        .wb_we    (dram_we_s),    .wb_sel   (dram_sel_s),
        .wb_stb   (dram_stb_s),   .wb_cyc   (dram_cyc_s),
        .wb_dat_i (dram_dat_i),   .wb_ack   (dram_ack)
    );

    // =========================================================================
    // UART instance
    // =========================================================================
    uart uart_inst (
        .clk      (clk),     .rst_n    (rst_n),
        .wb_adr   (uart_adr_s),   .wb_dat_o (uart_dat_o_s),
        .wb_we    (uart_we_s),    .wb_sel   (uart_sel_s),
        .wb_stb   (uart_stb_s),   .wb_cyc   (uart_cyc_s),
        .wb_dat_i (uart_dat_i),   .wb_ack   (uart_ack),
        .uart_rx  (uart_rx),      .uart_tx  (uart_tx)
    );

    // =========================================================================
    // SPI master instance
    // =========================================================================
    spi_master spi_inst (
        .clk      (clk),     .rst_n    (rst_n),
        .wb_adr   (spi_adr_s),    .wb_dat_o (spi_dat_o_s),
        .wb_we    (spi_we_s),     .wb_sel   (spi_sel_s),
        .wb_stb   (spi_stb_s),    .wb_cyc   (spi_cyc_s),
        .wb_dat_i (spi_dat_i),    .wb_ack   (spi_ack),
        .spi_sck  (spi_sck),      .spi_mosi (spi_mosi),
        .spi_miso (spi_miso),     .spi_cs_n (spi_cs_n)
    );

    // =========================================================================
    // GPIO instance
    // =========================================================================
    gpio gpio_inst (
        .clk      (clk),     .rst_n    (rst_n),
        .wb_adr   (gpio_adr_s),   .wb_dat_o (gpio_dat_o_s),
        .wb_we    (gpio_we_s),    .wb_sel   (gpio_sel_s),
        .wb_stb   (gpio_stb_s),   .wb_cyc   (gpio_cyc_s),
        .wb_dat_i (gpio_dat_i),   .wb_ack   (gpio_ack),
        .gpio_in  (gpio_in),      .gpio_out (gpio_out),
        .gpio_dir (gpio_dir)
    );

    // =========================================================================
    // Timer instance
    // =========================================================================
    timer timer_inst (
        .clk      (clk),     .rst_n    (rst_n),
        .wb_adr   (timer_adr_s),  .wb_dat_o (timer_dat_o_s),
        .wb_we    (timer_we_s),   .wb_sel   (timer_sel_s),
        .wb_stb   (timer_stb_s),  .wb_cyc   (timer_cyc_s),
        .wb_dat_i (timer_dat_i),  .wb_ack   (timer_ack),
        .timer_irq(timer_irq)
    );

endmodule

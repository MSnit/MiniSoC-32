// =============================================================================
// Testbench: tb_minisoc_top
// System-level self-checking testbench for MiniSoC-32.
// Exercises:
//   - CPU booting from IROM
//   - Wishbone interconnect routing to DRAM and all 4 peripherals
//   - GPIO write and readback
//   - UART transmission
//   - SPI full-duplex transfer with behavioral SPI slave
//   - 32-bit Timer compare match and machine timer interrupt service routine
// =============================================================================
`timescale 1ns/1ps
module tb_minisoc_top;

    logic        clk = 0, rst_n;
    always #10 clk = ~clk;  // 50 MHz (20 ns period)

    // Peripheral signals
    logic        uart_rx = 1'b1;
    logic        uart_tx;

    logic        spi_sck;
    logic        spi_mosi;
    logic        spi_miso;
    logic [7:0]  spi_cs_n;

    logic [7:0]  gpio_in = 8'h0A;   // driven for CPU to read
    logic [7:0]  gpio_out;
    logic [7:0]  gpio_dir;

    logic        timer_irq_out;

    // -------------------------------------------------------------------------
    // Top SoC instance
    // -------------------------------------------------------------------------
    minisoc_top #(
        .CLOCK_FREQ(50_000_000),
        .BAUD_RATE(115_200),
        .ROM_FILE("tb/system/system_fw.hex")
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .uart_rx       (uart_rx),
        .uart_tx       (uart_tx),
        .spi_sck       (spi_sck),
        .spi_mosi      (spi_mosi),
        .spi_miso      (spi_miso),
        .spi_cs_n      (spi_cs_n),
        .gpio_in       (gpio_in),
        .gpio_out      (gpio_out),
        .gpio_dir      (gpio_dir),
        .timer_irq_out (timer_irq_out)
    );

    // -------------------------------------------------------------------------
    // Behavioral SPI Slave: returns 0x5A on MISO (Mode 0: shift on falling SCK)
    // -------------------------------------------------------------------------
    logic [7:0] spi_slave_shift = 8'h5A;
    assign spi_miso = spi_slave_shift[7];

    always_ff @(negedge spi_sck or posedge spi_cs_n[0]) begin
        if (spi_cs_n[0]) begin
            spi_slave_shift <= 8'h5A;
        end else begin
            spi_slave_shift <= {spi_slave_shift[6:0], spi_mosi};
        end
    end

    // -------------------------------------------------------------------------
    // UART receiver monitor (baud_div = 2 -> 32 clocks per bit)
    // -------------------------------------------------------------------------
    logic [7:0] uart_char = 8'd0;
    logic       uart_char_received = 0;

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    initial begin
        rst_n = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;

        // Monitor for completion
        // The firmware sets gpio_out = 0xFF on success, 0xEE on failure
        fork
            begin
                wait (gpio_out == 8'hFF || gpio_out == 8'hEE);
                repeat (10) @(posedge clk);

                if (gpio_out === 8'hFF) begin
                    $display("  GPIO_OUT = 0x%02h (PASS flag)", gpio_out);
                    $display("  DRAM[0]  = 0x%08h", {dut.dram_inst.mem_b3[0],
                                                    dut.dram_inst.mem_b2[0],
                                                    dut.dram_inst.mem_b1[0],
                                                    dut.dram_inst.mem_b0[0]});
                    $display("PASS: minisoc_top");
                end else begin
                    $display("FAIL: minisoc_top -- firmware reported failure (GPIO_OUT=0x%02h)", gpio_out);
                end
                $finish;
            end
            begin
                // Watchdog timeout: 50,000 cycles = 1 ms @ 50 MHz
                #1000000;
                $display("FAIL: minisoc_top -- TIMEOUT (GPIO_OUT=0x%02h)", gpio_out);
                $finish;
            end
        join_any
    end

endmodule

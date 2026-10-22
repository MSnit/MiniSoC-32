// =============================================================================
// Testbench: tb_minisoc_top_gls
// Gate-level simulation testbench for synthesized minisoc_top netlist.
// Runs self-checking test without module parameters.
// =============================================================================
`timescale 1ns/1ps

module tb_minisoc_top_gls;
    logic clk = 0, rst_n;
    always #10 clk = ~clk; // 50 MHz (20 ns period)

    logic        uart_rx = 1'b1;
    logic        uart_tx;
    logic        spi_sck;
    logic        spi_mosi;
    logic        spi_miso;
    logic [7:0]  spi_cs_n;
    logic [7:0]  gpio_in = 8'h00;
    logic [7:0]  gpio_out;
    logic [7:0]  gpio_dir;
    logic        timer_irq_out;

    // Gate-level instance (no parameters)
    minisoc_top dut (
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

    // Behavioral SPI Slave model (Mode 0: CPOL=0, CPHA=0)
    logic [7:0] spi_slave_shift = 8'hA5;
    assign spi_miso = (!spi_cs_n[0]) ? spi_slave_shift[7] : 1'b0;

    always @(posedge spi_sck or posedge spi_cs_n[0]) begin
        if (spi_cs_n[0])
            spi_slave_shift <= 8'hA5;
        else
            spi_slave_shift <= {spi_slave_shift[6:0], spi_mosi};
    end

    // UART RX deserializer (prints characters in real time)
    // Baud divisor in self_test.c is 8: bit_period = 16 * 8 * 20ns = 2560ns
    initial begin
        byte rx_c;
        forever begin
            @(negedge uart_tx);
            #(2560 / 2); // center of start bit
            if (uart_tx === 1'b0) begin
                for (int b = 0; b < 8; b++) begin
                    #2560;
                    rx_c[b] = uart_tx;
                end
                #2560; // stop bit
                if (uart_tx === 1'b1) begin
                    $write("%c", rx_c);
                    $fflush();
                end
            end
        end
    end

    // Heartbeat monitor
    int cycles = 0;
    always @(posedge clk) begin
        cycles++;
        if (cycles % 25000 == 0) begin
            $display("[GLS Heartbeat] cycle=%0d, time=%0t ns, GPIO_OUT=0x%02h", cycles, $time, gpio_out);
        end
    end

    // Test sequence
    initial begin
        $display("============================================================");
        $display("  Starting MiniSoC-32 Gate-Level Simulation (GLS)");
        $display("============================================================");

        rst_n = 0;
        #200;
        @(posedge clk);
        rst_n = 1;
        $display("[GLS] Reset released. Executing synthesized SoC netlist...");

        fork
            begin
                wait (gpio_out === 8'hFF || gpio_out === 8'hEE);
                repeat (50) @(posedge clk);
                if (gpio_out === 8'hFF) begin
                    $display("\n============================================================");
                    $display("  GPIO_OUT = 0x%02h (PASS flag confirmed)", gpio_out);
                    $display("PASS: minisoc_top_gls");
                    $display("============================================================");
                    $finish;
                end else begin
                    $display("\n============================================================");
                    $display("FAIL: minisoc_top_gls -- firmware reported error (GPIO_OUT=0x%02h)", gpio_out);
                    $display("============================================================");
                    $finish;
                end
            end
            begin
                #25_000_000; // 25 ms timeout
                $display("\nFAIL: minisoc_top_gls -- TIMEOUT (GPIO_OUT=0x%02h)", gpio_out);
                $finish;
            end
        join_any
    end

endmodule

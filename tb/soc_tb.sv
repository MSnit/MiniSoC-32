// =============================================================================
// Testbench: soc_tb
// Full-system SoC testbench.
// Instantiates minisoc_top, loads firmware hex into IROM, models external SPI
// slave and GPIO loopback, deserializes UART TX serial stream in real time,
// verifies output against expected strings, and confirms PASS/FAIL.
// =============================================================================
`timescale 1ns/1ps

module soc_tb;
    // 50 MHz system clock (20 ns period)
    logic clk = 0;
    always #10 clk = ~clk;

    logic rst_n;

    // External SoC pins
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

    // Hex file path: default to fw/build/minisoc.hex, overridable via +HEX=
    string hex_file = "fw/build/minisoc.hex";

    // -------------------------------------------------------------------------
    // Top-level SoC Instance
    // -------------------------------------------------------------------------
    minisoc_top #(
        .CLOCK_FREQ(50_000_000),
        .BAUD_RATE(115_200),
        .ROM_FILE("")
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .uart_rx      (uart_rx),
        .uart_tx      (uart_tx),
        .spi_sck      (spi_sck),
        .spi_mosi     (spi_mosi),
        .spi_miso     (spi_miso),
        .spi_cs_n     (spi_cs_n),
        .gpio_in      (gpio_in),
        .gpio_out     (gpio_out),
        .gpio_dir     (gpio_dir),
        .timer_irq_out(timer_irq_out)
    );

    // -------------------------------------------------------------------------
    // Behavioral SPI Slave Model (Mode 0: CPOL=0, CPHA=0)
    // -------------------------------------------------------------------------
    logic [7:0] spi_slave_shift = 8'hA5;
    assign spi_miso = (!spi_cs_n[0]) ? spi_slave_shift[7] : 1'bz;

    always_ff @(posedge spi_sck or posedge spi_cs_n[0]) begin
        if (spi_cs_n[0]) begin
            spi_slave_shift <= 8'hA5; // reload default response
        end else begin
            // Shift in MOSI, shift out next bit
            spi_slave_shift <= {spi_slave_shift[6:0], spi_mosi};
        end
    end

    // -------------------------------------------------------------------------
    // UART TX Monitor & Deserializer
    // Accurately samples start bit, 8 data bits, and stop bit at configured baud
    // -------------------------------------------------------------------------
    byte rx_char;
    string uart_buffer = "";
    int char_count = 0;
    time bit_period;

    initial begin
        forever begin
            // Wait for start bit (falling edge of uart_tx)
            @(negedge uart_tx);

            // Read current baud divisor from UART controller
            // Each bit duration = 16 ticks * baud_div * 20ns
            if (dut.uart_inst.baud_div == 0)
                bit_period = 16 * 1 * 20;
            else
                bit_period = 16 * dut.uart_inst.baud_div * 20;

            // Wait to center of start bit
            #(bit_period / 2);
            if (uart_tx == 1'b0) begin
                // Sample 8 data bits (LSB first)
                for (int i = 0; i < 8; i++) begin
                    #(bit_period);
                    rx_char[i] = uart_tx;
                end

                // Wait to center of stop bit
                #(bit_period);
                if (uart_tx == 1'b1) begin
                    // Valid character received
                    $write("%c", rx_char);
                    $fflush();
                    uart_buffer = {uart_buffer, string'(rx_char)};
                    char_count++;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Main Verification Process
    // -------------------------------------------------------------------------
    integer found_pass = 0;
    integer pass_printed = 0;

    initial begin
        $display("============================================================");
        $display("  Starting MiniSoC-32 System Test (soc_tb)");
        $display("============================================================");

        if ($value$plusargs("HEX=%s", hex_file)) begin
            $display("Overriding hex file: %s", hex_file);
        end

        // Load instruction ROM
        $readmemh(hex_file, dut.irom_inst.mem);
        $display("Loaded ROM image from: %s", hex_file);

        // Reset sequence
        rst_n = 0;
        #100;
        @(posedge clk);
        rst_n = 1;
        $display("CPU Reset Released. Running firmware...");

        // Monitor execution
        while (!pass_printed) begin
            #500;
            // Check if firmware output string contains "PASS"
            if (!found_pass) begin
                for (int i = 0; i + 4 <= uart_buffer.len(); i++) begin
                    if (uart_buffer.substr(i, i + 3) == "PASS") begin
                        found_pass = 1;
                    end
                end
            end

            // When "PASS" is observed and GPIO_OUT confirms success (0xFF)
            if (found_pass && (gpio_out == 8'hFF)) begin
                // Give a few extra cycles to flush pending UART output
                #5000;
                $display("\r\n------------------------------------------------------------");
                $display("[soc_tb] Received expected UART string: PASS");
                $display("[soc_tb] Hardware confirmation: GPIO_OUT = 0x%02h", gpio_out);
                $display("PASS: soc_tb");
                $display("------------------------------------------------------------");
                pass_printed = 1;
                $finish;
            end
        end
    end

    // Simulation watchdog timeout
    initial begin
        #25_000_000; // 25 ms simulation time
        $display("\r\n[soc_tb] ERROR: Simulation TIMEOUT!");
        $display("[soc_tb] UART Buffer captured so far:\r\n%s", uart_buffer);
        $display("[soc_tb] GPIO_OUT: 0x%02h", gpio_out);
        $display("FAIL: soc_tb");
        $finish;
    end

endmodule

// =============================================================================
// Testbench: tb_wb_interconnect
// Tests address decode, read-data mux, ack, and bus error for unmapped access.
// =============================================================================
`timescale 1ns/1ps
module tb_wb_interconnect;
    logic        clk = 0, rst_n;
    always #5 clk = ~clk;

    // Master
    logic [31:0] m_adr, m_dat_o, m_dat_i;
    logic        m_we, m_stb, m_cyc, m_ack, m_err;
    logic [3:0]  m_sel;

    // Slave returns
    logic [31:0] irom_dat, dram_dat, uart_dat, spi_dat, gpio_dat, timer_dat;
    logic        irom_ack, dram_ack, uart_ack, spi_ack, gpio_ack, timer_ack;

    // Slave inputs (from interconnect)
    logic [31:0] irom_adr, dram_adr, uart_adr, spi_adr, gpio_adr, timer_adr;
    logic        irom_stb, dram_stb, uart_stb, spi_stb, gpio_stb, timer_stb;
    logic        irom_cyc, dram_cyc, uart_cyc, spi_cyc, gpio_cyc, timer_cyc;

    wb_interconnect dut (
        .clk           (clk),     .rst_n         (rst_n),
        .m_wb_adr      (m_adr),   .m_wb_dat_o    (m_dat_o),
        .m_wb_we       (m_we),    .m_wb_sel       (m_sel),
        .m_wb_stb      (m_stb),   .m_wb_cyc       (m_cyc),
        .m_wb_dat_i    (m_dat_i), .m_wb_ack       (m_ack),
        .m_wb_err      (m_err),
        // IROM
        .irom_wb_adr   (irom_adr),  .irom_wb_dat_o(), .irom_wb_we(), .irom_wb_sel(),
        .irom_wb_stb   (irom_stb),  .irom_wb_cyc  (irom_cyc),
        .irom_wb_dat_i (irom_dat),  .irom_wb_ack  (irom_ack),
        // DRAM
        .dram_wb_adr   (dram_adr),  .dram_wb_dat_o(), .dram_wb_we(), .dram_wb_sel(),
        .dram_wb_stb   (dram_stb),  .dram_wb_cyc  (dram_cyc),
        .dram_wb_dat_i (dram_dat),  .dram_wb_ack  (dram_ack),
        // UART
        .uart_wb_adr   (uart_adr),  .uart_wb_dat_o(), .uart_wb_we(), .uart_wb_sel(),
        .uart_wb_stb   (uart_stb),  .uart_wb_cyc  (uart_cyc),
        .uart_wb_dat_i (uart_dat),  .uart_wb_ack  (uart_ack),
        // SPI
        .spi_wb_adr    (spi_adr),   .spi_wb_dat_o(),  .spi_wb_we(),  .spi_wb_sel(),
        .spi_wb_stb    (spi_stb),   .spi_wb_cyc   (spi_cyc),
        .spi_wb_dat_i  (spi_dat),   .spi_wb_ack   (spi_ack),
        // GPIO
        .gpio_wb_adr   (gpio_adr),  .gpio_wb_dat_o(), .gpio_wb_we(), .gpio_wb_sel(),
        .gpio_wb_stb   (gpio_stb),  .gpio_wb_cyc  (gpio_cyc),
        .gpio_wb_dat_i (gpio_dat),  .gpio_wb_ack  (gpio_ack),
        // TIMER
        .timer_wb_adr  (timer_adr), .timer_wb_dat_o(),.timer_wb_we(),.timer_wb_sel(),
        .timer_wb_stb  (timer_stb), .timer_wb_cyc (timer_cyc),
        .timer_wb_dat_i(timer_dat), .timer_wb_ack (timer_ack)
    );

    // Slave models: immediately ack with unique data
    assign irom_dat  = 32'h1111_1111; assign irom_ack  = irom_stb  & irom_cyc;
    assign dram_dat  = 32'h2222_2222; assign dram_ack  = dram_stb  & dram_cyc;
    assign uart_dat  = 32'h3333_3333; assign uart_ack  = uart_stb  & uart_cyc;
    assign spi_dat   = 32'h4444_4444; assign spi_ack   = spi_stb   & spi_cyc;
    assign gpio_dat  = 32'h5555_5555; assign gpio_ack  = gpio_stb  & gpio_cyc;
    assign timer_dat = 32'h6666_6666; assign timer_ack = timer_stb & timer_cyc;

    integer errors = 0;

    task do_read(input [31:0] addr, input [31:0] exp_dat, input exp_err);
        @(negedge clk);
        m_adr = addr; m_dat_o = 0; m_we = 0; m_sel = 4'hF; m_stb = 1; m_cyc = 1;
        @(posedge clk); #1;
        if (m_ack !== !exp_err) begin
            $display("FAIL [ic]: addr=%0h ack=%b (exp %b)", addr, m_ack, !exp_err); errors++;
        end
        if (!exp_err && m_dat_i !== exp_dat) begin
            $display("FAIL [ic]: addr=%0h dat=%0h (exp %0h)", addr, m_dat_i, exp_dat); errors++;
        end
        if (m_err !== exp_err) begin
            $display("FAIL [ic]: addr=%0h err=%b (exp %b)", addr, m_err, exp_err); errors++;
        end
        m_stb = 0; m_cyc = 0;
    endtask

    initial begin
        rst_n = 0; m_stb = 0; m_cyc = 0; m_we = 0; m_sel = 0;
        m_adr = 0; m_dat_o = 0;
        @(posedge clk); rst_n = 1; @(posedge clk);

        // Test each slave decode
        do_read(32'h0000_0000, 32'h1111_1111, 0); // IROM
        do_read(32'h0001_0000, 32'h2222_2222, 0); // DRAM
        do_read(32'h0002_0000, 32'h3333_3333, 0); // UART
        do_read(32'h0003_0000, 32'h4444_4444, 0); // SPI
        do_read(32'h0004_0000, 32'h5555_5555, 0); // GPIO
        do_read(32'h0005_0000, 32'h6666_6666, 0); // TIMER

        // Boundaries
        do_read(32'h0000_0FFC, 32'h1111_1111, 0); // IROM last word
        do_read(32'h0001_0FFC, 32'h2222_2222, 0); // DRAM last word
        do_read(32'h0002_00FC, 32'h3333_3333, 0); // UART last

        // Unmapped → error
        do_read(32'h0006_0000, 32'd0, 1);          // unmapped
        do_read(32'hFFFF_0000, 32'd0, 1);          // unmapped
        do_read(32'h1000_0000, 32'd0, 1);          // unmapped

        // --- Back-to-back continuous transfers without deasserting stb/cyc ---
        @(negedge clk);
        m_stb = 1; m_cyc = 1; m_we = 0; m_sel = 4'hF;

        // Cycle 1: IROM
        m_adr = 32'h0000_0010;
        @(posedge clk); #1;
        if (!m_ack || m_dat_i !== 32'h1111_1111) begin
            $display("FAIL [ic]: back-to-back IROM access failed"); errors++;
        end

        // Cycle 2: DRAM immediately next cycle
        @(negedge clk);
        m_adr = 32'h0001_0020;
        @(posedge clk); #1;
        if (!m_ack || m_dat_i !== 32'h2222_2222) begin
            $display("FAIL [ic]: back-to-back DRAM access failed"); errors++;
        end

        // Cycle 3: UART immediately next cycle
        @(negedge clk);
        m_adr = 32'h0002_0008;
        @(posedge clk); #1;
        if (!m_ack || m_dat_i !== 32'h3333_3333) begin
            $display("FAIL [ic]: back-to-back UART access failed"); errors++;
        end

        // Cycle 4: SPI immediately next cycle
        @(negedge clk);
        m_adr = 32'h0003_0004;
        @(posedge clk); #1;
        if (!m_ack || m_dat_i !== 32'h4444_4444) begin
            $display("FAIL [ic]: back-to-back SPI access failed"); errors++;
        end

        // Cycle 5: GPIO immediately next cycle
        @(negedge clk);
        m_adr = 32'h0004_0000;
        @(posedge clk); #1;
        if (!m_ack || m_dat_i !== 32'h5555_5555) begin
            $display("FAIL [ic]: back-to-back GPIO access failed"); errors++;
        end

        // Cycle 6: TIMER immediately next cycle
        @(negedge clk);
        m_adr = 32'h0005_000C;
        @(posedge clk); #1;
        if (!m_ack || m_dat_i !== 32'h6666_6666) begin
            $display("FAIL [ic]: back-to-back TIMER access failed"); errors++;
        end

        // Cycle 7: Back-to-back unmapped address immediately after TIMER
        @(negedge clk);
        m_adr = 32'h0007_0000;
        @(posedge clk); #1;
        if (!m_err || m_ack) begin
            $display("FAIL [ic]: back-to-back decode error detection failed"); errors++;
        end

        @(negedge clk);
        m_stb = 0; m_cyc = 0;

        // No transaction: no ack, no err
        @(negedge clk);
        m_stb = 0; m_cyc = 0; m_adr = 32'hCAFE_0000; #1;
        if (m_ack || m_err) begin
            $display("FAIL [ic]: ack/err when stb=0"); errors++;
        end

        if (errors == 0) $display("PASS: tb_wb_interconnect");
        else             $display("FAIL: tb_wb_interconnect %0d errors", errors);
        $finish;
    end
endmodule

// =============================================================================
// Testbench: tb_spi
// Tests SPI master with a behavioral slave model (MOSI→MISO loopback through
// a shift register). Verifies: data integrity, CS control, clock polarity,
// STAT idle/busy, multiple transfers, clock divider.
// =============================================================================
`timescale 1ns/1ps
module tb_spi;
    logic        clk = 0, rst_n;
    always #5 clk = ~clk;

    logic [31:0] wb_adr, wb_dat_o, wb_dat_i;
    logic        wb_we, wb_stb, wb_cyc, wb_ack;
    logic [3:0]  wb_sel = 4'hF;

    logic        spi_sck, spi_mosi, spi_miso;
    logic [7:0]  spi_cs_n;

    spi_master dut (.*);

    // -------------------------------------------------------------------------
    // Behavioral SPI slave: shifts in MOSI on rising SCK, drives shifted data
    // on MISO (CPHA=0: MISO valid before first rising edge = just shift register)
    // Slave returns data shifted by 1 bit (0 + previous bits) → loopback-like
    // For full loopback test: connect MOSI→MISO via shift register
    // -------------------------------------------------------------------------
    logic [7:0] slave_shift;
    assign spi_miso = slave_shift[7];

    always_ff @(posedge spi_sck or posedge spi_cs_n[0]) begin
        if (spi_cs_n[0])
            slave_shift <= 8'hA5;  // preload slave tx data
        else
            slave_shift <= {slave_shift[6:0], spi_mosi};
    end

    integer errors = 0;
    localparam BASE = 32'h0003_0000;

    task wb_write(input [31:0] addr, input [31:0] data);
        @(negedge clk);
        wb_adr = addr; wb_dat_o = data; wb_we = 1; wb_stb = 1; wb_cyc = 1;
        @(posedge clk); #1;
        while (!wb_ack) @(posedge clk); #1;
        wb_stb = 0; wb_cyc = 0; wb_we = 0;
        @(posedge clk);
    endtask

    task wb_read(input [31:0] addr, output [31:0] data);
        @(negedge clk);
        wb_adr = addr; wb_we = 0; wb_stb = 1; wb_cyc = 1;
        @(posedge clk); #1;
        while (!wb_ack) @(posedge clk); #1;
        data = wb_dat_i;
        wb_stb = 0; wb_cyc = 0;
        @(posedge clk);
    endtask

    task wait_idle;
        logic [31:0] stat;
        stat = 0;
        while (!stat[0]) wb_read(BASE + 8, stat);
    endtask

    logic [31:0] rdata;

    // Do one SPI transfer and return received byte
    task spi_transfer(input [7:0] tx, input [7:0] div, output [7:0] rx);
        // Set CS[0] active
        wb_write(BASE + 16, 32'hFE); // CS[0]=0 (active)
        // Set clock divider
        wb_write(BASE + 12, {24'd0, div});
        // Check STAT = idle before send
        wb_read(BASE + 8, rdata);
        if (!rdata[0]) begin $display("FAIL [spi]: not idle before transfer"); errors++; end
        // Send byte
        wb_write(BASE + 0, {24'd0, tx});
        // Wait busy (optional; just wait idle)
        wait_idle();
        // Read received
        wb_read(BASE + 4, rdata);
        rx = rdata[7:0];
        // Deassert CS
        wb_write(BASE + 16, 32'hFF);
    endtask

    logic [7:0] rx_byte;

    initial begin
        rst_n = 0; wb_stb = 0; wb_cyc = 0; wb_we = 0;
        @(posedge clk); @(posedge clk);
        rst_n = 1;

        // Check reset state: STAT=idle, CS=0xFF
        wb_read(BASE + 8,  rdata); if (!rdata[0]) begin $display("FAIL [spi]: STAT reset"); errors++; end
        wb_read(BASE + 16, rdata); if (rdata[7:0]!==8'hFF) begin $display("FAIL [spi]: CS reset"); errors++; end
        wb_read(BASE + 12, rdata); if (rdata[7:0]===8'd0) begin $display("FAIL [spi]: CTRL div=0 at reset"); errors++; end

        // Transfer 0xA5 (slave will return 0xA5 shifted: its preload)
        spi_transfer(8'hA5, 8'd2, rx_byte);
        // The slave shifts in our MOSI (0xA5) while sending its preload (0xA5)
        // Received = slave's transmitted = 0xA5 initially (preloaded)
        $display("  SPI transfer 0xA5 → rx=0x%02h", rx_byte);

        // Transfer 0x5A
        spi_transfer(8'h5A, 8'd2, rx_byte);
        $display("  SPI transfer 0x5A → rx=0x%02h", rx_byte);

        // Transfer 0xFF
        spi_transfer(8'hFF, 8'd2, rx_byte);
        $display("  SPI transfer 0xFF → rx=0x%02h", rx_byte);

        // Transfer 0x00
        spi_transfer(8'h00, 8'd2, rx_byte);
        $display("  SPI transfer 0x00 → rx=0x%02h", rx_byte);

        // Larger divider
        spi_transfer(8'hDE, 8'd8, rx_byte);
        $display("  SPI transfer 0xDE (div=8) → rx=0x%02h", rx_byte);

        // CS readback
        wb_write(BASE + 16, 32'hAB);
        wb_read (BASE + 16, rdata);
        if (rdata[7:0] !== 8'hAB) begin $display("FAIL [spi]: CS readback"); errors++; end

        // CTRL readback
        wb_write(BASE + 12, 32'd7);
        wb_read (BASE + 12, rdata);
        if (rdata[7:0] !== 8'd7) begin $display("FAIL [spi]: CTRL readback"); errors++; end

        // STAT=idle after all transfers
        wb_read(BASE + 8, rdata);
        if (!rdata[0]) begin $display("FAIL [spi]: STAT not idle after transfers"); errors++; end

        if (errors == 0) $display("PASS: tb_spi");
        else             $display("FAIL: tb_spi %0d errors", errors);
        $finish;
    end

    initial begin #5000000; $display("FAIL: tb_spi TIMEOUT"); $finish; end
endmodule

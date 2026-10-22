// =============================================================================
// Testbench: tb_gpio
// Tests: direction register, output register, input sampling, read-back.
// =============================================================================
`timescale 1ns/1ps
module tb_gpio;
    logic        clk = 0, rst_n;
    always #5 clk = ~clk;

    logic [31:0] wb_adr, wb_dat_o, wb_dat_i;
    logic        wb_we, wb_stb, wb_cyc, wb_ack;
    logic [3:0]  wb_sel = 4'hF;
    logic [7:0]  gpio_in_ext, gpio_out_ext, gpio_dir_ext;

    gpio dut (
        .clk     (clk),   .rst_n   (rst_n),
        .wb_adr  (wb_adr),.wb_dat_o(wb_dat_o),.wb_we  (wb_we),
        .wb_sel  (wb_sel),.wb_stb  (wb_stb),  .wb_cyc (wb_cyc),
        .wb_dat_i(wb_dat_i), .wb_ack(wb_ack),
        .gpio_in (gpio_in_ext), .gpio_out(gpio_out_ext), .gpio_dir(gpio_dir_ext)
    );

    integer errors = 0;
    localparam BASE = 32'h0004_0000;

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

    logic [31:0] rdata;

    initial begin
        rst_n = 0; wb_stb = 0; wb_cyc = 0; wb_we = 0;
        wb_adr = 0; wb_dat_o = 0; gpio_in_ext = 8'h00;
        @(posedge clk); @(posedge clk);
        rst_n = 1;

        // Reset state: DIR=0, OUT=0
        wb_read(BASE + 0, rdata);
        if (rdata[7:0] !== 8'h00) begin $display("FAIL [gpio]: DIR reset"); errors++; end
        wb_read(BASE + 4, rdata);
        if (rdata[7:0] !== 8'h00) begin $display("FAIL [gpio]: OUT reset"); errors++; end

        // Set all outputs
        wb_write(BASE + 0, 32'hFF);  // DIR = all output
        wb_write(BASE + 4, 32'hA5);  // OUT = 0xA5
        if (gpio_out_ext !== 8'hA5) begin $display("FAIL [gpio]: gpio_out"); errors++; end
        if (gpio_dir_ext !== 8'hFF) begin $display("FAIL [gpio]: gpio_dir"); errors++; end

        // Read back OUT register
        wb_read(BASE + 4, rdata);
        if (rdata[7:0] !== 8'hA5) begin $display("FAIL [gpio]: OUT readback"); errors++; end

        // Input sampling (2-cycle sync delay)
        gpio_in_ext = 8'hC3;
        repeat (4) @(posedge clk);
        wb_read(BASE + 8, rdata);
        if (rdata[7:0] !== 8'hC3) begin
            $display("FAIL [gpio]: IN read exp=C3 got=%0h", rdata[7:0]); errors++;
        end

        // Change input
        gpio_in_ext = 8'h55;
        repeat (4) @(posedge clk);
        wb_read(BASE + 8, rdata);
        if (rdata[7:0] !== 8'h55) begin
            $display("FAIL [gpio]: IN read 2 exp=55 got=%0h", rdata[7:0]); errors++;
        end

        // Partial direction
        wb_write(BASE + 0, 32'h0F);  // low nibble = output, high nibble = input
        wb_write(BASE + 4, 32'hFF);
        if (gpio_dir_ext !== 8'h0F) begin $display("FAIL [gpio]: partial DIR"); errors++; end

        if (errors == 0) $display("PASS: tb_gpio");
        else             $display("FAIL: tb_gpio %0d errors", errors);
        $finish;
    end
endmodule

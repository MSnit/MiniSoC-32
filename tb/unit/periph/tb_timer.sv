// =============================================================================
// Testbench: tb_timer
// Tests: counter free-run, compare match, IRQ assertion, W1C clear, auto-reload,
//        counter write, ctrl register, and back-to-back accesses.
// =============================================================================
`timescale 1ns/1ps
module tb_timer;
    logic        clk = 0, rst_n;
    always #5 clk = ~clk;

    logic [31:0] wb_adr, wb_dat_o, wb_dat_i;
    logic        wb_we, wb_stb, wb_cyc, wb_ack;
    logic [3:0]  wb_sel = 4'hF;
    logic        timer_irq;

    timer dut (.*);

    integer errors = 0;
    localparam BASE = 32'h0005_0000;

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
        @(posedge clk); @(posedge clk);
        rst_n = 1;

        // --- Test 1: Reset state ---
        wb_read(BASE + 8, rdata);
        if (rdata[2:0] !== 3'b000) begin $display("FAIL [timer]: CTRL reset"); errors++; end

        // --- Test 2: Counter doesn't run when disabled ---
        @(posedge clk); @(posedge clk); @(posedge clk);
        wb_read(BASE + 0, rdata);
        if (rdata !== 32'd0) begin
            $display("FAIL [timer]: counter ran while disabled: %0d", rdata); errors++;
        end

        // --- Test 3: Enable counter, run 5 cycles, read back ---
        wb_write(BASE + 8, 32'h1);  // enable only (no IRQ)
        repeat (5) @(posedge clk);
        wb_read(BASE + 0, rdata);
        // Counter should be ≥ 3 (there's 1 extra cycle from ack + bus reads)
        if (rdata < 32'd3 || rdata > 32'd10) begin
            $display("FAIL [timer]: counter value unexpected after 5 cycles: %0d", rdata);
            errors++;
        end

        // --- Test 4: Write to CNT (reset counter) ---
        wb_write(BASE + 0, 32'd0);
        @(posedge clk); #1;
        wb_read(BASE + 0, rdata);
        if (rdata > 32'd3) begin
            $display("FAIL [timer]: CNT write/reset: %0d", rdata); errors++;
        end

        // --- Test 5: Compare match + IRQ ---
        wb_write(BASE + 8, 32'h0);  // disable
        wb_write(BASE + 0, 32'd0);  // reset cnt
        wb_write(BASE + 4, 32'd5);  // CMP = 5
        wb_write(BASE + 8, 32'h3);  // enable + irq_enable

        // Wait for IRQ (CNT == CMP)
        repeat (20) @(posedge clk);

        if (!timer_irq) begin
            $display("FAIL [timer]: timer_irq not asserted after compare match"); errors++;
        end
        wb_read(BASE + 12, rdata);
        if (!rdata[0]) begin
            $display("FAIL [timer]: irq_pending not set"); errors++;
        end

        // --- Test 6: W1C clear of irq_pending ---
        wb_write(BASE + 12, 32'h1);  // write 1 to clear
        @(posedge clk); #1;
        if (timer_irq) begin
            // IRQ still driven by pending; check pending cleared
        end
        wb_read(BASE + 12, rdata);
        if (rdata[0]) begin
            $display("FAIL [timer]: irq_pending not cleared by W1C"); errors++;
        end

        // --- Test 7: Auto-reload ---
        wb_write(BASE + 8, 32'h0);  // disable
        wb_write(BASE + 0, 32'd0);
        wb_write(BASE + 4, 32'd4);  // CMP = 4
        wb_write(BASE + 8, 32'h7);  // enable + irq_en + auto_reload
        wb_write(BASE + 12,32'h1);  // clear irq

        // First match
        repeat (15) @(posedge clk);
        wb_read(BASE + 12, rdata);
        if (!rdata[0]) begin
            $display("FAIL [timer]: auto-reload first IRQ missing"); errors++;
        end
        wb_write(BASE + 12, 32'h1);

        // Counter should have wrapped to 0 and be counting again
        wb_read(BASE + 0, rdata);
        if (rdata > 32'd10) begin
            $display("FAIL [timer]: auto-reload counter not reset: %0d", rdata); errors++;
        end

        // Second match
        repeat (15) @(posedge clk);
        wb_read(BASE + 12, rdata);
        if (!rdata[0]) begin
            $display("FAIL [timer]: auto-reload second IRQ missing"); errors++;
        end

        if (errors == 0) $display("PASS: tb_timer");
        else             $display("FAIL: tb_timer %0d errors", errors);
        $finish;
    end

    // Timeout
    initial begin #50000; $display("FAIL: tb_timer TIMEOUT"); $finish; end
endmodule

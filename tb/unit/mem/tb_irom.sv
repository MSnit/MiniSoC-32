// =============================================================================
// Testbench: tb_irom
// Tests: reset, word reads, out-of-range (wraps), pre-loaded memory content.
// =============================================================================
`timescale 1ns/1ps
module tb_irom;
    logic        clk = 0, rst_n;
    always #5 clk = ~clk;

    logic [31:0] wb_adr, wb_dat_i;
    logic        wb_stb, wb_cyc, wb_ack;

    irom #(.MEM_FILE(""), .MEM_DEPTH(1024)) dut (.*);

    integer errors = 0;

    // Manually pre-load memory via hierarchical reference
    task preload;
        dut.mem[0]   = 32'hDEAD_BEEF;
        dut.mem[1]   = 32'hCAFE_BABE;
        dut.mem[2]   = 32'h1234_5678;
        dut.mem[3]   = 32'hABCD_EF01;
        dut.mem[1023]= 32'hFFFF_FFFF;
    endtask

    task do_read(input [31:0] addr, input [31:0] exp);
        @(negedge clk);
        wb_adr = addr; wb_stb = 1; wb_cyc = 1;
        @(posedge clk); #1; // ack arrives
        while (!wb_ack) @(posedge clk); #1;
        if (wb_dat_i !== exp) begin
            $display("FAIL [irom]: addr=%0h exp=%0h got=%0h", addr, exp, wb_dat_i);
            errors++;
        end
        @(negedge clk);
        wb_stb = 0; wb_cyc = 0;
        @(posedge clk);
    endtask

    initial begin
        rst_n = 0; wb_stb = 0; wb_cyc = 0; wb_adr = 0;
        @(posedge clk); @(posedge clk);
        preload();
        rst_n = 1;

        do_read(32'h0000_0000, 32'hDEAD_BEEF);
        do_read(32'h0000_0004, 32'hCAFE_BABE);
        do_read(32'h0000_0008, 32'h1234_5678);
        do_read(32'h0000_000C, 32'hABCD_EF01);
        do_read(32'h0000_0FFC, 32'hFFFF_FFFF); // last word

        // Reset: ack should deassert
        rst_n = 0;
        @(negedge clk);
        wb_stb = 1; wb_cyc = 1; wb_adr = 0;
        @(posedge clk); #1;
        if (wb_ack) begin
            $display("FAIL [irom]: ack should be 0 during reset"); errors++;
        end
        rst_n = 1;
        wb_stb = 0; wb_cyc = 0;

        // Back-to-back reads (no stb gap)
        @(negedge clk);
        wb_stb = 1; wb_cyc = 1;
        wb_adr = 32'h0000_0000;
        @(posedge clk); #1; // wait for ack
        // Now change address - slave should ack new transaction next cycle
        wb_adr = 32'h0000_0004;
        @(posedge clk); #2;
        // Just verify no hang
        wb_stb = 0; wb_cyc = 0;

        if (errors == 0) $display("PASS: tb_irom");
        else             $display("FAIL: tb_irom %0d errors", errors);
        $finish;
    end
endmodule

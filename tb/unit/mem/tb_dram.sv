// =============================================================================
// Testbench: tb_dram
// Tests: word/halfword/byte read+write with byte enables, reset behavior.
// =============================================================================
`timescale 1ns/1ps
module tb_dram;
    logic        clk = 0, rst_n;
    always #5 clk = ~clk;

    logic [31:0] wb_adr, wb_dat_o, wb_dat_i;
    logic        wb_we, wb_stb, wb_cyc, wb_ack;
    logic [3:0]  wb_sel;

    dram #(.MEM_DEPTH(1024)) dut (.*);

    integer errors = 0;

    task do_write(input [31:0] addr, input [31:0] data, input [3:0] sel);
        @(negedge clk);
        wb_adr = addr; wb_dat_o = data; wb_we = 1; wb_sel = sel; wb_stb = 1; wb_cyc = 1;
        @(posedge clk); #1;
        while (!wb_ack) @(posedge clk); #1;
        @(negedge clk);
        wb_stb = 0; wb_cyc = 0; wb_we = 0;
        @(posedge clk);
    endtask

    task do_read(input [31:0] addr, input [31:0] exp, input [3:0] sel);
        @(negedge clk);
        wb_adr = addr; wb_we = 0; wb_sel = sel; wb_stb = 1; wb_cyc = 1;
        @(posedge clk); #1;
        while (!wb_ack) @(posedge clk); #1;
        if (wb_dat_i !== exp) begin
            $display("FAIL [dram]: addr=%0h sel=%0b exp=%0h got=%0h", addr, sel, exp, wb_dat_i);
            errors++;
        end
        @(negedge clk);
        wb_stb = 0; wb_cyc = 0;
        @(posedge clk);
    endtask

    initial begin
        rst_n = 0; wb_stb = 0; wb_cyc = 0; wb_we = 0; wb_sel = 4'hF;
        wb_adr = 0; wb_dat_o = 0;
        @(posedge clk); @(posedge clk);
        rst_n = 1;

        // Word write + read
        do_write(32'h0001_0000, 32'hDEAD_BEEF, 4'hF);
        do_read (32'h0001_0000, 32'hDEAD_BEEF, 4'hF);

        // Byte write (sel=0001 → byte 0)
        do_write(32'h0001_0004, 32'hFF_FF_FF_AA, 4'b0001); // only byte 0 written
        do_write(32'h0001_0004, 32'hFF_FF_BB_00, 4'b0010); // only byte 1 written
        do_write(32'h0001_0004, 32'hFF_CC_00_00, 4'b0100); // only byte 2 written
        do_write(32'h0001_0004, 32'hDD_00_00_00, 4'b1000); // only byte 3 written
        do_read (32'h0001_0004, 32'hDD_CC_BB_AA, 4'hF);   // full word read

        // Halfword write (sel=0011 → bytes 0+1)
        do_write(32'h0001_0008, 32'h0000_1234, 4'b0011);
        do_write(32'h0001_0008, 32'h5678_0000, 4'b1100);
        do_read (32'h0001_0008, 32'h5678_1234, 4'hF);

        // Multiple addresses
        for (int i = 0; i < 16; i++) begin
            do_write(32'h0001_0000 + i*4, 32'hA000_0000 | i, 4'hF);
        end
        for (int i = 0; i < 16; i++) begin
            do_read(32'h0001_0000 + i*4, 32'hA000_0000 | i, 4'hF);
        end

        // Reset check: ack deasserts
        rst_n = 0;
        @(negedge clk);
        wb_stb = 1; wb_cyc = 1; wb_adr = 0;
        @(posedge clk); #1;
        if (wb_ack) begin
            $display("FAIL [dram]: ack should be 0 during reset"); errors++;
        end
        rst_n = 1; wb_stb = 0; wb_cyc = 0;

        if (errors == 0) $display("PASS: tb_dram");
        else             $display("FAIL: tb_dram %0d errors", errors);
        $finish;
    end
endmodule

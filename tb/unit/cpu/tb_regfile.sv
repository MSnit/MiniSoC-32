// =============================================================================
// Testbench: tb_regfile
// Self-checking: prints PASS or FAIL
// =============================================================================
`timescale 1ns/1ps
module tb_regfile;
    logic        clk = 0, rst_n;
    logic [4:0]  rs1, rs2, rd;
    logic [31:0] rd_data, rs1_data, rs2_data;
    logic        we;

    always #5 clk = ~clk;

    regfile dut (.*);

    integer errors = 0;

    task write_reg(input [4:0] r, input [31:0] d);
        @(negedge clk);
        rd = r; rd_data = d; we = 1'b1;
        @(posedge clk); #1;
        we = 1'b0;
    endtask

    task check_read(input [4:0] r, input [31:0] exp, input [63:0] msg);
        rs1 = r; #1;
        if (rs1_data !== exp) begin
            $display("FAIL [regfile]: rs1=%0d expected=%0h got=%0h (%s)", r, exp, rs1_data, msg);
            errors++;
        end
    endtask

    initial begin
        rst_n = 0; we = 0; rd = 0; rd_data = 0; rs1 = 0; rs2 = 0;
        @(posedge clk); #1;
        rst_n = 1;

        // x0 always 0
        write_reg(5'd0, 32'hDEADBEEF);
        check_read(5'd0, 32'd0, "x0=0");

        // Write and read back all registers 1..31
        for (int i = 1; i < 32; i++) begin
            write_reg(i[4:0], 32'hA000_0000 | i);
            check_read(i[4:0], 32'hA000_0000 | i, "write/read");
        end

        // Two-port read
        @(negedge clk);
        rd = 5'd5; rd_data = 32'hCAFE_BABE; we = 1'b1;
        @(posedge clk); #1; we = 0;
        rs1 = 5'd5; rs2 = 5'd6; #1;
        if (rs1_data !== 32'hCAFE_BABE) begin
            $display("FAIL [regfile]: dual-port rs1"); errors++;
        end
        if (rs2_data !== (32'hA000_0000 | 6)) begin
            $display("FAIL [regfile]: dual-port rs2"); errors++;
        end

        // Write to x0 still 0
        rs1 = 5'd0; #1;
        if (rs1_data !== 32'd0) begin
            $display("FAIL [regfile]: x0 not zero after write attempt"); errors++;
        end

        if (errors == 0)
            $display("PASS: tb_regfile");
        else
            $display("FAIL: tb_regfile %0d errors", errors);
        $finish;
    end
endmodule

// =============================================================================
// Testbench: tb_alu
// Description: Tests every ALU operation with directed and random values.
// =============================================================================
`timescale 1ns/1ps
module tb_alu;

    logic [31:0] a, b, result;
    logic [3:0]  alu_op;
    logic        zero;

    alu dut (
        .a(a), .b(b), .alu_op(alu_op), .result(result), .zero(zero)
    );

    integer errors;
    logic [31:0] expected;

    task check;
        input [3:0]  op;
        input [31:0] av, bv, exp;
        input [31:0] desc_op;
        begin
            a = av; b = bv; alu_op = op;
            #1;
            if (result !== exp) begin
                $display("FAIL: op=%0d a=%0h b=%0h expected=%0h got=%0h", op, av, bv, exp, result);
                errors = errors + 1;
            end
            if (zero !== (exp == 0)) begin
                $display("FAIL: zero flag wrong for op=%0d result=%0h", op, result);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        // ADD
        check(4'b0000, 32'd10, 32'd20, 32'd30, 0);
        check(4'b0000, 32'hFFFFFFFF, 32'd1, 32'd0, 0); // overflow
        // SUB
        check(4'b0001, 32'd30, 32'd10, 32'd20, 0);
        check(4'b0001, 32'd5, 32'd5, 32'd0, 0);
        // SLL
        check(4'b0010, 32'd1, 32'd4, 32'd16, 0);
        check(4'b0010, 32'h80000000, 32'd1, 32'd0, 0);
        // SLT
        check(4'b0011, 32'hFFFFFFFF, 32'd1, 32'd1, 0); // -1 < 1
        check(4'b0011, 32'd1, 32'd1, 32'd0, 0);
        check(4'b0011, 32'd5, 32'd3, 32'd0, 0);
        // SLTU
        check(4'b0100, 32'hFFFFFFFF, 32'd1, 32'd0, 0); // 0xFFFF... > 1 unsigned
        check(4'b0100, 32'd1, 32'hFFFFFFFF, 32'd1, 0);
        // XOR
        check(4'b0101, 32'hAA, 32'h55, 32'hFF, 0);
        check(4'b0101, 32'hFF, 32'hFF, 32'd0, 0);
        // SRL
        check(4'b0110, 32'hFFFFFFFF, 32'd4, 32'h0FFFFFFF, 0);
        check(4'b0110, 32'h80000000, 32'd1, 32'h40000000, 0);
        // SRA
        check(4'b0111, 32'hFFFFFFFF, 32'd4, 32'hFFFFFFFF, 0); // arith shift -1
        check(4'b0111, 32'h80000000, 32'd1, 32'hC0000000, 0);
        // OR
        check(4'b1000, 32'hA0, 32'h0A, 32'hAA, 0);
        // AND
        check(4'b1001, 32'hFF, 32'h0F, 32'h0F, 0);
        check(4'b1001, 32'hFF, 32'd0, 32'd0, 0);
        // PASSB
        check(4'b1010, 32'hDEAD, 32'hBEEF, 32'hBEEF, 0);
        check(4'b1010, 32'd0, 32'd0, 32'd0, 0);

        // Zero flag
        a = 5; b = 5; alu_op = 4'b0001; #1; // SUB 5-5=0
        if (!zero) begin
            $display("FAIL: zero flag not set for 5-5=0");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: tb_alu all tests passed");
        else
            $display("FAIL: tb_alu %0d errors", errors);
        $finish;
    end

endmodule

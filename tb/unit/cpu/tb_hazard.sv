// =============================================================================
// Testbench: tb_hazard
// Tests forwarding, load-use stall, branch flush, irq/mret flush
// =============================================================================
`timescale 1ns/1ps
module tb_hazard;
    // Inputs
    logic [4:0] id_ex_rs1, id_ex_rs2, id_ex_rd;
    logic       id_ex_mem_read;
    logic [4:0] ex_mem_rd;
    logic       ex_mem_reg_write;
    logic [4:0] mem_wb_rd;
    logic       mem_wb_reg_write;
    logic [4:0] if_id_rs1, if_id_rs2;
    logic       branch_taken, jump, irq_taken, mret_taken;
    // Outputs
    logic [1:0] fwd_a, fwd_b;
    logic       stall_if, stall_id, flush_if_id, flush_id_ex, flush_ex_mem;

    hazard_unit dut (.*);

    integer errors = 0;

    task check_fwd(
        input [4:0] rs1_in, rs2_in,
        input [4:0] em_rd,  input em_rw,
        input [4:0] mw_rd,  input mw_rw,
        input [1:0] exp_a, exp_b,
        input [63:0] msg
    );
        id_ex_rs1 = rs1_in; id_ex_rs2 = rs2_in; id_ex_rd = 0;
        ex_mem_rd = em_rd;  ex_mem_reg_write = em_rw;
        mem_wb_rd = mw_rd;  mem_wb_reg_write = mw_rw;
        id_ex_mem_read = 0; branch_taken = 0; jump = 0; irq_taken = 0; mret_taken = 0;
        if_id_rs1 = 0; if_id_rs2 = 0;
        #1;
        if (fwd_a !== exp_a || fwd_b !== exp_b) begin
            $display("FAIL [hazard fwd] %s: fwd_a=%b(exp %b) fwd_b=%b(exp %b)",
                     msg, fwd_a, exp_a, fwd_b, exp_b);
            errors++;
        end
    endtask

    initial begin
        // Default all inputs off
        id_ex_rs1=0; id_ex_rs2=0; id_ex_rd=0; id_ex_mem_read=0;
        ex_mem_rd=0; ex_mem_reg_write=0;
        mem_wb_rd=0; mem_wb_reg_write=0;
        if_id_rs1=0; if_id_rs2=0;
        branch_taken=0; jump=0; irq_taken=0; mret_taken=0;
        #1;

        // --- Forwarding: no hazard ---
        check_fwd(5'd1, 5'd2, 5'd3, 1, 5'd4, 1, 2'b00, 2'b00, "no_fwd");

        // --- EX/MEM forward A ---
        check_fwd(5'd1, 5'd2, 5'd1, 1, 5'd9, 1, 2'b01, 2'b00, "fwd_a_exmem");

        // --- MEM/WB forward A ---
        check_fwd(5'd1, 5'd2, 5'd9, 0, 5'd1, 1, 2'b10, 2'b00, "fwd_a_memwb");

        // --- EX/MEM forward B ---
        check_fwd(5'd3, 5'd2, 5'd2, 1, 5'd9, 1, 2'b00, 2'b01, "fwd_b_exmem");

        // --- EX/MEM takes priority over MEM/WB ---
        check_fwd(5'd1, 5'd2, 5'd1, 1, 5'd1, 1, 2'b01, 2'b00, "exmem_priority");

        // --- x0 never forwarded ---
        check_fwd(5'd0, 5'd0, 5'd0, 1, 5'd0, 1, 2'b00, 2'b00, "x0_no_fwd");

        // --- Load-use stall ---
        id_ex_rs1 = 5'd0; id_ex_rs2 = 5'd0;
        id_ex_mem_read = 1'b1;
        id_ex_rd = 5'd5;  // EX stage load targeting rd=5
        if_id_rs1 = 5'd5; // ID stage uses rs1=5
        if_id_rs2 = 5'd6;
        branch_taken = 0; jump = 0; irq_taken = 0; mret_taken = 0;
        #1;
        if (!stall_if || !stall_id || !flush_id_ex) begin
            $display("FAIL [hazard]: load-use stall not asserted stall_if=%b stall_id=%b flush_id_ex=%b",
                     stall_if, stall_id, flush_id_ex);
            errors++;
        end
        if (flush_if_id || flush_ex_mem) begin
            $display("FAIL [hazard]: load-use should not flush if_id or ex_mem");
            errors++;
        end

        // No stall when rd=x0
        id_ex_rd = 5'd0;
        if_id_rs1 = 5'd0; if_id_rs2 = 5'd0; #1;
        if (stall_if) begin
            $display("FAIL [hazard]: load-use false positive for x0"); errors++;
        end

        // --- Branch flush ---
        id_ex_mem_read = 0; id_ex_rd = 0; if_id_rs1 = 0; if_id_rs2 = 0;
        branch_taken = 1; jump = 0; irq_taken = 0; mret_taken = 0; #1;
        if (!flush_if_id || !flush_id_ex) begin
            $display("FAIL [hazard]: branch flush not asserted"); errors++;
        end
        if (stall_if || stall_id || flush_ex_mem) begin
            $display("FAIL [hazard]: branch flush extra signals"); errors++;
        end

        // --- Jump flush ---
        branch_taken = 0; jump = 1; irq_taken = 0; mret_taken = 0; #1;
        if (!flush_if_id || !flush_id_ex) begin
            $display("FAIL [hazard]: jump flush not asserted"); errors++;
        end

        // --- IRQ flush ---
        branch_taken = 0; jump = 0; irq_taken = 1; mret_taken = 0; #1;
        if (!flush_if_id || !flush_id_ex || !flush_ex_mem) begin
            $display("FAIL [hazard]: irq flush not asserted"); errors++;
        end

        // --- MRET flush ---
        branch_taken = 0; jump = 0; irq_taken = 0; mret_taken = 1; #1;
        if (!flush_if_id || !flush_id_ex || !flush_ex_mem) begin
            $display("FAIL [hazard]: mret flush not asserted"); errors++;
        end

        // --- No stall/flush when idle ---
        id_ex_mem_read = 0; branch_taken = 0; jump = 0; irq_taken = 0; mret_taken = 0;
        if_id_rs1 = 5'd7; if_id_rs2 = 5'd8;
        ex_mem_rd = 5'd3; ex_mem_reg_write = 0; #1;
        if (stall_if || stall_id || flush_if_id || flush_id_ex || flush_ex_mem) begin
            $display("FAIL [hazard]: spurious hazard signals in idle"); errors++;
        end

        if (errors == 0)
            $display("PASS: tb_hazard");
        else
            $display("FAIL: tb_hazard %0d errors", errors);
        $finish;
    end
endmodule

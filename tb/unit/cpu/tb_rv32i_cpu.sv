// =============================================================================
// Testbench: tb_rv32i_cpu
// Full CPU test using embedded instruction memory.
// Tests: R/I-type ALU, loads/stores, branches, JAL/JALR, LUI/AUIPC,
//        forwarding, load-use stall, CSR, timer IRQ, MRET.
// Pass criterion: CPU writes 0xDEADBEEF to DRAM address 0 and halts.
// =============================================================================
`timescale 1ns/1ps
module tb_rv32i_cpu;

    logic        clk = 0, rst_n;
    always #5 clk = ~clk;  // 100 MHz (10 ns period)

    // -------------------------------------------------------------------------
    // Wishbone masters from CPU
    // -------------------------------------------------------------------------
    logic [31:0] imem_adr, imem_dat_i;
    logic        imem_stb, imem_cyc, imem_ack, imem_err;

    logic [31:0] dmem_adr, dmem_dat_o, dmem_dat_i;
    logic        dmem_we, dmem_stb, dmem_cyc, dmem_ack, dmem_err;
    logic [3:0]  dmem_sel;

    logic        timer_irq = 0;

    // -------------------------------------------------------------------------
    // DUT: CPU
    // -------------------------------------------------------------------------
    rv32i_cpu dut (
        .clk           (clk),          .rst_n         (rst_n),
        .imem_wb_adr   (imem_adr),     .imem_wb_stb   (imem_stb),
        .imem_wb_cyc   (imem_cyc),     .imem_wb_dat_i (imem_dat_i),
        .imem_wb_ack   (imem_ack),     .imem_wb_err   (imem_err),
        .dmem_wb_adr   (dmem_adr),     .dmem_wb_dat_o (dmem_dat_o),
        .dmem_wb_we    (dmem_we),      .dmem_wb_sel   (dmem_sel),
        .dmem_wb_stb   (dmem_stb),     .dmem_wb_cyc   (dmem_cyc),
        .dmem_wb_dat_i (dmem_dat_i),   .dmem_wb_ack   (dmem_ack),
        .dmem_wb_err   (dmem_err),     .timer_irq     (timer_irq)
    );

    assign imem_err = 1'b0;
    assign dmem_err = 1'b0;

    // -------------------------------------------------------------------------
    // Instruction ROM (256 words = 1 KB for test program) - 0 wait state
    // -------------------------------------------------------------------------
    logic [31:0] irom [0:255];
    assign imem_dat_i = (imem_stb && imem_cyc) ? irom[imem_adr[9:2]] : 32'd0;
    assign imem_ack   = imem_stb && imem_cyc && rst_n;

    // -------------------------------------------------------------------------
    // Data RAM (256 words) - 0 wait state read, synchronous write
    // -------------------------------------------------------------------------
    logic [7:0] dram_b0[0:255], dram_b1[0:255], dram_b2[0:255], dram_b3[0:255];

    assign dmem_dat_i = (dmem_stb && dmem_cyc && !dmem_we) ?
                        {dram_b3[dmem_adr[9:2]], dram_b2[dmem_adr[9:2]],
                         dram_b1[dmem_adr[9:2]], dram_b0[dmem_adr[9:2]]} : 32'd0;
    assign dmem_ack   = dmem_stb && dmem_cyc && rst_n;

    always_ff @(posedge clk) begin
        if (rst_n && dmem_stb && dmem_cyc && dmem_we) begin
            if (dmem_sel[0]) dram_b0[dmem_adr[9:2]] <= dmem_dat_o[7:0];
            if (dmem_sel[1]) dram_b1[dmem_adr[9:2]] <= dmem_dat_o[15:8];
            if (dmem_sel[2]) dram_b2[dmem_adr[9:2]] <= dmem_dat_o[23:16];
            if (dmem_sel[3]) dram_b3[dmem_adr[9:2]] <= dmem_dat_o[31:24];
        end
    end

    // -------------------------------------------------------------------------
    // Helper: encode instructions
    // -------------------------------------------------------------------------
    // R-type
    function automatic [31:0] R(input [6:0] op, input [4:0] rd, input [2:0] f3,
                                input [4:0] rs1, input [4:0] rs2, input [6:0] f7);
        return {f7, rs2, rs1, f3, rd, op};
    endfunction
    // I-type
    function automatic [31:0] I(input [6:0] op, input [4:0] rd, input [2:0] f3,
                                input [4:0] rs1, input [11:0] imm);
        return {imm, rs1, f3, rd, op};
    endfunction
    // S-type
    function automatic [31:0] S(input [6:0] op, input [2:0] f3, input [4:0] rs1,
                                input [4:0] rs2, input [11:0] imm);
        return {imm[11:5], rs2, rs1, f3, imm[4:0], op};
    endfunction
    // B-type
    function automatic [31:0] B(input [6:0] op, input [2:0] f3, input [4:0] rs1,
                                input [4:0] rs2, input [12:0] imm);
        return {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], op};
    endfunction
    // U-type
    function automatic [31:0] U(input [6:0] op, input [4:0] rd, input [31:12] imm);
        return {imm, rd, op};
    endfunction
    // J-type (JAL)
    function automatic [31:0] J(input [4:0] rd, input [20:0] imm);
        return {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b110_1111};
    endfunction
    // CSR
    function automatic [31:0] CSR(input [11:0] addr, input [4:0] rd, input [2:0] f3,
                                  input [4:0] rs1);
        return {addr, rs1, f3, rd, 7'b111_0011};
    endfunction

    // Instruction aliases (opcodes)
    localparam OP_REG  = 7'b011_0011;
    localparam OP_IMM  = 7'b001_0011;
    localparam OP_LOAD = 7'b000_0011;
    localparam OP_STOR = 7'b010_0011;
    localparam OP_BRNC = 7'b110_0011;
    localparam OP_JALR = 7'b110_0111;
    localparam OP_LUI  = 7'b011_0111;
    localparam OP_AUI  = 7'b001_0111;

    // NOP = ADDI x0, x0, 0
    localparam NOP = 32'h0000_0013;
    localparam IRQ_VECTOR = 200; // word index 200 = byte addr 0x320

    integer pc_idx;
    logic [31:0] result;

    initial begin
        // Clear
        for (int i = 0; i < 256; i++) irom[i] = NOP;
        for (int i = 0; i < 256; i++) begin
            dram_b0[i]=0; dram_b1[i]=0; dram_b2[i]=0; dram_b3[i]=0;
        end

        pc_idx = 0;

        // =====================================================================
        // Section 1: Basic ALU R-type
        // =====================================================================
        // x1 = 10, x2 = 3
        irom[pc_idx++] = I(OP_IMM, 5'd1, 3'b000, 5'd0, 12'd10);  // ADDI x1, x0, 10
        irom[pc_idx++] = I(OP_IMM, 5'd2, 3'b000, 5'd0, 12'd3);   // ADDI x2, x0, 3
        irom[pc_idx++] = R(OP_REG, 5'd3, 3'b000, 5'd1, 5'd2, 7'b000_0000); // ADD x3=13
        irom[pc_idx++] = R(OP_REG, 5'd4, 3'b000, 5'd1, 5'd2, 7'b010_0000); // SUB x4=7
        irom[pc_idx++] = R(OP_REG, 5'd5, 3'b001, 5'd1, 5'd2, 7'b000_0000); // SLL x5=10<<3=80
        irom[pc_idx++] = R(OP_REG, 5'd6, 3'b101, 5'd5, 5'd2, 7'b000_0000); // SRL x6=80>>3=10
        irom[pc_idx++] = R(OP_REG, 5'd7, 3'b010, 5'd2, 5'd1, 7'b000_0000); // SLT x7=1 (3<10)
        irom[pc_idx++] = R(OP_REG, 5'd8, 3'b110, 5'd1, 5'd2, 7'b000_0000); // OR  x8=11
        irom[pc_idx++] = R(OP_REG, 5'd9, 3'b111, 5'd1, 5'd2, 7'b000_0000); // AND x9=2
        irom[pc_idx++] = R(OP_REG, 5'd10,3'b100, 5'd1, 5'd2, 7'b000_0000); // XOR x10=9
        // Accumulate: x10 = x3+x4+x5+x6+x7+x8+x9+x10 = 13+7+80+10+1+11+2+9 = 133
        irom[pc_idx++] = R(OP_REG, 5'd10,3'b000, 5'd10,5'd3, 7'b000_0000); // x10+=x3
        irom[pc_idx++] = R(OP_REG, 5'd10,3'b000, 5'd10,5'd4, 7'b000_0000); // x10+=x4
        irom[pc_idx++] = R(OP_REG, 5'd10,3'b000, 5'd10,5'd5, 7'b000_0000); // x10+=x5
        irom[pc_idx++] = R(OP_REG, 5'd10,3'b000, 5'd10,5'd6, 7'b000_0000); // x10+=x6
        irom[pc_idx++] = R(OP_REG, 5'd10,3'b000, 5'd10,5'd7, 7'b000_0000); // x10+=x7
        irom[pc_idx++] = R(OP_REG, 5'd10,3'b000, 5'd10,5'd8, 7'b000_0000); // x10+=x8
        irom[pc_idx++] = R(OP_REG, 5'd10,3'b000, 5'd10,5'd9, 7'b000_0000); // x10+=x9
        // Store intermediate to DRAM[1] to test SW
        irom[pc_idx++] = I(OP_IMM, 5'd20, 3'b000, 5'd0, 12'd4);  // ADDI x20, x0, 4 (addr=4)
        irom[pc_idx++] = S(OP_STOR, 3'b010, 5'd20, 5'd10, 12'd0); // SW x10, 0(x20)

        // =====================================================================
        // Section 2: Load-use hazard test (SW then LW with 1-cycle stall)
        // =====================================================================
        irom[pc_idx++] = I(OP_LOAD, 5'd11, 3'b010, 5'd20, 12'd0);  // LW x11, 0(x20)
        irom[pc_idx++] = R(OP_REG, 5'd12, 3'b000, 5'd11, 5'd1, 7'b000_0000); // ADD x12=x11+x1 (hazard)

        // =====================================================================
        // Section 3: Forwarding test (back-to-back RAW)
        // =====================================================================
        irom[pc_idx++] = I(OP_IMM, 5'd13, 3'b000, 5'd0, 12'd100); // ADDI x13=100
        irom[pc_idx++] = I(OP_IMM, 5'd13, 3'b000, 5'd13,12'd100); // ADDI x13=200 (RAW fwd)
        irom[pc_idx++] = I(OP_IMM, 5'd13, 3'b000, 5'd13,12'd100); // ADDI x13=300 (RAW fwd)

        // =====================================================================
        // Section 4: Branch taken (BNE: x1!=x2 -> taken)
        // =====================================================================
        // BNE x1, x2, +8 -> skip next NOP, land on ADDI x14
        irom[pc_idx++] = B(OP_BRNC, 3'b001, 5'd1, 5'd2, 13'sd8); // BNE +8
        irom[pc_idx++] = NOP;  // skipped if branch taken
        irom[pc_idx++] = I(OP_IMM, 5'd14, 3'b000, 5'd0, 12'd55);  // ADDI x14=55

        // =====================================================================
        // Section 5: JAL + JALR
        // =====================================================================
        // JAL x15, +8 (skip 1 instruction)
        irom[pc_idx++] = J(5'd15, 21'sd8);                          // JAL x15, +8
        irom[pc_idx++] = I(OP_IMM, 5'd16, 3'b000, 5'd0, 12'd99);   // skipped by JAL
        irom[pc_idx++] = I(OP_IMM, 5'd16, 3'b000, 5'd0, 12'd77);   // x16=77 (target)
        // JALR: x15 has address of skipped instruction (pc_idx-2)*4
        // To jump forward past the next NOP: jump to x15 + 16
        irom[pc_idx++] = I(OP_JALR, 5'd17, 3'b000, 5'd15, 12'd16); // JALR x17, x15, 16
        irom[pc_idx++] = NOP;                                       // skipped by JALR

        // =====================================================================
        // Section 6: LUI / ADDI to construct 0xDEADBEEF
        // =====================================================================
        irom[pc_idx++] = U(OP_LUI, 5'd18, 20'hDEADC);               // LUI x18 = 0xDEADC000
        irom[pc_idx++] = I(OP_IMM, 5'd18, 3'b000, 5'd18, 12'hEEF); // ADDI x18, -273 -> 0xDEADBEEF

        // =====================================================================
        // Section 7: CSR test (CSRRW mtvec, CSRRS mstatus)
        // =====================================================================
        irom[pc_idx++] = I(OP_IMM, 5'd19, 3'b000, 5'd0, 12'd0);    // ADDI x19=0 (irq counter)
        // Set mtvec to word 200 * 4 = 0x320
        irom[pc_idx++] = I(OP_IMM, 5'd28, 3'b000, 5'd0, 12'h320>>1);// x28 = 0x190
        irom[pc_idx++] = I(OP_IMM, 5'd28, 3'b001, 5'd28, 12'd1);    // SLLI x28, x28, 1 = 0x320
        irom[pc_idx++] = CSR(12'h305, 5'd0, 3'b001, 5'd28);         // CSRRW mtvec, x28

        // Enable machine timer interrupt: mie[7]=MTIE=1
        irom[pc_idx++] = I(OP_IMM, 5'd29, 3'b000, 5'd0, 12'd128);   // x29 = 0x80
        irom[pc_idx++] = CSR(12'h304, 5'd0, 3'b001, 5'd29);         // CSRRW mie, x29
        // Enable global interrupts: mstatus[3]=MIE=1
        irom[pc_idx++] = I(OP_IMM, 5'd30, 3'b000, 5'd0, 12'd8);     // x30 = 8
        irom[pc_idx++] = CSR(12'h300, 5'd0, 3'b010, 5'd30);         // CSRRS mstatus, x30

        // Spin waiting for irq: wait until x19 != 0
        irom[pc_idx++] = B(OP_BRNC, 3'b000, 5'd19, 5'd0, 13'sd0);   // BEQ x19, x0, 0 (loop until IRQ)

        // =====================================================================
        // Section 8: Final store of 0xDEADBEEF
        // =====================================================================
        irom[pc_idx++] = S(OP_STOR, 3'b010, 5'd0, 5'd18, 12'd0);   // SW x18, 0(x0) -> DRAM[0]=0xDEADBEEF
        // Halt: infinite loop
        irom[pc_idx++] = J(5'd0, 21'sd0); // JAL x0, 0 -> self-loop

        // =====================================================================
        // IRQ handler at word 200 (byte 0x320)
        // =====================================================================
        pc_idx = IRQ_VECTOR;
        irom[pc_idx++] = I(OP_IMM, 5'd19, 3'b000, 5'd19, 12'd1);   // ADDI x19, x19, 1
        irom[pc_idx++] = 32'h3020_0073;                             // MRET encoding

        $display("Program loaded: %0d instructions", pc_idx);

        // =====================================================================
        // Run simulation
        // =====================================================================
        rst_n = 0;
        @(posedge clk); @(posedge clk);
        rst_n = 1;

        // After ~80 cycles, pulse timer_irq for 5 cycles
        repeat (80) @(posedge clk);
        timer_irq = 1;
        repeat (5) @(posedge clk);
        timer_irq = 0;

        // Wait for halt (up to 500 cycles)
        repeat (500) @(posedge clk);

        // Check result
        result = {dram_b3[0], dram_b2[0], dram_b1[0], dram_b0[0]};
        if (result === 32'hDEAD_BEEF) begin
            $display("PASS: tb_rv32i_cpu -- DRAM[0]=0x%08h", result);
        end else begin
            $display("FAIL: tb_rv32i_cpu -- DRAM[0]=0x%08h (expected 0xDEADBEEF)", result);
        end
        $finish;
    end

    // Timeout watchdog
    initial begin
        #100000;
        $display("FAIL: tb_rv32i_cpu -- TIMEOUT");
        $finish;
    end

endmodule

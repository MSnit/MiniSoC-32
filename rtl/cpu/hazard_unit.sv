// =============================================================================
// Module:      hazard_unit
// Description: Detects and resolves pipeline hazards:
//              1. Data forwarding: EX→EX (EX/MEM result) and MEM→EX (MEM/WB result)
//              2. Load-use stall: 1-cycle stall when EX stage is a load and its
//                 destination matches ID stage rs1 or rs2
//              3. Branch/Jump flush: flushes IF/ID and ID/EX when branch taken
//                 or jump (2-cycle penalty)
//              4. Interrupt / MRET flush: flushes IF/ID, ID/EX, EX/MEM
// Forwarding select encoding:
//   2'b00 = no forward (use register file output)
//   2'b01 = forward from EX/MEM (ALU result)
//   2'b10 = forward from MEM/WB (WB result: ALU or mem_data)
// =============================================================================
module hazard_unit (
    // ID/EX pipeline register fields
    input  logic [4:0]  id_ex_rs1,
    input  logic [4:0]  id_ex_rs2,
    input  logic [4:0]  id_ex_rd,
    input  logic        id_ex_mem_read,

    // EX/MEM pipeline register fields
    input  logic [4:0]  ex_mem_rd,
    input  logic        ex_mem_reg_write,

    // MEM/WB pipeline register fields
    input  logic [4:0]  mem_wb_rd,
    input  logic        mem_wb_reg_write,

    // ID stage instruction fields (for load-use detection)
    input  logic [4:0]  if_id_rs1,
    input  logic [4:0]  if_id_rs2,

    // Branch/jump taken (from EX stage)
    input  logic        branch_taken,
    input  logic        jump,

    // Interrupt / MRET taken (from MEM stage)
    input  logic        irq_taken,
    input  logic        mret_taken,

    // Forwarding selects
    output logic [1:0]  fwd_a,   // EX stage: ALU operand A
    output logic [1:0]  fwd_b,   // EX stage: ALU operand B

    // Stall signals
    output logic        stall_if,      // stall PC and IF/ID register
    output logic        stall_id,      // stall IF/ID register

    // Flush signals
    output logic        flush_if_id,   // insert NOP into IF/ID
    output logic        flush_id_ex,   // insert NOP into ID/EX
    output logic        flush_ex_mem   // insert NOP into EX/MEM
);

    // ---------------------------------------------------------------------------
    // Forwarding logic (EX stage)
    // EX/MEM forward takes priority over MEM/WB
    // ---------------------------------------------------------------------------
    always_comb begin
        // Forward for ALU operand A (rs1)
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1))
            fwd_a = 2'b01; // EX/MEM forward
        else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1))
            fwd_a = 2'b10; // MEM/WB forward
        else
            fwd_a = 2'b00; // no forward

        // Forward for ALU operand B (rs2)
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2))
            fwd_b = 2'b01; // EX/MEM forward
        else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2))
            fwd_b = 2'b10; // MEM/WB forward
        else
            fwd_b = 2'b00; // no forward
    end

    // ---------------------------------------------------------------------------
    // Load-use hazard detection
    // EX stage is a load AND destination matches ID stage rs1 or rs2
    // ---------------------------------------------------------------------------
    logic load_use_hazard;
    assign load_use_hazard = id_ex_mem_read && (id_ex_rd != 5'd0) &&
                             ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));

    // ---------------------------------------------------------------------------
    // Stall and flush generation
    // ---------------------------------------------------------------------------
    always_comb begin
        stall_if     = 1'b0;
        stall_id     = 1'b0;
        flush_if_id  = 1'b0;
        flush_id_ex  = 1'b0;
        flush_ex_mem = 1'b0;

        if (irq_taken || mret_taken) begin
            // Flush entire front end and EX/MEM
            flush_if_id  = 1'b1;
            flush_id_ex  = 1'b1;
            flush_ex_mem = 1'b1;
        end else if (load_use_hazard) begin
            // Stall PC and IF/ID; flush ID/EX (insert bubble)
            stall_if    = 1'b1;
            stall_id    = 1'b1;
            flush_id_ex = 1'b1;
        end else if (branch_taken || jump) begin
            // Flush 2 stages (IF and ID)
            flush_if_id = 1'b1;
            flush_id_ex = 1'b1;
        end
    end

endmodule

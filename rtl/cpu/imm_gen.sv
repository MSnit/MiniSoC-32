// =============================================================================
// Module:      imm_gen
// Description: Immediate generator for all RV32I instruction formats.
// =============================================================================
/* verilator lint_off UNUSEDSIGNAL */
module imm_gen (
    input  logic [31:0] instr,
    input  logic [2:0]  imm_type,
    output logic [31:0] imm_out
);
    localparam IMM_I = 3'b000;
    localparam IMM_S = 3'b001;
    localparam IMM_B = 3'b010;
    localparam IMM_U = 3'b011;
    localparam IMM_J = 3'b100;

    logic sign;
    assign sign = instr[31];

    always_comb begin
        case (imm_type)
            IMM_I:   imm_out = {{20{sign}}, instr[31:20]};
            IMM_S:   imm_out = {{20{sign}}, instr[31:25], instr[11:7]};
            IMM_B:   imm_out = {{19{sign}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            IMM_U:   imm_out = {instr[31:12], 12'd0};
            IMM_J:   imm_out = {{11{sign}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            default: imm_out = 32'd0;
        endcase
    end
endmodule
/* verilator lint_on UNUSEDSIGNAL */

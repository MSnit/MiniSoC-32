// =============================================================================
// Module:      control
// Description: Main decode/control unit for RV32I.
//              Decodes opcode + funct3 + funct7 and generates control signals.
//
// alu_op encoding (4 bits): matches alu.sv
//   ADD=0, SUB=1, SLL=2, SLT=3, SLTU=4, XOR=5, SRL=6, SRA=7, OR=8, AND=9, PASSB=10
//
// imm_type: 000=I, 001=S, 010=B, 011=U, 100=J
//
// csr_op: 00=none, 01=CSRRW, 10=CSRRS, 11=MRET
//
// branch_op: only valid when branch=1; encodes funct3 directly (BEQ=000…BGEU=111)
//
// pc_as_alu_a: 1 for AUIPC and JAL (forces A input of ALU to be PC)
// is_jalr:     1 for JALR only
// =============================================================================
/* verilator lint_off UNUSEDSIGNAL */
module control (
    input  logic [6:0]  opcode,
    input  logic [2:0]  funct3,
    input  logic [6:0]  funct7,
    output logic [3:0]  alu_op,
    output logic        alu_src,       // 0=rs2, 1=imm
    output logic        mem_read,
    output logic        mem_write,
    output logic [1:0]  mem_size,      // 00=byte,01=half,10=word
    output logic        mem_signed,    // 1=signed for LB/LH
    output logic        reg_write,
    output logic        mem_to_reg,    // 0=ALU, 1=memory
    output logic        branch,
    output logic [2:0]  branch_op,     // funct3 for branch condition
    output logic        jump,          // JAL or JALR
    output logic        is_jalr,       // JALR specifically
    output logic [2:0]  imm_type,
    output logic [1:0]  csr_op,
    output logic        pc_as_alu_a    // AUIPC and JAL: use PC as ALU A input
);

    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_SLL  = 4'b0010;
    localparam ALU_SLT  = 4'b0011;
    localparam ALU_SLTU = 4'b0100;
    localparam ALU_XOR  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_OR   = 4'b1000;
    localparam ALU_AND  = 4'b1001;
    localparam ALU_PASSB= 4'b1010;

    localparam IMM_I = 3'b000;
    localparam IMM_S = 3'b001;
    localparam IMM_B = 3'b010;
    localparam IMM_U = 3'b011;
    localparam IMM_J = 3'b100;

    localparam CSR_NONE = 2'b00;
    localparam CSR_RW   = 2'b01;
    localparam CSR_RS   = 2'b10;
    localparam CSR_MRET = 2'b11;

    always_comb begin
        alu_op      = ALU_ADD;
        alu_src     = 1'b0;
        mem_read    = 1'b0;
        mem_write   = 1'b0;
        mem_size    = 2'b10;
        mem_signed  = 1'b1;
        reg_write   = 1'b0;
        mem_to_reg  = 1'b0;
        branch      = 1'b0;
        branch_op   = 3'b000;
        jump        = 1'b0;
        is_jalr     = 1'b0;
        imm_type    = IMM_I;
        csr_op      = CSR_NONE;
        pc_as_alu_a = 1'b0;

        case (opcode)
            // R-type
            7'b0110011: begin
                reg_write = 1'b1;
                case ({funct7[5], funct3})
                    4'b0000: alu_op = ALU_ADD;
                    4'b1000: alu_op = ALU_SUB;
                    4'b0001: alu_op = ALU_SLL;
                    4'b0010: alu_op = ALU_SLT;
                    4'b0011: alu_op = ALU_SLTU;
                    4'b0100: alu_op = ALU_XOR;
                    4'b0101: alu_op = ALU_SRL;
                    4'b1101: alu_op = ALU_SRA;
                    4'b0110: alu_op = ALU_OR;
                    4'b0111: alu_op = ALU_AND;
                    default: alu_op = ALU_ADD;
                endcase
            end

            // I-type ALU
            7'b0010011: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                imm_type  = IMM_I;
                case (funct3)
                    3'b000: alu_op = ALU_ADD;
                    3'b010: alu_op = ALU_SLT;
                    3'b011: alu_op = ALU_SLTU;
                    3'b100: alu_op = ALU_XOR;
                    3'b110: alu_op = ALU_OR;
                    3'b111: alu_op = ALU_AND;
                    3'b001: alu_op = ALU_SLL;
                    3'b101: alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                    default: alu_op = ALU_ADD;
                endcase
            end

            // Loads
            7'b0000011: begin
                reg_write  = 1'b1;
                mem_read   = 1'b1;
                mem_to_reg = 1'b1;
                alu_src    = 1'b1;
                alu_op     = ALU_ADD;
                imm_type   = IMM_I;
                case (funct3)
                    3'b000: begin mem_size = 2'b00; mem_signed = 1'b1; end // LB
                    3'b001: begin mem_size = 2'b01; mem_signed = 1'b1; end // LH
                    3'b010: begin mem_size = 2'b10; mem_signed = 1'b1; end // LW
                    3'b100: begin mem_size = 2'b00; mem_signed = 1'b0; end // LBU
                    3'b101: begin mem_size = 2'b01; mem_signed = 1'b0; end // LHU
                    default: begin mem_size = 2'b10; mem_signed = 1'b1; end
                endcase
            end

            // Stores
            7'b0100011: begin
                mem_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = ALU_ADD;
                imm_type  = IMM_S;
                case (funct3)
                    3'b000: mem_size = 2'b00; // SB
                    3'b001: mem_size = 2'b01; // SH
                    3'b010: mem_size = 2'b10; // SW
                    default: mem_size = 2'b10;
                endcase
            end

            // Branches
            7'b1100011: begin
                branch    = 1'b1;
                branch_op = funct3;
                imm_type  = IMM_B;
                case (funct3)
                    3'b000,3'b001: alu_op = ALU_SUB;  // BEQ, BNE
                    3'b100,3'b101: alu_op = ALU_SLT;  // BLT, BGE
                    3'b110,3'b111: alu_op = ALU_SLTU; // BLTU, BGEU
                    default:       alu_op = ALU_SUB;
                endcase
            end

            // JAL
            7'b1101111: begin
                reg_write   = 1'b1;
                jump        = 1'b1;
                alu_src     = 1'b1;
                alu_op      = ALU_ADD;
                imm_type    = IMM_J;
                pc_as_alu_a = 1'b1;  // target = PC + imm
            end

            // JALR
            7'b1100111: begin
                reg_write = 1'b1;
                jump      = 1'b1;
                is_jalr   = 1'b1;
                alu_src   = 1'b1;
                alu_op    = ALU_ADD;
                imm_type  = IMM_I;
                // target = (rs1 + imm) & ~1; A = rs1 (pc_as_alu_a=0)
            end

            // LUI
            7'b0110111: begin
                reg_write   = 1'b1;
                alu_src     = 1'b1;
                alu_op      = ALU_PASSB;
                imm_type    = IMM_U;
            end

            // AUIPC
            7'b0010111: begin
                reg_write   = 1'b1;
                alu_src     = 1'b1;
                alu_op      = ALU_ADD;
                imm_type    = IMM_U;
                pc_as_alu_a = 1'b1;  // A = PC
            end

            // SYSTEM (CSR / MRET)
            7'b1110011: begin
                case (funct3)
                    3'b001: begin // CSRRW
                        reg_write = 1'b1;
                        csr_op    = CSR_RW;
                    end
                    3'b010: begin // CSRRS
                        reg_write = 1'b1;
                        csr_op    = CSR_RS;
                    end
                    3'b000: begin // ECALL/EBREAK/MRET
                        csr_op = CSR_MRET; // treat all funct3=000 as MRET for now
                    end
                    default: ;
                endcase
            end

            default: ; // NOP
        endcase
    end

endmodule
/* verilator lint_on UNUSEDSIGNAL */

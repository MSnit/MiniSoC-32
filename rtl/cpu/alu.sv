// =============================================================================
// Module:      alu
// Description: 32-bit ALU for RV32I
// alu_op:
//   0000=ADD, 0001=SUB, 0010=SLL, 0011=SLT, 0100=SLTU,
//   0101=XOR, 0110=SRL, 0111=SRA, 1000=OR, 1001=AND, 1010=PASSB
// =============================================================================
module alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [3:0]  alu_op,
    output logic [31:0] result,
    output logic        zero
);
    always_comb begin
        case (alu_op)
            4'b0000: result = a + b;
            4'b0001: result = a - b;
            4'b0010: result = a << b[4:0];
            4'b0011: result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            4'b0100: result = (a < b) ? 32'd1 : 32'd0;
            4'b0101: result = a ^ b;
            4'b0110: result = a >> b[4:0];
            4'b0111: result = $signed(a) >>> b[4:0];
            4'b1000: result = a | b;
            4'b1001: result = a & b;
            4'b1010: result = b;
            default: result = 32'd0;
        endcase
    end
    assign zero = (result == 32'd0);
endmodule

// =============================================================================
// Module:      regfile
// Description: RV32I 32×32 integer register file.
//              x0 is hardwired to zero (writes to x0 are silently discarded).
//              Two asynchronous read ports, one synchronous write port.
//              Synchronous active-low reset (rst_n) not needed for register
//              file state (regs power up to X; TB should not rely on reset).
// Ports:
//   clk       - Global clock
//   rst_n     - Active-low synchronous reset (unused here but kept for consistency)
//   rs1       - Read port 1 address
//   rs2       - Read port 2 address
//   rd        - Write port address
//   rd_data   - Write data
//   we        - Write enable
//   rs1_data  - Read port 1 data
//   rs2_data  - Read port 2 data
// =============================================================================
/* verilator lint_off UNUSEDSIGNAL */
module regfile (
    input  logic        clk,
    input  logic        rst_n,
    // Read ports (combinational)
    input  logic [4:0]  rs1,
    input  logic [4:0]  rs2,
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data,
    // Write port (synchronous)
    input  logic [4:0]  rd,
    input  logic [31:0] rd_data,
    input  logic        we
);

    logic [31:0] regs [31:0];

    // Synchronous write; x0 always zero
    always_ff @(posedge clk) begin
        if (we && (rd != 5'd0)) begin
            regs[rd] <= rd_data;
        end
    end

    // Asynchronous reads with internal write-through bypass; x0 always returns 0
    assign rs1_data = (rs1 == 5'd0) ? 32'd0 :
                      ((we && (rd == rs1)) ? rd_data : regs[rs1]);

    assign rs2_data = (rs2 == 5'd0) ? 32'd0 :
                      ((we && (rd == rs2)) ? rd_data : regs[rs2]);

endmodule
/* verilator lint_on UNUSEDSIGNAL */

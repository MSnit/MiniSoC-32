// =============================================================================
// Module:      irom
// Description: 4 KB Instruction ROM. Read-only Wishbone slave.
//              Loaded from a hex file at simulation/synthesis time via $readmemh.
//              Combinational read with 0-wait-state Wishbone ack.
// Parameters:
//   MEM_FILE   - Path to the hex file (default "firmware.hex")
//   MEM_DEPTH  - Number of 32-bit words (default 1024 = 4 KB)
// =============================================================================
/* verilator lint_off UNUSEDSIGNAL */
module irom #(
    parameter MEM_FILE  = "firmware.hex",
    parameter MEM_DEPTH = 1024   // 4 KB / 4 bytes per word
) (
    input  logic        clk,
    input  logic        rst_n,

    // Wishbone slave Port A (Instruction fetch from IMEM)
    input  logic [31:0] wb_adr,
    input  logic        wb_stb,
    input  logic        wb_cyc,
    output logic [31:0] wb_dat_i,
    output logic        wb_ack,

    // Wishbone slave Port B (Data fetch from DMEM for .rodata / constants)
    input  logic [31:0] b_wb_adr,
    input  logic        b_wb_stb,
    input  logic        b_wb_cyc,
    output logic [31:0] b_wb_dat_i,
    output logic        b_wb_ack
);

    logic [31:0] mem [0:MEM_DEPTH-1];

    // Load hex file at elaboration time
    initial begin
        integer i;
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            mem[i] = 32'd0;
        if (MEM_FILE != "")
            $readmemh(MEM_FILE, mem);
    end

    // Combinational read with immediate ack when selected
    // Port A
    assign wb_dat_i   = (wb_stb && wb_cyc) ? mem[wb_adr[11:2]] : 32'd0;
    assign wb_ack     = wb_stb && wb_cyc && rst_n;

    // Port B
    assign b_wb_dat_i = (b_wb_stb && b_wb_cyc) ? mem[b_wb_adr[11:2]] : 32'd0;
    assign b_wb_ack   = b_wb_stb && b_wb_cyc && rst_n;

endmodule
/* verilator lint_on UNUSEDSIGNAL */

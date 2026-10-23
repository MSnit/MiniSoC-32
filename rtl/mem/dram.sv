// =============================================================================
// Module:      dram
// Description: 4 KB Data RAM. Read/write Wishbone slave with byte-enable support.
//              Combinational read with 0-wait-state Wishbone ack.
//              Synchronous write on posedge clk with byte enables.
// Parameters:
//   MEM_DEPTH  - Number of words (default 1024 = 4 KB)
// =============================================================================
/* verilator lint_off UNUSEDSIGNAL */
module dram #(
    parameter MEM_DEPTH = 256   // Default 1 KB (256 words x 4 bytes)
) (
    input  logic        clk,
    input  logic        rst_n,

    // Wishbone slave
    input  logic [31:0] wb_adr,
    input  logic [31:0] wb_dat_o,   // write data from master
    input  logic        wb_we,
    input  logic [3:0]  wb_sel,
    input  logic        wb_stb,
    input  logic        wb_cyc,
    output logic [31:0] wb_dat_i,   // read data to master
    output logic        wb_ack
);

    logic [7:0] mem_b0 [0:MEM_DEPTH-1];  // byte 0 (bits  7:0)
    logic [7:0] mem_b1 [0:MEM_DEPTH-1];  // byte 1 (bits 15:8)
    logic [7:0] mem_b2 [0:MEM_DEPTH-1];  // byte 2 (bits 23:16)
    logic [7:0] mem_b3 [0:MEM_DEPTH-1];  // byte 3 (bits 31:24)

    // synthesis translate_off
    initial begin
        for (int i = 0; i < MEM_DEPTH; i++) begin
            mem_b0[i] = 8'd0;
            mem_b1[i] = 8'd0;
            mem_b2[i] = 8'd0;
            mem_b3[i] = 8'd0;
        end
    end
    // synthesis translate_on

    localparam AW = $clog2(MEM_DEPTH);
    logic [AW-1:0] word_addr;
    assign word_addr = wb_adr[AW+1:2];

    // Combinational read data
    assign wb_dat_i = (wb_stb && wb_cyc && !wb_we) ?
                      {mem_b3[word_addr], mem_b2[word_addr],
                       mem_b1[word_addr], mem_b0[word_addr]} : 32'd0;

    assign wb_ack = wb_stb && wb_cyc && rst_n;

    // Synchronous write with byte enables
    always_ff @(posedge clk) begin
        if (rst_n && wb_stb && wb_cyc && wb_we) begin
            if (wb_sel[0]) mem_b0[word_addr] <= wb_dat_o[7:0];
            if (wb_sel[1]) mem_b1[word_addr] <= wb_dat_o[15:8];
            if (wb_sel[2]) mem_b2[word_addr] <= wb_dat_o[23:16];
            if (wb_sel[3]) mem_b3[word_addr] <= wb_dat_o[31:24];
        end
    end

endmodule
/* verilator lint_on UNUSEDSIGNAL */

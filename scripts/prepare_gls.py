#!/usr/bin/env python3
import sys
import re

netlist_path = "syn/reports/minisoc_top_netlist.v"
output_path = "syn/reports/minisoc_top_gls.v"

replacement_rom = """
module \\$paramod$21b76a13e641e99c37a4b11b49a7e28bda917657\\irom (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] wb_adr,
    input  wire        wb_stb,
    input  wire        wb_cyc,
    output wire [31:0] wb_dat_i,
    output wire        wb_ack,
    input  wire [31:0] b_wb_adr,
    input  wire        b_wb_stb,
    input  wire        b_wb_cyc,
    output wire [31:0] b_wb_dat_i,
    output wire        b_wb_ack
);
    reg [31:0] mem [0:1023];
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1)
            mem[i] = 32'd0;
        $readmemh("fw/build/self_test.hex", mem);
    end

    assign wb_dat_i   = (wb_stb && wb_cyc) ? mem[wb_adr[11:2]] : 32'd0;
    assign wb_ack     = wb_stb && wb_cyc && rst_n;
    assign b_wb_dat_i = (b_wb_stb && b_wb_cyc) ? mem[b_wb_adr[11:2]] : 32'd0;
    assign b_wb_ack   = b_wb_stb && b_wb_cyc && rst_n;
endmodule
"""

replacement_ram = """
module \\$paramod\\dram\\MEM_DEPTH=s32'00000000000000000000010000000000 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] wb_adr,
    input  wire [31:0] wb_dat_o,
    input  wire        wb_we,
    input  wire [3:0]  wb_sel,
    input  wire        wb_stb,
    input  wire        wb_cyc,
    output wire [31:0] wb_dat_i,
    output wire        wb_ack
);
    reg [7:0] mem_b0 [0:1023];
    reg [7:0] mem_b1 [0:1023];
    reg [7:0] mem_b2 [0:1023];
    reg [7:0] mem_b3 [0:1023];

    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            mem_b0[i] = 8'd0;
            mem_b1[i] = 8'd0;
            mem_b2[i] = 8'd0;
            mem_b3[i] = 8'd0;
        end
    end

    wire [9:0] word_addr = wb_adr[11:2];

    assign wb_dat_i = (wb_stb && wb_cyc && !wb_we) ?
                      {mem_b3[word_addr], mem_b2[word_addr],
                       mem_b1[word_addr], mem_b0[word_addr]} : 32'd0;

    assign wb_ack = wb_stb && wb_cyc && rst_n;

    always @(posedge clk) begin
        if (rst_n && wb_stb && wb_cyc && wb_we) begin
            if (wb_sel[0]) mem_b0[word_addr] <= wb_dat_o[7:0];
            if (wb_sel[1]) mem_b1[word_addr] <= wb_dat_o[15:8];
            if (wb_sel[2]) mem_b2[word_addr] <= wb_dat_o[23:16];
            if (wb_sel[3]) mem_b3[word_addr] <= wb_dat_o[31:24];
        end
    end
endmodule
"""

regs_init = """
  reg [31:0] \\regs[9] ;
  initial begin
    \\regs[0]  = 32'd0;
    \\regs[1]  = 32'd0;
    \\regs[2]  = 32'd0;
    \\regs[3]  = 32'd0;
    \\regs[4]  = 32'd0;
    \\regs[5]  = 32'd0;
    \\regs[6]  = 32'd0;
    \\regs[7]  = 32'd0;
    \\regs[8]  = 32'd0;
    \\regs[9]  = 32'd0;
    \\regs[10] = 32'd0;
    \\regs[11] = 32'd0;
    \\regs[12] = 32'd0;
    \\regs[13] = 32'd0;
    \\regs[14] = 32'd0;
    \\regs[15] = 32'd0;
    \\regs[16] = 32'd0;
    \\regs[17] = 32'd0;
    \\regs[18] = 32'd0;
    \\regs[19] = 32'd0;
    \\regs[20] = 32'd0;
    \\regs[21] = 32'd0;
    \\regs[22] = 32'd0;
    \\regs[23] = 32'd0;
    \\regs[24] = 32'd0;
    \\regs[25] = 32'd0;
    \\regs[26] = 32'd0;
    \\regs[27] = 32'd0;
    \\regs[28] = 32'd0;
    \\regs[29] = 32'd0;
    \\regs[30] = 32'd0;
    \\regs[31] = 32'd0;
  end
"""

with open(netlist_path, "r") as f:
    content = f.read()

# Replace the first module (irom stub)
pattern_rom = r"module \\\$paramod\$21b76a13e641e99c37a4b11b49a7e28bda917657\\irom.*?\bendmodule\b"
content, count_rom = re.subn(pattern_rom, lambda m: replacement_rom.strip(), content, flags=re.DOTALL)
print(f"Replaced {count_rom} instances of irom stub.")

# Replace the second module (dram unrolled gate flops)
pattern_ram = r"module \\\$paramod\\dram\\MEM_DEPTH=s32'00000000000000000000010000000000.*?\bendmodule\b"
content, count_ram = re.subn(pattern_ram, lambda m: replacement_ram.strip(), content, flags=re.DOTALL)
print(f"Replaced {count_ram} instances of dram gate model.")

# Add initial block to regfile to initialize registers
pattern_regs = r"  reg \[31:0\] \\regs\[9\] ;"
content, count_regs = re.subn(pattern_regs, lambda m: regs_init.strip(), content, count=1)
print(f"Initialized {count_regs} regfile array instances.")

with open(output_path, "w") as f:
    f.write(content)
print(f"Wrote {output_path} ({len(content.splitlines())} lines)")

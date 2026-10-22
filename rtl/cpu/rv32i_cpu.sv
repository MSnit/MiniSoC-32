// =============================================================================
// Module:      rv32i_cpu
// Description: RV32I 5-stage pipelined CPU (IF/ID/EX/MEM/WB).
//              Features: data forwarding, load-use stall, branch/jump flush,
//              LUI/AUIPC, CSR (CSRRW/CSRRS/MRET), machine timer interrupt.
//              Two Wishbone masters: IMEM (read-only) and DMEM (read/write).
// =============================================================================
module rv32i_cpu (
    input  logic        clk,
    input  logic        rst_n,

    // Instruction memory Wishbone (read-only)
    output logic [31:0] imem_wb_adr,
    output logic        imem_wb_stb,
    output logic        imem_wb_cyc,
    input  logic [31:0] imem_wb_dat_i,
    input  logic        imem_wb_ack,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic        imem_wb_err,

    // Data memory Wishbone
    output logic [31:0] dmem_wb_adr,
    output logic [31:0] dmem_wb_dat_o,
    output logic        dmem_wb_we,
    output logic [3:0]  dmem_wb_sel,
    output logic        dmem_wb_stb,
    output logic        dmem_wb_cyc,
    input  logic [31:0] dmem_wb_dat_i,
    input  logic        dmem_wb_ack,
    input  logic        dmem_wb_err,
    /* verilator lint_on UNUSEDSIGNAL */

    // Timer interrupt
    input  logic        timer_irq
);

    // =========================================================================
    // IF/ID pipeline register
    // =========================================================================
    logic [31:0] if_id_instr;
    logic [31:0] if_id_pc;
    logic [31:0] if_id_pc_plus4;

    // =========================================================================
    // ID/EX pipeline register
    // =========================================================================
    logic [31:0] id_ex_rs1_data;
    logic [31:0] id_ex_rs2_data;
    logic [31:0] id_ex_imm;
    logic [4:0]  id_ex_rd;
    logic [4:0]  id_ex_rs1;
    logic [4:0]  id_ex_rs2;
    logic [3:0]  id_ex_alu_op;
    logic        id_ex_alu_src;
    logic        id_ex_mem_read;
    logic        id_ex_mem_write;
    logic [1:0]  id_ex_mem_size;
    logic        id_ex_mem_signed;
    logic        id_ex_reg_write;
    logic        id_ex_mem_to_reg;
    logic        id_ex_branch;
    logic [2:0]  id_ex_branch_op;
    logic        id_ex_jump;
    logic        id_ex_is_jalr;
    logic [31:0] id_ex_pc;
    logic [31:0] id_ex_pc_plus4;
    logic [1:0]  id_ex_csr_op;
    logic [11:0] id_ex_csr_addr;
    logic        id_ex_pc_as_alu_a;

    // =========================================================================
    // EX/MEM pipeline register
    // =========================================================================
    logic [31:0] ex_mem_alu_result;
    logic [31:0] ex_mem_rs2_data;
    logic [4:0]  ex_mem_rd;
    logic        ex_mem_mem_read;
    logic        ex_mem_mem_write;
    logic [1:0]  ex_mem_mem_size;
    logic        ex_mem_mem_signed;
    logic        ex_mem_reg_write;
    logic        ex_mem_mem_to_reg;
    logic [1:0]  ex_mem_csr_op;
    logic [11:0] ex_mem_csr_addr;
    logic [31:0] ex_mem_csr_wdata;

    // =========================================================================
    // MEM/WB pipeline register
    // =========================================================================
    logic [31:0] mem_wb_alu_result;
    logic [31:0] mem_wb_mem_data;
    logic [4:0]  mem_wb_rd;
    logic        mem_wb_reg_write;
    logic        mem_wb_mem_to_reg;

    // =========================================================================
    // Hazard / forwarding signals
    // =========================================================================
    logic [1:0]  fwd_a, fwd_b;
    logic        stall_if, stall_id;
    logic        flush_if_id, flush_id_ex, flush_ex_mem;
    logic        branch_taken, jump_taken;
    logic [31:0] branch_target;
    logic        irq_taken;

    // =========================================================================
    // CSR signals
    // =========================================================================
    logic [31:0] csr_rdata;
    logic [31:0] mtvec_out, mepc_out;
    logic        trap_taken, mret_taken;
    assign irq_taken = trap_taken;

    // =========================================================================
    // WB signals
    // =========================================================================
    logic [4:0]  wb_rd;
    logic [31:0] wb_result;
    logic        wb_we;
    assign wb_result = mem_wb_mem_to_reg ? mem_wb_mem_data : mem_wb_alu_result;
    assign wb_rd     = mem_wb_rd;
    assign wb_we     = mem_wb_reg_write;

    // =========================================================================
    // IF STAGE: PC register + IMEM fetch
    // =========================================================================
    logic [31:0] pc_reg;
    logic [31:0] pc_next;

    always_comb begin
        if (trap_taken)
            pc_next = mtvec_out;
        else if (mret_taken)
            pc_next = mepc_out;
        else if (branch_taken || jump_taken)
            pc_next = branch_target;
        else
            pc_next = pc_reg + 32'd4;
    end

    always_ff @(posedge clk) begin
        if (!rst_n)
            pc_reg <= 32'h0000_0000;
        else if (!stall_if)
            pc_reg <= pc_next;
    end

    assign imem_wb_adr = pc_reg;
    assign imem_wb_stb = 1'b1;
    assign imem_wb_cyc = 1'b1;

    // IF/ID register
    always_ff @(posedge clk) begin
        if (!rst_n || flush_if_id) begin
            if_id_instr    <= 32'h0000_0013; // NOP
            if_id_pc       <= 32'd0;
            if_id_pc_plus4 <= 32'd4;
        end else if (!stall_id) begin
            if_id_instr    <= imem_wb_ack ? imem_wb_dat_i : 32'h0000_0013;
            if_id_pc       <= pc_reg;
            if_id_pc_plus4 <= pc_reg + 32'd4;
        end
    end

    // =========================================================================
    // ID STAGE: Decode, regfile read, immediate generation
    // =========================================================================
    logic [6:0]  id_opcode;
    logic [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;
    logic [2:0]  id_funct3;
    logic [6:0]  id_funct7;
    logic [11:0] id_csr_addr_wire;

    assign id_opcode        = if_id_instr[6:0];
    assign id_rd_addr       = if_id_instr[11:7];
    assign id_funct3        = if_id_instr[14:12];
    assign id_rs1_addr      = if_id_instr[19:15];
    assign id_rs2_addr      = if_id_instr[24:20];
    assign id_funct7        = if_id_instr[31:25];
    assign id_csr_addr_wire = if_id_instr[31:20];

    // Control
    logic [3:0]  ctrl_alu_op;
    logic        ctrl_alu_src, ctrl_mem_read, ctrl_mem_write;
    logic [1:0]  ctrl_mem_size;
    logic        ctrl_mem_signed, ctrl_reg_write, ctrl_mem_to_reg;
    logic        ctrl_branch, ctrl_jump, ctrl_is_jalr;
    logic [2:0]  ctrl_branch_op, ctrl_imm_type;
    logic [1:0]  ctrl_csr_op;
    logic        ctrl_pc_as_alu_a;

    control ctrl_unit (
        .opcode      (id_opcode),
        .funct3      (id_funct3),
        .funct7      (id_funct7),
        .alu_op      (ctrl_alu_op),
        .alu_src     (ctrl_alu_src),
        .mem_read    (ctrl_mem_read),
        .mem_write   (ctrl_mem_write),
        .mem_size    (ctrl_mem_size),
        .mem_signed  (ctrl_mem_signed),
        .reg_write   (ctrl_reg_write),
        .mem_to_reg  (ctrl_mem_to_reg),
        .branch      (ctrl_branch),
        .branch_op   (ctrl_branch_op),
        .jump        (ctrl_jump),
        .is_jalr     (ctrl_is_jalr),
        .imm_type    (ctrl_imm_type),
        .csr_op      (ctrl_csr_op),
        .pc_as_alu_a (ctrl_pc_as_alu_a)
    );

    // Immediate
    logic [31:0] id_imm;
    imm_gen imm_gen_inst (
        .instr    (if_id_instr),
        .imm_type (ctrl_imm_type),
        .imm_out  (id_imm)
    );

    // Register file
    logic [31:0] id_rs1_data, id_rs2_data;
    regfile regfile_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1      (id_rs1_addr),
        .rs2      (id_rs2_addr),
        .rs1_data (id_rs1_data),
        .rs2_data (id_rs2_data),
        .rd       (wb_rd),
        .rd_data  (wb_result),
        .we       (wb_we)
    );

    // ID/EX register
    always_ff @(posedge clk) begin
        if (!rst_n || flush_id_ex) begin
            id_ex_rs1_data   <= 32'd0;
            id_ex_rs2_data   <= 32'd0;
            id_ex_imm        <= 32'd0;
            id_ex_rd         <= 5'd0;
            id_ex_rs1        <= 5'd0;
            id_ex_rs2        <= 5'd0;
            id_ex_alu_op     <= 4'b0000;
            id_ex_alu_src    <= 1'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
            id_ex_mem_size   <= 2'b10;
            id_ex_mem_signed <= 1'b1;
            id_ex_reg_write  <= 1'b0;
            id_ex_mem_to_reg <= 1'b0;
            id_ex_branch     <= 1'b0;
            id_ex_branch_op  <= 3'b000;
            id_ex_jump       <= 1'b0;
            id_ex_is_jalr    <= 1'b0;
            id_ex_pc         <= 32'd0;
            id_ex_pc_plus4   <= 32'd0;
            id_ex_csr_op     <= 2'b00;
            id_ex_csr_addr   <= 12'd0;
            id_ex_pc_as_alu_a<= 1'b0;
        end else begin
            id_ex_rs1_data   <= id_rs1_data;
            id_ex_rs2_data   <= id_rs2_data;
            id_ex_imm        <= id_imm;
            id_ex_rd         <= id_rd_addr;
            id_ex_rs1        <= id_rs1_addr;
            id_ex_rs2        <= id_rs2_addr;
            id_ex_alu_op     <= ctrl_alu_op;
            id_ex_alu_src    <= ctrl_alu_src;
            id_ex_mem_read   <= ctrl_mem_read;
            id_ex_mem_write  <= ctrl_mem_write;
            id_ex_mem_size   <= ctrl_mem_size;
            id_ex_mem_signed <= ctrl_mem_signed;
            id_ex_reg_write  <= ctrl_reg_write;
            id_ex_mem_to_reg <= ctrl_mem_to_reg;
            id_ex_branch     <= ctrl_branch;
            id_ex_branch_op  <= ctrl_branch_op;
            id_ex_jump       <= ctrl_jump;
            id_ex_is_jalr    <= ctrl_is_jalr;
            id_ex_pc         <= if_id_pc;
            id_ex_pc_plus4   <= if_id_pc_plus4;
            id_ex_csr_op     <= ctrl_csr_op;
            id_ex_csr_addr   <= id_csr_addr_wire;
            id_ex_pc_as_alu_a<= ctrl_pc_as_alu_a;
        end
    end

    // =========================================================================
    // EX STAGE: ALU, forwarding, branch decision
    // =========================================================================

    // Forwarding muxes
    logic [31:0] ex_fwd_a, ex_fwd_b;
    always_comb begin
        case (fwd_a)
            2'b01:   ex_fwd_a = ex_mem_alu_result;
            2'b10:   ex_fwd_a = wb_result;
            default: ex_fwd_a = id_ex_rs1_data;
        endcase
        case (fwd_b)
            2'b01:   ex_fwd_b = ex_mem_alu_result;
            2'b10:   ex_fwd_b = wb_result;
            default: ex_fwd_b = id_ex_rs2_data;
        endcase
    end

    // ALU A: use PC for AUIPC and JAL
    logic [31:0] ex_alu_a, ex_alu_b;
    assign ex_alu_a = id_ex_pc_as_alu_a ? id_ex_pc : ex_fwd_a;
    assign ex_alu_b = id_ex_alu_src      ? id_ex_imm : ex_fwd_b;

    logic [31:0] ex_alu_result;
    logic        ex_alu_zero;

    alu alu_inst (
        .a      (ex_alu_a),
        .b      (ex_alu_b),
        .alu_op (id_ex_alu_op),
        .result (ex_alu_result),
        .zero   (ex_alu_zero)
    );

    // Branch condition
    always_comb begin
        branch_taken = 1'b0;
        if (id_ex_branch) begin
            case (id_ex_branch_op)
                3'b000: branch_taken =  ex_alu_zero;       // BEQ
                3'b001: branch_taken = !ex_alu_zero;       // BNE
                3'b100: branch_taken =  ex_alu_result[0];  // BLT
                3'b101: branch_taken = !ex_alu_result[0];  // BGE
                3'b110: branch_taken =  ex_alu_result[0];  // BLTU
                3'b111: branch_taken = !ex_alu_result[0];  // BGEU
                default: branch_taken = 1'b0;
            endcase
        end
    end

    // Branch / jump target
    always_comb begin
        if (id_ex_jump) begin
            if (id_ex_is_jalr)
                branch_target = ex_alu_result & 32'hFFFF_FFFE; // JALR: (rs1+imm)&~1
            else
                branch_target = ex_alu_result; // JAL: PC+imm (alu_a=PC, alu_b=imm)
        end else begin
            branch_target = id_ex_pc + id_ex_imm; // Branch: PC + B-imm
        end
    end

    assign jump_taken = id_ex_jump;

    // JAL/JALR writeback = PC+4
    logic [31:0] ex_alu_result_wb;
    assign ex_alu_result_wb = id_ex_jump ? id_ex_pc_plus4 : ex_alu_result;

    // CSR write data = forwarded rs1
    logic [31:0] ex_csr_wdata;
    assign ex_csr_wdata = ex_fwd_a;

    // EX/MEM register
    always_ff @(posedge clk) begin
        if (!rst_n || flush_ex_mem) begin
            ex_mem_alu_result <= 32'd0;
            ex_mem_rs2_data   <= 32'd0;
            ex_mem_rd         <= 5'd0;
            ex_mem_mem_read   <= 1'b0;
            ex_mem_mem_write  <= 1'b0;
            ex_mem_mem_size   <= 2'b10;
            ex_mem_mem_signed <= 1'b1;
            ex_mem_reg_write  <= 1'b0;
            ex_mem_mem_to_reg <= 1'b0;
            ex_mem_csr_op     <= 2'b00;
            ex_mem_csr_addr   <= 12'd0;
            ex_mem_csr_wdata  <= 32'd0;
        end else begin
            ex_mem_alu_result <= ex_alu_result_wb;
            ex_mem_rs2_data   <= ex_fwd_b;
            ex_mem_rd         <= id_ex_rd;
            ex_mem_mem_read   <= id_ex_mem_read;
            ex_mem_mem_write  <= id_ex_mem_write;
            ex_mem_mem_size   <= id_ex_mem_size;
            ex_mem_mem_signed <= id_ex_mem_signed;
            ex_mem_reg_write  <= id_ex_reg_write;
            ex_mem_mem_to_reg <= id_ex_mem_to_reg;
            ex_mem_csr_op     <= id_ex_csr_op;
            ex_mem_csr_addr   <= id_ex_csr_addr;
            ex_mem_csr_wdata  <= ex_csr_wdata;
        end
    end

    // =========================================================================
    // MEM STAGE: load/store, CSR, interrupt
    // =========================================================================

    // Wishbone byte select
    logic [3:0] dmem_sel_wire;
    logic [1:0] addr_lsb;
    assign addr_lsb = ex_mem_alu_result[1:0];

    always_comb begin
        case (ex_mem_mem_size)
            2'b00: begin // byte
                case (addr_lsb)
                    2'b00: dmem_sel_wire = 4'b0001;
                    2'b01: dmem_sel_wire = 4'b0010;
                    2'b10: dmem_sel_wire = 4'b0100;
                    default: dmem_sel_wire = 4'b1000;
                endcase
            end
            2'b01: dmem_sel_wire = addr_lsb[1] ? 4'b1100 : 4'b0011; // half
            default: dmem_sel_wire = 4'b1111; // word
        endcase
    end

    // Store data (byte-replicated)
    logic [31:0] dmem_wdata_wire;
    always_comb begin
        case (ex_mem_mem_size)
            2'b00: dmem_wdata_wire = {4{ex_mem_rs2_data[7:0]}};
            2'b01: dmem_wdata_wire = {2{ex_mem_rs2_data[15:0]}};
            default: dmem_wdata_wire = ex_mem_rs2_data;
        endcase
    end

    assign dmem_wb_adr   = {ex_mem_alu_result[31:2], 2'b00};
    assign dmem_wb_dat_o = dmem_wdata_wire;
    assign dmem_wb_we    = ex_mem_mem_write;
    assign dmem_wb_sel   = dmem_sel_wire;
    assign dmem_wb_stb   = ex_mem_mem_read | ex_mem_mem_write;
    assign dmem_wb_cyc   = ex_mem_mem_read | ex_mem_mem_write;

    // Load data extraction
    logic [7:0]  load_byte;
    logic [15:0] load_half;
    logic [31:0] mem_load_data_wire;

    always_comb begin
        case (addr_lsb)
            2'b00: load_byte = dmem_wb_dat_i[7:0];
            2'b01: load_byte = dmem_wb_dat_i[15:8];
            2'b10: load_byte = dmem_wb_dat_i[23:16];
            default: load_byte = dmem_wb_dat_i[31:24];
        endcase
        load_half = addr_lsb[1] ? dmem_wb_dat_i[31:16] : dmem_wb_dat_i[15:0];

        case (ex_mem_mem_size)
            2'b00: mem_load_data_wire = ex_mem_mem_signed ?
                       {{24{load_byte[7]}}, load_byte} :
                       {24'd0, load_byte};
            2'b01: mem_load_data_wire = ex_mem_mem_signed ?
                       {{16{load_half[15]}}, load_half} :
                       {16'd0, load_half};
            default: mem_load_data_wire = dmem_wb_dat_i; // word
        endcase
    end

    // PC to save on interrupt
    logic [31:0] interrupt_pc;
    always_comb begin
        if (branch_taken || jump_taken)
            interrupt_pc = branch_target;
        else if (if_id_pc != 32'd0)
            interrupt_pc = if_id_pc;
        else
            interrupt_pc = pc_reg;
    end

    // CSR instance
    csr_regfile csr_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .csr_addr   (ex_mem_csr_addr),
        .csr_wdata  (ex_mem_csr_wdata),
        .csr_op     (ex_mem_csr_op),
        .csr_rdata  (csr_rdata),
        .timer_irq  (timer_irq),
        .pc_plus4   (interrupt_pc),
        .trap_taken (trap_taken),
        .mret_taken (mret_taken),
        .mtvec_out  (mtvec_out),
        .mepc_out   (mepc_out)
    );

    // WB data: CSR read replaces ALU result for CSR instructions
    logic [31:0] mem_wb_alu_result_in;
    assign mem_wb_alu_result_in = (ex_mem_csr_op != 2'b00) ? csr_rdata : ex_mem_alu_result;

    // MEM/WB register
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mem_wb_alu_result <= 32'd0;
            mem_wb_mem_data   <= 32'd0;
            mem_wb_rd         <= 5'd0;
            mem_wb_reg_write  <= 1'b0;
            mem_wb_mem_to_reg <= 1'b0;
        end else begin
            mem_wb_alu_result <= mem_wb_alu_result_in;
            mem_wb_mem_data   <= mem_load_data_wire;
            mem_wb_rd         <= ex_mem_rd;
            mem_wb_reg_write  <= ex_mem_reg_write;
            mem_wb_mem_to_reg <= ex_mem_mem_to_reg;
        end
    end

    // =========================================================================
    // HAZARD UNIT
    // =========================================================================
    hazard_unit haz (
        .id_ex_rs1        (id_ex_rs1),
        .id_ex_rs2        (id_ex_rs2),
        .id_ex_rd         (id_ex_rd),
        .id_ex_mem_read   (id_ex_mem_read),
        .ex_mem_rd        (ex_mem_rd),
        .ex_mem_reg_write (ex_mem_reg_write),
        .mem_wb_rd        (mem_wb_rd),
        .mem_wb_reg_write (mem_wb_reg_write),
        .if_id_rs1        (id_rs1_addr),
        .if_id_rs2        (id_rs2_addr),
        .branch_taken     (branch_taken),
        .jump             (jump_taken),
        .irq_taken        (irq_taken),
        .mret_taken       (mret_taken),
        .fwd_a            (fwd_a),
        .fwd_b            (fwd_b),
        .stall_if         (stall_if),
        .stall_id         (stall_id),
        .flush_if_id      (flush_if_id),
        .flush_id_ex      (flush_id_ex),
        .flush_ex_mem     (flush_ex_mem)
    );

endmodule

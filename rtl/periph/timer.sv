// =============================================================================
// Module:      timer
// Description: 32-bit free-running timer with compare-match and interrupt.
//
// Register map (base = 0x0005_0000):
//   0x00  TIMER_CNT   R/W    32-bit counter (writable to reset)
//   0x04  TIMER_CMP   R/W    Compare value; IRQ fires when CNT == CMP
//   0x08  TIMER_CTRL  R/W    [0]=enable, [1]=irq_enable, [2]=auto_reload
//   0x0C  TIMER_STAT  R/W1C  [0]=irq_pending (write 1 to clear)
//
// auto_reload: when set, CNT reloads to 0 after compare match (period timer)
// irq: timer_irq is held high while irq_pending && irq_enable
// =============================================================================
/* verilator lint_off UNUSEDSIGNAL */
module timer (
    input  logic        clk,
    input  logic        rst_n,

    // Wishbone slave
    input  logic [31:0] wb_adr,
    input  logic [31:0] wb_dat_o,
    input  logic        wb_we,
    input  logic [3:0]  wb_sel,
    input  logic        wb_stb,
    input  logic        wb_cyc,
    output logic [31:0] wb_dat_i,
    output logic        wb_ack,

    // Interrupt output
    output logic        timer_irq
);

    logic [31:0] cnt_reg;
    logic [31:0] cmp_reg;
    logic [2:0]  ctrl_reg;     // [0]=en, [1]=irq_en, [2]=reload
    logic        irq_pending;

    logic        t_enable;
    logic        t_irq_en;
    logic        t_reload;
    assign t_enable  = ctrl_reg[0];
    assign t_irq_en  = ctrl_reg[1];
    assign t_reload  = ctrl_reg[2];

    assign timer_irq = irq_pending & t_irq_en;

    // Combinational read
    always_comb begin
        case (wb_adr[3:2])
            2'b00: wb_dat_i = cnt_reg;
            2'b01: wb_dat_i = cmp_reg;
            2'b10: wb_dat_i = {29'd0, ctrl_reg};
            2'b11: wb_dat_i = {31'd0, irq_pending};
            default: wb_dat_i = 32'd0;
        endcase
    end

    assign wb_ack = wb_stb && wb_cyc && rst_n;

    // Counter and synchronous write logic
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cnt_reg     <= 32'd0;
            cmp_reg     <= 32'hFFFF_FFFF;
            ctrl_reg    <= 3'd0;
            irq_pending <= 1'b0;
        end else begin
            // Free-running counter
            if (t_enable) begin
                if (cnt_reg == cmp_reg) begin
                    irq_pending <= 1'b1;
                    if (t_reload)
                        cnt_reg <= 32'd0;
                    else
                        cnt_reg <= cnt_reg + 32'd1;
                end else begin
                    cnt_reg <= cnt_reg + 32'd1;
                end
            end

            // Wishbone write overrides
            if (wb_stb && wb_cyc && wb_we) begin
                case (wb_adr[3:2])
                    2'b00: cnt_reg  <= wb_dat_o;
                    2'b01: cmp_reg  <= wb_dat_o;
                    2'b10: ctrl_reg <= wb_dat_o[2:0];
                    2'b11: begin // W1C
                        if (wb_dat_o[0]) irq_pending <= 1'b0;
                    end
                    default: ;
                endcase
            end
        end
    end

endmodule
/* verilator lint_on UNUSEDSIGNAL */

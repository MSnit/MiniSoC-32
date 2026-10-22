// =============================================================================
// Module:      csr_regfile
// Description: Minimal machine-mode CSR file with interrupt handling.
// CSRs: mstatus(0x300), mie(0x304), mtvec(0x305), mepc(0x341), mcause(0x342), mip(0x344)
// csr_op: 00=none, 01=CSRRW, 10=CSRRS, 11=MRET
// =============================================================================
module csr_regfile (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [11:0] csr_addr,
    input  logic [31:0] csr_wdata,
    input  logic [1:0]  csr_op,
    output logic [31:0] csr_rdata,
    input  logic        timer_irq,
    input  logic [31:0] pc_plus4,
    output logic        trap_taken,
    output logic        mret_taken,
    output logic [31:0] mtvec_out,
    output logic [31:0] mepc_out
);
    logic [31:0] mstatus, mie, mtvec, mepc, mcause;
    logic [31:0] mip;
    assign mip = {24'd0, timer_irq, 7'd0};

    logic irq_enabled;
    assign irq_enabled = mstatus[3] & mie[7] & timer_irq;
    assign trap_taken  = irq_enabled;
    assign mret_taken  = (csr_op == 2'b11);
    assign mtvec_out   = mtvec;
    assign mepc_out    = mepc;

    always_comb begin
        case (csr_addr)
            12'h300: csr_rdata = mstatus;
            12'h304: csr_rdata = mie;
            12'h305: csr_rdata = mtvec;
            12'h341: csr_rdata = mepc;
            12'h342: csr_rdata = mcause;
            12'h344: csr_rdata = mip;
            default: csr_rdata = 32'd0;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mstatus <= 32'd0;
            mie     <= 32'd0;
            mtvec   <= 32'd0;
            mepc    <= 32'd0;
            mcause  <= 32'd0;
        end else begin
            if (irq_enabled) begin
                mepc       <= pc_plus4;
                mcause     <= 32'h8000_0007;
                mstatus[3] <= 1'b0;
            end else if (csr_op == 2'b11) begin
                // MRET
                mstatus[3] <= 1'b1;
            end else begin
                case (csr_op)
                    2'b01: begin // CSRRW
                        case (csr_addr)
                            12'h300: mstatus <= csr_wdata;
                            12'h304: mie     <= csr_wdata;
                            12'h305: mtvec   <= csr_wdata;
                            12'h341: mepc    <= csr_wdata;
                            12'h342: mcause  <= csr_wdata;
                            default: ;
                        endcase
                    end
                    2'b10: begin // CSRRS
                        case (csr_addr)
                            12'h300: mstatus <= mstatus | csr_wdata;
                            12'h304: mie     <= mie     | csr_wdata;
                            12'h305: mtvec   <= mtvec   | csr_wdata;
                            12'h341: mepc    <= mepc    | csr_wdata;
                            12'h342: mcause  <= mcause  | csr_wdata;
                            default: ;
                        endcase
                    end
                    default: ;
                endcase
            end
        end
    end
endmodule

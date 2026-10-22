// =============================================================================
// Module:      gpio
// Description: 8-bit GPIO controller with direction register.
//
// Register map (base = 0x0004_0000):
//   0x00  GPIO_DIR  R/W  [7:0] pin direction: 1=output, 0=input
//   0x04  GPIO_OUT  R/W  [7:0] output data register
//   0x08  GPIO_IN   R    [7:0] sampled input pin values (2-FF synchronized)
// =============================================================================
/* verilator lint_off UNUSEDSIGNAL */
module gpio (
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

    // GPIO pins
    input  logic [7:0]  gpio_in,
    output logic [7:0]  gpio_out,
    output logic [7:0]  gpio_dir
);

    logic [7:0] dir_reg;
    logic [7:0] out_reg;
    logic [7:0] in_sync0, in_sync1;   // 2-FF synchronizer

    assign gpio_out = out_reg;
    assign gpio_dir = dir_reg;

    // Input synchronizer
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            in_sync0 <= 8'd0;
            in_sync1 <= 8'd0;
        end else begin
            in_sync0 <= gpio_in;
            in_sync1 <= in_sync0;
        end
    end

    // Combinational read
    always_comb begin
        case (wb_adr[3:2])
            2'b00: wb_dat_i = {24'd0, dir_reg};  // GPIO_DIR
            2'b01: wb_dat_i = {24'd0, out_reg};  // GPIO_OUT
            2'b10: wb_dat_i = {24'd0, in_sync1}; // GPIO_IN
            default: wb_dat_i = 32'd0;
        endcase
    end

    assign wb_ack = wb_stb && wb_cyc && rst_n;

    // Synchronous write
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            dir_reg <= 8'd0;
            out_reg <= 8'd0;
        end else if (wb_stb && wb_cyc && wb_we) begin
            case (wb_adr[3:2])
                2'b00: dir_reg <= wb_dat_o[7:0];  // GPIO_DIR
                2'b01: out_reg <= wb_dat_o[7:0];  // GPIO_OUT
                default: ;
            endcase
        end
    end

endmodule
/* verilator lint_on UNUSEDSIGNAL */

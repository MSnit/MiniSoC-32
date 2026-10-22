// =============================================================================
// Module:      spi_master
// Description: SPI master, mode 0 (CPOL=0, CPHA=0).
//              Full-duplex 8-bit transfer. Write to SPI_TXD starts a transfer.
//
// Register map (base = 0x0003_0000):
//   0x00  SPI_TXD   W    Write byte (starts transfer)
//   0x04  SPI_RXD   R    Read received byte
//   0x08  SPI_STAT  R    [0]=idle (1=ready/idle, 0=busy)
//   0x0C  SPI_CTRL  R/W  [7:0] clock divider: SCK = clk / (2 × div)
//   0x10  SPI_CS    R/W  [7:0] chip select lines (active low)
// =============================================================================
/* verilator lint_off UNUSEDSIGNAL */
module spi_master (
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

    // SPI pins
    output logic        spi_sck,
    output logic        spi_mosi,
    input  logic        spi_miso,
    output logic [7:0]  spi_cs_n
);

    logic [7:0] clk_div;    // SCK divider
    logic [7:0] cs_reg;     // chip select (active low)
    logic [7:0] rx_data;    // received byte

    logic [7:0] tx_shift;   // TX shift register (MSB first)
    logic [7:0] rx_shift;   // RX shift register
    logic [2:0] bit_cnt;    // bit counter (7 downto 0)
    logic [7:0] clk_cnt;    // clock divider counter
    logic       busy;
    logic       sck_r;      // SCK output register

    assign spi_sck  = sck_r;
    assign spi_mosi = tx_shift[7]; // MSB first
    assign spi_cs_n = cs_reg;

    typedef enum logic [1:0] {SPI_IDLE, SPI_SCK_LO, SPI_SCK_HI, SPI_DONE} spi_state_t;
    spi_state_t spi_state;

    // Combinational read
    always_comb begin
        case (wb_adr[4:2])
            3'b000: wb_dat_i = 32'd0;              // TXD (write-only)
            3'b001: wb_dat_i = {24'd0, rx_data};   // SPI_RXD
            3'b010: wb_dat_i = {31'd0, !busy};     // SPI_STAT
            3'b011: wb_dat_i = {24'd0, clk_div};   // SPI_CTRL
            3'b100: wb_dat_i = {24'd0, cs_reg};    // SPI_CS
            default: wb_dat_i = 32'd0;
        endcase
    end

    assign wb_ack = wb_stb && wb_cyc && rst_n;

    // SPI state machine + Wishbone write
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            clk_div   <= 8'd4;
            cs_reg    <= 8'hFF;
            tx_shift  <= 8'd0;
            rx_shift  <= 8'd0;
            bit_cnt   <= 3'd7;
            clk_cnt   <= 8'd0;
            busy      <= 1'b0;
            sck_r     <= 1'b0;
            rx_data   <= 8'd0;
            spi_state <= SPI_IDLE;
        end else begin
            // Wishbone write
            if (wb_stb && wb_cyc && wb_we) begin
                case (wb_adr[4:2])
                    3'b000: begin // SPI_TXD: start transfer
                        if (!busy) begin
                            tx_shift  <= wb_dat_o[7:0];
                            rx_shift  <= 8'd0;
                            bit_cnt   <= 3'd7;
                            clk_cnt   <= 8'd0;
                            busy      <= 1'b1;
                            spi_state <= SPI_SCK_LO;
                        end
                    end
                    3'b011: clk_div <= (wb_dat_o[7:0] != 8'd0) ? wb_dat_o[7:0] : 8'd1;
                    3'b100: cs_reg  <= wb_dat_o[7:0];
                    default: ;
                endcase
            end

            // FSM progress
            case (spi_state)
                SPI_IDLE: begin
                    sck_r   <= 1'b0;
                    bit_cnt <= 3'd7;
                end

                SPI_SCK_LO: begin
                    if (clk_cnt == clk_div - 1) begin
                        clk_cnt   <= 8'd0;
                        sck_r     <= 1'b1;
                        spi_state <= SPI_SCK_HI;
                    end else begin
                        clk_cnt <= clk_cnt + 8'd1;
                    end
                end

                SPI_SCK_HI: begin
                    if (clk_cnt == 8'd0) begin
                        rx_shift <= {rx_shift[6:0], spi_miso}; // sample on rising edge
                    end
                    if (clk_cnt == clk_div - 1) begin
                        clk_cnt <= 8'd0;
                        sck_r   <= 1'b0;
                        if (bit_cnt == 3'd0) begin
                            spi_state <= SPI_DONE;
                        end else begin
                            tx_shift  <= {tx_shift[6:0], 1'b0};
                            bit_cnt   <= bit_cnt - 3'd1;
                            spi_state <= SPI_SCK_LO;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 8'd1;
                    end
                end

                SPI_DONE: begin
                    rx_data   <= rx_shift;
                    busy      <= 1'b0;
                    spi_state <= SPI_IDLE;
                end

                default: spi_state <= SPI_IDLE;
            endcase
        end
    end

endmodule
/* verilator lint_on UNUSEDSIGNAL */

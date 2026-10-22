// =============================================================================
// Module:      uart
// Description: UART TX+RX with configurable baud divisor and Wishbone interface.
//
// Register map (base = 0x0002_0000):
//   0x00  UART_TXD   W    Write byte to transmit
//   0x04  UART_RXD   R    Read received byte (clears rx_ready)
//   0x08  UART_STAT  R    [1]=tx_idle, [0]=rx_ready
//   0x0C  UART_CTRL  R/W  [15:0] baud_div (clk / (baud * 16))
// =============================================================================
/* verilator lint_off UNUSEDSIGNAL */
module uart (
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

    // UART pins
    input  logic        uart_rx,
    output logic        uart_tx
);

    logic [15:0] baud_div;

    // TX state & control
    typedef enum logic [1:0] {TX_IDLE, TX_SEND} tx_state_t;
    tx_state_t   tx_state;
    logic [9:0]  tx_shift;
    logic [3:0]  tx_bits_left;
    logic [15:0] tx_baud_cnt;
    logic [3:0]  tx_tick_cnt;

    // RX state & registers
    logic        rx_sync0, rx_sync1;
    logic [15:0] rx_baud_cnt;
    logic        rx_tick;

    typedef enum logic [1:0] {
        RX_IDLE  = 2'b00,
        RX_START = 2'b01,
        RX_DATA  = 2'b10,
        RX_STOP  = 2'b11
    } rx_state_t;

    rx_state_t  rx_state;
    logic [3:0]  rx_tick_cnt;
    logic [2:0]  rx_bit_idx;
    logic [7:0]  rx_shift;
    logic [7:0]  rx_data_reg;
    logic        rx_ready;
    logic        rx_read_clear;

    assign uart_tx = (tx_state == TX_SEND) ? tx_shift[0] : 1'b1;

    // Combinational read
    always_comb begin
        case (wb_adr[3:2])
            2'b00: wb_dat_i = 32'd0;
            2'b01: wb_dat_i = {24'd0, rx_data_reg};
            2'b10: wb_dat_i = {30'd0, (tx_state == TX_IDLE), rx_ready};
            2'b11: wb_dat_i = {16'd0, baud_div};
            default: wb_dat_i = 32'd0;
        endcase
    end

    assign wb_ack = wb_stb && wb_cyc && rst_n;
    assign rx_read_clear = wb_stb && wb_cyc && !wb_we && (wb_adr[3:2] == 2'b01);

    // TX & Wishbone Write Handling
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            tx_state     <= TX_IDLE;
            tx_shift     <= 10'h3FF;
            tx_bits_left <= 4'd0;
            tx_baud_cnt  <= 16'd0;
            tx_tick_cnt  <= 4'd0;
            baud_div     <= 16'd27;
        end else begin
            // Wishbone write
            if (wb_stb && wb_cyc && wb_we) begin
                case (wb_adr[3:2])
                    2'b00: begin // UART_TXD
                        if (tx_state == TX_IDLE) begin
                            tx_shift     <= {1'b1, wb_dat_o[7:0], 1'b0};
                            tx_bits_left <= 4'd10;
                            tx_baud_cnt  <= 16'd0;
                            tx_tick_cnt  <= 4'd0;
                            tx_state     <= TX_SEND;
                        end
                    end
                    2'b11: begin // UART_CTRL
                        if (wb_dat_o[15:0] != 16'd0)
                            baud_div <= wb_dat_o[15:0];
                    end
                    default: ;
                endcase
            end

            // TX Progress
            if (tx_state == TX_SEND && !(wb_stb && wb_cyc && wb_we && (wb_adr[3:2] == 2'b00))) begin
                if (tx_baud_cnt == baud_div - 1) begin
                    tx_baud_cnt <= 16'd0;
                    if (tx_tick_cnt == 4'd15) begin
                        tx_tick_cnt <= 4'd0;
                        tx_shift    <= {1'b1, tx_shift[9:1]};
                        if (tx_bits_left == 4'd1) begin
                            tx_state <= TX_IDLE;
                        end else begin
                            tx_bits_left <= tx_bits_left - 4'd1;
                        end
                    end else begin
                        tx_tick_cnt <= tx_tick_cnt + 4'd1;
                    end
                end else begin
                    tx_baud_cnt <= tx_baud_cnt + 16'd1;
                end
            end
        end
    end

    // RX Logic
    always_ff @(posedge clk) begin
        rx_sync0 <= uart_rx;
        rx_sync1 <= rx_sync0;
    end

    assign rx_tick = (rx_baud_cnt == baud_div - 1);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rx_state    <= RX_IDLE;
            rx_baud_cnt <= 16'd0;
            rx_tick_cnt <= 4'd0;
            rx_bit_idx  <= 3'd0;
            rx_shift    <= 8'd0;
            rx_data_reg <= 8'd0;
            rx_ready    <= 1'b0;
        end else begin
            if (rx_read_clear) begin
                rx_ready <= 1'b0;
            end

            if (rx_tick) begin
                rx_baud_cnt <= 16'd0;
            end else if (rx_state != RX_IDLE) begin
                rx_baud_cnt <= rx_baud_cnt + 16'd1;
            end

            case (rx_state)
                RX_IDLE: begin
                    rx_baud_cnt <= 16'd0;
                    rx_tick_cnt <= 4'd0;
                    if (!rx_sync1) begin
                        rx_state <= RX_START;
                    end
                end

                RX_START: begin
                    if (rx_tick) begin
                        rx_tick_cnt <= rx_tick_cnt + 4'd1;
                        if (rx_tick_cnt == 4'd7) begin
                            rx_tick_cnt <= 4'd0;
                            if (!rx_sync1) begin
                                rx_state   <= RX_DATA;
                                rx_bit_idx <= 3'd0;
                            end else begin
                                rx_state <= RX_IDLE;
                            end
                        end
                    end
                end

                RX_DATA: begin
                    if (rx_tick) begin
                        rx_tick_cnt <= rx_tick_cnt + 4'd1;
                        if (rx_tick_cnt == 4'd15) begin
                            rx_tick_cnt <= 4'd0;
                            rx_shift    <= {rx_sync1, rx_shift[7:1]};
                            rx_bit_idx  <= rx_bit_idx + 3'd1;
                            if (rx_bit_idx == 3'd7) begin
                                rx_state <= RX_STOP;
                            end
                        end
                    end
                end

                RX_STOP: begin
                    if (rx_tick) begin
                        rx_tick_cnt <= rx_tick_cnt + 4'd1;
                        if (rx_tick_cnt == 4'd15) begin
                            rx_tick_cnt <= 4'd0;
                            rx_state    <= RX_IDLE;
                            if (rx_sync1) begin
                                rx_data_reg <= rx_shift;
                                rx_ready    <= 1'b1;
                            end
                        end
                    end
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

endmodule
/* verilator lint_on UNUSEDSIGNAL */

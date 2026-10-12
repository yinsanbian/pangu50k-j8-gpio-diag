// Module: uart_rx -- 8N1 receiver; two-flop asynchronous input synchronizer.
// LATENCY: about 9.5*DIV+2 cycles from start edge to valid.
// Stop-bit/framing failure invalidates the current command line.
`default_nettype none
module uart_rx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200
)(
    input wire clk,
    input wire rst_n,
    input wire rx,
    output reg [7:0] data,
    output reg valid,
    output reg frame_error
);
    localparam integer DIV = (CLK_HZ + BAUD/2) / BAUD;
    localparam [1:0] IDLE=2'd0, START=2'd1, DATA=2'd2, STOP=2'd3;
    reg rx_meta;
    reg rx_sync;
    reg [1:0] state;
    reg [31:0] ticks;
    reg [2:0] bit_index;
    reg [7:0] shift;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            ticks <= 32'd0;
            bit_index <= 3'd0;
            shift <= 8'd0;
            data <= 8'd0;
            valid <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            valid <= 1'b0;
            frame_error <= 1'b0;
            case (state)
                IDLE: begin
                    ticks <= 32'd0;
                    if (!rx_sync) state <= START;
                end
                START: begin
                    if (ticks == DIV/2-1) begin
                        ticks <= 32'd0;
                        if (!rx_sync) begin
                            bit_index <= 3'd0;
                            state <= DATA;
                        end else state <= IDLE;
                    end else ticks <= ticks + 32'd1;
                end
                DATA: begin
                    if (ticks == DIV-1) begin
                        ticks <= 32'd0;
                        shift[bit_index] <= rx_sync;
                        if (bit_index == 3'd7) state <= STOP;
                        else bit_index <= bit_index + 3'd1;
                    end else ticks <= ticks + 32'd1;
                end
                STOP: begin
                    if (ticks == DIV-1) begin
                        ticks <= 32'd0;
                        state <= IDLE;
                        if (rx_sync) begin
                            data <= shift;
                            valid <= 1'b1;
                        end else frame_error <= 1'b1;
                    end else ticks <= ticks + 32'd1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire

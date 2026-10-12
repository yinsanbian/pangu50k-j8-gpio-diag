// Module: uart_tx -- registered 8N1 transmitter, ready/valid byte interface.
// LATENCY: accepted byte starts immediately; frame lasts 10*DIV cycles.
`default_nettype none
module uart_tx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200
)(
    input wire clk,
    input wire rst_n,
    input wire [7:0] data,
    input wire valid,
    output wire ready,
    output reg tx
);
    localparam integer DIV = (CLK_HZ + BAUD/2) / BAUD;
    reg [31:0] ticks;
    reg [3:0] bit_index;
    reg [9:0] frame;
    reg active;
    assign ready = !active;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ticks <= 32'd0;
            bit_index <= 4'd0;
            frame <= 10'h3ff;
            active <= 1'b0;
            tx <= 1'b1;
        end else if (!active) begin
            tx <= 1'b1;
            if (valid) begin
                frame <= {1'b1, data, 1'b0};
                tx <= 1'b0;
                bit_index <= 4'd0;
                ticks <= 32'd0;
                active <= 1'b1;
            end
        end else if (ticks == DIV-1) begin
            ticks <= 32'd0;
            if (bit_index == 4'd9) begin
                active <= 1'b0;
                tx <= 1'b1;
            end else begin
                bit_index <= bit_index + 4'd1;
                tx <= frame[bit_index + 4'd1];
            end
        end else begin
            ticks <= ticks + 32'd1;
        end
    end
endmodule
`default_nettype wire

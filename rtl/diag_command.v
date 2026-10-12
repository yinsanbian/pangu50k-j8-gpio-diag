// Module: diag_command -- bounded ASCII line parser, uppercase commands.
// LATENCY: one cycle after CR/LF to command pulse/configuration update.
// ARM attests external loopback AND verified bias on both pins. Consumed by RUN.
// CROSS additionally requires REF OK; selection clears both attestations.
`default_nettype none
module diag_command (
    input wire clk,
    input wire rst_n,
    input wire [7:0] rx_data,
    input wire rx_valid,
    input wire frame_error,
    input wire busy,
    input wire result_valid,
    output reg [5:0] pin_a,
    output reg [5:0] pin_b,
    output reg [4:0] pair_number,
    output reg [1:0] mode,
    output reg qualified,
    output reg start,
    output reg abort,
    output reg event_valid,
    output reg [3:0] event_code
);
    reg [247:0] line;
    reg [5:0] length;
    reg bad_line;
    reg armed;
    reg cross_mode;
    reg reference_ok;
    wire pair_syntax = length == 6'd7 && line[55:16] == "PAIR ";
    wire cross_syntax = length == 6'd11 && line[87:40] == "CROSS " && line[23:16] == 8'h20;
    wire digits_a = line[39:32] >= "0" && line[39:32] <= "9" && line[31:24] >= "0" && line[31:24] <= "9";
    wire digits_b = line[15:8] >= "0" && line[15:8] <= "9" && line[7:0] >= "0" && line[7:0] <= "9";
    wire [7:0] number_b = ({4'd0,line[11:8]} * 8'd10) + {4'd0,line[3:0]};
    wire [7:0] number_a = ({4'd0,line[35:32]} * 8'd10) + {4'd0,line[27:24]};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line <= 248'd0;
            length <= 6'd0;
            bad_line <= 1'b0;
            armed <= 1'b0;
            cross_mode <= 1'b0;
            reference_ok <= 1'b0;
            pin_a <= 6'd0;
            pin_b <= 6'd1;
            pair_number <= 5'd1;
            mode <= 2'd0;
            qualified <= 1'b0;
            start <= 1'b0;
            abort <= 1'b0;
            event_valid <= 1'b0;
            event_code <= 4'd0;
        end else begin
            start <= 1'b0;
            abort <= 1'b0;
            qualified <= 1'b0;
            event_valid <= 1'b0;
            if (frame_error) bad_line <= 1'b1;
            if (rx_valid) begin
                if (rx_data == 8'h0d || rx_data == 8'h0a) begin
                    line <= 248'd0;
                    length <= 6'd0;
                    bad_line <= 1'b0;
                    if (length != 6'd0 || bad_line || frame_error) begin
                        event_valid <= 1'b1;
                        event_code <= 4'd7;
                        if (!bad_line && !frame_error) begin
                            // STOP works even while testing/reporting, independent of ARM.
                            if (line == "STOP") begin
                                abort <= 1'b1;
                                armed <= 1'b0;
                                event_code <= 4'd10;
                            end else if (busy) begin
                                event_code <= 4'd9;
                            end else if (pair_syntax && digits_b && number_b >= 8'd1 && number_b <= 8'd17) begin
                                pin_a <= ({1'b0,number_b[4:0]} - 6'd1) << 1;
                                pin_b <= (({1'b0,number_b[4:0]} - 6'd1) << 1) + 6'd1;
                                pair_number <= number_b[4:0];
                                armed <= 1'b0;
                                reference_ok <= 1'b0;
                                cross_mode <= 1'b0;
                                event_code <= 4'd2;
                            end else if (cross_syntax && digits_a && digits_b && number_a >= 8'd3 && number_a <= 8'd36 && number_b >= 8'd3 && number_b <= 8'd36 && number_a != number_b) begin
                                pin_a <= number_a[5:0] - 6'd3;
                                pin_b <= number_b[5:0] - 6'd3;
                                pair_number <= 5'd0;
                                armed <= 1'b0;
                                reference_ok <= 1'b0;
                                cross_mode <= 1'b1;
                                event_code <= 4'd2;
                            end else if (line == "ARM") begin
                                armed <= 1'b1;
                                event_code <= 4'd3;
                            end else if (line == "REF OK" && cross_mode) begin
                                reference_ok <= 1'b1;
                                event_code <= 4'd4;
                            end else if (line == "RUN SMOKE" || line == "RUN NORMAL" || line == "RUN STRESS") begin
                                if (armed && (!cross_mode || reference_ok)) begin
                                    if (line == "RUN SMOKE") mode <= 2'd0;
                                    else if (line == "RUN NORMAL") mode <= 2'd1;
                                    else mode <= 2'd2;
                                    qualified <= 1'b1;
                                    start <= 1'b1;
                                    armed <= 1'b0;
                                    event_code <= 4'd5;
                                end else event_code <= 4'd8;
                            end else if (line == "REPORT") begin
                                if (result_valid) event_code <= 4'd6;
                                else event_code <= 4'd11;
                            end else if (line == "HELP") event_code <= 4'd1;
                        end
                    end
                end else if (length < 6'd31) begin
                    line <= {line[239:0],rx_data};
                    length <= length + 6'd1;
                    if (rx_data < 8'h20 || rx_data > 8'h7e) bad_line <= 1'b1;
                end else bad_line <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire

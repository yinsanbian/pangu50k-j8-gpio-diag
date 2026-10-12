// Module: gpio_diag_top -- MES50HP J8 GPIO loopback diagnostic.
// LATENCY: reset release 2 clocks; command 1 clock; GPIO sync 2 clocks.
// No PLL/generated clock, no internal loopback. KEY1 is the reset source.
// After configuration/power-up press KEY1; no unverified RTL POR/initial.
`default_nettype none
module gpio_diag_top #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200,
    parameter integer SYMBOL_CYCLES = 50000,
    parameter integer SETTLE_CYCLES = 5000,
    parameter integer GAP_CYCLES = 5000,
    parameter integer SMOKE_SAMPLES = 100,
    parameter integer NORMAL_SAMPLES = 10000,
    parameter integer STRESS_SAMPLES = 100000
)(
    input wire clk_50m,
    input wire rst_n,
    input wire uart_rx,
    output wire uart_tx,
    inout wire [33:0] j8_gpio
);
    wire internal_rst_n;
    wire [7:0] rx_data;
    wire rx_valid, frame_error;
    wire [5:0] selected_a, selected_b;
    wire [4:0] selected_pair;
    wire [1:0] selected_mode;
    wire start, abort, qualified;
    wire command_event_valid;
    wire [3:0] command_event;
    wire [33:0] drive_en, rx_raw;
    wire tx_gpio, core_busy, core_done;
    wire [1:0] status_ab, status_ba;
    wire [31:0] errors_ab, errors_ba, samples_ab, samples_ba;
    wire [31:0] block_errors_ab, block_errors_ba;
    wire core_aborted, direction;
    wire report_busy, serial_ready;
    wire [7:0] serial_data;
    wire serial_valid;
    reg boot_pending, done_pending, busy_pending;
    reg last_result_valid;
    reg report_valid;
    reg [3:0] report_code;
    reg [5:0] report_a, report_b;
    reg [4:0] report_pair;
    reg [1:0] report_mode;
    reg [5:0] run_a, run_b;
    reg [4:0] run_pair;
    reg [1:0] run_mode;
    reg [5:0] last_a, last_b;
    reg [4:0] last_pair;
    reg [1:0] last_mode, last_status_ab, last_status_ba;
    reg last_aborted;
    reg [31:0] last_errors_ab, last_errors_ba, last_samples_ab, last_samples_ba;
    reg [31:0] last_block_ab, last_block_ba;
    wire command_busy = core_busy || core_done || report_busy || report_valid ||
                        boot_pending || done_pending || start;

    reset_sync u_reset (.clk(clk_50m), .rst_n(rst_n), .sync_rst_n(internal_rst_n));
    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_rx (
        .clk(clk_50m), .rst_n(internal_rst_n), .rx(uart_rx),
        .data(rx_data), .valid(rx_valid), .frame_error(frame_error)
    );
    diag_command u_command (
        .clk(clk_50m), .rst_n(internal_rst_n),
        .rx_data(rx_data), .rx_valid(rx_valid), .frame_error(frame_error),
        .busy(command_busy), .result_valid(last_result_valid),
        .pin_a(selected_a), .pin_b(selected_b), .pair_number(selected_pair),
        .mode(selected_mode), .qualified(qualified), .start(start), .abort(abort),
        .event_valid(command_event_valid), .event_code(command_event)
    );
    gpio_pair_mux u_gpio (
        .drive_en(drive_en), .tx_data(tx_gpio), .j8_gpio(j8_gpio), .rx_raw(rx_raw)
    );
    gpio_test_ctrl #(
        .CLK_HZ(CLK_HZ), .SYMBOL_CYCLES(SYMBOL_CYCLES),
        .SETTLE_CYCLES(SETTLE_CYCLES), .GAP_CYCLES(GAP_CYCLES),
        .SMOKE_SAMPLES(SMOKE_SAMPLES), .NORMAL_SAMPLES(NORMAL_SAMPLES),
        .STRESS_SAMPLES(STRESS_SAMPLES)
    ) u_ctrl (
        .clk(clk_50m), .rst_n(internal_rst_n), .start(start), .abort(abort),
        .pin_a(selected_a), .pin_b(selected_b), .mode(selected_mode),
        .qualified(qualified), .rx_raw(rx_raw), .drive_en(drive_en),
        .tx_data(tx_gpio), .busy(core_busy), .done(core_done),
        .status_ab(status_ab), .status_ba(status_ba),
        .errors_ab(errors_ab), .errors_ba(errors_ba),
        .samples_ab(samples_ab), .samples_ba(samples_ba),
        .aborted(core_aborted), .block_errors_ab(block_errors_ab),
        .block_errors_ba(block_errors_ba), .direction(direction)
    );
    uart_report u_report (
        .clk(clk_50m), .rst_n(internal_rst_n),
        .event_valid(report_valid), .event_code(report_code),
        .pin_a(report_a), .pin_b(report_b), .pair_number(report_pair), .mode(report_mode),
        .status_ab(last_status_ab), .status_ba(last_status_ba), .aborted(last_aborted),
        .errors_ab(last_errors_ab), .samples_ab(last_samples_ab), .block_errors_ab(last_block_ab),
        .errors_ba(last_errors_ba), .samples_ba(last_samples_ba), .block_errors_ba(last_block_ba),
        .tx_data(serial_data), .tx_valid(serial_valid), .tx_ready(serial_ready), .busy(report_busy)
    );
    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk_50m), .rst_n(internal_rst_n), .data(serial_data),
        .valid(serial_valid), .ready(serial_ready), .tx(uart_tx)
    );

    // Completed results are retained independently of later pin selections.
    // Completion has priority over command acknowledgments. STOP always reaches
    // the controller; ordinary commands during TX are rejected and coalesced
    // into one BUSY response, so no successful command is silently queued.
    always @(posedge clk_50m or negedge internal_rst_n) begin
        if (!internal_rst_n) begin
            boot_pending <= 1'b1; done_pending <= 1'b0; busy_pending <= 1'b0;
            last_result_valid <= 1'b0;
            report_valid <= 1'b0; report_code <= 4'd0;
            report_a <= 6'd0; report_b <= 6'd1; report_pair <= 5'd1; report_mode <= 2'd0;
            run_a <= 6'd0; run_b <= 6'd1; run_pair <= 5'd1; run_mode <= 2'd0;
            last_a <= 6'd0; last_b <= 6'd1; last_pair <= 5'd1; last_mode <= 2'd0;
            last_status_ab <= 2'd3; last_status_ba <= 2'd3; last_aborted <= 1'b0;
            last_errors_ab <= 32'd0; last_errors_ba <= 32'd0;
            last_samples_ab <= 32'd0; last_samples_ba <= 32'd0;
            last_block_ab <= 32'd0; last_block_ba <= 32'd0;
        end else begin
            report_valid <= 1'b0;
            if (start) begin
                run_a <= selected_a; run_b <= selected_b;
                run_pair <= selected_pair; run_mode <= selected_mode;
            end
            if (core_done) begin
                last_a <= run_a; last_b <= run_b; last_pair <= run_pair; last_mode <= run_mode;
                last_status_ab <= status_ab; last_status_ba <= status_ba;
                last_aborted <= core_aborted;
                last_errors_ab <= errors_ab; last_errors_ba <= errors_ba;
                last_samples_ab <= samples_ab; last_samples_ba <= samples_ba;
                last_block_ab <= block_errors_ab; last_block_ba <= block_errors_ba;
                last_result_valid <= 1'b1;
                done_pending <= 1'b1;
            end
            if (!report_busy && !report_valid) begin
                if (done_pending) begin
                    report_valid <= 1'b1; report_code <= 4'd6;
                    report_a <= last_a; report_b <= last_b;
                    report_pair <= last_pair; report_mode <= last_mode;
                    done_pending <= 1'b0;
                    // A command sent at completion may be rejected as BUSY.
                    if (command_event_valid && command_event == 4'd9) busy_pending <= 1'b1;
                end else if (boot_pending) begin
                    report_valid <= 1'b1; report_code <= 4'd0;
                    boot_pending <= 1'b0;
                end else if (command_event_valid) begin
                    report_valid <= 1'b1; report_code <= command_event;
                    if (command_event == 4'd6) begin
                        report_a <= last_a; report_b <= last_b;
                        report_pair <= last_pair; report_mode <= last_mode;
                    end else begin
                        report_a <= selected_a; report_b <= selected_b;
                        report_pair <= selected_pair; report_mode <= selected_mode;
                    end
                end else if (busy_pending) begin
                    report_valid <= 1'b1; report_code <= 4'd9;
                    busy_pending <= 1'b0;
                end
            end else if (command_event_valid) begin
                busy_pending <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire

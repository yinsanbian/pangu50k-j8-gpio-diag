`timescale 1ns/1ps
`default_nettype none
// Independent complete-message and physical UART-frame checks. This test
// specifies readable expected messages; it does not call DUT render functions.
module tb_uart_report;
    localparam integer DIV = 8;
    localparam integer BIT_NS = DIV * 10;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = !clk;

    reg event_valid = 1'b0;
    reg [3:0] event_code = 4'd0;
    reg [5:0] pin_a = 6'd32;
    reg [5:0] pin_b = 6'd33;
    reg [4:0] pair_number = 5'd17;
    reg [1:0] mode = 2'd2;
    reg [1:0] status_ab = 2'd0;
    reg [1:0] status_ba = 2'd1;
    reg aborted = 1'b0;
    reg [31:0] errors_ab = 32'd0;
    reg [31:0] samples_ab = 32'd10000;
    reg [31:0] block_errors_ab = 32'd100000;
    reg [31:0] errors_ba = 32'hffffffff;
    reg [31:0] samples_ba = 32'd100000;
    reg [31:0] block_errors_ba = 32'd10000;
    wire [7:0] tx_data;
    wire tx_valid;
    wire tx_ready;
    wire busy;
    wire uart_pin;

    uart_report dut (
        .clk(clk), .rst_n(rst_n), .event_valid(event_valid),
        .event_code(event_code), .pin_a(pin_a), .pin_b(pin_b),
        .pair_number(pair_number), .mode(mode), .status_ab(status_ab),
        .status_ba(status_ba), .aborted(aborted), .errors_ab(errors_ab),
        .samples_ab(samples_ab), .block_errors_ab(block_errors_ab),
        .errors_ba(errors_ba), .samples_ba(samples_ba),
        .block_errors_ba(block_errors_ba), .tx_data(tx_data),
        .tx_valid(tx_valid), .tx_ready(tx_ready), .busy(busy)
    );
    uart_tx #(.CLK_HZ(800000), .BAUD(100000)) sender (
        .clk(clk), .rst_n(rst_n), .data(tx_data), .valid(tx_valid),
        .ready(tx_ready), .tx(uart_pin)
    );

    string expected = "";
    string observed = "";
    integer accepted_count = 0;
    integer received_count = 0;
    integer cases = 0;
    integer checks = 0;
    reg monitoring = 1'b0;
    reg in_frame = 1'b0;
    reg stalled = 1'b0;
    reg [7:0] stalled_data = 8'd0;

    task automatic check(input bit condition, input string reason);
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("TB_FAIL uart_report case=%0d accepted=%0d received=%0d %s", cases, accepted_count, received_count, reason);
                $fatal(1, "uart_report assertion");
            end
        end
    endtask

    always @(posedge clk) begin
        if (rst_n && monitoring) begin
            if (in_frame) check(busy === 1'b1, "busy deasserted before complete UART stop bit");
            if (stalled) check(tx_valid && tx_data === stalled_data, "byte changed under UART backpressure");
            stalled = tx_valid && !tx_ready;
            stalled_data = tx_data;
            if (tx_valid && tx_ready) begin
                check(accepted_count < expected.len(), "unexpected extra byte");
                check(tx_data === expected[accepted_count], $sformatf("byte renderer mismatch index=%0d expected=%02x actual=%02x", accepted_count, expected[accepted_count], tx_data));
                accepted_count = accepted_count + 1;
            end
        end else stalled = 1'b0;
    end

    // Decode the physical output independently at each bit center. Sampling
    // continues through the entire stop bit, then waits for the next start.
    initial begin : decode_uart
        reg [7:0] decoded;
        integer bit_no;
        forever begin
            @(negedge uart_pin);
            if (rst_n && monitoring) begin
                in_frame = 1'b1;
                #(BIT_NS/2);
                check(uart_pin === 1'b0, "start bit center must be low");
                for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                    #BIT_NS;
                    decoded[bit_no] = uart_pin;
                end
                #BIT_NS;
                check(uart_pin === 1'b1, "stop bit center must be high");
                check(busy === 1'b1, "report busy must cover final stop-bit center");
                check(received_count < expected.len(), "unexpected extra UART frame");
                check(decoded === expected[received_count], $sformatf("physical UART mismatch index=%0d expected=%02x actual=%02x", received_count, expected[received_count], decoded));
                observed = {observed, $sformatf("%c", decoded)};
                #(BIT_NS/2);
                in_frame = 1'b0;
                received_count = received_count + 1;
            end
        end
    end

    task automatic send_and_check(input reg [3:0] code_value, input string text_value, input bit mutate_inputs);
        integer timeout_cycles;
        begin
            @(negedge clk);
            cases = cases + 1;
            expected = text_value;
            observed = "";
            accepted_count = 0;
            received_count = 0;
            monitoring = 1'b1;
            event_code = code_value;
            event_valid = 1'b1;
            @(negedge clk);
            event_valid = 1'b0;
            check(busy === 1'b1, "event must be accepted");
            if (mutate_inputs) begin
                pin_a = 6'd0; pin_b = 6'd1; pair_number = 5'd1;
                mode = 2'd0; status_ab = 2'd3; status_ba = 2'd3;
                aborted = !aborted;
                errors_ab = 32'd77; samples_ab = 32'd77; block_errors_ab = 32'd77;
                errors_ba = 32'd77; samples_ba = 32'd77; block_errors_ba = 32'd77;
                event_code = 4'd11;
            end
            timeout_cycles = 0;
            while (busy && timeout_cycles < 100000) begin
                @(negedge clk);
                timeout_cycles = timeout_cycles + 1;
            end
            check(!busy, "timeout waiting for complete report");
            check(tx_ready && uart_pin, "busy cleared before UART is idle");
            check(accepted_count == expected.len(), "wrong accepted message length");
            check(received_count == expected.len(), "wrong physical message length");
            check(observed == expected, "complete message mismatch");
            repeat (3) @(negedge clk);
            check(!tx_valid, "report repeated without another event");
            monitoring = 1'b0;
            $display("CASE_PASS uart_report n=%0d code=%0d bytes=%0d drain_cycles=%0d", cases, code_value, received_count, timeout_cycles);
        end
    endtask

    task automatic nominal_metadata;
        begin
            pin_a = 6'd32; pin_b = 6'd33; pair_number = 5'd17;
            mode = 2'd2; status_ab = 2'd0; status_ba = 2'd1; aborted = 1'b0;
            errors_ab = 32'd0; samples_ab = 32'd10000; block_errors_ab = 32'd100000;
            errors_ba = 32'hffffffff; samples_ba = 32'd100000; block_errors_ba = 32'd10000;
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        send_and_check(4'd0, "PANGU50K MES50HP J8 GPIO DIAGNOSTIC\015\012FPGA=PGL50H-6IFBG484 UART=115200 8N1\015\012INVALID: NOT_ARMED / NO_LOOPBACK. GPIO HIGH-Z.\015\012Send HELP. Fit 1k loopback and TWO 10k pulldowns, then ARM.\015\012", 1'b0);
        send_and_check(4'd1, "PAIR 01..17 | CROSS 03 09 | REF OK | ARM\015\012RUN SMOKE | RUN NORMAL | RUN STRESS | STOP | REPORT | HELP\015\012ARM confirms harness and BOTH pulldowns. RUN consumes ARM.\015\012CROSS requires a verified reference and REF OK.\015\012", 1'b0);
        nominal_metadata();
        send_and_check(4'd2, "SELECT PAIR=17 J8=35/36 NEED_ARM\015\012", 1'b1);
        send_and_check(4'd3, "ARMED: harness and both input biases confirmed by operator.\015\012", 1'b0);
        send_and_check(4'd4, "REFERENCE_CONFIRMED: operator has verified the reference IO.\015\012", 1'b0);
        nominal_metadata();
        send_and_check(4'd5, "RUN MODE=STRESS J8=35/36\015\012", 1'b1);
        nominal_metadata();
        send_and_check(4'd6, "PAIR=17 J8=35/36 MODE=STRESS ABORTED=0\015\01235->36: PASS         errors=0000000000/0000010000 MAX10K=0000100000\015\01236->35: INTERMITTENT errors=4294967295/0000100000 MAX10K=0000010000\015\012NOTE=PATH_ONLY; INVALID=NO_LOOPBACK_OR_STUCK/ABORT. RETEST_REQUIRED.\015\012", 1'b1);
        send_and_check(4'd7, "ERR INVALID_COMMAND_OR_LINE (uppercase; max 31 characters)\015\012", 1'b0);
        send_and_check(4'd8, "INVALID: NOT_ARMED_OR_REFERENCE_UNCONFIRMED. GPIO HIGH-Z.\015\012", 1'b0);
        send_and_check(4'd9, "BUSY: command rejected. Wait for report, then resend.\015\012", 1'b0);
        send_and_check(4'd10, "STOP: outputs disabled; incomplete run is INVALID.\015\012", 1'b0);
        send_and_check(4'd11, "INVALID: NO_RESULT. GPIO HIGH-Z.\015\012", 1'b0);
        nominal_metadata();
        pin_a = 6'd0; pin_b = 6'd1; pair_number = 5'd1;
        mode = 2'd0; status_ab = 2'd2; status_ba = 2'd3; aborted = 1'b1;
        errors_ab = 32'hffffffff; samples_ab = 32'hffffffff; block_errors_ab = 32'hffffffff;
        errors_ba = 32'd0; samples_ba = 32'd0; block_errors_ba = 32'd0;
        send_and_check(4'd6, "PAIR=01 J8=03/04 MODE=SMOKE  ABORTED=1\015\01203->04: FAIL         errors=4294967295/4294967295 MAX10K=4294967295\015\01204->03: INVALID      errors=0000000000/0000000000 MAX10K=0000000000\015\012NOTE=PATH_ONLY; INVALID=NO_LOOPBACK_OR_STUCK/ABORT. RETEST_REQUIRED.\015\012", 1'b1);
        nominal_metadata();
        pair_number = 5'd0; pin_a = 6'd0; pin_b = 6'd33; mode = 2'd1;
        errors_ab = 32'd10000; samples_ab = 32'd100000; block_errors_ab = 32'd0;
        errors_ba = 32'd10000; samples_ba = 32'd10000; block_errors_ba = 32'd100000;
        send_and_check(4'd6, "PAIR=00 J8=03/36 MODE=NORMAL ABORTED=0\015\01203->36: PASS         errors=0000010000/0000100000 MAX10K=0000000000\015\01236->03: INTERMITTENT errors=0000010000/0000010000 MAX10K=0000100000\015\012NOTE=PATH_ONLY; INVALID=NO_LOOPBACK_OR_STUCK/ABORT. RETEST_REQUIRED.\015\012", 1'b1);
        $display("TB_PASS uart_report cases=%0d checks=%0d", cases, checks);
        $finish;
    end

    initial begin
        #3000000;
        $fatal(1, "TB_FAIL uart_report watchdog");
    end
endmodule
`default_nettype wire

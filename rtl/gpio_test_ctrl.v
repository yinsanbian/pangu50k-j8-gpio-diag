// ============================================================
// Module : gpio_test_ctrl
// Desc   : A->B, high-Z gap, then B->A; only one of 34 IOs drives.
// LATENCY: 2 cycles (rx_raw to rx_sync); sample at SETTLE_CYCLES.
// Note   : Default timing: 1 ms symbols, >=100 us before comparison,
//          >=100 us high-Z turnaround, at 50 MHz. Faster overrides
//          are for simulation; retain physical board timing in builds.
// ============================================================
`default_nettype none

module gpio_test_ctrl #(
    parameter integer CLK_HZ         = 50000000,
    parameter integer SYMBOL_CYCLES  = 50000,
    parameter integer SETTLE_CYCLES  = 5000,
    parameter integer GAP_CYCLES     = 5000,
    parameter integer SMOKE_SAMPLES  = 100,
    parameter integer NORMAL_SAMPLES = 10000,
    parameter integer STRESS_SAMPLES = 100000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        abort,
    input  wire [5:0]  pin_a,
    input  wire [5:0]  pin_b,
    input  wire [1:0]  mode,
    input  wire        qualified,
    input  wire [33:0] rx_raw,
    output wire [33:0] drive_en,
    output reg         tx_data,
    output reg         busy,
    output reg         done,
    output reg  [1:0]  status_ab,
    output reg  [1:0]  status_ba,
    output reg  [31:0] errors_ab,
    output reg  [31:0] errors_ba,
    output reg  [31:0] samples_ab,
    output reg  [31:0] samples_ba,
    output reg         aborted,
    output reg  [31:0] block_errors_ab,
    output reg  [31:0] block_errors_ba,
    output wire        direction
);
    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_RUN  = 2'd1;
    localparam [1:0] ST_GAP  = 2'd2;

    localparam [1:0] RESULT_PASS         = 2'd0;
    localparam [1:0] RESULT_INTERMITTENT = 2'd1;
    localparam [1:0] RESULT_FAIL         = 2'd2;
    localparam [1:0] RESULT_INVALID      = 2'd3;

    localparam [31:0] SYMBOL_LAST = SYMBOL_CYCLES - 1;
    localparam [31:0] SETTLE_LAST = SETTLE_CYCLES - 1;
    localparam [31:0] GAP_LAST    = GAP_CYCLES - 1;
    localparam [31:0] SMOKE_GOAL  = SMOKE_SAMPLES;
    localparam [31:0] NORMAL_GOAL = NORMAL_SAMPLES;
    localparam [31:0] STRESS_GOAL = STRESS_SAMPLES;
    localparam [15:0] PRBS_SEED  = 16'h1ace;
    localparam integer PARAMS_VALID =
        (CLK_HZ > 0) && (SETTLE_CYCLES >= 3) &&
        (SYMBOL_CYCLES > SETTLE_CYCLES) && (GAP_CYCLES >= 1) &&
        (SMOKE_SAMPLES >= 2) && (NORMAL_SAMPLES >= 4) &&
        (STRESS_SAMPLES >= 4);

    reg  [1:0]  state;
    reg  [5:0]  pin_a_latched;
    reg  [5:0]  pin_b_latched;
    reg  [1:0]  mode_latched;
    reg         qualified_latched;
    reg         direction_reg;
    reg  [31:0] sample_goal;
    reg  [31:0] symbol_index;
    reg  [31:0] symbol_cycle;
    reg  [31:0] gap_cycle;
    reg  [15:0] prbs;

    // Independent asynchronous GPIO bits, not a coherent multi-bit bus.
    // Constraint exceptions target only rx_raw -> rx_meta D pins.
    reg  [33:0] rx_meta;
    reg  [33:0] rx_sync;

    wire [5:0]  tx_pin;
    wire [5:0]  rx_pin;
    wire        request_valid;
    wire        counter_clear;
    wire        sample_strobe;
    wire        sampled_bit;
    wire [31:0] next_symbol_index;
    wire [31:0] prbs_begin;
    wire [15:0] next_prbs;
    wire [31:0] count_errors_ab;
    wire [31:0] count_errors_ba;
    wire [31:0] count_samples_ab;
    wire [31:0] count_samples_ba;
    wire [31:0] count_block_errors_ab;
    wire [31:0] count_block_errors_ba;
    wire        seen_zero_ab;
    wire        seen_one_ab;
    wire        seen_zero_ba;
    wire        seen_one_ba;

    // Four deterministic segments: low, high, alternating, PRBS16.
    function pattern_value;
        input [1:0]  pattern_mode;
        input [31:0] index;
        input [31:0] goal;
        input [15:0] lfsr;
        reg   [31:0] quarter;
        reg   [31:0] half;
        reg   [31:0] last_quarter;
        begin
            quarter      = goal >> 2'd2;
            half         = goal >> 1'd1;
            last_quarter = goal - quarter;
            pattern_value = 1'b0;
            if (pattern_mode == 2'd0) begin
                pattern_value = index[0];
            end else if (index < quarter) begin
                pattern_value = 1'b0;
            end else if (index < half) begin
                pattern_value = 1'b1;
            end else if (index < last_quarter) begin
                pattern_value = index[0];
            end else begin
                pattern_value = lfsr[15];
            end
        end
    endfunction

    function [1:0] classify_result;
        input [31:0] error_count;
        input [31:0] sample_count;
        input        observed_zero;
        input        observed_one;
        input        qualification;
        reg   [35:0] ten_errors;
        begin
            ten_errors = {4'd0, error_count} * 36'd10;
            classify_result = RESULT_INVALID;
            // An absent loopback and a stuck input cannot be distinguished
            // reliably by this loopback test. Missing coverage is INVALID.
            if (!qualification || !observed_zero || !observed_one ||
                (sample_count == 32'd0)) begin
                classify_result = RESULT_INVALID;
            end else if (error_count == 32'd0) begin
                classify_result = RESULT_PASS;
            end else if (ten_errors <= {4'd0, sample_count}) begin
                classify_result = RESULT_INTERMITTENT;
            end else begin
                classify_result = RESULT_FAIL;
            end
        end
    endfunction

    assign direction = direction_reg;
    assign tx_pin = direction_reg ? pin_b_latched : pin_a_latched;
    assign rx_pin = direction_reg ? pin_a_latched : pin_b_latched;
    assign drive_en = ((state == ST_RUN) && rst_n && !abort) ?
                      (34'd1 << tx_pin) : 34'd0;
    assign request_valid = (PARAMS_VALID != 0) &&
                           (pin_a < 6'd34) && (pin_b < 6'd34) &&
                           (pin_a != pin_b) && (mode < 2'd3) && qualified;
    assign counter_clear = (state == ST_IDLE) && start && !abort;
    assign sample_strobe = (state == ST_RUN) &&
                           (symbol_cycle == SETTLE_LAST) && rst_n && !abort;
    assign sampled_bit = rx_sync[rx_pin];
    assign next_symbol_index = symbol_index + 32'd1;
    assign prbs_begin = sample_goal - (sample_goal >> 2'd2);
    // x^16 + x^14 + x^13 + x^11 + 1, fixed non-zero seed.
    assign next_prbs = ((mode_latched != 2'd0) && (symbol_index >= prbs_begin)) ?
                       {prbs[14:0], prbs[15] ^ prbs[13] ^ prbs[12] ^ prbs[10]} :
                       prbs;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 34'd0;
            rx_sync <= 34'd0;
        end else begin
            rx_meta <= rx_raw;
            rx_sync <= rx_meta;
        end
    end

    error_counter u_count_ab (
        .clk(clk), .rst_n(rst_n), .clear(counter_clear),
        .sample_enable(sample_strobe && !direction_reg),
        .expected(tx_data), .sampled(sampled_bit),
        .errors(count_errors_ab), .samples(count_samples_ab),
        .max_block_errors(count_block_errors_ab),
        .seen_zero(seen_zero_ab), .seen_one(seen_one_ab)
    );

    error_counter u_count_ba (
        .clk(clk), .rst_n(rst_n), .clear(counter_clear),
        .sample_enable(sample_strobe && direction_reg),
        .expected(tx_data), .sampled(sampled_bit),
        .errors(count_errors_ba), .samples(count_samples_ba),
        .max_block_errors(count_block_errors_ba),
        .seen_zero(seen_zero_ba), .seen_one(seen_one_ba)
    );

    always @(*) begin
        errors_ab       = count_errors_ab;
        errors_ba       = count_errors_ba;
        samples_ab      = count_samples_ab;
        samples_ba      = count_samples_ba;
        block_errors_ab = count_block_errors_ab;
        block_errors_ba = count_block_errors_ba;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= ST_IDLE;
            pin_a_latched     <= 6'd0;
            pin_b_latched     <= 6'd1;
            mode_latched      <= 2'd0;
            qualified_latched <= 1'b0;
            direction_reg     <= 1'b0;
            sample_goal       <= 32'd0;
            symbol_index      <= 32'd0;
            symbol_cycle      <= 32'd0;
            gap_cycle         <= 32'd0;
            prbs              <= PRBS_SEED;
            tx_data           <= 1'b0;
            busy              <= 1'b0;
            done              <= 1'b0;
            status_ab         <= RESULT_INVALID;
            status_ba         <= RESULT_INVALID;
            aborted           <= 1'b0;
        end else begin
            done <= 1'b0;
            if (abort) begin
                // Counters are deliberately preserved for post-abort review.
                state     <= ST_IDLE;
                tx_data   <= 1'b0;
                busy      <= 1'b0;
                done      <= busy;
                status_ab <= RESULT_INVALID;
                status_ba <= RESULT_INVALID;
                aborted   <= 1'b1;
            end else begin
                case (state)
                    ST_IDLE: begin
                        tx_data <= 1'b0;
                        busy    <= 1'b0;
                        if (start) begin
                            status_ab <= RESULT_INVALID;
                            status_ba <= RESULT_INVALID;
                            aborted   <= 1'b0;
                            if (request_valid) begin
                                pin_a_latched     <= pin_a;
                                pin_b_latched     <= pin_b;
                                mode_latched      <= mode;
                                qualified_latched <= qualified;
                                direction_reg     <= 1'b0;
                                symbol_index      <= 32'd0;
                                symbol_cycle      <= 32'd0;
                                gap_cycle         <= 32'd0;
                                prbs              <= PRBS_SEED;
                                tx_data           <= 1'b0;
                                busy              <= 1'b1;
                                state             <= ST_RUN;
                                case (mode)
                                    2'd0: sample_goal <= SMOKE_GOAL;
                                    2'd1: sample_goal <= NORMAL_GOAL;
                                    2'd2: sample_goal <= STRESS_GOAL;
                                    default: sample_goal <= 32'd0;
                                endcase
                            end else begin
                                done <= 1'b1;
                            end
                        end
                    end
                    ST_RUN: begin
                        if (symbol_cycle == SYMBOL_LAST) begin
                            symbol_cycle <= 32'd0;
                            if (next_symbol_index == sample_goal) begin
                                tx_data <= 1'b0;
                                if (!direction_reg) begin
                                    status_ab <= classify_result(
                                        count_errors_ab, count_samples_ab,
                                        seen_zero_ab, seen_one_ab, qualified_latched);
                                    gap_cycle <= 32'd0;
                                    state     <= ST_GAP;
                                end else begin
                                    status_ba <= classify_result(
                                        count_errors_ba, count_samples_ba,
                                        seen_zero_ba, seen_one_ba, qualified_latched);
                                    busy  <= 1'b0;
                                    done  <= 1'b1;
                                    state <= ST_IDLE;
                                end
                            end else begin
                                symbol_index <= next_symbol_index;
                                prbs         <= next_prbs;
                                tx_data      <= pattern_value(mode_latched,
                                                next_symbol_index, sample_goal, next_prbs);
                            end
                        end else begin
                            symbol_cycle <= symbol_cycle + 32'd1;
                        end
                    end
                    ST_GAP: begin
                        tx_data <= 1'b0;
                        if (gap_cycle == GAP_LAST) begin
                            direction_reg <= 1'b1;
                            symbol_index  <= 32'd0;
                            symbol_cycle  <= 32'd0;
                            prbs          <= PRBS_SEED;
                            state         <= ST_RUN;
                        end else begin
                            gap_cycle <= gap_cycle + 32'd1;
                        end
                    end
                    default: begin
                        state     <= ST_IDLE;
                        tx_data   <= 1'b0;
                        busy      <= 1'b0;
                        done      <= 1'b1;
                        status_ab <= RESULT_INVALID;
                        status_ba <= RESULT_INVALID;
                    end
                endcase
            end
        end
    end
endmodule

`default_nettype wire

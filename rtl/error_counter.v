// ============================================================
// Module : error_counter
// Desc   : Counts one comparison per sample and tracks input coverage.
// LATENCY: 1 cycles (sample_enable to registered totals)
// Note   : max_block_errors includes the current incomplete tail block.
// ============================================================
`default_nettype none

module error_counter #(
    parameter integer BLOCK_SAMPLES = 10000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,
    input  wire        sample_enable,
    input  wire        expected,
    input  wire        sampled,
    output reg  [31:0] errors,
    output reg  [31:0] samples,
    output reg  [31:0] max_block_errors,
    output reg         seen_zero,
    output reg         seen_one
);
    localparam [31:0] BLOCK_LAST = BLOCK_SAMPLES - 1;

    reg  [31:0] block_samples;
    reg  [31:0] block_error_count;
    wire        sample_mismatch;
    wire [31:0] block_errors_next;

    // Case inequality counts X/Z as errors in simulation. In hardware,
    // sampled is a physical binary input, so this is a one-bit comparator.
    assign sample_mismatch = (sampled !== expected);
    assign block_errors_next = block_error_count + {31'd0, sample_mismatch};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            errors            <= 32'd0;
            samples           <= 32'd0;
            max_block_errors  <= 32'd0;
            seen_zero         <= 1'b0;
            seen_one          <= 1'b0;
            block_samples     <= 32'd0;
            block_error_count <= 32'd0;
        end else if (clear) begin
            errors            <= 32'd0;
            samples           <= 32'd0;
            max_block_errors  <= 32'd0;
            seen_zero         <= 1'b0;
            seen_one          <= 1'b0;
            block_samples     <= 32'd0;
            block_error_count <= 32'd0;
        end else if (sample_enable) begin
            samples <= samples + 32'd1;
            errors  <= errors + {31'd0, sample_mismatch};
            if (sampled === 1'b0) begin
                seen_zero <= 1'b1;
            end
            if (sampled === 1'b1) begin
                seen_one <= 1'b1;
            end
            if (block_errors_next > max_block_errors) begin
                max_block_errors <= block_errors_next;
            end
            if (block_samples == BLOCK_LAST) begin
                block_samples     <= 32'd0;
                block_error_count <= 32'd0;
            end else begin
                block_samples     <= block_samples + 32'd1;
                block_error_count <= block_errors_next;
            end
        end
    end
endmodule

`default_nettype wire

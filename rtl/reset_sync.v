// Module: reset_sync -- asynchronous assertion, two-clock release.
// LATENCY: 2 cycles after rst_n rises; assertion is asynchronous.
`default_nettype none
module reset_sync (
    input wire clk,
    input wire rst_n,
    output wire sync_rst_n
);
    reg reset_meta;
    reg reset_sync_ff;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reset_meta <= 1'b0;
            reset_sync_ff <= 1'b0;
        end else begin
            reset_meta <= 1'b1;
            reset_sync_ff <= reset_meta;
        end
    end
    assign sync_rst_n = reset_sync_ff;
endmodule
`default_nettype wire

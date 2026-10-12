// ============================================================
// Module : gpio_pair_mux
// Desc   : Physical J8 pins 3..36, index = physical pin - 3.
// LATENCY: 0 cycles (physical bidirectional IO connection)
// Note   : drive_en must be one-hot or zero; tested in simulation.
// ============================================================
`default_nettype none

module gpio_pair_mux (
    input  wire [33:0] drive_en,
    input  wire        tx_data,
    inout  wire [33:0] j8_gpio,
    output wire [33:0] rx_raw
);
    genvar pin_index;
    generate
        for (pin_index = 0; pin_index < 34; pin_index = pin_index + 1) begin : g_gpio
            assign j8_gpio[pin_index] = drive_en[pin_index] ? tx_data : 1'bz;
        end
    endgenerate

    assign rx_raw = j8_gpio;
endmodule

`default_nettype wire

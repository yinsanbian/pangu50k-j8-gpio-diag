# PDS IO 映射逐脚审计

结果：PASS；38 个物理端口，34 个 GTP_IOBUF。

生成 PCF：`pds/device_map/gpio_diag_top.pcf`
综合报告：`pds/synthesize/gpio_diag_top.snr`
约束检查：`pds/synthesize/constraint_check.ccr`

| 端口 | J8物理脚 | 封装脚 | 方向 | IO标准 | 结果 |
|---|---:|---|---|---|---|
| clk_50m | — | P20 | INPUT | LVCMOS33 | PASS |
| rst_n | — | K18 | INPUT | LVCMOS33 | PASS |
| uart_rx | — | R8 | INPUT | LVCMOS33 | PASS |
| uart_tx | — | R9 | OUTPUT | LVCMOS33 | PASS |
| j8_gpio[0] | 3 | AB13 | INOUT | LVCMOS33 | PASS |
| j8_gpio[1] | 4 | Y13 | INOUT | LVCMOS33 | PASS |
| j8_gpio[2] | 5 | AB11 | INOUT | LVCMOS33 | PASS |
| j8_gpio[3] | 6 | Y11 | INOUT | LVCMOS33 | PASS |
| j8_gpio[4] | 7 | W11 | INOUT | LVCMOS33 | PASS |
| j8_gpio[5] | 8 | V11 | INOUT | LVCMOS33 | PASS |
| j8_gpio[6] | 9 | AB10 | INOUT | LVCMOS33 | PASS |
| j8_gpio[7] | 10 | AA10 | INOUT | LVCMOS33 | PASS |
| j8_gpio[8] | 11 | Y10 | INOUT | LVCMOS33 | PASS |
| j8_gpio[9] | 12 | W10 | INOUT | LVCMOS33 | PASS |
| j8_gpio[10] | 13 | T11 | INOUT | LVCMOS33 | PASS |
| j8_gpio[11] | 14 | R11 | INOUT | LVCMOS33 | PASS |
| j8_gpio[12] | 15 | Y12 | INOUT | LVCMOS33 | PASS |
| j8_gpio[13] | 16 | W12 | INOUT | LVCMOS33 | PASS |
| j8_gpio[14] | 17 | U12 | INOUT | LVCMOS33 | PASS |
| j8_gpio[15] | 18 | T12 | INOUT | LVCMOS33 | PASS |
| j8_gpio[16] | 19 | U10 | INOUT | LVCMOS33 | PASS |
| j8_gpio[17] | 20 | T10 | INOUT | LVCMOS33 | PASS |
| j8_gpio[18] | 21 | AB9 | INOUT | LVCMOS33 | PASS |
| j8_gpio[19] | 22 | Y9 | INOUT | LVCMOS33 | PASS |
| j8_gpio[20] | 23 | V9 | INOUT | LVCMOS33 | PASS |
| j8_gpio[21] | 24 | U9 | INOUT | LVCMOS33 | PASS |
| j8_gpio[22] | 25 | U8 | INOUT | LVCMOS33 | PASS |
| j8_gpio[23] | 26 | T8 | INOUT | LVCMOS33 | PASS |
| j8_gpio[24] | 27 | W8 | INOUT | LVCMOS33 | PASS |
| j8_gpio[25] | 28 | V7 | INOUT | LVCMOS33 | PASS |
| j8_gpio[26] | 29 | AB8 | INOUT | LVCMOS33 | PASS |
| j8_gpio[27] | 30 | AA8 | INOUT | LVCMOS33 | PASS |
| j8_gpio[28] | 31 | Y6 | INOUT | LVCMOS33 | PASS |
| j8_gpio[29] | 32 | W6 | INOUT | LVCMOS33 | PASS |
| j8_gpio[30] | 33 | AB5 | INOUT | LVCMOS33 | PASS |
| j8_gpio[31] | 34 | Y5 | INOUT | LVCMOS33 | PASS |
| j8_gpio[32] | 35 | AB4 | INOUT | LVCMOS33 | PASS |
| j8_gpio[33] | 36 | AA4 | INOUT | LVCMOS33 | PASS |

内部偏置 NONE=TRUE；所有输出和双向端口均 DRIVE=4、SLEW=SLOW；没有重复占用封装脚。
GPIO 输入异常例外匹配到第一同步级 u_ctrl/rx_meta[33:0]，并保留后级 50 MHz 时序检查。

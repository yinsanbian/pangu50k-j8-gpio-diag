# UART report independent verification

- Engine: actual local `pango-mcp-local` `fpga_msim_sim`, ModelSim SE-64 10.7.
- Testbench: [tb_uart_report.sv](../sim/tb/tb_uart_report.sv).
- Repeatable request: [arguments.json](../sim/report_test/arguments.json).
- Result: **PASS, 14 cases, 261,590 checks, 0 errors, 0 warnings**.
- Full MCP and vendor transcripts are kept on the build machine and are not part of this public source package.

The test defines complete readable expected messages independently of the RTL
renderer, compares every accepted byte, and independently decodes the physical
UART output at bit centers. UART timing is accelerated to 8 clocks per bit in
this isolated report test; production baud configuration is covered separately
by the project configuration and end-to-end UART verification.

| Coverage | Evidence |
|---|---|
| All 12 event messages | Complete messages for codes 0 through 11, including exact lengths and CR/LF bytes |
| Decimal formatting | 0, 10,000, 100,000 and 4,294,967,295 across all six numeric fields |
| Pin metadata | 01/17 pair numbers, CROSS pair 00, physical J8 03/04/35/36 |
| Mode/status formatting | SMOKE, NORMAL, STRESS and PASS/INTERMITTENT/FAIL/INVALID |
| Metadata snapshot | Input pins, pair, mode, statuses, abort flag, counters and event code deliberately changed after event acceptance |
| Backpressure | Each byte remains valid and stable while the physical transmitter is occupied |
| Final stop bit | Report busy remains asserted throughout every physical frame, including the last full stop bit |
| No replay | No further valid byte appears without a new event |

An independent top-level review also found the one-clock completion window in
`command_busy`: `core_busy` had dropped before `done_pending` became visible.
The project author added `core_done` to that busy condition. The end-to-end
verification bench includes a dedicated completion-window regression.

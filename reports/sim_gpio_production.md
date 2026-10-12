# 生产参数 SMOKE 自检结果

**PASS — 2026-10-10**。由真实 pango-mcp `fpga_msim_sim` 调用 ModelSim SE-64 10.7，未使用缓存。编译及仿真 0 错误、0 警告，两项 MCP 日志断言通过。

`TB_PASS gpio_production checks=24778444 samples=100/100 min_settle_ns=100000 gap_ns=100000 uart_div=434 bytes=553`

此台实例化 `gpio_diag_top` 时未覆盖任何参数。实际时钟 50 MHz；UART 115200 baud 采用真实分频 434；码元 50,000 个周期，稳定等待 5,000 个周期，高阻换向 5,000 个周期。仿真 KEY1 低有效复位后，通过完整串口 8N1 帧发送 PAIR 01、ARM、RUN SMOKE。通过实际 `inout` 连接外部 2 ns 延迟回路和两端弱下拉；两个方向各 100 个样本，零错且 PASS，全 GPIO 最终高阻。

从实际发送脚电平变化到采样的最短时间为 100,000 ns；两个方向之间的高阻间隔为 100,000 ns。完整串口结果共 553 字节，RUN 确认和最终报告逐字节比对通过。仿真总时长 247,769,391 ns，未将生产测试时间缩短。

生产仿真在本机生成 `gpio_production.vcd`（12条所选信号，76,760字节）。公开仓库收录从该波形截取的4.1ms换向片段 `gpio_turnaround.vcd` 和渲染图；本机原始仿真VCD不纳入仓库。该结果证明生产参数的仿真行为，实板测试仍需在 J8 接触端接线后单独实施。

复现：`./sim/run_sim.ps1 -Test production`。波形图和选择后的换向 VCD 随仓库提供；完整 MCP、ModelSim 与许可证日志保留在本机。

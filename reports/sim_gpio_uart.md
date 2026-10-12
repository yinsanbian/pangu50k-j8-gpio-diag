# UART 顶层集成自检结果

**PASS — 2026-10-10**。由真实 pango-mcp `fpga_msim_sim` 调用 ModelSim SE-64 10.7，未使用缓存。编译及仿真 0 错误、0 警告，两项 MCP 日志断言通过。

`TB_PASS gpio_uart cases=64 checks=18525597 tx_bytes=5929 starts=9 completions=9`

独立串口发送器以真实 8N1 电平激励 `uart_rx`，独立解码器仅观察 `uart_tx` 引脚并逐字节比对完整 ASCII 回应。包含启动、HELP、REPORT、全部 17 个 PAIR 映射、首末脚双向 CROSS、ARM 消耗与重新选择后的 REF 重确认、SMOKE/NORMAL/STRESS（生产样本计数 100/10000/100000）、PASS/FAIL/INTERMITTENT/INVALID 四类结果、断路错误计数与十位十进制输出。

CR/LF/CRLF 均只触发一次指令；大小写错误、非法脚、相同脚、超过 31 字节的行与坏停止位拒绝整行，不启动测试。运行期间普通命令拒绝并合并 BUSY，STOP 保存部分计数并立即释放输出。完成结果保存原测试 metadata，后续切换 PAIR 不会改变 REPORT。加速 SMOKE 在 RUN 确认消息尚未完成时结束，验证结果排队不丢失。另在 `core_done` 的单周期窗口通过解析器级 terminator 激励检查拒绝 PAIR，验证完成与指令仲裁修复。

顶层台保持外部 2 ns 接线回路及两端弱下拉。串口 CLK_HZ/BAUD 参数为 1.6 MHz/100000（分频 16），码元/采样等待/高阻间隔为 16/8/8；完整生产时钟与波特率另由 `sim_gpio_production.md` 验证。该结果不代表实板串口、引脚导通或焊点测试已完成。

复现：`./sim/run_sim.ps1 -Test uart`。MCP、ModelSim 与许可证日志属于本机生成文件，不纳入公开仓库。

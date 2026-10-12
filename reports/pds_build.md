# PDS 工程实现验收

结果：PASS。真实 pango-mcp tools/call 执行 PDS 2023.2-SP3，目标 Logos/PGL50H/-6/FBG484。

| 阶段 | 结果 |
|---|---|
| compile | PASS |
| synthesize | PASS |
| dev_map | PASS |
| pnr | PASS |
| report_timing | PASS |
| gen_bit_stream | PASS |

时钟要求：50 MHz；时序结论：All Constraints Met.。
Setup 最差余量：8.853 ns；Hold 最差余量：0.183 ns；Fmax：89.7102 MHz。

资源：LUT=2268，寄存器=1695，锁存器=0，DRM/APM=0，IO=38。
综合报告明确有 34 个 GTP_IOBUF，GPIO 三态映射正确；38 路管脚逐项审计见 io_audit.md。

位流输出目录：`pds/generate_bitstream/`；主配置时钟已显式设置 40M。位流由本机 PDS 重新生成，不随仓库发布。
独立归档的时序报告：`reports/timing_gpio_diag_top.rtr`（保存在本机生成目录，不随源代码仓库发布）。

## 已审查的工具提示

KEY1 与 J8 的 AB13/Y13/AB5/Y5 属于器件共享配置脚，PDS 提示 share pin；这些管脚来自原厂板卡手册，PCF 与实现已匹配，未启用保留并行配置端口。
GPIO 回环和 UART 是异步接口，TA 提示未设置同步 IO delay 并按组合 IO 处理。工程不虚构外部时钟相位；对输入只切除到第一同步级的异步建立/保持检查，对输出施加 100 ns max_delay，后级与内部逻辑按 50 MHz 检查。
原输入命令计数器最高位被优化为常数，这是参数范围内的正常优化；没有 latch 和多驱动。
验证摘要由本机 pango-mcp 和 PDS 输出整理；原始工具日志与许可证配置留在本机，不纳入公开仓库。
本次只进行了离线创建、仿真与实现；未执行任何器件下载或实板诊断。

完整阶段证据和本机源码/位流 SHA-256 清单留存在构建机器上。

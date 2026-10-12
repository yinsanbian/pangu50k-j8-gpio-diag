# J8 GPIO 测试工程交付验收

日期：2026-10-10。结果：**离线验收 PASS**；未执行板卡下载或实物焊点检测。

目标：MES50HP 标准版，硬件 PGL50H-6IFBG484；开发验证使用 PDS 2023.2-SP3、ModelSim SE-64 10.7 和本机 pango-mcp MCP 服务。创建、构建、仿真与波形均通过 MCP 调用完成。以下内容为已脱敏的验收摘要。

## 可直接使用的交付物

- [PDS 工程](../pds/pangu50k_j8_gpio_diag.pds)：9份RTL、当前版本精确FDC、38路IO。
- 位流配置时钟40M；本地运行PDS可按验收摘要复现并生成 `.sbit` 和 `.smsk`。
- [中文接线和串口操作说明](../README.md)：两端各10kΩ下拉、1kΩ外部环回；下载/上电后按KEY1。
- [引脚逐项审计](io_audit.md)：全部38脚匹配方案及附加KEY1复位，无重用封装脚。
- [换向波形](gpio_turnaround.wave.html)、[原始生产仿真VCD](gpio_production.vcd)、[独立波形审计](production_wave_audit.json)。

## 功能验证

| 自检台 | 最终结果 | 关键证据 |
|---|---|---|
| GPIO核心 | 42案例，15,160,084检查，PASS | 17对双向、CROSS、断线、单向异常、间歇错误、0～1覆盖、PRBS、配置锁存、10%阈值、STOP/复位 |
| UART顶层 | 64案例，18,525,597检查，5,929字节，PASS | 完整ASCII逐字比对、CRLF、超长/坏帧拒绝、ARM消耗、REF重确认、REPORT原元数据、完成窗口仲裁 |
| 报告独立验证 | 14案例，261,590检查，PASS | 12种事件、全状态、全部数字字段及32位最大值、背压、最后停止位 |
| 原生产参数SMOKE | 24,778,444检查，PASS | 所有顶层参数保持默认，50MHz / 115200，434周期/串口位，双向各100样本零错 |

共120个功能案例，另外完成一轮真实生产参数SMOKE。所有最终仿真的编译与运行均 **0错误、0警告**。功能测试保留100 / 10,000 / 100,000真实样本数量，全面测试仅缩短等待周期；生产SMOKE未覆盖任何参数。

各自报告：[核心](sim_gpio_core.md)、[顶层UART](sim_gpio_uart.md)、[报告模块](sim_uart_report.md)、[生产参数](sim_gpio_production.md)。

生产VCD经独立解析复核：输出使能依次0→1→0→2→0，每方向100ms；码元1ms；每次有效比较距码元开始100µs；方向切换全高阻100µs。原VCD保持不变，`gpio_turnaround.vcd`截取换向附近4.1ms并平移时间原点；原始绝对时间范围记录在波形审计JSON。该片段经 pango-mcp `fpga_wave` 渲染，无信号抽样删减。

## PDS 实现

综合、器件映射、布局布线、时序分析、生成位流全部PASS。50MHz时序为 **All Constraints Met**；Setup WNS=8.853ns，Hold最差=0.183ns，全部角点TNS=0、失败端点=0。

LUT 2,268 / 42,800（5.30%），FF 1,695 / 64,200（2.64%），DRM/APM=0，锁存器=0。综合网表明确为34个GTP_IOBUF，GPIO三态进入物理IO，没有用内部回读代替外部环回。

PDS存在经审查的共享配置脚及异步IO延时提示；最终阶段未留下错误或Critical，解释见 [PDS验收](pds_build.md)。异步输入只到第一级同步器设例外，后级保持50MHz约束；输出传播上限100ns。详细的机器路径、许可证配置、原始MCP与厂商日志不随仓库公开。

## 复现与实板记录

关闭PDS GUI后，用 `scripts/run_pds.ps1` 重建并重新核对IO与时序。`sim/run_sim.ps1 -Test all` 顺序运行核心、UART、独立报告与生产参数四项，通过真实pango-mcp调用ModelSim；也可单选core/uart/report/production。波形审计与渲染参数在scripts中。

串口原始仿真记录、`simulation_uart_results.csv` **仅为仿真资料**，不能作为实板维修记录。该CSV保留重复REPORT帧，行数不代表独立测试次数。真实记录模板为 `docs/test_record.csv`，17对均初始化UNTESTED。

实板下载与接线核对由操作者执行。FPGA无法验证偏置电阻和参考脚可靠性，ARM / REF OK为操作员确认。INVALID涵盖无环回、卡死、资格不足和中止；FAIL只表明路径候选异常，必须换线、交叉和复测后再判断焊点。低速PASS不替代高速质量或长期可靠性检查。

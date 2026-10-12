# MES50HP 标准版引脚与工具核查

核查日期：2026-10-10；方案限定 MES50HP 标准版，不使用 MES50KN、MES50KH、50Pro 的映射。

## 原厂依据

已阅读方案所引的 [MES50HP 硬件使用手册 1V1](https://szlogicmatrix.com/wp-content/uploads/2025/12/MES50HP%E5%BC%80%E5%8F%91%E6%9D%BF%E7%A1%AC%E4%BB%B6%E4%BD%BF%E7%94%A8%E6%89%8B%E5%86%8C_1V1.pdf)，并核对其中表 3-12（PDF 零基索引 35）、表 2-3（索引 9）、表 3-5（索引 26）、表 3-8（索引 32）。34 路 GPIO 与用户方案完全一致，索引 i 对应 J8 物理 i+3。

| Pair | J8 A/B | A/B 封装脚 |
|---:|---|---|
| 01 | 3/4 | AB13/Y13 |
| 02 | 5/6 | AB11/Y11 |
| 03 | 7/8 | W11/V11 |
| 04 | 9/10 | AB10/AA10 |
| 05 | 11/12 | Y10/W10 |
| 06 | 13/14 | T11/R11 |
| 07 | 15/16 | Y12/W12 |
| 08 | 17/18 | U12/T12 |
| 09 | 19/20 | U10/T10 |
| 10 | 21/22 | AB9/Y9 |
| 11 | 23/24 | V9/U9 |
| 12 | 25/26 | U8/T8 |
| 13 | 27/28 | W8/V7 |
| 14 | 29/30 | AB8/AA8 |
| 15 | 31/32 | Y6/W6 |
| 16 | 33/34 | AB5/Y5 |
| 17 | 35/36 | AB4/AA4 |

附加控制资源：clk_50m=P20，uart_tx=R9，uart_rx=R8，rst_n=KEY1 K18。KEY1 为规范要求的可靠外部复位，因此工程总 IO 数为 38，较原方案的可选 UART 顶层新增一个按键复位输入。

J8-1/37/38 为 GND，2 为 5V0，39/40 为 A3V3；这些电源和地脚不进入 RTL，不能通过 GPIO 动态检测。

## 当前工具与语法证据

- pango-mcp 为本机 `tools/pango-mcp` 的本地重建版 0.1.0，共 30 个工具；通过真正的 stdio JSON-RPC initialize/tools/call 使用，非直接调用内部函数替代 MCP。
- 已通过 MCP 调用环境/器件检索、PDS 工程创建与 ModelSim 仿真工具。
- PDS 2023.2-SP3 build 154097；器件字段 Logos/PGL50H/-6/FBG484 经厂商生成的 .pds 核对。
- ModelSim SE-64 10.7 用于功能仿真；公开文档不记本机安装路径、许可证路径或原始服务器响应。
- FDC 的 define_attribute 格式经本机官方例程验证，4 mA 驱动有同安装版本官方 DDR3 示范约束，最终支持以本工程 PDS IO 映射结果核验。
- GTP_GRS 在 MCP 默认 Logos2 检索库和实际 Logos gtp_lib.v 都只有 GRS_N 输入，不存在 GRS 输出；工程采用 KEY1 与 reset_sync，需上电/下载后按键复位。
- 当前 fpga_pds_create_project 工具只能创建模板，不接受 sources；工程先由该工具调用厂商创建，然后备份 .pds、替换明确的源/约束 widget 与顶层，再经 fpga_project_info 及 PDS 编译复核。

## 电气与时序条件

所有诊断 GPIO 配置 3.3V 单端 LVCMOS33、4 mA、SLOW；明确禁用内部拉阻。硬件自动双向检测时应在两端均安装 10 kohm 对地电阻，并通过 1 kohm 跨接 J8 接触端，避免需要在运行中换偏置位置。未验证接线和输入偏置不得申报 PASS。

UART RX 与 J8 回环均异步输入，在 RTL 两级同步，约束只放开到第一级 rx_meta；KEY1 异步复位用 reset_sync 同步释放。输出到异步外部接收端施加 100 ns 传播上限，远小于最低 100 us 的稳定等待。内部全部使用 50 MHz，无 PLL、衍生时钟和跨时钟总线。

器件实现通过后还需在实板确认电源、VCCIO 和 J8 Pin1 朝向；离线综合或仿真无法确认这些实物条件。

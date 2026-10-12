# GPIO 核心自检结果

**PASS — 2026-10-10**。由真实 pango-mcp `fpga_msim_sim` 调用 ModelSim SE-64 10.7，未使用缓存。编译及仿真 0 错误、0 警告，两项 MCP 日志断言通过。

`TB_PASS gpio_core cases=42 checks=15160084 active_drive_cycles=3619993`

34 路 GPIO 的 17 对相邻连接全部双向通过；3 组跨对/反向 CROSS 通过。SMOKE 保留每方向 100 样本，NORMAL 保留 10,000，STRESS 保留 100,000；仅缩短码元/采样等待/换向间隔为 16/8/8 周期。所有样本由独立交替/四段码型/PRBS16 参考逐位检查。

断路与固定高均得到 INVALID；双方向单独反相得到对应方向 FAIL；单错得到 INTERMITTENT；10%/11% 错误的分类边界正确。STRESS 注入 5 个错误分布于不同固定 10k 样本块，最大块错数为 2。未确认、非法脚、相同脚、非法模式均不驱动 GPIO。每周期检查一个或零个输出，以及方向切换时完整高阻等待。四个阶段的中止、再次启动、异步复位以及运行中配置锁存/重复 START 均通过。

测试经 `gpio_pair_mux` 的真实 `inout` 与外部 2 ns 传播模型、弱下拉返回接收脚。该结果验证 RTL 行为，不能证明实板接触端或焊点导通。

复现：`./sim/run_sim.ps1 -Test core`。MCP、ModelSim 与许可证日志属于本机生成文件，不纳入公开仓库。

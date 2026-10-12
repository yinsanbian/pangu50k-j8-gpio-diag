# 参与贡献

感谢你关注 J8 GPIO 测试工程。改动前请先说明目标板卡版本、PDS 版本及复现步骤。

## 修改 RTL

- 目标器件保持 MES50HP 标准版 `PGL50H-6IFBG484`。
- 每个模块注明功能和延迟；使用 Verilog-2001、明确位宽、完整组合默认值与异步低有效复位。
- GPIO 异步输入经过两级同步；仅在一个选中的物理 GPIO 上启用输出。IDLE、换向、中止及测试结束均须全高阻。
- 不要根据另一版盘古板改写 J8 引脚表。变更约束时同时更新 IO 审计与引脚核对文档。
- 所有运行结果须区分 RTL 仿真、PDS 实现和实板测试，不把其中一种证据表述成另一种。

## 本地验证

仿真需配置可调用的 Pango MCP 与 ModelSim：

```powershell
$env:PANGO_MCP_SERVER = 'C:/path/to/pango-mcp/src/index.mjs'
$env:PANGO_MCP_ENV_FILE = 'C:/path/to/pango-mcp.env'
./sim/run_sim.ps1 -Test all
```

PDS 实现需安装并授权 PDS 2023.2-SP3，且关闭工程 GUI 后运行：

```powershell
./scripts/run_pds.ps1
```

若本机无法运行厂商工具，请在贡献说明中注明限制与尚未验证的阶段。提交源代码、约束、可复现自检与简洁验收摘要；不要提交本机许可证、原始 MCP/ModelSim 日志、PDS 数据库或临时串口记录。

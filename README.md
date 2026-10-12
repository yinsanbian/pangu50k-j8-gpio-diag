# 盘古 50K 标准版 J8 GPIO 测试 PDS 工程

适用 **MES50HP 标准版 / PGL50H-6IFBG484**，测试 J8 物理 3～36 脚的 34 路 GPIO。工程入口为 [pds/pangu50k_j8_gpio_diag.pds](pds/pangu50k_j8_gpio_diag.pds)，顶层 `gpio_diag_top`，PDS 目标 `Logos / PGL50H / -6 / FBG484`。实现 17 对双向环回、SMOKE/NORMAL/STRESS、任意两只 GPIO 的 CROSS 复测、串口控制与报告。

这是外部接触端环回工程。内部输出回读不能代替 J8 接触端接线。结果说明被测试的连接路径，本轮 PASS 不等于焊点长期可靠，FAIL 不能直接定位某一只脚虚焊。

## 首次使用

1. 核对实物型号、J8 Pin1 方向及 BANK 电压；本工程使用单端 LVCMOS33 / 3.3V，4mA、SLOW，关闭内部上下拉。移除 J8 上其他模块。
2. 在 PDS 打开上述 `.pds` 并生成位流。本仓库只发布 RTL 与工程配置，不附带板卡位流。
3. 串口连接板载 CP2102 Type-C，115200 / 8N1，无流控；**下载或重新上电后按一下 KEY1**（K18，低有效复位）。本工程使用真实按键复位及两级同步释放，未依赖未经验证的 RTL 上电复位。按键复位清除所有测试、确认与结果。
4. 不接跳线先复位，应看到 `INVALID: NOT_ARMED / NO_LOOPBACK. GPIO HIGH-Z.`。此时 GPIO 不驱动。先完成这一启动检查，再断电接线。
5. 首对在 J8 **3/4 的外部接触端**跨接 **1kΩ**，并在 **3脚和4脚各接一只10kΩ到GND**。核对后上电、按 KEY1，按下例逐条发送命令，**每条等回复完成再发送下一条**。

```text
PAIR 01
ARM
RUN SMOKE
```

自动先 3→4，再全高阻至少100µs，然后4→3；约0.2秒完成100次/方向，结束后全高阻。两端各一个10kΩ是对原方案“接收端单下拉并随换向移动”的适配，可自动双向测试，无需运行中改线。只有一只下拉的夹具应先补齐另一端偏置，不能直接运行自动双向检测。

**ARM 是操作员对已核实外部接触端环回和两端可靠输入偏置的确认，FPGA 无法从数字电平自动证明电阻已安装。** 未 ARM 的 RUN 不驱动；每次 RUN 消耗 ARM，重新测试前再次确认并发送 ARM。

J8-2 是5V，禁止接到GPIO。1/37/38为GND，39/40为3.3V，均不进入测试端口。转移跳线前确保测试完成或STOP并等待回复，再断电移线、核对后上电复位。通过匹配的适配件接触插座，避免撑坏触点。

## 串口命令

命令使用大写，CR、LF或CRLF终止；最长31个可打印ASCII字符。超长行、乱码及错误停止位会丢弃整行。终端应关闭自动循环发送。

| 命令 | 行为 |
|---|---|
| `PAIR 01` ～ `PAIR 17` | 选定相邻对，清除 ARM 和参考确认；未自动启动 |
| `CROSS 03 09` | 任意 J8 物理3～36脚配对；两脚必须不同；报告 PAIR=00 |
| `REF OK` | 仅 CROSS 有效，确认其中的参考 IO 已经实测可靠 |
| `ARM` | 确认外部环回与两端10kΩ偏置；不驱动GPIO |
| `RUN SMOKE` | 每方向100样本，交替0/1，约0.1秒/方向 |
| `RUN NORMAL` | 每方向10,000样本，约10秒/方向 |
| `RUN STRESS` | 每方向100,000样本，约100秒/方向 |
| `STOP` | 无论测试或报告状态都可中止输出；未完成结果 INVALID |
| `REPORT` | 重发最近一次结果，保留原测试对、模式和脚号 |
| `HELP` | 显示命令及确认条件 |

NORMAL/STRESS 的样本均依次包含全低、全高、交替、PRBS16四段。码元默认为50,000个50MHz时钟（1ms），驱动变化后等待5,000时钟（100µs）才比较一次，输入先两级同步。PRBS固定非零种子，两个方向独立重播。

运行期间或报告发送期间，普通命令会拒绝并提示 BUSY；等待输出结束后重发。持续大量发送可能合并为一次 BUSY 回复，成功操作不排队。STOP始终有效，当前串口帧/报告可以先发完，GPIO停止不依赖报告结束。完成瞬间也纳入 BUSY，避免下一次启动覆盖上一结果。

对于已确认可靠的 J8-3 参考脚与可疑 J8-9，可断电改接3/9、两端下拉，随后依次发送：

```text
CROSS 03 09
REF OK
ARM
RUN NORMAL
```

CROSS 使用RUN选择的样本模式；原方案中的CROSS是接线方式，SMOKE/NORMAL/STRESS是码型与样本数量。选择新测试对会清除两种确认。

## 如何读结果

```text
PAIR=01 J8=03/04 MODE=NORMAL ABORTED=0
03->04: PASS         errors=0000000000/0000010000 MAX10K=0000000000
04->03: PASS         errors=0000000000/0000010000 MAX10K=0000000000
NOTE=PATH_ONLY; INVALID=NO_LOOPBACK_OR_STUCK/ABORT. RETEST_REQUIRED.
```

所有数字均是**十进制**，补零至10位。`errors`为错样数/有效样本数；`MAX10K`是连续每10,000个样本分块后，错误最多一块的错误数，包括不足10,000的尾块。STRESS每方向10块，MAX10K用于观察错误是否集中，未提供各块的完整时间序列。

| 状态 | 本轮判定 |
|---|---|
| PASS | 资格确认满足、观测到高低两种输入且零错误 |
| INTERMITTENT | 高低覆盖完整，错误大于0且不超过10%；提示换线/复测 |
| FAIL | 高低覆盖完整，错误超过10%；路径异常候选，须复测确认 |
| INVALID | 未确认、参数非法、中止，或未观测到完整高低覆盖 |

不接线且有下拉、输入卡0或卡1，均报 INVALID / NO_LOOPBACK_OR_STUCK。数字测试不能区分断线和完全卡死，也不能自动验证接线、偏置、参考脚真实性。错误率10%是本工程筛查阈值，符合方案建议的“少量/大量错误”分类，不能作为焊点虚焊的定论。

完成全部17对须由操作者逐对移动夹具，每对确认后启动；单根跳线不能自动完成17对实物连接。测试记录模板见 [docs/test_record.csv](docs/test_record.csv)。报告摘要工具 [scripts/summarize_log.py](scripts/summarize_log.py) 可从保存的串口文本生成结果CSV和17对统计，未测试对保持UNTESTED，不补造通过结果。

## 工程与验证

```text
rtl/             9个Verilog-2001模块，无initial、仿真delay和隐式网络
constraints/     当前PDS版本的38路IO及50MHz/同步器约束
pds/             PDS工程描述；数据库、综合和位流由本机PDS生成，不提交
sim/             外部延迟环回模型、自检激励、串口集成及报告验证
scripts/         实际pango-mcp JSON-RPC客户端、可重复构建/仿真参数
docs/            原方案副本、引脚核查、适用开发规范、实物记录模板
reports/         已脱敏的验收摘要和生产参数波形
```


```powershell
./scripts/run_pds.ps1
./sim/run_sim.ps1 -Test all
```

工程源码和FDC使用相对路径。克隆后从 PDS GUI 打开工程重新构建；若运行 MCP 脚本，在本机设置上述两个环境变量和 PDS/ModelSim 许可证配置。

开发规范和适用范围见 [docs/development_rules.md](docs/development_rules.md)，38路引脚依据及核查见 [docs/pinmap_verification.md](docs/pinmap_verification.md)。附加KEY1复位为落实规范所需，J8原方案映射保持一致。

# AFE 数据接收故障排查步骤

## 当前问题
- 重新生成 bitstream 后，`shift_hi` 和 `shift_lo` 仍然没有数据
- 说明 LVDS 数据链路的某个环节有问题

## 逐级排查清单

### 级别 1: 基础使能信号（必须先检查）

#### 1.1 检查 PLL 锁定
**ILA 信号**: `pll_locked`

**期望**: 1

**如果为 0**:
- PLL 未锁定，所有时钟都不可用
- 检查输入时钟（sys_clk）
- 检查 PLL 配置

#### 1.2 检查 SPI 配置完成
**ILA 信号**: `spi_cfg_done`

**期望**: 1（SPI 配置完成后变为 1）

**如果为 0**:
```
原因: AFE 芯片未配置，不会输出数据
解决:
1. 检查 SPI 引脚连接（SDI, SCK, CS）
2. 检查 AFE 电源（AVDD, DVDD）
3. 用逻辑分析仪查看 SPI 波形
4. 检查 spi_sdo_p0/p1 的回读数据
```

**如果一直为 1（从未变化）**:
- 可能是 ILA 触发时机问题
- 尝试在 PLL 锁定后立即触发捕获

---

### 级别 2: Gate Driver 信号

#### 2.1 检查帧起始信号
**ILA 信号**: `frame_start_100m` (probe7[12])

**期望**: 周期性出现脉冲（每帧一次，约 20 fps = 50ms 间隔）

**如果一直为 0**:
```
原因: Gate Driver 未启动
解决:
1. 检查 50MHz 时钟（clk_50m）
2. 检查 nt39565d_gate_ctrl 模块的使能条件
3. 检查 busy 信号状态
```

#### 2.2 检查行起始信号
**ILA 信号**: `line_start_pulse` (probe7[13])

**期望**: 连续脉冲（每行一次，541 次/帧）

**如果一直为 0**:
```
原因: Gate Driver 未产生行扫描信号
解决:
1. 确认 frame_start_100m 已有信号
2. 检查跨时钟域同步（50MHz → 100MHz）
3. 检查 gate_ctrl 状态机
```

---

### 级别 3: AFE 控制信号

#### 3.1 检查 AFE 控制器状态
**ILA 信号**: `ctrl_state` (probe7[11:8])

**期望**: 状态循环变化
```
S_IDLE        = 2  (等待 frame_start)
S_SYNC_SETUP  = 3  (SYNC 建立)
S_ACLK        = 4  (发送 ACLK)
S_SYNC_HOLD   = 5  (SYNC 保持)
S_LINE_GAP    = 6  (行间隔)
```

**状态机卡住的可能情况**:

| 卡住状态 | 原因 | 解决方法 |
|---------|------|---------|
| 一直为 2 (IDLE) | 未收到 frame_start | 检查级别 2 的 Gate Driver |
| 卡在其他状态 | 状态机逻辑错误 | 检查 ad71143_ctrl.v 代码 |

#### 3.2 检查 SYNC 信号
**ILA 信号**: `sync_int` (probe7[15])

**期望**: 周期性变化（每行从 1→0→1）
```
正常波形：
sync_int: ──┐  ┌──┐  ┌──┐  ┌──
             └──┘  └──┘  └──┘
            (每行一次，低有效)
```

**如果一直为 1**:
- SYNC 从未拉低
- AFE 不会开始采样
- 检查 ctrl_state 是否运行

#### 3.3 检查 ACLK 信号
**ILA 信号**: `aclk_int` (通过输出引脚测量，或添加到 ILA)

**期望**: 每行发送 8 个时钟脉冲

**如果没有 ACLK**:
- AFE 不会采样数据
- 检查 ad71143_ctrl 状态机

---

### 级别 4: LVDS 物理层

#### 4.1 检查 LVDS 原始输入
**ILA 信号**: 
- `dbg_p1_dout_a_raw` (probe7[1]) - Panel 1 LVDS A
- Panel 0 的对应信号

**期望**: 应该看到数据变化（0 和 1 交替）

**可能情况**:

| 观察到的现象 | 原因 | 解决方法 |
|------------|------|---------|
| 一直为 0 | LVDS 无信号/断线 | 检查线缆连接、AFE 输出使能 |
| 一直为 1 | LVDS 极性接反 | 交换 P/N 引脚 |
| 有变化 | LVDS 物理层正常 | 继续检查下一级 |

#### 4.2 检查 DCLK 输出
**ILA 信号**: 通过示波器测量 `dclk_p_A0/A1` 引脚

**期望**: 应该有时钟输出（反馈给 AFE）

**如果没有 DCLK**:
- AFE 无法同步数据
- 检查 ODDR 配置

---

### 级别 5: 数据接收器

#### 5.1 检查 burst 使能
**ILA 信号**: `dbg_p1_burst_en` (probe5[0] 或类似)

**期望**: 周期性脉冲（每个 burst 一次）

**如果一直为 0**:
- 数据接收状态机未运行
- 检查 sync_in 输入

#### 5.2 检查 Header 校验
**ILA 信号**: `header_ok`

**期望**: 在每行开始时为 1

**如果为 0**:
```
原因: 接收到的数据 Header 不是 0x0A
可能:
1. LVDS 数据错误
2. 时序不对
3. AFE 配置错误
```

#### 5.3 检查 merged_valid
**ILA 信号**: `merged_valid` (probe2[255])

**期望**: 周期性脉冲（每个 burst 一次，64 次/行）

**如果一直为 0**:
- 最终数据未生成
- 检查前面所有步骤

---

## 诊断流程图

```
1. pll_locked = 1? 
   NO → 检查输入时钟
   YES ↓

2. spi_cfg_done = 1?
   NO → 检查 SPI 配置和 AFE 电源
   YES ↓

3. frame_start_100m 有脉冲?
   NO → 检查 Gate Driver 和 50MHz 时钟
   YES ↓

4. line_start_pulse 连续脉冲?
   NO → 检查跨时钟域同步
   YES ↓

5. ctrl_state 在循环?
   NO → 检查 AFE 控制器状态机
   YES ↓

6. sync_int 周期性变化?
   NO → 检查 ctrl_state = S_SYNC_SETUP
   YES ↓

7. dbg_p1_dout_a_raw 有数据变化?
   NO → 检查 LVDS 物理连接和 AFE 输出
   YES ↓

8. header_ok = 1?
   NO → 检查 LVDS 时序和 AFE 配置
   YES ↓

9. merged_valid 有脉冲?
   NO → 检查数据接收器状态机
   YES ↓

10. shift_hi/lo 有数据?
    应该有了！

```

---

## ILA 捕获建议

### 捕获方式 1: 全局概览（推荐首先执行）
```
触发条件: 无（自由运行）
捕获深度: 4096 样本
采样率: 100MHz

目的: 查看所有信号的整体状态
重点观察:
- spi_cfg_done
- frame_start_100m
- line_start_pulse
- ctrl_state
- sync_int
- merged_valid
```

### 捕获方式 2: 捕获第一个行起始
```
触发条件: line_start_pulse 上升沿
触发位置: 10%
捕获深度: 8192 样本

目的: 详细查看一行的完整时序
重点观察:
- ctrl_state 状态转换
- sync_int 变化
- LVDS 数据流
- merged_valid 脉冲数量（应该是 64）
```

### 捕获方式 3: 捕获 SPI 配置过程
```
触发条件: spi_cfg_done 上升沿
触发位置: 50%

目的: 查看 SPI 配置完成的时刻
```

---

## 快速诊断命令

### 在 ILA 中添加总线观察
```tcl
# 在 Vivado TCL Console
set_property DISPLAY_NAME ctrl_state [get_hw_probes {hw_ila_1/probe7[11:8]}]
set_property RADIX UNSIGNED [get_hw_probes {hw_ila_1/probe7[11:8]}]
```

### 查看当前值（无需触发）
```tcl
# 刷新当前值
refresh_hw_device [current_hw_device]
get_property INPUT_VALUE [get_hw_probes spi_cfg_done]
get_property INPUT_VALUE [get_hw_probes frame_start_100m]
```

---

## 请现在执行

**第一步**: 打开 ILA，使用"捕获方式 1"抓取一次波形

**第二步**: 检查以下信号并报告结果：
1. `spi_cfg_done` = ?
2. `frame_start_100m` 是否有脉冲？
3. `line_start_pulse` 是否有脉冲？
4. `ctrl_state` 的值是多少？是否变化？
5. `sync_int` 是否变化？
6. `merged_valid` 是否有脉冲？

根据你的报告，我会帮你定位具体问题所在！

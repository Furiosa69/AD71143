# AFE LVDS 数据接收诊断清单

## 问题现象
- `shift_hi` 和 `shift_lo` 没有数据
- 说明 LVDS 数据未接收到

## 诊断步骤

### 1. 检查 SPI 配置状态
**ILA 信号**：`spi_cfg_done`

**期望**：应该为 1

**如果为 0**：
- SPI 配置未完成
- 检查 SPI 时钟和数据线
- 检查 AFE 电源

### 2. 检查 Gate Driver 状态
**ILA 信号**：
- `frame_start_100m`：帧起始信号
- `line_start_pulse`：行起始信号（CDC 后）

**期望**：
- `frame_start_100m` 应该周期性出现（每帧一次）
- `line_start_pulse` 应该连续出现（每行一次，541 次/帧）

**如果没有信号**：
- Gate Driver 未运行
- 检查 50MHz 时钟
- 检查 `busy` 信号

### 3. 检查 AFE 控制信号
**ILA 信号**：
- `sync_int` (probe7[15])：SYNC 信号，应该周期性变化（每行一次）
- `roic_reset_int` (probe7[14])：ROIC 复位信号
- `ctrl_state` (probe7[11:8])：AFE 控制器状态机

**期望**：
- `sync_int` 应该周期性从 1→0→1（每行一次）
- `ctrl_state` 应该在状态之间循环：
  - `S_IDLE = 2`
  - `S_SYNC_SETUP = 3`
  - `S_ACLK = 4`
  - `S_SYNC_HOLD = 5`
  - `S_LINE_GAP = 6`

**如果 `ctrl_state` 一直停在 `S_IDLE`**：
- 没有收到 `frame_start` 信号
- Gate Driver 未启动

### 4. 检查 ACLK 信号
**ILA 信号**：`aclk_int` (通过 ACLK 输出引脚观察)

**期望**：应该周期性发送 8 个时钟脉冲（每行一次）

**如果没有 ACLK**：
- AFE 控制器未运行
- 检查前面的步骤

### 5. 检查 LVDS 物理连接
**ILA 信号**：
- `dbg_p1_dout_a_raw` (probe7[1])：Panel 1 LVDS A 原始输入
- DOUT 引脚电平

**期望**：应该看到数据变化（不是固定 0 或 1）

**如果一直为 0 或 1**：
- LVDS 线缆未连接
- AFE 未输出数据
- 差分对极性接反

### 6. 检查 FIFO 状态
**ILA 信号**：
- `dbg_fifo_full` (probe7[7])：FIFO 满
- `dbg_fifo_empty` (probe7[6])：FIFO 空

**期望**：
- 正常情况下都应该为 0
- 如果 `full=1`：数据发送速度跟不上接收速度（之前的问题）
- 如果 `empty=1`：没有数据进入 FIFO

## 常见问题排查

### 问题 1: SPI 配置未完成
**症状**：`spi_cfg_done = 0`

**解决方案**：
1. 检查 SPI 引脚连接（SDI, SCK, CS）
2. 检查 AFE 电源（AVDD, DVDD）
3. 查看 SPI 波形，确认配置数据发送成功
4. 检查 `spi_sdo_p0` 和 `spi_sdo_p1` 的回读数据

### 问题 2: Gate Driver 未启动
**症状**：`frame_start_100m = 0`, `line_start_pulse = 0`

**解决方案**：
1. 检查 50MHz 时钟是否运行
2. 检查 Gate Driver 使能信号
3. 检查 `busy` 信号（应该周期性变化）
4. 确认 Gate Driver 时序参数正确

### 问题 3: AFE 控制器卡在 IDLE
**症状**：`ctrl_state = 2` (S_IDLE) 不变

**解决方案**：
1. 确认 `frame_start_100m` 信号到达 `ad71143_ctrl` 模块
2. 检查跨时钟域同步是否工作（50MHz → 100MHz）
3. 检查复位信号 `rst_n_100m`

### 问题 4: LVDS 无数据
**症状**：`dbg_p1_dout_a_raw = 0` (一直为 0 或 1)

**解决方案**：
1. 检查 LVDS 线缆连接
2. 确认 AFE 输出使能（通过 SPI 配置）
3. 检查 DCLK 是否输出到 AFE
4. 用示波器测量 DOUT_P 和 DOUT_N 差分电压

## ILA 触发建议

### 触发条件 1: 捕获 SPI 配置完成时刻
```
触发信号: spi_cfg_done
触发条件: 上升沿
```

### 触发条件 2: 捕获第一个 line_start
```
触发信号: line_start_pulse
触发条件: 上升沿
位置: 10%（捕获触发前 10% 和触发后 90% 的数据）
```

### 触发条件 3: 捕获 LVDS 数据到达
```
触发信号: merged_valid (probe2[255])
触发条件: 上升沿
```

## 测试步骤

### 步骤 1: 验证基础信号
1. 打开 ILA
2. 运行捕获
3. 检查：
   - `spi_cfg_done` 是否为 1
   - `frame_start_100m` 是否周期性出现
   - `sync_int` 是否变化

### 步骤 2: 验证 AFE 控制时序
1. 设置触发：`line_start_pulse` 上升沿
2. 运行捕获
3. 检查：
   - `ctrl_state` 状态转换：2→3→4→5→6→3...
   - `sync_int`：应该在状态 3,4,5 时为低
   - `aclk_int`：应该在状态 4 时有 8 个脉冲

### 步骤 3: 验证 LVDS 数据
1. 设置触发：`merged_valid` 上升沿
2. 运行捕获
3. 检查：
   - `shift_hi` 和 `shift_lo` 应该有变化的数据
   - `merged_burst` 应该有有效数据
   - `merged_burst_index` 应该从 0 递增到 63

## 预期信号时序图

```
frame_start_100m: ┌─┐________________________┌─┐
line_start_pulse: __┌┐__┌┐__┌┐...(541次)___┌┐
sync_int:         ──┐└──┘└──┘└...───────────┐└
aclk_int:         ___┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐_______┌┐
                     (8个ACLK脉冲)
merged_valid:     ____┌┐__┌┐__┌┐...(64次)___┌┐
```

## 下一步

1. **打开 ILA，捕获当前状态**
2. **检查上述关键信号**
3. **根据发现的问题，选择对应的解决方案**
4. **如果所有信号都正常但还是没有数据，检查 LVDS 物理连接**

## 常用 ILA 命令（Vivado TCL Console）

```tcl
# 连接硬件
open_hw_manager
connect_hw_server
open_hw_target

# 刷新 ILA
refresh_hw_device [current_hw_device]

# 运行 ILA
run_hw_ila [get_hw_ilas]

# 等待触发
wait_on_hw_ila [get_hw_ilas]

# 显示波形
display_hw_ila_data [upload_hw_ila_data [get_hw_ilas]]
```

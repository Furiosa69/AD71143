# FIFO空诊断指南 - AFE数据稀疏问题

## 现象
- `fifo_empty` 大部分时间为1
- 偶尔变为0后立即又空了
- 说明：**AFE产生的数据非常少**（不是FIFO溢出）

## 根本原因

FIFO大部分时间为空 → AFE数据产生速度远低于预期

**预期**: 每帧35,165个burst (541行 × 65 bursts/行)
**实际**: 可能只有几十到几百个burst

---

## 🔍 逐步诊断

### Step 1: 检查merged_valid频率

**在ILA中查看 probe0[0] (merged_valid)**:

#### 问题1: 是否有脉冲？
- ✅ 有偶尔的脉冲 → AFE在工作但数据很少
- ❌ 完全没脉冲 → AFE完全不工作

#### 问题2: 每行产生多少个脉冲？

**设置ILA触发**:
```
Trigger: ctrl_line_start == 1 (probe0[4])
Capture window: 足够长以覆盖整行
```

**观察**:
- 从一个 `ctrl_line_start` 到下一个 `ctrl_line_start` 之间
- 数一下有多少个 `merged_valid` 脉冲

**判断**:
- 预期: 65个脉冲/行
- 如果只有 1-5个 → **严重丢失数据**
- 如果 0个 → **完全没数据**

---

### Step 2: 检查Panel 1数据接收状态

**在ILA中观察**:

#### 信号1: `dbg_p1_merged_valid` (probe0[1])
- 应该和 `merged_valid` 同步（因为只用Panel 1）
- 如果一直为0 → Panel 1没产生数据

#### 信号2: `dbg_p1_header_ok` (probe7[2])  
- 每行开始时应该为1（识别到0x0A header）
- 如果一直为0 → **Header识别失败！**

#### 信号3: `dbg_p1_line_done` (probe7[1])
- 每行结束时应该有脉冲
- 如果无脉冲 → 行未完成

#### 信号4: `dbg_p1_state` (probe3[2:0])
- 状态机应该正常跳转
- S_IDLE(0) → S_WAIT(1) → S_ACT(2) → S_MUTE(3) → ...

---

### Step 3: 检查LVDS数据输入

**关键信号: `dbg_p1_dout_a_raw` (probe7[5])**

这是LVDS差分接收器的原始输出，应该是**高频串行数据流**。

#### 正常情况:
```
dout_a_raw: 01011001010110100101... (快速跳变)
```

#### 异常情况A: 一直为0
```
dout_a_raw: 0000000000000000000...
```
**原因**: 
- LVDS差分对接线错误
- AD71143没有输出数据
- FPGA引脚配置错误

#### 异常情况B: 一直为1
```
dout_a_raw: 1111111111111111111...
```
**原因**:
- LVDS差分对接反了（P/N互换）
- AD71143输出idle状态

#### 异常情况C: 偶尔跳变
```
dout_a_raw: 0000001110000000011...
```
**原因**:
- 只有少数burst有数据
- AD71143工作不正常

---

### Step 4: 检查ACLK和SYNC时序

**在ILA中观察控制信号时序关系**:

#### 触发设置:
```
Trigger: ctrl_line_start == 1
```

#### 观察时序:
1. `sync_int` → 应该在line_start后立即拉低
2. `aclk_int` (probe7[4]) → 应该产生9个脉冲
3. `aclk_done` (probe0[5]) → ACLK完成后拉高
4. `dbg_p1_burst_en` (probe7[3]) → 应该在ACLK期间为1

**正常时序**:
```
line_start:  _|‾|___________________
sync:        ‾‾|______|‾‾‾‾‾‾‾‾‾‾‾‾
aclk:        ____|‾|_|‾|_|‾|______|  (9个脉冲)
burst_en:    ____|‾‾‾‾‾‾‾‾‾‾‾|_____
aclk_done:   __________|‾|_________
```

**异常情况**: SYNC和ACLK时序不对
- SYNC太晚 → AD71143错过采样窗口
- ACLK脉冲数不对 → CDS时序错误

---

## 🔴 最可能的原因

### **原因1: Header识别失败** (最可能)

**症状**:
- `dbg_p1_header_ok` 一直为0
- `merged_valid` 很少或没有

**根本原因**:
AD71143的第一个burst应该是Header (0x0A)，如果识别不到：
- 状态机不会进入数据接收状态
- 所有后续burst被忽略
- 只有偶尔碰巧误识别才产生数据

**检查**: `dbg_p1_shift_hi` (probe5[7:0])
- 应该在每行开始时 = 0x0A
- 如果不是0x0A → Header错误

**可能原因**:
1. LVDS数据bit序错误（MSB/LSB反了）
2. DCLK相位偏移导致采样错误
3. AD71143没有发送正确的Header

---

### **原因2: SYNC信号延迟太大**

**症状**:
- ACLK正常产生
- 但`merged_valid`很少

**问题**: 
`line_start_pulse`是从50MHz域CDC到100MHz域的，可能有2-3个时钟周期延迟。

**位置**: `top.v` 第777行
```verilog
.sync_in(line_start_pulse),  // CDC延迟可能太大
```

**验证方法**:
在ILA中测量`line_start_pulse`和`aclk_int`的时间差，应该 < 200ns。

---

### **原因3: AD71143 LVDS输出禁用**

**检查SPI配置**:

**当前配置** (`top.v` 528-533):
```verilog
Reg0 = 10'h003  // PWR=Normal(000), IFS=3
Reg1 = 10'h0B0  // DM=1(单LVDS), LPF=01, CDS2_RESETEN=1
Reg2 = 10'h027  // RNDOMIZE=1, DOUTMODE=1, ECHOCLK=1, Pipeline=1
```

**可能问题**:
- Reg0的PWR位可能使芯片进入低功耗模式
- Reg2的某些位配置错误

**测试方法**: 启用LFSR测试模式
```verilog
Reg11 = 10'h040  // LFSR_EN=1
```

如果启用LFSR后`merged_valid`变多 → **ADC采样有问题**
如果启用LFSR后`merged_valid`仍然很少 → **LVDS通路有问题**

---

## 🛠️ 修复方案

### **修复1: 降低DCLK频率测试**

**位置**: `ad71143_data_rx.v` 第63行

**当前**: 
```verilog
localparam integer ACTIVE_DCLK = 64;    // 每lane 64bit
```

这意味着DCLK = 100MHz（和clk_sys同频）。

**问题**: 100MHz可能对LVDS设置时间要求太高。

**测试**: 暂时降低到50MHz
- 修改顶层，将`clk_50m`传入`ad71143_data_rx`模块
- 或者在100MHz时钟域内2分频

---

### **修复2: 直接使用ctrl_line_start作为sync_in**

**位置**: `top.v` 第777行

**当前**:
```verilog
.sync_in(line_start_pulse),  // 50MHz CDC过来
```

**改为**:
```verilog
.sync_in(ctrl_line_start),  // 直接用100MHz域的信号
```

**注意**: 这样会跳过CDC，需要确保不违反时序。

---

### **修复3: 检查LVDS差分对极性**

**硬件检查**:
- DOUT_P 和 DOUT_N 是否接对
- 如果接反，会导致全1或全0

**软件测试**: 反转输入
```verilog
// ad71143_data_rx.v IBUFDS后
assign dout_a_i_inv = ~dout_a_i;  // 反转
// 然后使用dout_a_i_inv进行采样
```

---

### **修复4: 增加PRE_DELAY**

**位置**: `ad71143_data_rx.v` 第64行

**当前**:
```verilog
localparam integer PRE_DELAY = 1;  // 跳过1个周期
```

**改为**:
```verilog
localparam integer PRE_DELAY = 2;  // 跳过2个周期
```

给AD71143更多时间稳定输出。

---

## 📊 快速诊断表

| ILA观察 | 判断 | 问题定位 |
|---------|------|----------|
| `dout_a_raw`一直为0 | LVDS无输入 | 硬件连接或AD71143不工作 |
| `dout_a_raw`快速跳变，但`merged_valid`很少 | LVDS有数据但识别失败 | Header识别或状态机问题 |
| `header_ok`一直为0 | Header识别失败 | LVDS bit序错误或相位错误 |
| `shift_hi` != 0x0A | Header数据错误 | AD71143输出错误或采样错误 |
| `aclk`脉冲数 != 9 | 控制时序错误 | ad71143_ctrl配置错误 |
| `merged_valid`完全无脉冲 | AFE完全不工作 | SPI配置失败或复位问题 |

---

## 🎯 立即执行的测试

### 测试1: 查看Header字节

**在ILA中**:
1. 触发: `ctrl_line_start == 1`
2. 观察: `dbg_p1_shift_hi` (probe5[7:0])
3. 在每行开始后约650ns（65个DCLK周期后）
4. 该值应该 = 0x0A

**如果不是0x0A**:
- 记录实际值是多少
- 如果是0x50 (0x0A的bit反转) → LVDS bit序反了
- 如果是0x00 → 没采到数据
- 如果是随机值 → 相位错误

### 测试2: 强制启用LFSR

**修改 `top.v` 第539行**:
```verilog
(cfg_reg_idx == 4'd11) ? 10'h040 :  // LFSR_EN=1
```

**重新烧录后观察**:
- 如果`merged_valid`变多 → ADC采样问题
- 如果`merged_valid`仍然很少 → LVDS通路问题

---

## 下一步

1. **在ILA中捕获波形**，查看上述关键信号
2. **报告以下信息**:
   - `dbg_p1_shift_hi`的值（应该是0x0A）
   - `dbg_p1_header_ok`是否为1
   - `dout_a_raw`是否快速跳变
   - 每行有多少个`merged_valid`脉冲
3. **根据结果选择修复方案**

需要我根据您的ILA波形进一步分析吗？

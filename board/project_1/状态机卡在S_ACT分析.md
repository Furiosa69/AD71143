# 关键发现：state=2但header_ok=0

## 当前状态

```
p1_state = 2         ✓ 状态机在S_ACT
header_ok = 0        ✗ lane_a_shift[63:56] != 0x0A
burst_en = ?         需要确认（应该=1）
```

## 问题分析

### header_ok定义
```verilog
// ad71143_data_rx.v:336
assign header_ok = (lane_a_shift[63:56] == 8'h0A);
```

**header_ok=0 说明**：
- `lane_a_shift[63:56]` 不等于 `0x0A`
- 可能是 `0x00`（没有数据）
- 可能是其他值（数据错误）

## 根本原因排查

### 原因1: DCLK没有输出 ⚠️⚠️⚠️ 最可能

**DCLK生成逻辑**（line 342-354）:
```verilog
ODDR #(
    .DDR_CLK_EDGE("OPPOSITE_EDGE"),
    ...
) oddr_dclk (
    .Q  (dclk_pre),
    .C  (clk_sys),
    .CE (burst_en),      ← 关键：被burst_en门控
    .D1 (1'b1),
    .D2 (1'b0),
    ...
);
```

**问题**：
- DCLK由`burst_en`门控
- `burst_en`来自状态机（line 331）：
  ```verilog
  assign burst_en = burst_en_reg;
  
  always @(posedge clk_sys) begin
      burst_en_reg <= (state_next == S_ACT);  // 提前一拍
  end
  ```

**如果burst_en=0**：
- DCLK不会输出
- AD71143不会输出数据
- lane_a_shift永远是0

### 原因2: LVDS接收无数据

**可能原因**：
1. **DOUT差分对接反** - 数据全0或全1
2. **AD71143未配置** - SPI配置失败
3. **SYNC/ACLK时序不对** - AD71143未启动输出
4. **物理连接问题** - 线缆、焊接

### 原因3: 采样时序错误

**DCLK域采样逻辑**（line 278-319）:
```verilog
always @(posedge dclko_i) begin
    if (cap_active_dclko) begin
        if (pre_delay_cnt > 0) begin
            pre_delay_cnt <= pre_delay_cnt - 1'b1;
        end else begin
            lane_a_shift <= {lane_a_shift[62:0], dout_a_mid};  // 移位
        end
    end
end
```

**检查点**：
- `cap_active_dclko` 是否激活？
- `dout_a_mid` / `dout_b_mid` 是否有数据翻转？

## 诊断步骤

### 第1步：确认ILA中的关键信号值

**必须检查的信号**：
```
1. burst_en          - 是否 = 1？（如果=0，DCLK不输出）
2. shift_hi[7:0]     - lane_a_shift[63:56]的实际值（应该是0x0A）
3. shift_lo[7:0]     - lane_a_shift[7:0]的值
4. burst_cnt[6:0]    - burst计数器（应该在0~34循环）
5. cap_active_dclko  - DCLK域采样是否激活（需要添加输出）
```

### 第2步：检查burst_en信号

**如果burst_en=0**：
- 问题在状态机逻辑
- 检查 `state_next == S_ACT` 的条件

**如果burst_en=1但shift_hi=0x00**：
- LVDS接收无数据
- 检查硬件连接

### 第3步：添加调试输出

修改 `ad71143_data_rx.v`，将内部信号引出：

```verilog
// 在模块端口添加
output wire        dbg_cap_active,
output wire [6:0]  dbg_burst_cnt,
output wire        dbg_burst_en,

// 在模块内部添加
assign dbg_cap_active = cap_active_dclko;
assign dbg_burst_cnt  = burst_cnt;
assign dbg_burst_en   = burst_en;
```

然后在 `top.v` 连接到ILA。

## 快速验证方案

### 方案A：检查DCLK物理输出

用示波器测量DCLK引脚：
- **应该看到**: 100MHz方波（在burst期间）
- **如果没有**: burst_en=0，状态机问题
- **如果有但无数据**: LVDS接收问题

### 方案B：强制DCLK常开（调试用）

临时修改ODDR使能：
```verilog
// ad71143_data_rx.v:349
.CE (1'b1),  // 临时：强制DCLK常开，不受burst_en控制
```

**目的**: 验证AD71143是否响应DCLK

### 方案C：检查SPI配置

添加ILA探针确认：
```
1. spi_cfg_done      - SPI配置完成标志
2. cfg_state[1:0]    - SPI配置FSM状态
3. cfg_reg_idx[3:0]  - 当前配置的寄存器索引
```

## 最可能的根本原因

根据你的现象（state=2卡住，header_ok=0），我怀疑：

### **burst_en一直为0** ⚠️⚠️⚠️

原因：
```verilog
// ad71143_data_rx.v:328
burst_en_reg <= (state_next == S_ACT);
```

如果状态机在`S_ACT`停留但`capture_done_pulse_sys`不产生，会导致：
1. `state_next`一直等于`S_ACT`
2. `burst_en_reg = 1`（理论上）
3. 但如果有其他逻辑问题，可能`burst_en=0`

### 验证方法
在ILA中查看 `burst_en` 或 `dbg_p1_burst_en` 的值。

## 下一步行动

**请立即检查ILA中的以下信号值**：
```
1. burst_en (或 dbg_p1_burst_en) = ?
2. shift_hi[7:0] = ?
3. burst_cnt[6:0] = ?
```

根据这3个值，我可以准确定位问题：
- `burst_en=0` → 状态机逻辑问题
- `burst_en=1, shift_hi=0x00` → LVDS无数据（硬件/配置问题）
- `burst_en=1, shift_hi=其他值` → Header不对（可能是时序/配置问题）

---
**生成时间**: 2026-07-27  
**当前假设**: burst_en=0导致DCLK不输出，AD71143无法响应

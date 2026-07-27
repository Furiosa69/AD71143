# ILA调试分析：状态机卡住问题

## 观察到的现象

通过ILA观察到：
```
header_ok = 1        ✓ (lane_a_shift[63:56] == 0x0A, Header正确)
burst_en = 0         ✗ (应该在S_ACT时为1)
merged_valid = 0     ✗ (没有数据输出)
```

## 问题分析

### ad71143_data_rx.v 状态机流程
```
S_IDLE → S_WAIT → S_ACT → S_MUTE → S_ACT → ... → S_DONE
         ↑        ↑
      sync_fall  aclk_done
```

### 转换条件（line 136-137）
```verilog
S_IDLE: if (sync_fall)   state_next = S_WAIT;
S_WAIT: if (aclk_done)   state_next = S_ACT;
```

## 根本原因

**burst_en = 0 说明状态机没有进入S_ACT**，有3种可能：

### 可能1: aclk_done信号没有产生 ⚠️ 最可能
```verilog
// ad71143_data_rx.v:137
S_WAIT: if (aclk_done) state_next = S_ACT;
```

**检查点**:
- `aclk_done` 是 `ad71143_ctrl` 模块产生的单周期脉冲
- 必须在 ACLK 序列（9个脉冲）完成后产生
- 如果 aclk_done 时序不对，状态机会卡在 S_WAIT

### 可能2: sync_in信号问题
```verilog
// ad71143_data_rx.v:136
S_IDLE: if (sync_fall) state_next = S_WAIT;
```

**检查点**:
- `sync_in` 应该是 `line_start_pulse`（从100MHz CDC到100MHz）
- 但实际代码中：
  ```verilog
  // top.v:756
  .sync_in (line_start_pulse),  // 使用 line_start_pulse
  ```

### 可能3: capture_done_pulse_sys时序问题
```verilog
// ad71143_data_rx.v:138-142
S_ACT: if (capture_done_pulse_sys) begin
         if (burst_cnt == TOTAL_BURSTS - 1)
             state_next = S_DONE;
         else
             state_next = S_MUTE;
       end
```

## 诊断步骤

### 第1步: 检查ILA中的关键信号

需要在ILA中添加/检查以下信号：
```
1. aclk_done         - 是否有脉冲？
2. sync_in           - line_start_pulse是否有效？
3. state[2:0]        - 当前状态（0=IDLE, 1=WAIT, 2=ACT, 3=MUTE, 4=DONE）
4. burst_cnt[6:0]    - burst计数器值
5. cap_active_dclko  - DCLK域采样是否激活？
```

### 第2步: 验证ad71143_ctrl的输出

检查 `ad71143_ctrl` 模块：
```verilog
// top.v:689-709
ad71143_ctrl #(
    .ACLK_PULSES      (9),        // 每行 9 个 ACLK
    .LINE_CYCLES      (6000),     // 60μs @ 100MHz
    .RESET_CYCLES     (1000),     // 10μs
    .INIT_WAIT_CYCLES (10000),    // 100μs
    .FRAME_LINES      (FRAME_LINES)
) u_ad71143_ctrl (
    .clk          (clk_100m),
    .rst_n        (rst_n_100m),
    .frame_start  (frame_start_100m),
    .aclk_done    (aclk_done)      ← 这个信号
);
```

### 第3步: 检查CDC路径

**问题路径**：
```
50MHz gate_clk domain:
  line_start (nt39565d_ctrl) 
    ↓ (toggle CDC)
  line_start_pulse @ gate_clk
    ↓ (toggle CDC to 100MHz)
  line_start_pulse @ clk_100m
    ↓
  sync_in (ad71143_data_rx)
```

**潜在问题**: 多重CDC可能导致时序错位

## 临时调试方案

### 方案A: 添加ILA探针（推荐）

在 `top.v` 的ILA中添加：
```verilog
ila_1 u_ila_datapath (
    .clk    (clk_100m),
    
    // 添加这些探针
    .probe8 (aclk_done),              // [0] ACLK完成信号
    .probe9 (line_start_pulse),       // [0] 行开始脉冲
    .probe10 ({dbg_p1_state}),        // [2:0] Panel1状态机
    .probe11 (dbg_p1_burst_cnt),      // [6:0] burst计数器（需添加输出）
    .probe12 (dbg_p1_cap_active)      // [0] 采样激活标志（需添加输出）
);
```

### 方案B: 强制触发测试（验证硬件）

临时修改 `ad71143_data_rx.v`，绕过状态机：
```verilog
// 在 line 200 附近添加强制触发
S_WAIT: begin
    mute_cnt <= 10'd0;
    // 临时：跳过aclk_done检查，直接进入S_ACT
    cap_start_tgl_sys <= ~cap_start_tgl_sys;
    state_next = S_ACT;  // 强制进入
end
```

**目的**: 验证LVDS接收和数据解析是否正常

### 方案C: 检查line_start_pulse生成

检查 `top.v:388` 的CDC逻辑：
```verilog
assign line_start_pulse = line_start_sync2 ^ line_start_sync3;
```

**可能问题**: 如果 `ctrl_line_start_toggle` 没有翻转，就不会产生脉冲

## 最可能的根本原因

根据你的描述（header_ok=1但无数据），我怀疑：

### **ACLK序列未完成** ⚠️⚠️⚠️

`ad71143_ctrl` 可能卡在ACLK输出阶段，导致：
1. `aclk_done` 没有产生
2. `ad71143_data_rx` 卡在 `S_WAIT` 状态
3. 永远不会进入 `S_ACT`，所以 `burst_en=0`
4. AD71143内部已经输出了Header（所以header_ok=1），但FPGA没有接收

**验证方法**: 
用ILA抓 `aclk` 信号，确认是否有9个脉冲输出

## 下一步行动

1. **立即检查**: ILA中是否有 `aclk_done` 探针？如果有，它是否有脉冲？
2. **添加探针**: 如果没有，添加 `aclk_done` 和 `state[2:0]` 到ILA
3. **报告观察**: 
   - `aclk_done` 是否出现？
   - `state` 停在哪个值？（1=S_WAIT, 2=S_ACT）
   - `aclk` 信号是否有9个脉冲？

---
**生成时间**: 2026-07-27  
**关键假设**: aclk_done未产生导致状态机卡在S_WAIT

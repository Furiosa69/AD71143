# line_start无脉冲问题诊断和修复

## 🔴 关键发现
- `line_done` **有脉冲** → Gate Driver在工作
- `line_start` **无脉冲** → AFE控制器未启动
- 结果：AD71143从未开始采样，所以FIFO一直为空

---

## 🔍 必须确认的ILA信号

请在ILA中查看以下信号并报告状态：

### **关键信号检查表**

| 信号名 | ILA位置 | 预期值 | 实际值? | 说明 |
|--------|---------|--------|---------|------|
| `cfg_all_done` | probe0[7] | 1 | ? | SPI配置完成 |
| `ctrl_init_done` | probe0[6] | 1 | ? | AFE初始化完成 |
| `aclk_done` | probe0[5] | 周期性脉冲 | ? | ACLK序列完成 |
| `ctrl_line_start` | probe0[4] | 周期性脉冲 | ? | AFE行开始 |
| `ctrl_line_done` | probe0[3] | 周期性脉冲 | ✅ | AFE行完成 |
| `merged_valid` | probe0[0] | 周期性脉冲 | ? | 数据有效 |

---

## 📊 诊断场景

### **场景A: cfg_all_done = 0**

**问题**: SPI配置未完成

**原因**:
- CFG_DELAY时间不够（应该1秒）
- SPI通信失败
- spi_done信号卡住

**位置**: `top.v` 第493行
```verilog
localparam CFG_DELAY = 28'd100_000_000;  // 1s @ 100MHz
```

**修复**: 添加ILA探针监测SPI状态
- `cfg_state` (probe1[1:0]) - SPI配置FSM状态
- `cfg_reg_idx` (probe2[3:0]) - 当前配置的寄存器索引

**临时绕过**: 强制认为配置完成
```verilog
// top.v 约616行
assign spi_cfg_done = 1'b1;  // 强制为1，跳过SPI配置等待
```

---

### **场景B: ctrl_init_done = 0**

**问题**: ad71143_ctrl初始化未完成

**原因**:
- RESET_CYCLES或INIT_WAIT_CYCLES配置错误
- rst_n_100m复位信号异常

**当前配置** (`top.v` 713-714行):
```verilog
.RESET_CYCLES     (1000),     // 10μs @ 100MHz
.INIT_WAIT_CYCLES (10000),    // 100μs @ 100MHz
```

**检查**: 上电多久后检查？
- 应该在上电110μs后 `ctrl_init_done = 1`

**修复**: 如果时间足够但仍为0，可能是复位逻辑问题

---

### **场景C: cfg_all_done=1, ctrl_init_done=1, 但ctrl_line_start=0**

**问题**: ad71143_ctrl未收到frame_start触发

**数据流**:
```
Top FSM (50MHz) 产生 frame_start
    ↓ CDC
frame_start_100m (100MHz)
    ↓ 输入
ad71143_ctrl
    ↓ 输出
ctrl_line_start (每行一次脉冲)
```

**可能原因**:
1. Top FSM卡在某个状态
2. CDC丢失frame_start信号
3. cfg_done_synced延迟太大

**检查Top FSM状态** (`top.v` 630-703行):
```
TOP_POWERUP → TOP_WAIT_INIT → TOP_WAIT_CFG → TOP_IDLE → TOP_START
```

---

## 🛠️ 快速修复方案

### **修复1: 强制启动AFE（最快）**

**目的**: 绕过Top FSM，直接给ad71143_ctrl一个持续的frame_start

**修改 `top.v` 第719行**:

```verilog
// 方法1: 使用一个简单的周期信号
reg [23:0] force_frame_cnt;
reg force_frame_start;

always @(posedge clk_100m or negedge rst_n_100m) begin
    if (!rst_n_100m) begin
        force_frame_cnt <= 24'd0;
        force_frame_start <= 1'b0;
    end else begin
        force_frame_start <= 1'b0;
        if (force_frame_cnt >= 24'd5_000_000) begin  // 50ms @ 100MHz = 20fps
            force_frame_cnt <= 24'd0;
            force_frame_start <= 1'b1;
        end else begin
            force_frame_cnt <= force_frame_cnt + 24'd1;
        end
    end
end

// 修改ad71143_ctrl的frame_start输入
ad71143_ctrl u_ad71143_ctrl (
    .frame_start  (force_frame_start),  // 改为使用强制启动信号
    // .frame_start  (frame_start_100m),  // 原来的
    ...
);
```

**或者更简单的方法2: 直接用init_done**:

```verilog
ad71143_ctrl u_ad71143_ctrl (
    .frame_start  (ctrl_init_done & cfg_all_done),  // 初始化完成就一直启动
    ...
);
```

---

### **修复2: 检查CDC逻辑**

**位置**: `top.v` 412-437行

```verilog
// CDC: frame_start (50MHz → 100MHz)
always @(posedge gate_clk or negedge rst_n_50m) begin
    if (!rst_n_50m)
        frame_start_toggle_50m <= 1'b0;
    else if (frame_start)
        frame_start_toggle_50m <= ~frame_start_toggle_50m;
end

reg frame_start_sync1, frame_start_sync2, frame_start_sync3;

always @(posedge clk_100m or negedge rst_n_100m) begin
    if (!rst_n_100m) begin
        frame_start_sync1 <= 1'b0;
        frame_start_sync2 <= 1'b0;
        frame_start_sync3 <= 1'b0;
    end else begin
        frame_start_sync1 <= frame_start_toggle_50m;
        frame_start_sync2 <= frame_start_sync1;
        frame_start_sync3 <= frame_start_sync2;
    end
end

assign frame_start_100m = frame_start_sync2 ^ frame_start_sync3;
```

**问题检查**:
- `frame_start`（50MHz域）是否产生？
- Toggle机制是否工作正常？

---

### **修复3: 添加ILA探针监测Top FSM**

如果ILA还有空余探针，添加：

```verilog
// top.v 增加调试信号输出
output wire [2:0] dbg_top_state;
assign dbg_top_state = top_state;

// 在ILA中添加
.probe10(top_state)  // 观察Top FSM状态
```

**状态含义**:
- 0 = TOP_POWERUP
- 1 = TOP_WAIT_INIT (等待ctrl_init_done)
- 2 = TOP_WAIT_CFG (等待cfg_done_synced)
- 3 = TOP_IDLE
- 4 = TOP_START (应该在这里产生frame_start)
- 5 = TOP_WAIT_FRAME
- 6 = TOP_FRAME_GAP

---

## 🧪 测试步骤

### **测试1: 检查关键信号状态**

捕获ILA波形并报告：
```
cfg_all_done     = ?
ctrl_init_done   = ?
aclk_done        = ?
ctrl_line_start  = ?
```

### **测试2: 使用修复1（强制启动）**

1. 添加`force_frame_start`逻辑
2. 修改ad71143_ctrl的frame_start输入
3. 重新编译烧录
4. 观察`ctrl_line_start`是否产生脉冲

**预期结果**:
- `ctrl_line_start` 开始有周期性脉冲
- `aclk_done` 开始有周期性脉冲
- `merged_valid` 开始有脉冲（如果LVDS正常）

### **测试3: 如果修复1有效**

说明问题在Top FSM或CDC，需要进一步调试：
- 添加ILA探针看Top FSM状态
- 检查CDC逻辑

### **测试4: 如果修复1仍无效**

说明ad71143_ctrl内部有问题：
- 检查`ctrl_init_done`是否为1
- 检查ad71143_ctrl状态机逻辑

---

## 📋 完整的修复代码

### **在top.v中添加（约710行之前）**:

```verilog
// =========================================================================
// 强制AFE启动信号生成（临时调试用）
// =========================================================================
reg [23:0] force_frame_cnt;
reg force_frame_start;

always @(posedge clk_100m or negedge rst_n_100m) begin
    if (!rst_n_100m) begin
        force_frame_cnt   <= 24'd0;
        force_frame_start <= 1'b0;
    end else begin
        force_frame_start <= 1'b0;
        
        // 等待初始化和配置完成
        if (ctrl_init_done && spi_cfg_done) begin
            if (force_frame_cnt >= 24'd5_000_000) begin  // 50ms = 20fps
                force_frame_cnt   <= 24'd0;
                force_frame_start <= 1'b1;
            end else begin
                force_frame_cnt <= force_frame_cnt + 24'd1;
            end
        end
    end
end
```

### **修改ad71143_ctrl实例化（约719行）**:

```verilog
ad71143_ctrl u_ad71143_ctrl (
    .clk          (clk_100m),
    .rst_n        (rst_n_100m),
    // .frame_start  (frame_start_100m),     // 原来的
    .frame_start  (force_frame_start),       // 修改：使用强制启动
    .roic_reset   (roic_reset_int),
    ...
);
```

---

## 🎯 预期结果

**修复后ILA应该看到**:
```
Time:           0    100μs  1s    1.05s  1.1s   1.15s
ctrl_init_done: 0    1      1     1      1      1
cfg_all_done:   0    0      1     1      1      1
ctrl_line_start:____|‾|__|‾|__|‾|__|‾|__|‾|__  (周期性脉冲)
ctrl_line_done: ____|‾|__|‾|__|‾|__|‾|__|‾|__  (周期性脉冲)
aclk_done:      ____|‾|__|‾|__|‾|__|‾|__|‾|__  (周期性脉冲)
merged_valid:   ____|‾|‾|‾|‾|‾|‾|‾|‾|‾|‾|‾|__  (大量脉冲)
```

---

## ✅ 总结

**立即执行**:
1. 在ILA中确认 `cfg_all_done` 和 `ctrl_init_done` 的值
2. 添加 `force_frame_start` 逻辑
3. 修改 ad71143_ctrl 的 frame_start 输入
4. 重新编译、烧录、测试

**如果成功**:
- `ctrl_line_start` 会有脉冲
- AFE会开始产生数据
- FIFO不再一直为空

然后我们可以进一步调试为什么原来的Top FSM没有工作。

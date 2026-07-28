# AD71143 立即修复指南

## 现象
- 黑屏、偶尔白色噪点
- 对光源无响应

## 根本原因
**LVDS数据采样时钟相位错误** - 这会导致采样到错误的数据或全0

---

## 🔴 关键修复1: LVDS采样相位（必须修复）

**文件**: `board/project_1/project_1.srcs/sources_1/imports/src/ad71143_data_rx.v`

**位置**: 第317行

**当前代码（错误）**:
```verilog
lane_a_shift <= {lane_a_shift[62:0], dout_a_i};
```

**修改为**:
```verilog
lane_a_shift <= {lane_a_shift[62:0], dout_a_mid};
```

**原因**: 
- `dout_a_i`是LVDS输入的组合逻辑，在时钟边沿可能有建立时间违例
- `dout_a_mid`是在`clk_sys`下降沿采样的稳定值（见第98行）
- AD71143 LVDS输出在DCLK上升沿有效，FPGA应该在DCLK下降沿采样以获得最大建立时间

---

## 🔴 关键修复2: Top.v信号名错误（会导致编译失败）

**文件**: `board/project_1/project_1.srcs/sources_1/imports/src/top.v`

### 修复位置1: Line 980-984 (ILA probe0)

**当前代码（错误）**:
```verilog
    .probe0 ({
        cfg_all_done,          // [7] SPI 配置完成
        init_done,             // [6] AD71143 初始化完成  <-- 错误
        aclk_done,             // [5] ACLK 序列完成
        line_start,            // [4] 行开始信号  <-- 错误
        line_done,             // [3] 行完成信号  <-- 错误
        dbg_p0_merged_valid,   // [2] Panel 0 数据有效  <-- 未定义
        dbg_p1_merged_valid,   // [1] Panel 1 数据有效
        merged_valid           // [0] 合并后数据有效
    }),
```

**修改为**:
```verilog
    .probe0 ({
        cfg_all_done,          // [7] SPI 配置完成
        ctrl_init_done,        // [6] AD71143 初始化完成  <-- 修复
        aclk_done,             // [5] ACLK 序列完成
        ctrl_line_start,       // [4] 行开始信号  <-- 修复
        ctrl_line_done,        // [3] 行完成信号  <-- 修复
        1'b0,                  // [2] Panel 0 数据有效 (未使用)  <-- 修复
        dbg_p1_merged_valid,   // [1] Panel 1 数据有效
        merged_valid           // [0] 合并后数据有效
    }),
```

### 修复位置2: Line 999 (ILA probe4)

**当前代码（错误）**:
```verilog
    .probe4 (dbg_p1_burst_index),
```

**修改为**:
```verilog
    .probe4 (merged_burst_index),
```

---

## 🟡 可选修复: 添加上位机调试输出

**文件**: `host_pc/panel2_receiver.py`

**在`parse_packet`函数中添加**（第108行之后）:

```python
def parse_packet(self, data):
    """解析 UDP 数据包"""
    if len(data) < self.PAYLOAD_SIZE:
        print(f"[WARN] 数据包长度不足: {len(data)} < {self.PAYLOAD_SIZE}")
        return None

    # 提取 Payload（最后 32 bytes）
    payload = data[-self.PAYLOAD_SIZE:]
    
    # === 添加调试输出 ===
    # 检查是否全0
    if all(b == 0 for b in payload):
        print("[DEBUG] WARNING: 收到全0数据包!")
        return None
    
    # 打印Panel 1数据（前16字节）
    panel1_hex = payload[0:16].hex()
    print(f"[DEBUG] Panel1 data: {panel1_hex}")
    # === 调试输出结束 ===

    # 提取 Panel 1 数据（高 16 bytes = 128 bits）
    panel1_data = payload[self.PANEL1_START:self.PANEL1_START + self.PANEL_SIZE]
    ...
```

---

## 📋 修复步骤

### Step 1: 修复FPGA代码
1. 打开 `ad71143_data_rx.v`，修改第317行
2. 打开 `top.v`，修改第980-984行和第999行
3. 保存所有文件

### Step 2: 重新编译
1. 在Vivado中点击 "Generate Bitstream"
2. 等待编译完成（约10-30分钟）
3. 烧录新的比特流到FPGA

### Step 3: 测试
1. 运行上位机：`python host_pc/panel2_receiver.py`
2. 查看调试输出：
   - 如果仍然全0 → 检查SPI配置和控制时序
   - 如果有数据但图像错误 → 检查数据格式
   - 如果图像正常 → 修复成功！

### Step 4: 使用ILA调试（如果还是不行）

在Vivado Hardware Manager中查看ILA波形：
1. `cfg_all_done` - 应该在启动1秒后变为1
2. `merged_valid` - 应该周期性产生脉冲（每个burst一次）
3. `merged_burst[127:64]` - 应该有非0数据（Panel 1数据）
4. `dbg_p1_header_ok` - 应该在每行开始时为1

---

## ⚠️ 如果修复后仍然黑屏

检查以下可能性：

### 1. SPI配置未生效
**症状**: ILA显示`cfg_all_done=0`或`merged_burst`全0

**检查**:
- `top.v:493` 的 `CFG_DELAY` 是否足够长（当前1秒）
- SPI时钟频率是否正确（应该是25MHz）

### 2. ACLK时序问题
**症状**: ILA显示`aclk_done=1`但`merged_valid=0`

**检查**:
- `ad71143_ctrl.v` 中ACLK脉冲数（应该是9个）
- SYNC信号时序（应该在ACLK前拉低）

### 3. LVDS接口问题
**症状**: ILA显示`dbg_p1_dout_a_raw`一直是0或1

**可能原因**:
- LVDS差分对接线错误
- FPGA引脚配置错误
- AD71143芯片损坏

### 4. 光源问题
**症状**: 数据有但不随光源变化

**检查**:
- TFT背光是否开启
- 光源是否照到传感器（不是照到TFT）
- AD71143的LFSR测试模式是否禁用（Reg11应该=0x000，当前=0x040需要改）

---

## 🔧 发现了额外问题：LFSR测试模式被启用

**位置**: `top.v:539`

```verilog
(cfg_reg_idx == 4'd11) ? 10'h040 :  // Reg11: LFSR_EN=1 (启用LFSR测试模式)
```

**问题**: LFSR测试模式会产生伪随机数据，而不是真实的ADC数据！

**修改为**:
```verilog
(cfg_reg_idx == 4'd11) ? 10'h000 :  // Reg11: LFSR_EN=0 (禁用测试模式)
```

**这可能就是"不响应光源"的根本原因！**

---

## 总结

**必须修复（编译会失败）**:
1. ✅ top.v 信号名错误

**强烈建议修复（可能导致数据错误）**:
2. 🔴 ad71143_data_rx.v LVDS采样相位
3. 🔴 top.v LFSR测试模式（**最可能导致不响应光源**）

**可选修复（调试用）**:
4. 🟡 panel2_receiver.py 添加调试输出

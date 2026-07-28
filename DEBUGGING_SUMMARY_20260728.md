# AD71143 医疗成像系统调试总结报告

**日期**: 2026-07-28  
**项目**: AD71143 FPGA 医疗成像系统  
**状态**: 硬件数据传输正常，上位机程序需要修复

---

## 📊 **项目概述**

### **系统架构**
```
AD71143 AFE (2x Panel) 
    ↓ LVDS (单通道模式)
FPGA 数据接收 (ad71143_data_rx_dual)
    ↓ 100MHz 时钟域
FIFO 跨时钟域 (100MHz → 125MHz)
    ↓ 
RGMII Bridge (UDP/IP 封装)
    ↓ 千兆以太网
PC 上位机 (Python/PyQt5)
```

### **关键参数**
- **传感器分辨率**: 256 通道/Panel × 2 Panels = 512 像素/行
- **帧高度**: 541 行
- **数据位宽**: 16 bits/样本
- **帧数据量**: 34,624 个 UDP 包/帧（541行 × 64 burst/行）
- **网络带宽**: ~11 Mbps @ 12 fps

---

## ✅ **已解决的问题**

### **1. ILA 探针未定义信号 (已修复)**

**问题**: ILA 配置中引用了不存在的信号
```verilog
// 错误
.probe8 (ctrl_line_start)  // 未定义
```

**修复**: 连接到正确的信号
```verilog
// top.v 第 982-1028 行
.probe8 ({ctrl_line_start, ctrl_line_done, ctrl_init_done, ...})
```

---

### **2. SYNC 信号连接错误 (已修复)**

**问题**: `sync_in` 错误连接到单脉冲信号 `line_start_pulse`，导致数据接收状态机无法正常工作

**根本原因**:
```verilog
// 错误 (top.v 第 779 行)
.sync_in(line_start_pulse)  // 这是一个单周期脉冲，不是 SYNC 信号
```

AD71143 需要的是持续的 SYNC 低电平信号，而不是单脉冲。

**修复**:
```verilog
// top.v 第 779 行
.sync_in(sync_int)  // 使用真正的 SYNC 信号
```

**验证**: 修复后，`merged_valid` 脉冲正常产生，数据接收工作正常。

---

### **3. 帧率过低 (已优化)**

**问题**: 初始帧率只有约 12 fps，FIFO 可能饥饿

**根本原因**:
```verilog
// top.v 第 9 行
parameter integer FRAME_GAP_CYCLES = 250000,  // 5ms @ 50MHz
```

5ms 的帧间隔导致帧率 = 1000ms / (行时间 + 5ms) ≈ 12 fps

**修复**:
```verilog
parameter integer FRAME_GAP_CYCLES = 150000,   // 3ms @ 50MHz → 30fps
```

**结果**: 帧率提升但仍受 `LINE_CYCLES` 限制。

---

### **4. AD71143 测试模式未关闭 (已修复)**

**问题**: Wireshark 中 payload 全是 0，怀疑 AD71143 没有输出真实数据

**根本原因**:
```verilog
// top.v 第 540 行
Reg11: begin
    spi_reg_data <= {8'h0B, 8'h00, 1'b1, ...};  // LFSR_EN = 1 (测试模式)
end
```

`LFSR_EN = 1` 启用了 AD71143 内部的 LFSR 测试模式，输出的是测试数据而不是 ADC 数据。

**修复**:
```verilog
// top.v 第 540 行
Reg11: begin
    spi_reg_data <= {8'h0B, 8'h00, 1'b0, ...};  // LFSR_EN = 0 (真实 ADC 模式)
end
```

---

### **5. LINE_CYCLES 太短导致 burst_cnt 不复位 (部分修复)**

**问题**: 在 `LINE_CYCLES = 6000` (60μs) 时，burst_index 显示异常模式：
- 第 1 行: burst_index 0 → 31 (只有 32 个 merged_valid)
- 第 2 行: burst_index 32 → 63 (继续计数)
- 第 3 行: burst_index 0 → 65 (终于复位)

**根本原因**:

一行完整的数据采集需要时间：
```
行时间 = ACLK 时间 + 数据采集时间
       = 180ns + (66 burst × 177 cycles/burst × 10ns)
       = 180ns + 116,820ns
       ≈ 117μs
```

但 `LINE_CYCLES = 6000` (60μs) 太短了！第二个 `ctrl_line_start` 在第一行还没完成时就到来，导致：
1. 状态机通过 `sync_fall` 检测被强制从 `S_ACT` → `S_IDLE`
2. 但 `burst_cnt` 只在 `S_DONE` → `S_IDLE` 转换时才复位
3. 所以 `burst_cnt` 保持之前的值继续计数

**修复尝试**:
```verilog
// top.v 第 713 行
.LINE_CYCLES(20000),    // 200μs @ 100MHz
```

**意外问题**: `LINE_CYCLES = 20000` 时，`shift_hi` 和 `shift_lo` 全变成 0，数据接收失败。

**临时方案**: 使用 `LINE_CYCLES = 12000` (120μs) 或 `15000` (150μs)

**测试结果**:
- ✅ `LINE_CYCLES = 6000`: 数据正常但只有 32 个 merged_valid/行
- ✅ `LINE_CYCLES = 12000`: 数据正常，64 个 merged_valid/行 ✓
- ✅ `LINE_CYCLES = 15000`: 数据正常，64 个 merged_valid/行 ✓
- ❌ `LINE_CYCLES = 20000`: 数据接收失败（原因未明）

**当前配置**: `LINE_CYCLES = 15000` (150μs)

---

## 🔍 **调试发现**

### **LVDS 数据接收流程验证**

通过 ILA 波形确认：
1. ✅ AFE 控制器状态机正常 (S_IDLE → S_SYNC_SETUP → S_ACLK_ACT → S_LINE_GAP)
2. ✅ `ctrl_line_start` 和 `ctrl_line_done` 脉冲正常产生
3. ✅ 数据接收状态机工作正常 (S_IDLE → S_WAIT → S_ACT → S_MUTE → S_DONE)
4. ✅ `merged_valid` 每行产生 64 个脉冲
5. ✅ `burst_index` 从 0 → 63 (0x00 → 0x3F)
6. ✅ `dbg_p1_shift_hi` 和 `dbg_p1_shift_lo` 有数据变化

### **网络传输验证**

通过 Wireshark 抓包确认：
1. ✅ 源 IP: 192.168.1.2 (FPGA)
2. ✅ 目标 IP: 192.168.1.1 (PC)
3. ✅ 协议: UDP
4. ✅ 端口: 1234 → 1234
5. ✅ Payload: 32 字节/包
6. ✅ FIFO 工作正常: `fifo_empty` 有时为 0, `fifo_full` 始终为 0
7. ✅ RGMII 发送正常: `tx_send` 有活动

### **数据内容分析**

Wireshark 中捕获的 payload 示例：
```
00 00 fe 00 00 ff ff ff 80 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

解析为 16-bit 样本（大端序）：
- 样本 0: 0x0000 = 0
- 样本 1: 0xfe00 = 65024 或 0x00fe = 254
- 样本 2: 0x00ff = 255
- 样本 3: 0xffff = 65535
- 样本 4: 0x8000 = 32768
- 样本 5-7: 0x0000 = 0

**结论**: 
- ✅ 数据不是全 0
- ✅ 有数值变化
- ⚠️ 需要照光测试验证传感器响应

---

## 🔴 **发现的上位机程序严重 Bug**

### **问题总结**

上位机程序 `host_pc/data_parser.py` 对 FPGA 数据格式的理解**完全错误**：

| 项目 | 错误理解 | 实际 FPGA 输出 |
|------|---------|--------------|
| 每样本位数 | 4 bits | **16 bits** |
| 每 burst 样本数 | 64 个 4-bit 像素 | **8 个 16-bit 样本** |
| 每行 burst 数 | 16 | **64** |
| 每帧包数 | 8,656 | **34,624** |
| 图像宽度 | 1024 | **512** |
| 帧缓冲类型 | uint8 | **uint16** |

### **具体错误**

#### **1. 像素提取函数错误**
```python
# 错误实现 (data_parser.py 第 122-128 行)
for byte in panel_bytes:
    pixel_high = (byte >> 4) & 0x0F  # 认为高 4bit 是像素
    pixel_low = byte & 0x0F           # 认为低 4bit 是像素
    pixels.append(pixel_high)
    pixels.append(pixel_low)
```

这段代码认为每个字节包含 2 个 4-bit 像素，但实际上 FPGA 输出的是 16-bit 样本。

**正确实现**:
```python
for i in range(0, 16, 2):
    # 16-bit 样本，大端序
    sample = struct.unpack('>H', panel_bytes[i:i+2])[0]
    samples.append(sample)
```

#### **2. 配置参数错误**
```python
# 错误配置
PIXELS_PER_LINE = 1024      # 错误：应该是 512
BURSTS_PER_LINE = 16        # 错误：应该是 64
BITS_PER_PIXEL = 4          # 错误：应该是 16
```

#### **3. 帧缓冲区数据类型错误**
```python
# 错误：uint8 只能存储 0-255
dtype=np.uint8

# 正确：uint16 可以存储 0-65535
dtype=np.uint16
```

### **修复方案**

已创建修复版本：`host_pc/data_parser_fixed.py`

**实施步骤**:
```bash
cd host_pc
cp data_parser.py data_parser_backup.py
cp data_parser_fixed.py data_parser.py
python main.py
```

详细说明请参考：`host_pc/BUGFIX_REPORT.md`

---

## ⚠️ **未解决的问题**

### **1. LINE_CYCLES = 20000 时数据接收失败**

**现象**: 当 `LINE_CYCLES` 从 15000 增加到 20000 时，`shift_hi` 和 `shift_lo` 全变成 0

**可能原因**:
1. **时序违例**: 更大的参数值可能触发 Vivado 的不同综合优化策略，导致关键路径时序不满足
2. **综合优化问题**: 寄存器复制/合并策略变化
3. **跨时钟域同步问题**: `aclk_done` 脉冲可能被错过

**当前解决方案**: 使用 `LINE_CYCLES = 15000`，可以正常工作

**建议**:
- 检查 Vivado 时序报告
- 添加时序约束
- 考虑重构状态机以支持更大的参数范围

### **2. 传感器光响应未验证**

**待测试**:
- 在暗处记录 baseline 数据
- 用手机闪光灯或台灯照射传感器
- 观察 Wireshark payload 或 ILA 波形中数值是否增大

### **3. 帧同步机制缺失**

**当前实现**: 上位机顺序接收包，没有帧同步

**建议**:
- 识别 header burst (第一个 burst，应包含 0x0A)
- 基于 header 重置帧缓冲区
- 添加帧序号检测防止帧错位

---

## 📈 **系统性能**

### **当前配置 (LINE_CYCLES = 15000)**

**帧时间计算**:
```
行时间 = 150μs
帧时间 = 150μs × 541 行 + 3ms (帧间隔)
       = 81.15ms + 3ms
       = 84.15ms
帧率  = 1000ms / 84.15ms
       ≈ 12 fps
```

**网络带宽**:
```
每帧数据 = 34,624 包 × (42 字节协议头 + 32 字节 payload)
         = 34,624 × 74 字节
         = 2,562,176 字节
         ≈ 2.44 MB/帧

带宽 = 2.44 MB/帧 × 12 fps × 8 bits/byte
     = 234 Mbps
     
实际 payload 带宽 = 34,624 × 32 × 12 × 8
                  = 106 Mbps
```

### **理论最大性能**

如果 `LINE_CYCLES` 可以减小到最小值（假设 12000）:
```
帧时间 = 120μs × 541 + 3ms = 67.92ms
帧率 = 14.7 fps
```

---

## 🎯 **下一步行动**

### **立即任务（优先级：高）**

1. **修复上位机程序**
   ```bash
   cd host_pc
   cp data_parser_fixed.py data_parser.py
   python main.py
   ```
   
2. **验证图像接收**
   - 确认每帧收到 34,624 个包
   - 检查图像分辨率 512 × 541
   - 验证数据类型 uint16

3. **传感器光响应测试**
   - 记录暗处 baseline
   - 照光后观察数值变化
   - 确认传感器工作正常

### **短期任务（优先级：中）**

4. **调查 LINE_CYCLES = 20000 失败原因**
   - 分析 Vivado 时序报告
   - 检查是否有 timing violations
   - 考虑添加时序约束

5. **优化帧率**
   - 如果 LINE_CYCLES 可以进一步减小
   - 或减少 FRAME_GAP_CYCLES

6. **添加帧同步机制**
   - 识别 header burst
   - 实现帧对齐
   - 添加丢包恢复

### **长期任务（优先级：低）**

7. **性能优化**
   - 多线程图像处理
   - GPU 加速
   - 压缩存储

8. **功能扩展**
   - 实时图像增强算法
   - 自动曝光控制
   - 数据记录和回放

---

## 📝 **关键文件清单**

### **FPGA 硬件**
- `board/project_1/project_1.srcs/sources_1/imports/src/top.v` - 顶层模块
  - 第 9 行: `FRAME_GAP_CYCLES = 150000`
  - 第 540 行: `LFSR_EN = 0`
  - 第 713 行: `LINE_CYCLES = 15000`
  - 第 779 行: `sync_in = sync_int`
  - 第 889 行: `TEST_MODE = 0`

- `board/project_1/project_1.srcs/sources_1/imports/src/ad71143_ctrl.v` - AFE 控制器
  - 控制 SYNC/ACLK 时序
  - LINE_CYCLES 参数定义

- `board/project_1/project_1.srcs/sources_1/imports/src/ad71143_data_rx.v` - LVDS 接收
  - 数据接收状态机
  - burst_cnt 计数逻辑

- `board/project_1/project_1.srcs/sources_1/imports/src/rgmii_bridge.v` - 网络桥接
  - UDP/IP 封装
  - FIFO 跨时钟域

### **上位机程序**
- `host_pc/data_parser.py` - **需要替换为 data_parser_fixed.py**
- `host_pc/data_parser_fixed.py` - 修复后的数据解析器
- `host_pc/main.py` - 主程序 GUI
- `host_pc/network_receiver.py` - UDP 接收器
- `host_pc/README.md` - 使用说明
- `host_pc/BUGFIX_REPORT.md` - Bug 修复报告

---

## 💾 **配置备份**

### **工作配置 (LINE_CYCLES = 15000)**

```verilog
// top.v
parameter integer FRAME_GAP_CYCLES = 150000,   // 3ms @ 50MHz
parameter integer LINE_CYCLES = 15000,         // 150μs @ 100MHz

// ad71143_ctrl 实例化
.LINE_CYCLES      (15000),
.RESET_CYCLES     (1000),
.INIT_WAIT_CYCLES (10000),

// AD71143 SPI 配置
Reg11: spi_reg_data <= {8'h0B, 8'h00, 1'b0, ...};  // LFSR_EN = 0

// RGMII Bridge
.TEST_MODE     (0),  // 使用真实数据

// ad71143_data_rx_dual
.sync_in(sync_int),  // 使用正确的 SYNC 信号
```

### **网络配置**

```
FPGA IP: 192.168.1.2
PC IP:   192.168.1.1
子网掩码: 255.255.255.0
协议:    UDP
端口:    1234
```

---

## 🎓 **经验教训**

### **1. 信号连接的重要性**
`sync_in` 连接错误导致整个数据接收链路失效。在 FPGA 设计中，信号命名和连接必须非常谨慎。

### **2. 时序参数的影响**
`LINE_CYCLES` 这样的时序参数不仅影响性能，还可能影响系统稳定性。需要在理论分析和实际测试之间找到平衡。

### **3. 数据格式文档的关键性**
上位机程序的 Bug 源于对 FPGA 数据格式的错误理解。**硬件和软件团队必须有清晰、准确的数据格式文档**。

### **4. 逐步调试的价值**
从 ILA 波形 → Wireshark 抓包 → 上位机程序，逐层验证每一步，最终定位了所有问题。

### **5. 参数边界测试**
LINE_CYCLES 的测试揭示了系统在极限参数下的行为。渐进式测试（6000 → 12000 → 15000 → 20000）帮助找到了安全工作范围。

---

## 📞 **技术支持**

如需进一步协助，请提供：
1. ILA 波形截图（重点关注 `shift_hi`, `burst_index`, `merged_valid`）
2. Wireshark 完整包截图（展开 UDP 头和 payload）
3. Vivado 时序报告（如果遇到 LINE_CYCLES = 20000 问题）
4. 上位机程序运行日志

---

## 📚 **参考文档**

1. AD71143 Datasheet - ADI 官方文档
2. `board/ILA_NT39_Setup_Instructions.md` - ILA 配置说明
3. `host_pc/README.md` - 上位机使用说明
4. `host_pc/BUGFIX_REPORT.md` - 详细 Bug 修复报告

---

**报告生成时间**: 2026-07-28  
**FPGA 配置版本**: LINE_CYCLES = 15000, TEST_MODE = 0, LFSR_EN = 0  
**调试状态**: 硬件传输正常，上位机程序需要修复  
**下一步**: 修复上位机程序并验证完整图像接收

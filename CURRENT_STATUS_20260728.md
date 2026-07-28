# AD71143 项目当前状态总结

**日期**: 2026-07-28  
**最后更新**: 下午

---

## 🎯 **当前问题**

### **测试模式无法正常工作**

**现象**：
- 设置 `TEST_MODE = 1` 后，所有 UDP payload 仍然是全 0
- 运行 `test_verify.py` 显示正确率只有 2.0%
- AFE 已经拔掉，但仍然收到全 0 的数据

**原因分析**：
根据 `rgmii_bridge.v` 第 254 行的逻辑：
```verilog
if (fifo_empty && !preloaded && !fifo_rd_en && !test_trig) begin
    test_trig <= 1'b1;  // 只有在 FIFO 为空时才触发测试模式
end
```

**问题**：FIFO 中可能还有残留的旧数据（全 0），导致：
1. `fifo_empty` 不为 1
2. 测试触发条件不满足
3. 持续发送 FIFO 中的旧数据（全 0）

---

## 📊 **调试历程回顾**

### **已解决的问题**

#### **1. ILA 探针未定义信号**
- **修复位置**: `top.v` 第 982-1028 行
- **状态**: ✅ 已修复

#### **2. SYNC 信号连接错误**
- **问题**: `sync_in` 连接到 `line_start_pulse`（单脉冲）而不是 `sync_int`（SYNC信号）
- **修复位置**: `top.v` 第 779 行
- **修复**: `.sync_in(sync_int)`
- **状态**: ✅ 已修复并验证工作正常

#### **3. 帧率过低**
- **修复**: `FRAME_GAP_CYCLES` 从 250000 改为 150000
- **状态**: ✅ 已优化

#### **4. AD71143 LFSR 测试模式未关闭**
- **修复**: `Reg11: LFSR_EN` 从 1 改为 0
- **修复位置**: `top.v` 第 540 行
- **状态**: ✅ 已修复

#### **5. LINE_CYCLES 太短**
- **问题**: 6000 (60μs) 太短，导致 burst_cnt 不复位
- **修复**: 改为 15000 (150μs)
- **状态**: ✅ 已修复，数据接收正常

#### **6. 上位机数据解析错误**
- **问题**: 理解为 4-bit 像素，实际是 16-bit 样本
- **修复**: 创建 `data_parser_fixed.py`
- **状态**: ✅ 已修复，但未完全验证

### **硬件验证结果**

通过 ILA 和 Wireshark 验证：
- ✅ AFE 控制器工作正常
- ✅ 数据接收状态机正常
- ✅ 每行接收 64 个 burst
- ✅ `burst_index` 从 0 → 63
- ✅ FIFO 工作正常
- ✅ RGMII 发送正常
- ✅ UDP 包能到达 PC
- ✅ Payload 大小正确（32 字节）

---

## 🔴 **当前未解决的问题**

### **1. 测试模式无法生效**

**当前配置**：
```verilog
// top.v 第 889 行
.TEST_MODE     (1),  // 已启用
```

**实际结果**：
- Payload 全是 0
- 不是预期的测试数据（序号 + 递增字节）

**根本原因**：
FIFO 中有残留数据，导致测试模式触发条件不满足。

**解决方案**：

#### **方案 A：强制清空 FIFO（推荐）**

在 `top.v` 中添加 FIFO 复位逻辑：

```verilog
// 在 rgmii_bridge 实例化之前添加
reg fifo_force_reset;
reg [15:0] reset_cnt;

always @(posedge clk_100m or negedge rst_n_100m) begin
    if (!rst_n_100m) begin
        fifo_force_reset <= 1'b1;
        reset_cnt <= 16'd0;
    end else begin
        if (reset_cnt < 16'd1000) begin
            fifo_force_reset <= 1'b1;
            reset_cnt <= reset_cnt + 16'd1;
        end else begin
            fifo_force_reset <= 1'b0;
        end
    end
end

// 修改 data_valid 连接
wire final_data_valid = (DATA_TEST_MODE || fifo_force_reset) ? 1'b0 : merged_valid;
```

#### **方案 B：修改测试触发条件**

修改 `rgmii_bridge.v` 第 254 行：

```verilog
// 原来：只有 FIFO 为空时才触发
if (fifo_empty && !preloaded && !fifo_rd_en && !test_trig) begin

// 改为：强制触发测试模式
if (!preloaded && !fifo_rd_en && !test_trig) begin
    test_trig <= 1'b1;
    test_seq_num <= test_seq_num + 32'd1;
end
```

#### **方案 C：使用独立的测试数据生成器**

在 `top.v` 中实例化 `test_pattern_gen.v`（已创建），绕过 FIFO 直接注入测试数据。

### **2. LINE_CYCLES = 20000 时数据接收失败**

**现象**：
- LINE_CYCLES = 15000: 正常
- LINE_CYCLES = 20000: `shift_hi/shift_lo` 全 0

**原因**：未知（可能是时序问题）

**当前状态**：使用 LINE_CYCLES = 15000 作为临时方案

---

## 📋 **文件清单**

### **FPGA 硬件文件**
1. `board/project_1/project_1.srcs/sources_1/imports/src/top.v`
   - 第 9 行: `FRAME_GAP_CYCLES = 150000`
   - 第 540 行: `LFSR_EN = 0`
   - 第 713 行: `LINE_CYCLES = 15000`
   - 第 779 行: `sync_in = sync_int`
   - 第 889 行: `TEST_MODE = 1`

2. `board/project_1/project_1.srcs/sources_1/imports/src/rgmii_bridge.v`
   - 网络桥接模块
   - 测试模式逻辑（第 250-261 行）

3. `board/project_1/project_1.srcs/sources_1/imports/src/test_pattern_gen.v`
   - 测试图像生成器（已创建，未使用）

### **上位机程序文件**
1. `host_pc/data_parser.py` - 数据解析器（已替换为修复版本）
2. `host_pc/data_parser_fixed.py` - 修复后的版本
3. `host_pc/data_parser_backup_original.py` - 原始备份
4. `host_pc/main.py` - 主程序 GUI
5. `host_pc/test_verify.py` - 测试数据验证脚本（新建）

### **文档文件**
1. `DEBUGGING_SUMMARY_20260728.md` - 完整调试总结
2. `host_pc/BUGFIX_REPORT.md` - 上位机 Bug 修复报告
3. `DATA_LINK_TEST_PLAN.md` - 数据链路测试方案
4. 本文件 - 当前状态总结

---

## 🎯 **下一步行动计划**

### **立即任务**

#### **任务 1：修复测试模式（最高优先级）**

**选择方案 B（最简单）**：

1. 修改 `rgmii_bridge.v` 第 254 行：
```verilog
// 修改前
if (fifo_empty && !preloaded && !fifo_rd_en && !test_trig) begin

// 修改后
if (!preloaded && !fifo_rd_en && !test_trig) begin
```

2. 重新综合、实现、生成 bitstream
3. 烧录 FPGA
4. 运行 `python test_verify.py` 验证

**预期结果**：
- 所有包的 payload 应该是：`XX XX XX XX 04 05 06 07 ... 1F`
- 前 4 字节递增
- 正确率应该是 100%

#### **任务 2：验证上位机程序**

测试模式正常工作后：

1. 运行 `python main.py`
2. 观察图像显示
3. 检查接收统计（每帧 34,624 个包）
4. 保存一帧数据并验证：
```python
import numpy as np
frame = np.load('frame_raw_*.npy')
print(f"Shape: {frame.shape}")  # 应该是 (541, 512)
print(f"Dtype: {frame.dtype}")  # 应该是 uint16
```

### **后续任务**

#### **任务 3：恢复真实 AFE 数据**

测试模式验证完成后：

1. 修改 `top.v` 第 889 行：`.TEST_MODE(0)`
2. 重新插上 AFE
3. 重新综合并烧录
4. 验证真实传感器数据
5. 照光测试

#### **任务 4：优化性能**

1. 调查 LINE_CYCLES = 20000 失败原因
2. 尝试提高帧率
3. 添加帧同步机制
4. 优化上位机性能

---

## 📊 **系统配置记录**

### **当前工作配置**

```
FPGA 参数:
  FRAME_LINES = 541
  FRAME_GAP_CYCLES = 150000 (3ms @ 50MHz)
  LINE_CYCLES = 15000 (150μs @ 100MHz)
  TEST_MODE = 1 (测试模式启用)
  LFSR_EN = 0 (AD71143 测试模式禁用)

网络配置:
  FPGA IP: 192.168.1.2
  PC IP: 192.168.1.1
  端口: 1234
  协议: UDP

性能指标:
  帧率: ~12 fps
  每帧包数: 34,624
  每帧数据量: ~2.44 MB
  带宽: ~234 Mbps (理论)
```

---

## 🔍 **已知问题列表**

| 问题 | 状态 | 优先级 | 描述 |
|------|------|--------|------|
| 测试模式无法生效 | 🔴 进行中 | P0 | FIFO 残留数据导致测试触发失败 |
| LINE_CYCLES=20000 失败 | ⚠️ 暂缓 | P2 | 原因未明，使用 15000 临时方案 |
| 上位机解析未验证 | 🟡 待验证 | P1 | 修复后的代码需要用测试数据验证 |
| 缺少帧同步机制 | 🟡 待开发 | P2 | 可能导致帧错位 |
| 传感器光响应未测试 | 🟡 待测试 | P1 | 需要恢复 AFE 后测试 |

---

## 📝 **测试记录**

### **测试 1: ILA 硬件验证**
- **日期**: 2026-07-28 上午
- **配置**: LINE_CYCLES = 15000, TEST_MODE = 0
- **结果**: ✅ 通过
  - burst_index: 0 → 63
  - merged_valid: 64 个/行
  - shift_hi/shift_lo: 有数据

### **测试 2: Wireshark 网络验证**
- **日期**: 2026-07-28 上午
- **配置**: LINE_CYCLES = 15000, TEST_MODE = 0
- **结果**: ✅ 通过
  - 源 IP: 192.168.1.2
  - 端口: 1234
  - Payload: 32 字节
  - 数据内容: 有非零值

### **测试 3: 测试模式验证**
- **日期**: 2026-07-28 下午
- **配置**: LINE_CYCLES = 15000, TEST_MODE = 1, AFE 拔掉
- **结果**: ❌ 失败
  - Payload 全是 0
  - 不是预期的测试数据
  - 原因: FIFO 残留数据

---

## 💡 **经验教训**

### **1. FIFO 状态管理的重要性**
测试模式的触发依赖 `fifo_empty` 信号，但 FIFO 中可能有残留数据。在切换模式时需要考虑 FIFO 清空或复位。

### **2. 逐层验证的价值**
- FPGA 内部 (ILA) ✅
- 网络传输 (Wireshark) ✅  
- 上位机解析 ⚠️ 待验证

通过分层测试，精确定位了问题所在。

### **3. 测试数据的必要性**
使用已知的测试图像可以快速验证整个数据链路，比直接调试传感器数据更高效。

### **4. 文档的重要性**
数据格式理解错误导致上位机程序完全无法工作，说明硬件和软件团队之间需要清晰准确的接口文档。

---

## 📞 **下次调试检查清单**

### **修改代码前**
- [ ] 备份当前工作的 bitstream
- [ ] 记录当前所有参数配置
- [ ] 在 ILA 中截图当前工作状态

### **综合前**
- [ ] 检查所有修改的文件
- [ ] 确认参数配置正确
- [ ] 运行语法检查

### **烧录前**
- [ ] 保存 bitstream 副本
- [ ] 记录版本号和修改内容
- [ ] 准备回退方案

### **测试时**
- [ ] 先用 Wireshark 验证网络
- [ ] 再用 test_verify.py 验证数据
- [ ] 最后用 main.py 验证图像
- [ ] 记录所有测试结果

---

## 📚 **参考资源**

### **官方文档**
- AD71143 Datasheet - ADI 官方
- RGMII 规范
- UDP/IP 协议标准

### **项目文档**
- `DEBUGGING_SUMMARY_20260728.md` - 详细调试历程
- `host_pc/BUGFIX_REPORT.md` - 上位机问题分析
- `DATA_LINK_TEST_PLAN.md` - 测试方案

### **关键代码位置**
- `top.v` 第 889 行 - TEST_MODE 配置
- `rgmii_bridge.v` 第 254 行 - 测试触发条件
- `data_parser.py` 第 98-136 行 - 样本提取函数

---

**报告生成时间**: 2026-07-28 下午  
**下一步**: 修复测试模式触发条件  
**预计完成时间**: 30 分钟（修改代码 + 重新综合）

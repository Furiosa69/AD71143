# FIFO 深度修复指南

## 已完成的修改 ✓

### 1. FIFO IP 核配置文件已更新
**文件**: `board/project_1/project_1.srcs/sources_1/ip/fifo_generator_0/fifo_generator_0.xci`

**修改内容**:
- `Input_Depth`: 16 → **1024**
- `Output_Depth`: 16 → **1024**
- `Data_Count_Width`: 4 → **10** (log2(1024))
- `Write_Data_Count_Width`: 4 → **10**
- `Read_Data_Count_Width`: 4 → **10**
- `Full_Threshold_Assert_Value`: 13 → **1021**
- `Full_Threshold_Negate_Value`: 12 → **1020**

### 2. 软件帧同步已更新
**文件**: `host_pc/data_parser.py`

**修改内容**:
```python
# 帧阈值从 300 行增加到 500 行
self.lines_per_frame_threshold = 500
```

## 下一步：重新生成 Bitstream

### 方法 1: 使用 TCL 脚本（推荐）

1. **启动 Vivado**
   ```
   打开 Vivado 2023.2
   ```

2. **在 TCL Console 中执行**
   ```tcl
   source D:/project/AD71143/board/rebuild_bitstream.tcl
   ```

3. **等待完成**
   - 预计时间：10-30 分钟
   - 过程：IP 生成 → 综合 → 实现 → 生成 bitstream
   - 完成后文件位置：`board/project_1/Result/top.bit`

### 方法 2: 手动操作

1. **打开项目**
   ```
   File → Open Project → board/project_1/project_1.xpr
   ```

2. **重新生成 FIFO IP 核**
   ```
   IP Sources → fifo_generator_0 → 右键 → Reset Output Products
   IP Sources → fifo_generator_0 → 右键 → Generate Output Products
   ```

3. **重新综合**
   ```
   Flow → Run Synthesis
   等待完成后点击 OK
   ```

4. **运行实现**
   ```
   Flow → Run Implementation
   等待完成后点击 OK
   ```

5. **生成 Bitstream**
   ```
   Flow → Generate Bitstream
   等待完成
   ```

6. **复制文件**
   ```
   复制 project_1.runs/impl_1/top.bit 到 Result/top.bit
   复制 project_1.runs/impl_1/top.bin 到 Result/top.bin
   ```

## 验证新 Bitstream

### 1. 下载到 FPGA
使用 Vivado Hardware Manager 或其他工具下载 `Result/top.bit`

### 2. 测试行数分布
```bash
cd host_pc
python test_line_distribution.py
```

**期望结果**:
```
帧 #1: 540 行 (34560 个 burst)
帧 #2: 541 行 (34624 个 burst)
帧 #3: 541 行 (34624 个 burst)
...
平均行数: 541.0
```

### 3. 测试图像显示
```bash
python main.py
```

**期望效果**:
- ✓ 图像不滚动（位置固定）
- ✓ 显示完整 541 行
- ✓ 渐变从黑色（第 0 行）到白色（第 540 行）
- ✓ 帧率稳定（约 20 fps）

## 预期改进

### 修复前（FIFO 深度 = 16）
- 每帧只接收 **309 行**（57%）
- 图像不完整，下半部分黑色
- 丢失约 15000 个数据包/帧

### 修复后（FIFO 深度 = 1024）
- 每帧接收 **541 行**（100%）
- 图像完整显示
- 无数据丢失

### FIFO 容量分析
```
旧配置: 16 × 256 bits = 512 bytes = 16 个 burst
新配置: 1024 × 256 bits = 32 KB = 1024 个 burst

缓冲时间:
- 旧: 16 × 2μs = 32μs
- 新: 1024 × 2μs = 2048μs = 2ms

一帧持续时间:
- 541 行 × 64 burst/行 × 2μs/burst = 69ms
- FIFO 可缓冲约 3% 的帧数据（足够平滑速率差异）
```

## 资源使用估计

### BRAM 使用
- 旧配置: 1 BRAM (36Kb)
- 新配置: 8 BRAM (288Kb)
- 增加: 7 个 BRAM

### 对于 Artix-7 系列 FPGA
通常有 100+ 个 BRAM，增加 7 个 BRAM 是可接受的。

## 常见问题

### Q1: 如果还是只收到 300-400 行怎么办？
检查：
1. 确认新 bitstream 已下载到 FPGA
2. 检查 ILA 或 UART 调试信息确认 FIFO 深度
3. 运行 `test_frame_gap.py` 查看实际包数

### Q2: 如果 FIFO 还是会满？
可能需要：
1. 进一步增加 FIFO 深度到 2048
2. 优化 RGMII 发送速度（减少帧间延迟）
3. 降低测试图像生成速率（增加 TEST_INTERVAL）

### Q3: 综合/实现失败？
检查：
1. BRAM 资源是否充足
2. 时序约束是否满足
3. 查看 Vivado 报告的具体错误

## 完成后的系统状态

- ✓ FIFO 深度: 1024
- ✓ 软件阈值: 500 行
- ✓ 硬件发送: 541 行完整帧
- ✓ 帧同步: 基于行数计数
- ✓ 图像显示: 稳定不滚动

新的 bitstream 准备好后，整个系统将能够稳定接收和显示完整的 541 行图像！

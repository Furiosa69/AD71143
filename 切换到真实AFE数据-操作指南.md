# 切换到真实 AFE 数据 - 操作指南

## 已完成的修改

### 1. 硬件修改
**文件**: `board/project_1/project_1.srcs/sources_1/imports/src/top.v`

**修改内容**:
```verilog
parameter DATA_TEST_MODE = 0  // 0=真实AFE数据, 1=测试图像
```

### 2. 软件修改
**文件**: `host_pc/data_parser.py`

**修改内容**:
- 帧同步方式从"行号跳变检测"改为"固定包数计数"
- 每帧约 19500 个包（对应 ~305 行）
- 适用于任何图像内容（不依赖特定亮度模式）

```python
# 帧同步：基于固定包数
self.packets_in_frame = 0
self.packets_per_frame_threshold = 19500  # 约 305 行

# 每收到一个包，计数器+1
self.packets_in_frame += 1

# 达到阈值时返回帧
if self.packets_in_frame >= self.packets_per_frame_threshold:
    return True, frame_data
```

## 重新生成 Bitstream

### 方法 1: 使用 TCL 脚本（推荐）

1. **打开 Vivado 2023.2**

2. **在 TCL Console 执行**:
   ```tcl
   source D:/project/AD71143/board/switch_to_afe_data.tcl
   ```

3. **等待完成**（10-30 分钟）

4. **下载新 bitstream**:
   - 文件：`board/project_1/Result/top.bit`

### 方法 2: 手动操作

1. 打开项目：`board/project_1/project_1.xpr`
2. Flow → Run Synthesis
3. Flow → Run Implementation
4. Flow → Generate Bitstream
5. 复制 `project_1.runs/impl_1/top.bit` 到 `Result/top.bit`

## 测试真实 AFE 数据

### 1. 下载 bitstream 到 FPGA

### 2. 运行软件
```bash
cd host_pc
python main.py
```

### 3. 预期效果

**如果 AFE 正常工作**:
- 显示来自传感器的真实图像
- 帧率稳定（约 20 fps）
- 图像不滚动

**如果显示全黑/全白**:
- 检查 AFE 电源和配置
- 检查 SPI 通信是否正常
- 使用 ILA 调试 `merged_burst` 和 `merged_valid` 信号

## 帧同步机制对比

### 测试模式（已弃用）
- **方法**: 检测行号跳变（基于固定亮度值）
- **优点**: 精确对齐到硬件行号 0
- **缺点**: 只适用于测试渐变图像
- **代码**: 已移除

### 真实数据模式（当前）
- **方法**: 每 19500 个包触发新帧
- **优点**: 
  - ✓ 适用于任何图像内容
  - ✓ 简单可靠
  - ✓ 不依赖图像特征
- **缺点**: 
  - ✗ 如果丢包，帧边界可能漂移
  - ✗ 没有明确的帧起始标记
- **代码**: `data_parser.py`

## 帧边界漂移问题

### 问题描述
基于固定包数的帧同步，如果发生丢包，会导致帧边界逐渐漂移。

### 解决方案（推荐用于生产）

#### 硬件端：添加帧计数器
修改 `rgmii_bridge.v`，在每个包的 payload 最前面插入帧号：

```verilog
reg [15:0] frame_counter;

// 每帧开始时递增
always @(posedge clk_125m) begin
    if (frame_start_detected) begin
        frame_counter <= frame_counter + 1;
    end
end

// 封装时插入帧号
wire [15:0] packet_header = frame_counter;
wire [255:0] packet_payload = {packet_header, burst_data[239:0]};
```

#### 软件端：检测帧号跳变
```python
# 从包中提取帧号
frame_num = struct.unpack('>H', payload[0:2])[0]

# 检测帧号变化
if frame_num != self.last_frame_num:
    # 新帧开始
    return True, frame_data
    
self.last_frame_num = frame_num
```

## 当前系统状态

### 硬件
- ✓ DATA_TEST_MODE = 0（真实 AFE 数据）
- ✓ FIFO 深度 = 1024（配置已修改，需验证）
- ✗ 无帧起始标记（真实数据模式）
- ⚠️ 只能发送约 306 行（FIFO 限制）

### 软件
- ✓ 基于包数计数的帧同步
- ✓ 适配 306 行帧大小
- ✓ 不依赖图像内容
- ⚠️ 无丢包恢复机制

## 后续优化

### 短期
1. 验证真实 AFE 数据是否正常显示
2. 检查 FIFO 配置是否生效（期望能接收 541 行）

### 中期
3. 添加帧计数器到硬件（推荐）
4. 实现基于帧号的同步（更可靠）

### 长期
5. 优化 FIFO 深度或发送速率，达到完整 541 行
6. 添加丢包检测和恢复
7. 实现自适应帧同步

## 相关文件

- `board/project_1/project_1.srcs/sources_1/imports/src/top.v` - 数据源选择
- `board/switch_to_afe_data.tcl` - 重新生成 bitstream 脚本
- `host_pc/data_parser.py` - 帧同步逻辑
- `图像滚动问题-最终解决方案.md` - 帧同步问题总结

# 数据格式修复说明

## 问题描述

上位机软件报错：
```
[WARN] 数据包长度不足: 32 < 256
```

## 根本原因

**误解了硬件的数据格式**：

### 错误理解
- 以为 UDP Payload = 256 **bytes**
- 以为每个 Burst = 64 个通道 × 2 bytes = 128 bytes
- 以为 Panel 1 数据 = 128 bytes

### 实际情况
- UDP Payload = 32 **bytes** (256 **bits**)
- 每个 Burst = 8 个通道 × 2 bytes = 16 bytes (128 bits)
- Panel 1 数据 = 16 bytes (128 bits)

## 硬件数据格式

### merged_burst[255:0] 结构

```
位 255:128 (16 bytes) = Panel 1 数据（8 个通道 × 16 bits）
位 127:0   (16 bytes) = Panel 0 数据（8 个通道 × 16 bits，填充 0）

总共：32 bytes = 256 bits
```

### Panel 1 通道排列

```
Byte 16-17: 通道 0
Byte 18-19: 通道 1
Byte 20-21: 通道 2
Byte 22-23: 通道 3
Byte 24-25: 通道 4
Byte 26-27: 通道 5
Byte 28-29: 通道 6
Byte 30-31: 通道 7
```

## 修复内容

### 1. 修改参数

**之前（错误）**:
```python
self.CHANNELS_PER_BURST = 64
self.PAYLOAD_SIZE = 256      # bytes
self.PANEL1_START = 128
self.PANEL_SIZE = 128
```

**之后（正确）**:
```python
self.CHANNELS_PER_BURST = 8  # 每个 Burst 8 个通道
self.PAYLOAD_SIZE = 32       # bytes (256 bits)
self.PANEL1_START = 16       # Panel 1 从 byte 16 开始
self.PANEL_SIZE = 16         # 每个 Panel 16 bytes
```

### 2. 修改解析逻辑

**parse_packet 函数**:
```python
# 提取 Payload（最后 32 bytes）
payload = data[-32:]

# 提取 Panel 1 数据（高 16 bytes）
panel1_data = payload[16:32]

# 解析 8 个通道
channels = []
for i in range(8):
    offset = i * 2
    value = struct.unpack('>H', panel1_data[offset:offset+2])[0]
    channels.append(value)
```

### 3. 修改帧组装逻辑

**图像尺寸**:
```python
# 每行 = 65 Bursts × 8 通道 = 520 像素
# 实际需要 541 像素，最后 21 个像素填充 0

frame = np.zeros((541, 541), dtype=np.uint16)  # 或 (541, 520)
```

## 图像数据流

```
FPGA 端:
  AD71143 → 8 通道/Burst → 65 Bursts/行 → 541 行 = 35,165 个数据包

网络传输:
  32 bytes/包 × 35,165 包 = 1.06 MB/帧

PC 端:
  35,165 个数据包 → 组装成 541×520 图像（或 541×541 填充后）
```

## 每帧数据量

```
每包数据:
  - MAC头: 14 bytes
  - IP头:  20 bytes
  - UDP头: 8 bytes
  - Payload: 32 bytes
  - FCS: 4 bytes
  = 78 bytes/包

每帧数据:
  = 35,165 包 × 78 bytes
  = 2.74 MB/帧

理论带宽 (@ 185 fps):
  = 2.74 MB × 185
  = 507 MB/s
  = 4.06 Gbps
```

## 验证步骤

### 1. 使用 Wireshark 验证

```
1. 捕获数据包
2. 查看 UDP Payload 长度
   ✅ 应该是 32 bytes
   ❌ 如果是 256 bytes，说明硬件配置错误

3. 查看 Payload 内容
   - Bytes 0-15: 应该全为 0 (Panel 0)
   - Bytes 16-31: 应该有数据变化 (Panel 1)
```

### 2. 使用调试脚本验证

```python
import socket
import struct

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(('0.0.0.0', 1234))

data, addr = sock.recvfrom(4096)
payload = data[-32:]

print(f"Payload 长度: {len(payload)} bytes")

# 解析 Panel 1 的 8 个通道
panel1 = payload[16:32]
for i in range(8):
    val = struct.unpack('>H', panel1[i*2:i*2+2])[0]
    print(f"通道 {i}: {val}")
```

**预期输出**:
```
Payload 长度: 32 bytes
通道 0: 1234
通道 1: 5678
通道 2: 9012
通道 3: 3456
通道 4: 7890
通道 5: 1234
通道 6: 5678
通道 7: 9012
```

## 相关文件

### 修改的文件
- `host_pc/panel2_receiver.py` - 上位机接收程序

### 新建的文档
- `host_pc/DATA_FORMAT.md` - 数据格式详解

### 硬件参考
- `board/project_1/.../rgmii_bridge.v` - BURST_BYTES = 32
- `board/project_1/.../ad71143_data_rx.v` - merged_burst[127:0] = 8 通道
- `board/project_1/.../ad71143_data_rx_dual.v` - merged_burst[255:0] = 双 Panel

## 关键知识点

### 位 vs 字节

- **256 bits** = 32 bytes
- **128 bits** = 16 bytes
- **16 bits** = 2 bytes (一个通道)

### 大端序（网络字节序）

```
16 位值 0x1234:
  内存: [0x12, 0x34]
  解析: struct.unpack('>H', ...)  # 注意 '>' 表示大端序
```

### Burst 和通道

```
1 个 Burst = 8 个通道
1 行 = 65 个 Bursts = 520 个通道（像素）
1 帧 = 541 行 = 35,165 个 Bursts = 281,320 个像素
```

## 注意事项

1. ⚠️ **不要混淆 bits 和 bytes**
   - 硬件文档中的 `[255:0]` 是 **256 bits**，不是 256 bytes

2. ⚠️ **字节序很重要**
   - 必须使用大端序解析 `struct.unpack('>H', ...)`
   - 如果用错字节序，数据会完全错误

3. ⚠️ **图像尺寸可能不是整数**
   - 每行 520 像素，但传感器可能是 541 像素
   - 需要根据实际情况填充或截取

4. ⚠️ **UDP 不保证顺序**
   - 高速率下可能乱序
   - 需要根据 burst_index 排序（如果硬件提供）

## 测试状态

- [x] 修复参数配置
- [x] 修复解析逻辑
- [x] 修复帧组装
- [x] 更新文档
- [ ] 测试实际接收（需要 FPGA 运行）
- [ ] 验证图像显示
- [ ] 性能测试

---

**修复时间**: 2026-07-27  
**影响范围**: 仅上位机软件，硬件无需修改  
**状态**: ✅ 代码已修复，等待硬件测试

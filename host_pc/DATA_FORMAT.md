# AD71143 数据格式详解

## 一、硬件数据流

### 1.1 AD71143 数据输出

**单个 Panel 输出**:
```
ad71143_data_rx 模块:
  - 输入: LVDS 数据流（Lane A + Lane B）
  - 输出: merged_burst[127:0]
  - 每个 Burst = 128 bits = 8 个通道 × 16 bits/通道
```

**通道排列**:
```verilog
merged_burst[127:112] = 通道 0 (16 bits)
merged_burst[111:96]  = 通道 1 (16 bits)
merged_burst[95:80]   = 通道 2 (16 bits)
merged_burst[79:64]   = 通道 3 (16 bits)
merged_burst[63:48]   = 通道 4 (16 bits)
merged_burst[47:32]   = 通道 5 (16 bits)
merged_burst[31:16]   = 通道 6 (16 bits)
merged_burst[15:0]    = 通道 7 (16 bits)
```

### 1.2 双 Panel 合并

**ad71143_data_rx_dual 模块**:
```verilog
// 原始双 Panel 模式（已修改为单 Panel 测试）
merged_burst[255:0] = {Panel1[127:0], Panel0[127:0]}

// 当前测试模式：Panel 0 位置填充 0
merged_burst[127:0]   = Panel 0 数据（全为 0）
merged_burst[255:128] = Panel 1 数据（8 个通道）
```

**字节表示**:
```
Byte 0-1:   Panel 0, 通道 0 (填充 0)
Byte 2-3:   Panel 0, 通道 1 (填充 0)
...
Byte 14-15: Panel 0, 通道 7 (填充 0)
Byte 16-17: Panel 1, 通道 0 (有效数据) ← 这是我们需要的
Byte 18-19: Panel 1, 通道 1 (有效数据)
...
Byte 30-31: Panel 1, 通道 7 (有效数据)
```

### 1.3 RGMII 封装

**rgmii_bridge 模块**:
```
参数:
  BURST_WIDTH = 256 bits
  BURST_BYTES = 32 bytes

以太网帧结构:
  - Preamble: 7 bytes (0x55)
  - SFD: 1 byte (0xD5)
  - MAC 头: 14 bytes
  - IP 头: 20 bytes
  - UDP 头: 8 bytes
  - Payload: 32 bytes ← merged_burst[255:0]
  - FCS: 4 bytes (CRC32)
  
总长度 = 7 + 1 + 14 + 20 + 8 + 32 + 4 = 86 bytes
```

---

## 二、网络协议详解

### 2.1 以太网帧格式

```
+----------+----------+----------+----------+----------+
| Preamble |   SFD    | MAC 头   |  IP 头   | UDP 头   |
|  7 bytes | 1 byte   | 14 bytes | 20 bytes | 8 bytes  |
+----------+----------+----------+----------+----------+
| Payload (32 bytes)                        |   FCS    |
+-------------------------------------------+----------+
                                            | 4 bytes  |
                                            +----------+
```

### 2.2 MAC 头 (14 bytes)

```
Offset  Field           Value               Description
------  -----           -----               -----------
0-5     DMAC            FF:FF:FF:FF:FF:FF   目标 MAC（广播）
6-11    SMAC            02:00:00:00:00:01   源 MAC（FPGA）
12-13   EtherType       0x0800              IPv4
```

### 2.3 IP 头 (20 bytes)

```
Offset  Field           Value       Description
------  -----           -----       -----------
0       Version/IHL     0x45        IPv4, 头长度=20
1       DSCP/ECN        0x00        默认
2-3     Total Length    0x003C      60 bytes (IP+UDP+Payload)
4-5     Identification  0x0000      
6-7     Flags/Fragment  0x0000      不分片
8       TTL             0x40        64
9       Protocol        0x11        UDP
10-11   Checksum        0xF75D      预计算
12-15   Source IP       192.168.1.2  FPGA IP
16-19   Dest IP         192.168.1.1  PC IP
```

### 2.4 UDP 头 (8 bytes)

```
Offset  Field           Value       Description
------  -----           -----       -----------
0-1     Source Port     1234        0x04D2
2-3     Dest Port       1234        0x04D2
4-5     Length          40          8 + 32 (UDP头+Payload)
6-7     Checksum        0x0000      未计算（允许）
```

### 2.5 Payload (32 bytes)

```
Offset  Field               Description
------  -----               -----------
0-15    Panel 0 数据        全为 0（测试模式）
16-31   Panel 1 数据        8 个通道 × 2 bytes

Panel 1 详细结构:
Byte 16-17: 通道 0 (大端序，16 位)
Byte 18-19: 通道 1
Byte 20-21: 通道 2
Byte 22-23: 通道 3
Byte 24-25: 通道 4
Byte 26-27: 通道 5
Byte 28-29: 通道 6
Byte 30-31: 通道 7
```

---

## 三、图像数据组织

### 3.1 单行数据

```
一行 = 65 个 Bursts × 8 通道/Burst = 520 个像素

Burst 0:  像素 0-7
Burst 1:  像素 8-15
Burst 2:  像素 16-23
...
Burst 64: 像素 512-519

总共: 520 个像素（实际有效 541 个，最后 21 个像素可能来自其他 Burst 或填充 0）
```

### 3.2 完整帧数据

```
一帧 = 541 行

行 0:   像素 0-519 (或 0-540)
行 1:   像素 0-519 (或 0-540)
...
行 540: 像素 0-519 (或 0-540)

图像矩阵: 541 (行) × 520 (列) ≈ 541 × 541（如果填充）
像素深度: 16 位（0-65535）
```

### 3.3 数据包数量

```
每行数据包数 = 65 个 Bursts
每帧数据包数 = 541 行 × 65 Bursts/行 = 35,165 个数据包

每秒数据包数 (@ 185 fps):
  = 35,165 包/帧 × 185 帧/秒
  = 6,505,525 包/秒
  ≈ 6.5M pps

每秒数据量:
  = 35,165 × 298 bytes/包 × 185 fps
  = 1,939 MB/s
  ≈ 15.5 Gbps（理论值，实际取决于 FRAME_GAP）
```

---

## 四、上位机解析

### 4.1 UDP Socket 接收

```python
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(('0.0.0.0', 1234))

data, addr = sock.recvfrom(4096)
# data 长度可能是：
# - 完整帧: 86 bytes (Preamble+SFD+MAC+IP+UDP+Payload+FCS)
# - 或只有: 42 + 32 = 74 bytes (MAC+IP+UDP+Payload)
# - 或只有: 32 bytes (仅 Payload)
```

### 4.2 Payload 提取

```python
# 假设接收到完整数据包（可能包含各种头）
# 安全的做法：从末尾提取 32 bytes
payload = data[-32:]

# Panel 0 数据（bytes 0-15，全为 0）
panel0_data = payload[0:16]

# Panel 1 数据（bytes 16-31，有效数据）
panel1_data = payload[16:32]
```

### 4.3 通道解析

```python
import struct

channels = []
for i in range(8):  # 8 个通道
    offset = i * 2
    # 大端序解析 16 位无符号整数
    value = struct.unpack('>H', panel1_data[offset:offset+2])[0]
    channels.append(value)

# channels[0] = 通道 0
# channels[1] = 通道 1
# ...
# channels[7] = 通道 7
```

### 4.4 帧组装

```python
import numpy as np

# 创建帧缓冲
frame = np.zeros((541, 520), dtype=np.uint16)

bursts_received = []  # 收集所有 Burst

# 当收集到 35,165 个 Burst 时
for line_idx in range(541):
    for burst_idx in range(65):
        packet_idx = line_idx * 65 + burst_idx
        burst = bursts_received[packet_idx]  # 8 个通道
        
        # 填充到图像
        pixel_start = burst_idx * 8
        frame[line_idx, pixel_start:pixel_start+8] = burst

# 如果需要 541 列，最后 21 列填充 0 或截取
if frame.shape[1] < 541:
    frame = np.pad(frame, ((0, 0), (0, 541 - frame.shape[1])), mode='constant')
```

---

## 五、字节序说明

### 5.1 硬件字节序（网络字节序 = 大端序）

```
16 位值 0x1234:
  Byte 0 (高字节): 0x12
  Byte 1 (低字节): 0x34

在内存中存储为: [0x12, 0x34]
```

### 5.2 Python 解析

```python
# 大端序（网络字节序）
value = struct.unpack('>H', bytes([0x12, 0x34]))[0]
# value = 0x1234 = 4660

# 小端序（Intel x86）
value = struct.unpack('<H', bytes([0x12, 0x34]))[0]
# value = 0x3412 = 13330
```

**重要**: 必须使用大端序 `'>H'` 解析！

---

## 六、常见问题

### Q1: 为什么只有 8 个通道，不是 64 个？

**A**: AD71143 使用 DDR 模式，每次输出 2 个 Lane（A 和 B），每个 Lane 包含 4 个 16 位样本。一个 Burst = 2 Lanes × 4 samples = 8 个通道。要获得完整的 64 个通道，需要 8 个 Bursts。

### Q2: 为什么图像是 541×520 而不是 541×541？

**A**: 每行 65 个 Bursts × 8 通道 = 520 像素。如果实际传感器是 541 像素宽，可能需要额外的 Bursts 或者最后 21 个像素在其他地方编码。

### Q3: 如何验证数据是否正确？

**A**: 
1. 检查 Panel 0 数据（bytes 0-15）是否全为 0
2. 检查 Panel 1 数据（bytes 16-31）是否有变化
3. 检查通道值范围是否合理（0-65535）
4. 使用 Wireshark 查看原始数据包

### Q4: 丢包怎么办？

**A**:
1. 增加 Socket 接收缓冲区：`sock.setsockopt(socket.SO_RCVBUF, 4*1024*1024)`
2. 使用千兆网卡
3. 检查 CPU 占用，降低处理延迟
4. 在上位机软件中添加丢包检测和重传机制（如果 FPGA 支持）

---

## 七、调试工具

### Wireshark 过滤器

```
# 只显示 UDP 1234 端口
udp.port == 1234

# 显示来自 FPGA 的包
ip.src == 192.168.1.2

# 显示 Payload 长度为 32 bytes 的包
data.len == 32
```

### Python 调试脚本

```python
import socket

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(('0.0.0.0', 1234))

data, addr = sock.recvfrom(4096)
print(f"收到 {len(data)} bytes 来自 {addr}")
print(f"前 64 bytes (hex): {data[:64].hex()}")

# 提取 Payload
payload = data[-32:]
print(f"Payload (32 bytes): {payload.hex()}")

# 检查 Panel 0 是否全为 0
panel0 = payload[0:16]
if all(b == 0 for b in panel0):
    print("✅ Panel 0 全为 0（正确）")
else:
    print("❌ Panel 0 不全为 0（异常）")

# 检查 Panel 1 是否有数据
panel1 = payload[16:32]
if any(b != 0 for b in panel1):
    print("✅ Panel 1 有数据（正确）")
else:
    print("❌ Panel 1 全为 0（可能异常）")
```

---

**文档版本**: v1.1  
**更新时间**: 2026-07-27  
**适用于**: Panel 2 单通道测试模式

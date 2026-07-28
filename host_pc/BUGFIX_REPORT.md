# AD71143 上位机程序 Bug 修复报告

## 🔴 **发现的严重问题**

### **问题 1：数据格式理解完全错误**

#### **错误的理解（原 data_parser.py 和 README.md）：**
```python
# 错误：认为每个 burst 包含 64 个 4-bit 像素
BITS_PER_PIXEL = 4          # 每像素位数
PIXELS_PER_BURST = 64       # 每个 burst 包含的像素数
```

#### **实际的 FPGA 数据格式：**
```verilog
// ad71143_data_rx.v
localparam integer DATA_BURSTS = 64;    // 单LVDS: 256ch * 16bit / (4 samples/burst)
```

**每个 burst（32 字节）实际包含：**
- Panel 0: 16 字节 = **8 个 16-bit 样本**（不是 32 个 4-bit 像素！）
- Panel 1: 16 字节 = **8 个 16-bit 样本**
- 总共：**8 个 16-bit 样本**（不是 64 个 4-bit 像素！）

---

### **问题 2：图像分辨率计算错误**

#### **错误的参数（原 README.md）：**
```
分辨率: 1024 × 541 (Panel0: 512px + Panel1: 512px)
每像素: 4 bits (0-15)
每行: 16 bursts (1024 / 64 = 16)
每帧: 541 × 16 = 8656 个数据包
```

#### **实际的 FPGA 配置：**
```
分辨率: 512 × 541 (Panel0: 256ch + Panel1: 256ch)
每样本: 16 bits (0-65535)
每行: 64 bursts (256 / 4 = 64)
每帧: 541 × 64 = 34,624 个数据包
```

**错误导致的后果：**
- ❌ 期待 8,656 个包/帧，实际 FPGA 发送 34,624 个包/帧
- ❌ 期待 16 个 burst/行，实际需要 64 个 burst/行
- ❌ 期待 4-bit 像素，实际是 16-bit 样本
- ❌ 图像重建算法完全错误，无法正确解析数据

---

### **问题 3：字节序解析错误**

#### **错误的实现（原 data_parser.py，第 122-128 行）：**
```python
def extract_pixels_from_panel(panel_bytes: bytes) -> np.ndarray:
    pixels = []
    for byte in panel_bytes:
        # 高4位是第一个像素，低4位是第二个像素
        pixel_high = (byte >> 4) & 0x0F
        pixel_low = byte & 0x0F
        pixels.append(pixel_high)
        pixels.append(pixel_low)
    return np.array(pixels, dtype=np.uint8)
```

这段代码认为每个字节包含 2 个 4-bit 像素，但实际上：
- FPGA 输出的是 **16-bit 样本**（大端序）
- 每 2 个字节组成 1 个样本

#### **正确的实现：**
```python
def extract_samples_from_panel(panel_bytes: bytes) -> np.ndarray:
    samples = []
    for i in range(0, 16, 2):
        # 大端序：高字节在前
        sample = struct.unpack('>H', panel_bytes[i:i+2])[0]
        samples.append(sample)
    return np.array(samples, dtype=np.uint16)
```

---

### **问题 4：帧缓冲区数据类型错误**

#### **错误：**
```python
self.frame_buffer = np.zeros(
    (self.config.FRAME_LINES, self.config.PIXELS_PER_LINE),
    dtype=np.uint8  # 错误：uint8 只能存储 0-255
)
```

#### **正确：**
```python
self.frame_buffer = np.zeros(
    (self.config.FRAME_LINES, self.config.PIXELS_PER_LINE),
    dtype=np.uint16  # 正确：uint16 可以存储 0-65535
)
```

---

## ✅ **修复方案**

### **1. 更新配置参数**

```python
@dataclass
class ImageConfig:
    """图像配置参数（修复版本）"""
    FRAME_LINES = 541           # 每帧行数
    CHANNELS_PER_PANEL = 256    # 每个 Panel 的通道数（单 LVDS 模式）
    PANELS = 2                  # Panel 数量
    PIXELS_PER_LINE = 512       # 每行像素数 = 256 × 2
    BURST_BYTES = 32            # 每个 burst 字节数
    BITS_PER_SAMPLE = 16        # 每样本位数
    SAMPLES_PER_BURST_PER_PANEL = 4  # 每个 Panel 每个 burst 的样本数
    SAMPLES_PER_BURST = 8       # 总样本数 = 4 × 2
    BURSTS_PER_LINE = 64        # 每行需要的 burst 数 (256 / 4 = 64)
```

### **2. 修复样本提取函数**

```python
def extract_samples_from_burst(self, burst_data: bytes) -> np.ndarray:
    """
    从 burst 数据中提取样本值（修复版本）
    
    burst_data[31:0] = {Panel1[15:0], Panel0[15:0]}
    每个 Panel: 16 bytes = 8 个 16-bit 样本（大端序）
    """
    if len(burst_data) != 32:
        raise ValueError(f"Invalid burst data length: {len(burst_data)}")

    # Panel 0: bytes[15:0]
    panel0_data = burst_data[0:16]
    # Panel 1: bytes[31:16]
    panel1_data = burst_data[16:32]

    def extract_samples_from_panel(panel_bytes: bytes) -> np.ndarray:
        samples = []
        for i in range(0, 16, 2):
            # 大端序：高字节在前
            sample = struct.unpack('>H', panel_bytes[i:i+2])[0]
            samples.append(sample)
        return np.array(samples, dtype=np.uint16)

    panel0_samples = extract_samples_from_panel(panel0_data)
    panel1_samples = extract_samples_from_panel(panel1_data)

    # 拼接两个 Panel 的样本
    all_samples = np.concatenate([panel0_samples, panel1_samples])
    return all_samples
```

### **3. 修复归一化函数**

```python
@staticmethod
def normalize_image(frame: np.ndarray) -> np.ndarray:
    """
    归一化图像到 0-255 范围（修复版本）
    
    原始数据是 16bit (0-65535)，需要映射到 0-255
    使用自适应归一化以增强对比度
    """
    # 计算有效范围（排除异常值）
    min_val = np.percentile(frame, 1)  # 1% 分位数
    max_val = np.percentile(frame, 99)  # 99% 分位数

    if max_val > min_val:
        normalized = np.clip(
            (frame.astype(np.float32) - min_val) / (max_val - min_val) * 255.0, 
            0, 255
        )
    else:
        normalized = np.zeros_like(frame, dtype=np.float32)

    return normalized.astype(np.uint8)
```

---

## 📋 **实施步骤**

### **方法 1：使用修复后的文件（推荐）**

1. 备份原文件：
```bash
cd host_pc
cp data_parser.py data_parser_backup.py
```

2. 使用修复版本：
```bash
cp data_parser_fixed.py data_parser.py
```

3. 重新运行程序：
```bash
python main.py
```

### **方法 2：手动修改**

按照上述修复方案，手动修改 `data_parser.py` 中的：
1. `ImageConfig` 类的参数
2. `extract_pixels_from_burst()` → `extract_samples_from_burst()`
3. `normalize_image()` 函数
4. `frame_buffer` 的数据类型

---

## 🧪 **验证方法**

### **1. 检查接收统计**

运行修复后的程序，观察统计信息：
- **每帧包数**：应该收到约 **34,624 个包**（541行 × 64 burst）
- **丢包率**：应该 < 1%
- **帧率**：约 12 fps（基于当前 LINE_CYCLES = 15000 配置）

### **2. 检查图像显示**

- 图像分辨率应该是：**512 × 541**
- 在暗处：图像应该接近全黑（暗电流）
- 照光后：图像应该有明显的亮度变化

### **3. 检查原始数据**

保存一帧原始数据并检查：
```python
import numpy as np
frame = np.load('frame_raw_YYYYMMDD_HHMMSS.npy')
print(f"Shape: {frame.shape}")  # 应该是 (541, 512)
print(f"Dtype: {frame.dtype}")  # 应该是 uint16
print(f"Min: {frame.min()}, Max: {frame.max()}")  # 应该在 0-65535 范围内
```

---

## 📊 **性能对比**

### **修复前（错误配置）：**
- 期待包数/帧：8,656
- 实际包数/帧：34,624
- **结果**：帧永远无法完成（只完成 25%）

### **修复后（正确配置）：**
- 期待包数/帧：34,624
- 实际包数/帧：34,624
- **结果**：帧可以正常完成

---

## ⚠️ **注意事项**

1. **字节序**：FPGA 输出是**大端序**（MSB first），务必使用 `'>H'` 解析
2. **数据类型**：必须使用 `np.uint16` 存储 16-bit 样本
3. **burst 数量**：每行 64 个 burst，不是 16 个
4. **分辨率**：512 × 541，不是 1024 × 541

---

## 🎯 **后续优化建议**

### **1. 添加帧同步机制**
当前实现是顺序接收，没有帧同步。建议：
- 识别 header burst（第一个 burst，应该包含 0x0A）
- 基于 header 重置帧缓冲区
- 添加帧序号检测

### **2. 优化内存使用**
- 当前使用完整的 uint16 缓冲区，内存占用较大
- 可以考虑使用滚动缓冲区或压缩存储

### **3. 添加实时统计**
- 每行接收时间
- burst 接收间隔
- 丢包位置分析

---

## 📝 **总结**

上位机程序的核心问题是**对 FPGA 数据格式的理解完全错误**：

| 项目 | 错误理解 | 实际情况 |
|------|---------|---------|
| 每像素位数 | 4 bits | 16 bits |
| 每 burst 像素数 | 64 | 8 (样本) |
| 每行 burst 数 | 16 | 64 |
| 每帧包数 | 8,656 | 34,624 |
| 图像宽度 | 1024 | 512 |
| 数据类型 | uint8 | uint16 |

**修复后，程序应该能够正确接收和显示 AD71143 的图像数据。**

---

**创建时间**：2026-07-28  
**修复文件**：`data_parser_fixed.py`  
**测试状态**：待验证

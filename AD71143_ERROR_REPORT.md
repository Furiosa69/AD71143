# AD71143 系统错误报告

## 现象
- 上位机显示：黑屏、偶尔白色噪点
- 对光源无响应（照射TFT板，图像无变化）

## 根本原因分析

### 🔴 **致命错误1: 数据通道数错误**

**位置**: `ad71143_data_rx.v` + `panel2_receiver.py`

**问题**: 
- 硬件实际输出：每个burst **4个通道**（单LVDS模式，64位有效数据）
- 上位机期望：每个burst **4个通道** ✓（已修复）
- 但之前的代码认为是8个通道

**已修复**:
- ✅ ad71143_data_rx.v: 移除数据重复，输出 `{4通道, 64'b0}`
- ✅ panel2_receiver.py: `CHANNELS_PER_BURST = 4`, `PIXELS_PER_LINE = 260`

---

### 🔴 **致命错误2: Panel数据位置错误**

**位置**: `ad71143_data_rx_dual.v:233`

```verilog
merged_burst <= {panel1_hold, 128'd0};  // Panel 1在高128位，Panel 0填充0
```

**问题**: 
- Panel 1（有数据）在 **高128位** = `merged_burst[255:128]`
- Panel 0（填充0）在 **低128位** = `merged_burst[127:0]`

**RGMII打包** (rgmii_bridge.v:317):
```verilog
// MSB first: i=0 取 [255:248], i=1 取 [247:240] ...
frame_buf[42+i] <= fifo_dout[(31-i)*8 +: 8];
```

**UDP Payload字节序**:
```
Byte 42 = merged_burst[255:248]  // Panel 1 最高字节
Byte 43 = merged_burst[247:240]
...
Byte 57 = merged_burst[128:121]  // Panel 1 最低字节
Byte 58 = merged_burst[127:120]  // Panel 0 (全0)
...
Byte 73 = merged_burst[7:0]      // Panel 0 (全0)
```

**上位机解析** (panel2_receiver.py:120):
```python
panel1_data = payload[0:16]  # bytes 0-15 = UDP payload的前16字节
```

**但实际UDP payload**:
- `payload = data[-32:]`  # 取最后32字节
- 对应 frame_buf[42:73]
- 所以 `payload[0:16]` = frame_buf[42:57] = Panel 1数据 ✓

**看起来对齐是正确的！但让我检查是否有其他问题...**

---

### 🔴 **致命错误3: 通道数量与上位机不匹配**

**上位机当前配置**:
```python
self.CHANNELS_PER_BURST = 4       # 每个 Burst 4 个通道
self.BURSTS_PER_LINE = 65         # 每行 65 个 Bursts
self.PIXELS_PER_LINE = 260        # 4×65=260
```

**但硬件实际输出**:
```verilog
// ad71143_data_rx.v
merged_burst_next = {
    a_word0,  // [127:112] 通道0
    a_word1,  // [111:96]  通道1
    a_word2,  // [95:80]   通道2
    a_word3,  // [79:64]   通道3
    64'd0     // [63:0]    填充0
};
```

每个Panel的128位输出：
- 高64位 = 4个通道 × 16位
- 低64位 = 0

**UDP打包后**:
```
bytes[42:49]  = Panel 1 的 4个通道 (8字节)
bytes[50:57]  = Panel 1 的填充0 (8字节)
bytes[58:65]  = Panel 0 的填充0 (8字节)
bytes[66:73]  = Panel 0 的填充0 (8字节)
```

**上位机解析** (panel2_receiver.py:120-129):
```python
panel1_data = payload[0:16]  # 取16字节
for i in range(4):  # 解析4个通道
    offset = i * 2
    value = struct.unpack('>H', panel1_data[offset:offset+2])[0]
```

解析顺序：
- `i=0`: `panel1_data[0:2]` = bytes[42:43] ✓ 通道0
- `i=1`: `panel1_data[2:4]` = bytes[44:45] ✓ 通道1  
- `i=2`: `panel1_data[4:6]` = bytes[46:47] ✓ 通道2
- `i=3`: `panel1_data[6:8]` = bytes[48:49] ✓ 通道3

**这部分是正确的！**

---

### 🔴 **致命错误4: SPI配置可能有问题**

**位置**: `top.v:528-543`

检查AD71143 SPI寄存器配置：

```verilog
// Reg1: DM=1(单LVDS), bit4应该是DOUTMODE位，不是单通道使能
10'h0B0  // bit7-4=1011 = DM=1, LPF=01, CDS2_RESETEN=1
```

**问题**: 根据AD71143数据手册：
- Reg1[7] = DM (DOUT Mode): 1=单LVDS
- Reg2[1] = DOUTMODE: 1=DDR模式

当前配置Reg2=0x027 = `0000100111`:
- bit[1] DOUTMODE = 1 ✓
- bit[0] Pipeline = 1 ✓

**这部分配置看起来正确。**

---

### 🔴 **致命错误5: 数据有效性检查**

**问题**: 从"偶尔有白色噪点"判断，说明：
1. 数据通路是通的（能收到数据包）
2. 但数据内容全是0或随机值
3. ADC可能没有正确采样光信号

**可能原因**:
1. **ACLK时序问题** - CDS采样时序不对
2. **SYNC时序问题** - 行同步信号延迟
3. **LVDS数据未正确接收** - 时钟相位问题
4. **AD71143未正确初始化** - SPI配置延迟不足

---

## 需要修复的问题

### ✅ 已修复
1. ad71143_data_rx.v - 数据重复问题
2. panel2_receiver.py - 通道数和像素数

### ⚠️ 需要验证

#### 1. **Top.v ILA探针信号错误**

**位置**: `top.v:980-987, 999`

```verilog
// 错误的信号名
init_done,             // 应该是 ctrl_init_done
line_start,            // 应该是 ctrl_line_start  
line_done,             // 应该是 ctrl_line_done
dbg_p0_merged_valid,   // 未定义，应改为 1'b0
dbg_p1_burst_index,    // 未定义，应改为 merged_burst_index
```

#### 2. **检查LVDS时钟相位**

**位置**: `ad71143_data_rx.v:97-100`

```verilog
always @(negedge clk_sys) begin
    dout_a_mid <= dout_a_i;  // 下降沿采样
end
```

然后在上升沿使用：
```verilog
always @(posedge dclko_i) begin
    lane_a_shift <= {lane_a_shift[62:0], dout_a_i};  // 直接用dout_a_i
end
```

**问题**: 应该使用`dout_a_mid`（下降沿采样的稳定值），而不是`dout_a_i`（组合逻辑）

#### 3. **SPI配置延迟**

**位置**: `top.v:493`

```verilog
localparam CFG_DELAY = 28'd100_000_000;  // 1s @ 100MHz
```

**建议**: 延迟时间足够，但检查是否真的等待了这么久才开始采集

#### 4. **SYNC信号时序**

**位置**: `top.v:777`

```verilog
.sync_in(line_start_pulse),  // 使用line_start_pulse作为SYNC
```

**问题**: `line_start_pulse`是从50MHz域CDC过来的，可能有延迟。应该检查：
- line_start_pulse 与 aclk 的时序关系
- SYNC应该在ACLK前拉低

---

## 建议的调试步骤

### Step 1: 验证数据通路
```python
# 在panel2_receiver.py中添加调试输出
def parse_packet(self, data):
    payload = data[-32:]
    print(f"Payload hex: {payload.hex()}")
    
    # 检查是否全0
    if all(b == 0 for b in payload):
        print("WARNING: All payload bytes are 0!")
    
    # 检查Panel 1数据
    panel1_data = payload[0:16]
    print(f"Panel1 hex: {panel1_data.hex()}")
```

### Step 2: 使用ILA查看FPGA内部信号

**需要监测**:
1. `merged_valid` - 是否产生数据
2. `merged_burst[127:64]` - Panel 1的实际数据值
3. `aclk_done` - ACLK序列是否完成
4. `dbg_p1_header_ok` - Header是否正确
5. `cfg_all_done` - SPI配置是否完成

### Step 3: 修复top.v的信号错误

### Step 4: 检查LVDS采样时钟相位

修改 `ad71143_data_rx.v:317`:
```verilog
lane_a_shift <= {lane_a_shift[62:0], dout_a_mid};  // 使用下降沿采样的值
```

---

## 最可能的问题

基于"黑屏+白噪点+不响应光源"的现象，**最可能的原因是**:

1. ✅ **数据格式错误** - 已修复（通道数问题）
2. 🔴 **AD71143未真正采样** - ACLK/SYNC时序不对，或SPI配置错误
3. 🟡 **LVDS数据相位错误** - 时钟边沿采样不正确

**建议优先检查**: 使用ILA看FPGA内部`merged_burst`的值是否为全0。如果是全0，说明AD71143没有输出数据，需要检查SPI配置和控制时序。

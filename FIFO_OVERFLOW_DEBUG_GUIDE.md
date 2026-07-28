# FIFO溢出检测修改指南

## 目的
检测RGMII Bridge中的FIFO是否溢出导致数据丢失

## 已完成的修改

### ✅ 修改1: rgmii_bridge.v
已添加FIFO状态调试输出：
- `dbg_fifo_full` - FIFO满标志
- `dbg_fifo_empty` - FIFO空标志

### ✅ 修改2: top.v 
已添加信号定义并连接到rgmii_bridge模块

## 需要手动完成的修改

### 修改3: 更新ILA IP核配置

**方法1: 在Vivado中重新配置ILA IP（推荐）**

1. 在Vivado中打开IP Catalog
2. 找到已实例化的 `ila_1` IP
3. 双击打开配置界面
4. 增加探针数量：
   - 当前：probe0 到 probe8（9个探针）
   - 修改为：probe0 到 probe9（10个探针）
5. 配置新探针probe9:
   - Width: 8 bits
   - Name: RGMII_FIFO_Debug
6. 点击OK，重新生成IP

7. 然后在 `top.v` 的ILA实例化部分（约1025行）添加：

```verilog
    .probe8(dbg_p1_lane_a_shift),
    
    // probe9 [7:0]: RGMII + FIFO 调试信号 - 新增
    .probe9 ({
        rgmii_dbg_fifo_full,   // [7] FIFO满 - 关键信号！
        rgmii_dbg_fifo_empty,  // [6] FIFO空
        rgmii_dbg_tx_send,     // [5] RGMII发送中
        rgmii_dbg_startup,     // [4] 启动完成
        rgmii_dbg_crc_busy,    // [3] CRC计算中
        rgmii_dbg_crc_done_r,  // [2] CRC完成
        rgmii_dbg_tx_fsm[1:0]  // [1:0] RGMII_tx FSM状态
    })
);
```

**方法2: 如果ILA探针已满，复用现有探针**

如果ILA已经达到最大探针数，可以修改probe7，牺牲一些不太重要的信号：

在 `top.v` 约1016行，修改probe7为：

```verilog
    // probe7 [7:0]: FIFO状态 + 关键调试信号（修改）
    .probe7 ({
        rgmii_dbg_fifo_full,   // [7] FIFO满 - 最关键！
        rgmii_dbg_fifo_empty,  // [6] FIFO空
        rgmii_dbg_tx_send,     // [5] RGMII发送中
        aclk_int,              // [4] ACLK信号
        dbg_p1_burst_en,       // [3] Panel 1 burst 使能
        dbg_p1_header_ok,      // [2] Panel 1 header 正确
        dbg_p1_line_done,      // [1] Panel 1 行完成
        merged_valid           // [0] 合并数据有效
    }),
```

---

## 修改4: 降低帧率以缓解FIFO压力（可选但建议）

**文件**: `top.v` 第9行

**当前配置**:
```verilog
parameter integer FRAME_GAP_CYCLES = 250000,  // 5ms @ 50MHz = 200fps
```

**修改为**（降低到20fps进行测试）:
```verilog
parameter integer FRAME_GAP_CYCLES = 2500000,  // 50ms @ 50MHz = 20fps
```

这样可以降低80%的数据率，如果FIFO溢出问题消失，就确认了是带宽问题。

---

## 修改5: 增加上位机接收缓冲区

**文件**: `host_pc/panel2_receiver.py` 第74行

**当前配置**:
```python
self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 2*1024*1024)  # 2MB
```

**修改为**:
```python
self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 10*1024*1024)  # 10MB
```

---

## 修改6: 添加上位机丢包统计

**文件**: `host_pc/panel2_receiver.py`

在 `receive_loop` 函数中添加统计输出（约244行附近）:

```python
# 定期打印统计信息
current_time = time.time()
if current_time - self.last_stats_time >= self.stats_interval:
    if not callback:  # 如果没有回调，才打印统计
        stats = self.get_stats()
        self.print_stats(stats)
        
        # === 新增：计算丢包率 ===
        expected_packets = self.frames_completed * self.LINES_PER_FRAME * self.BURSTS_PER_LINE
        if expected_packets > 0:
            loss_rate = (expected_packets - self.packets_received) / expected_packets * 100
            print(f"\n[丢包率] {loss_rate:.2f}% ({expected_packets - self.packets_received}/{expected_packets})")
        # === 新增结束 ===
        
    self.last_stats_time = current_time
```

---

## 编译和测试步骤

### Step 1: 编译FPGA
1. 在Vivado中打开项目
2. 点击 "Generate Bitstream"
3. 等待编译完成

### Step 2: 烧录FPGA
1. 连接FPGA板
2. 打开Hardware Manager
3. 烧录新的比特流

### Step 3: 使用ILA捕获波形

**关键信号监测**:

1. **触发条件设置**:
   ```
   Trigger: rgmii_dbg_fifo_full == 1
   或者
   Trigger: merged_valid == 1 (捕获正常工作状态)
   ```

2. **观察以下信号**:
   - `probe9[7]` 或 `probe7[7]`: **rgmii_dbg_fifo_full**
     - 如果经常为1 → **确认是FIFO溢出！**
     - 如果一直为0 → FIFO正常，问题在别处
   
   - `probe9[6]` 或 `probe7[6]`: **rgmii_dbg_fifo_empty**
     - 如果一直为1 → AFE没产生数据
     - 如果正常跳变 → AFE数据产生正常
   
   - `probe0[0]`: **merged_valid**
     - 应该周期性产生脉冲
     - 每行65次，每帧35,165次
   
   - `probe9[5]` 或 `probe7[5]`: **rgmii_dbg_tx_send**
     - 应该周期性为1（正在发送）
     - 如果一直为0 → RGMII发送有问题

3. **波形分析**:

   **情况A: FIFO溢出**
   ```
   merged_valid:  __|‾|__|‾|__|‾|__|‾|__|‾|__  (持续产生)
   fifo_full:     __|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|__  (长时间为1)
   tx_send:       __|‾|__|‾|__|‾|__________|  (发送跟不上)
   ```
   **诊断**: RGMII发送太慢，需要增大FIFO或降低帧率

   **情况B: FIFO正常**
   ```
   merged_valid:  __|‾|__|‾|__|‾|__|‾|__|‾|__  (持续产生)
   fifo_full:     ___________________________  (一直为0)
   fifo_empty:    ‾‾|__|‾|__|‾|__|‾|__|‾‾‾‾‾‾  (正常跳变)
   tx_send:       __|‾|__|‾|__|‾|__|‾|__|‾|__  (正常发送)
   ```
   **诊断**: FIFO和RGMII工作正常，问题在上位机或网络

   **情况C: AFE无数据**
   ```
   merged_valid:  ___________________________  (无脉冲)
   fifo_empty:    ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾  (一直为1)
   tx_send:       ___________________________  (无发送)
   ```
   **诊断**: AD71143未产生数据，检查SPI配置和控制时序

### Step 4: 运行上位机测试

```bash
cd host_pc
python panel2_receiver.py
```

观察输出：
- 丢包率应该显示在统计信息中
- 如果丢包率 > 50% → 严重问题
- 如果丢包率 < 10% → 可接受范围

---

## 根据ILA结果的修复方案

### 如果确认是FIFO溢出：

#### 方案1: 增大FIFO深度（最有效）

1. 在Vivado IP Catalog中打开 `fifo_generator_0`
2. 修改FIFO深度：
   - 当前可能是：16或32
   - 修改为：512或1024
3. 重新生成IP
4. 重新编译、烧录

#### 方案2: 降低AFE数据率

永久降低到20fps:
```verilog
// top.v 第9行
parameter integer FRAME_GAP_CYCLES = 2500000,  // 50ms @ 50MHz
```

#### 方案3: 减少每行发送的burst数（临时测试）

修改 `ad71143_data_rx_dual.v`，只发送偶数burst:

```verilog
// 约232行，在merged_valid赋值前添加
if (p1_burst_index[0] == 1'b0) begin  // 只发送偶数索引
    merged_burst       <= {panel1_hold, 128'd0};
    merged_burst_index <= p1_burst_index;
    merged_valid       <= 1'b1;
    // ... 其余代码
end
```

这样数据率减半，可验证是否带宽问题。

### 如果FIFO正常但仍然丢包：

检查：
1. 网线质量（建议用Cat6或更好）
2. 网络交换机性能
3. 上位机CPU负载
4. 防火墙设置

---

## 预期结果

**修复前（FIFO溢出）**:
- ILA显示: `fifo_full`经常为1
- 上位机: 丢包率 > 90%
- 图像: 黑屏+稀疏白点

**修复后（FIFO正常）**:
- ILA显示: `fifo_full`一直为0或偶尔短暂为1
- 上位机: 丢包率 < 5%
- 图像: 完整的静态噪点纹理（LFSR模式）

---

## 总结

**必须完成的修改**:
1. ✅ rgmii_bridge.v - 已完成
2. ✅ top.v 信号定义 - 已完成
3. ⚠️ ILA探针配置 - 需手动修改
4. ⚠️ top.v ILA实例化 - 需手动添加probe9

**建议完成的修改**:
5. 降低帧率 - `FRAME_GAP_CYCLES = 2500000`
6. 增加上位机缓冲区 - `SO_RCVBUF = 10MB`
7. 添加丢包统计 - panel2_receiver.py

完成这些修改后重新编译，使用ILA捕获波形即可确认是否是FIFO溢出问题。

# AD71143 数据链路测试方案

**目的**: 通过发送已知的测试图像，验证 FPGA → 网络 → 上位机的完整数据链路是否正常工作

**日期**: 2026-07-28

---

## 🎯 **测试目标**

通过这个测试，我们可以确定问题出在哪里：

1. ✅ **如果测试图像正确显示** → FPGA 数据传输和上位机解析都正常，问题在 AD71143 传感器
2. ❌ **如果测试图像显示错误** → 问题在数据传输链路或上位机解析
3. ❌ **如果无法接收到数据** → 问题在 FPGA 网络传输

---

## 📝 **方案 1：最简单的测试（推荐）**

### **使用 RGMII Bridge 的现有测试模式**

RGMII Bridge 已经有内置的测试模式，可以直接使用。

#### **步骤 1：修改 top.v 启用测试模式**

```verilog
// top.v 第 889 行
rgmii_bridge #(
    .TEST_MODE     (1),           // 启用测试模式：1=生成测试数据
    .TEST_INTERVAL (10000)
) u_rgmii_bridge (
```

**测试数据格式**（参考 `rgmii_bridge.v` 第 319-324 行）：
```verilog
// Payload[0:3] = 32-bit 序号（每包递增）
// Payload[4:31] = 递增字节 (04 05 06 07 ... 1F)
frame_buf[HDR_BYTES + 0] <= test_seq_num[31:24];
frame_buf[HDR_BYTES + 1] <= test_seq_num[23:16];
frame_buf[HDR_BYTES + 2] <= test_seq_num[15: 8];
frame_buf[HDR_BYTES + 3] <= test_seq_num[ 7: 0];
for (i = 4; i < BURST_BYTES; i = i + 1) begin
    frame_buf[HDR_BYTES + i] <= i[7:0];  // 04 05 06 ... 1F
end
```

#### **步骤 2：重新综合并烧录**

```bash
# 在 Vivado 中
1. Run Synthesis
2. Run Implementation
3. Generate Bitstream
4. Program Device
```

#### **步骤 3：运行上位机验证**

```bash
cd host_pc
python main.py
```

**预期结果**：
- 在 Wireshark 中应该看到规律的测试数据：
  ```
  包1: 00 00 00 00 04 05 06 07 ... 1F
  包2: 00 00 00 01 04 05 06 07 ... 1F
  包3: 00 00 00 02 04 05 06 07 ... 1F
  ...
  ```

- 上位机应该能接收并解析数据
- 图像应该显示出规律的模式

---

## 📝 **方案 2：自定义测试图像（更直观）**

### **生成水平渐变测试图像**

这个方案会生成一个从上到下逐渐变亮的渐变图像，非常容易验证。

#### **实现方式：在 top.v 中注入测试数据**

在 `top.v` 中添加测试数据生成逻辑，在 RGMII Bridge 之前注入：

```verilog
// =========================================================================
// 测试模式：生成水平渐变测试图像
// =========================================================================
wire [255:0] test_data_burst;
wire         test_data_valid;
reg  [9:0]   test_line_cnt;
reg  [6:0]   test_burst_cnt;
reg          test_frame_active;

// 测试数据生成器
always @(posedge clk_100m or negedge rst_n_100m) begin
    if (!rst_n_100m) begin
        test_line_cnt    <= 10'd0;
        test_burst_cnt   <= 7'd0;
        test_frame_active <= 1'b0;
        test_data_valid   <= 1'b0;
    end else begin
        test_data_valid <= 1'b0;

        if (DATA_TEST_MODE) begin
            // 测试模式启用
            if (frame_start_100m && !test_frame_active) begin
                test_frame_active <= 1'b1;
                test_line_cnt     <= 10'd0;
                test_burst_cnt    <= 7'd0;
            end

            if (test_frame_active) begin
                // 生成测试数据：每行像素值 = 行号
                // 8 个样本，每个 16-bit，值都等于行号
                test_data_burst <= {
                    {6'd0, test_line_cnt},  // 样本 7 (Panel 1)
                    {6'd0, test_line_cnt},  // 样本 6
                    {6'd0, test_line_cnt},  // 样本 5
                    {6'd0, test_line_cnt},  // 样本 4
                    {6'd0, test_line_cnt},  // 样本 3 (Panel 0)
                    {6'd0, test_line_cnt},  // 样本 2
                    {6'd0, test_line_cnt},  // 样本 1
                    {6'd0, test_line_cnt}   // 样本 0
                };
                test_data_valid <= 1'b1;

                // 更新计数器
                if (test_burst_cnt < 7'd63) begin
                    test_burst_cnt <= test_burst_cnt + 7'd1;
                end else begin
                    test_burst_cnt <= 7'd0;
                    if (test_line_cnt < FRAME_LINES - 1) begin
                        test_line_cnt <= test_line_cnt + 10'd1;
                    end else begin
                        test_frame_active <= 1'b0;
                        test_line_cnt     <= 10'd0;
                    end
                end
            end
        end
    end
end

// 选择真实数据或测试数据
wire [255:0] final_data_burst = DATA_TEST_MODE ? test_data_burst : merged_burst;
wire         final_data_valid = DATA_TEST_MODE ? test_data_valid : merged_valid;

// RGMII Bridge - 使用选择后的数据
rgmii_bridge #(
    .TEST_MODE     (0),           // 禁用 RGMII 内部测试模式
    .TEST_INTERVAL (10000)
) u_rgmii_bridge (
    .rst_n      (pll_locked  ),
    .clk_100m   (clk_100m    ),
    .clk_125m   (clk_125m    ),
    .clk_125m_ph90 (clk_125m_ph90),
    .data_in    (final_data_burst),  // 使用选择后的数据
    .data_valid (final_data_valid),  // 使用选择后的 valid
    .TXC        (rgmii_txc   ),
    .TX_CTL     (rgmii_tx_ctl),
    ...
```

**预期图像**：
- 顶部（第 0 行）：全黑
- 中间（第 270 行）：中等亮度
- 底部（第 540 行）：最亮

---

## 📝 **方案 3：使用 ILA 验证（最可靠）**

### **不修改任何代码，直接用 ILA 查看数据**

这个方案可以在不重新综合的情况下验证数据内容。

#### **步骤 1：在 ILA 中查看当前数据**

触发条件：
```
merged_valid == 1
```

观察信号：
```
merged_burst[255:0]
merged_burst_index[6:0]
dbg_p1_shift_hi[7:0]
dbg_p1_shift_lo[7:0]
```

#### **步骤 2：手动分析第一个 burst**

第一个 burst（burst_index = 0）应该是 header burst：
- `dbg_p1_shift_hi[7:0]` = 0x0A（header 标识）

后续 burst（burst_index = 1-64）应该是数据：
- 检查 `merged_burst` 的值是否有变化
- 给传感器照光，观察数值是否增大

---

## 🎯 **推荐实施顺序**

### **第一步：使用方案 1（RGMII 测试模式）**

**优点**：
- ✅ 最简单，只需改一行代码
- ✅ 测试数据有规律，容易识别
- ✅ 可以验证网络传输和上位机解析

**实施**：
```verilog
// top.v 第 889 行
.TEST_MODE     (1),  // 改为 1
```

**验证**：
- Wireshark 应该看到规律的递增序号
- 上位机应该能接收到数据

### **第二步：如果方案 1 成功，使用方案 2（自定义测试图像）**

**优点**：
- ✅ 生成直观的渐变图像
- ✅ 更容易验证图像重建算法
- ✅ 可以精确定位数据错位问题

**实施**：
需要在 `top.v` 中添加上述测试数据生成代码

**验证**：
- 上位机显示的图像应该是从上到下的渐变
- 可以通过肉眼直接判断是否正确

### **第三步：如果前两步都失败，使用方案 3（ILA 分析）**

**优点**：
- ✅ 不需要重新综合
- ✅ 可以实时观察数据
- ✅ 可以精确定位问题位置

**实施**：
使用 Vivado Hardware Manager 打开 ILA

---

## 📊 **预期测试结果**

### **场景 1：测试图像正确显示**

**结论**：✅ 数据链路正常，问题在 AD71143 传感器

**下一步**：
1. 检查 AD71143 供电和偏置
2. 给传感器照光测试
3. 检查 LVDS 信号质量
4. 验证 SPI 配置寄存器

### **场景 2：测试图像部分正确**

**结论**：⚠️ 数据链路部分工作，可能有丢包或解析错误

**下一步**：
1. 检查 Wireshark 中的丢包率
2. 检查上位机解析逻辑（字节序、数据类型）
3. 检查 FIFO 是否溢出（`fifo_full` 信号）

### **场景 3：完全无法接收数据**

**结论**：❌ 网络传输失败

**下一步**：
1. 检查网线连接
2. 检查 PC 网卡 IP 配置
3. 检查 FPGA MDIO link_up 信号
4. 使用 Wireshark 查看是否有任何 UDP 包

### **场景 4：接收到数据但图像混乱**

**结论**：⚠️ 上位机解析逻辑错误

**下一步**：
1. 确认使用了修复后的 `data_parser.py`
2. 检查数据类型（uint16 vs uint8）
3. 检查字节序（大端 vs 小端）
4. 检查图像尺寸（512×541 vs 1024×541）

---

## 🛠️ **快速实施指南（方案 1）**

### **5 分钟快速测试**

```bash
# 1. 修改 top.v
# 找到第 889 行，改为：
.TEST_MODE     (1),

# 2. 在 Vivado 中重新生成比特流
# Run Synthesis → Run Implementation → Generate Bitstream

# 3. 烧录 FPGA
# Program Device

# 4. 启动上位机
cd host_pc
python main.py

# 5. 在 Wireshark 中验证
# 过滤器: ip.src == 192.168.1.2 && udp.port == 1234
# 查看 payload 是否有规律的递增序号
```

### **预期 Wireshark 数据**

```
包 1: 00 00 00 00 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f ...
包 2: 00 00 00 01 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f ...
包 3: 00 00 00 02 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f ...
...
```

前 4 字节递增，后面固定为 `04 05 06 ... 1F`

---

## 📝 **测试记录模板**

```
测试日期: ___________
测试方案: 方案 1 / 方案 2 / 方案 3
FPGA 配置: TEST_MODE = ___

Wireshark 结果:
[ ] 能收到 UDP 包
[ ] 源 IP = 192.168.1.2
[ ] 端口 = 1234
[ ] Payload 长度 = 32 字节
[ ] Payload 内容：____________________

上位机结果:
[ ] 能启动程序
[ ] 能接收到数据
[ ] 每帧包数 = ___________
[ ] 图像显示：[ ] 正常 / [ ] 异常 / [ ] 无显示

结论:
_______________________________________
_______________________________________

下一步:
_______________________________________
_______________________________________
```

---

## 📚 **参考文件**

1. `board/project_1/project_1.srcs/sources_1/imports/src/top.v` - 顶层模块
2. `board/project_1/project_1.srcs/sources_1/imports/src/rgmii_bridge.v` - 网络桥接
3. `host_pc/data_parser.py` - 上位机数据解析
4. `host_pc/BUGFIX_REPORT.md` - Bug 修复报告
5. `DEBUGGING_SUMMARY_20260728.md` - 完整调试总结

---

**创建时间**: 2026-07-28  
**状态**: 待测试  
**推荐方案**: 方案 1（最简单）

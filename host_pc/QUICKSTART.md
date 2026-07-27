# Panel 2 单通道测试 - 快速启动指南

## 一、硬件准备

### 1. FPGA 端修改完成清单

- [x] `ad71143_data_rx_dual.v` - 修改为只输出 Panel 1 数据
- [x] `nt39565d_ctrl.v` - 修复状态机，移除 XAO_SHUT_S
- [x] ILA 调试配置完成

### 2. 硬件连接

```
[FPGA] ----网线----> [PC 网口]
  
FPGA 端:
  - 网口 LED 应该亮起（表示链路正常）
  - MDIO link_up 信号应该为高（可通过 ILA 查看）

PC 端:
  - 使用千兆网卡（推荐）
  - 网线直连或通过交换机
```

### 3. 编译并下载 FPGA

```
1. Vivado → Generate Bitstream
2. Hardware Manager → Program Device
3. 使用 ILA 验证 NT39 状态机正常工作
```

---

## 二、PC 端配置

### 1. 配置网卡 IP 地址

**Windows 系统**:
```
1. 控制面板 → 网络和共享中心 → 更改适配器设置
2. 右键点击网卡 → 属性
3. 选择 "Internet 协议版本 4 (TCP/IPv4)" → 属性
4. 选择 "使用下面的 IP 地址":
   IP 地址:    192.168.1.1
   子网掩码:   255.255.255.0
   默认网关:   (留空)
5. 点击 确定
```

**Linux 系统**:
```bash
# 方法 1: 使用 ifconfig
sudo ifconfig eth0 192.168.1.1 netmask 255.255.255.0 up

# 方法 2: 使用 ip 命令
sudo ip addr add 192.168.1.1/24 dev eth0
sudo ip link set eth0 up
```

**macOS 系统**:
```
1. 系统偏好设置 → 网络
2. 选择以太网接口
3. 配置 IPv4: 手动
4. IP 地址: 192.168.1.1
5. 子网掩码: 255.255.255.0
6. 点击 应用
```

### 2. 验证网络连接

```bash
# Windows
ping 192.168.1.2

# Linux/macOS
ping -c 4 192.168.1.2
```

**注意**: FPGA 端的 IP 协议栈可能不响应 ping（因为是简化的 UDP 发送器），ping 不通是正常的。关键是网线链路 LED 亮起。

### 3. 配置防火墙

**Windows**:
```powershell
# 临时关闭防火墙（测试用）
netsh advfirewall set allprofiles state off

# 或者添加规则允许 UDP 1234 端口
netsh advfirewall firewall add rule name="AD71143 UDP" dir=in action=allow protocol=UDP localport=1234
```

**Linux**:
```bash
# Ubuntu/Debian
sudo ufw allow 1234/udp

# CentOS/RHEL
sudo firewall-cmd --add-port=1234/udp --permanent
sudo firewall-cmd --reload
```

---

## 三、安装上位机软件

### 1. 安装 Python 依赖

```bash
cd d:\project\AD71143\host_pc

# 创建虚拟环境（推荐）
python -m venv venv

# 激活虚拟环境
# Windows:
venv\Scripts\activate
# Linux/macOS:
source venv/bin/activate

# 安装依赖
pip install numpy opencv-python
```

**所需依赖包**:
- `numpy` - 数值计算
- `opencv-python` - 图像处理和显示

### 2. 验证安装

```python
python -c "import numpy; import cv2; print('OK')"
```

如果输出 `OK`，说明安装成功。

---

## 四、运行上位机软件

### 模式 1: 实时显示窗口（推荐）

```bash
python panel2_receiver.py
```

**功能**:
- 实时显示 Panel 2 图像
- 自动伪彩色映射（JET 色图）
- 显示帧率和统计信息
- 每 10 帧自动保存一次
- 按 'q' 键退出

**预期效果**:
```
[INFO] UDP socket 已绑定到 0.0.0.0:1234
[INFO] 接收缓冲区大小: 2097152 bytes
[INFO] 开始接收数据...
[STATS] 包:   8656 | 帧:    1 | 速率:  10000.0 pps |  20.48 Mbps |  1.15 fps
```

### 模式 2: 简单接收（无 GUI）

```bash
python panel2_receiver.py --simple
```

**功能**:
- 接收 5 帧数据后自动退出
- 保存原始数据（.npy）和图像（.png）
- 适合无显示器的服务器环境

---

## 五、数据查看和分析

### 1. 保存的文件

所有数据保存在 `./captured_frames/` 目录：

```
captured_frames/
├── panel2_raw_20260727_143052_123.npy   # 原始 16 位数据
├── panel2_img_20260727_143052_123.png   # 伪彩色图像
├── panel2_raw_20260727_143053_456.npy
└── panel2_img_20260727_143053_456.png
```

### 2. 离线分析原始数据

```python
import numpy as np
import cv2

# 加载原始数据
frame = np.load('panel2_raw_20260727_143052_123.npy')

# 查看数据信息
print(f"形状: {frame.shape}")        # 应该是 (541, 541)
print(f"数据类型: {frame.dtype}")    # 应该是 uint16
print(f"最小值: {np.min(frame)}")
print(f"最大值: {np.max(frame)}")
print(f"平均值: {np.mean(frame):.2f}")

# 显示直方图
import matplotlib.pyplot as plt
plt.hist(frame.flatten(), bins=100)
plt.xlabel('Pixel Value')
plt.ylabel('Count')
plt.title('Histogram')
plt.show()

# 重新处理并显示
frame_8bit = (frame / 256).astype(np.uint8)
frame_color = cv2.applyColorMap(frame_8bit, cv2.COLORMAP_HOT)
cv2.imshow('Frame', frame_color)
cv2.waitKey(0)
```

### 3. 批量处理

```python
import glob
import numpy as np

# 读取所有原始数据
files = glob.glob('captured_frames/panel2_raw_*.npy')

frames = []
for file in files:
    frame = np.load(file)
    frames.append(frame)

# 计算平均帧
avg_frame = np.mean(frames, axis=0)

# 保存平均帧
np.save('average_frame.npy', avg_frame)
```

---

## 六、预期结果和验证

### 1. 正常工作指标

✅ **网络接收**:
- 每帧接收 35,165 个数据包 (541 行 × 65 Bursts)
- 数据包大小固定（42 字节头 + 256 字节 Payload = 298 字节）
- 包速率: ~6,500 pps (在 185 fps 时)
- 数据速率: ~15 Mbps

✅ **图像质量**:
- 图像尺寸: 541×541
- 图像清晰，无明显条纹
- 像素值分布合理（不全黑或全白）
- 帧间变化平滑（如果是静态场景）

✅ **性能**:
- 帧率: ~185 fps（取决于 FPGA FRAME_GAP_CYCLES）
- CPU 占用: < 30%（单核）
- 内存占用: < 500 MB
- 无丢包或丢包率 < 0.1%

### 2. 图像示例

**正常情况**（假设有光信号输入）:
```
- 图像应显示传感器接收到的光信号
- 使用伪彩色后，不同亮度区域应有明显色彩区分
- 边缘清晰，无明显噪声
```

**异常情况诊断**:

| 现象 | 可能原因 | 解决方法 |
|------|---------|---------|
| 图像全黑 | 1. 传感器无光输入<br>2. AD71143 增益过低 | 1. 检查光源<br>2. 调整 SPI 配置 |
| 图像全白/饱和 | AD71143 增益过高或积分时间过长 | 降低增益或积分时间 |
| 横向条纹 | NT39 时序异常 | 检查 ILA，验证 CPV 周期 |
| 竖向条纹 | LVDS 数据接收异常 | 检查 DCLK、DOUT 信号 |
| 收不到数据 | 网络配置错误 | 检查 IP、端口、防火墙 |
| 帧率低 | 网络拥塞或 FPGA 发送慢 | 检查网卡配置 |

---

## 七、故障排查

### 问题 1: 收不到任何数据包

**检查步骤**:

1. **验证网线连接**
   ```bash
   # Windows
   ipconfig
   # 查看网卡状态，应该显示 "已连接"
   
   # Linux
   ip link show eth0
   # 状态应该是 "UP"
   ```

2. **使用 Wireshark 抓包**
   ```
   - 下载 Wireshark: https://www.wireshark.org/
   - 打开 Wireshark，选择连接 FPGA 的网卡
   - 过滤器输入: udp.port == 1234
   - 点击开始捕获
   - 观察是否有数据包
   ```

3. **检查 FPGA 端**
   ```
   - 使用 ILA 查看 rgmii_bridge 模块
   - 验证 dbg_tx_sending 信号是否有效
   - 验证 TXC、TX_CTL、TXD 是否有数据输出
   ```

### 问题 2: 收到数据包但无法解析

**调试方法**:

```python
# 修改 panel2_receiver.py，添加调试输出
def parse_packet(self, data):
    print(f"Packet length: {len(data)}")
    print(f"First 16 bytes: {data[:16].hex()}")
    
    # ... 原有代码
```

**预期数据包格式**:
```
Bytes 0-5:    FF FF FF FF FF FF (目标 MAC，广播)
Bytes 6-11:   02 00 00 00 00 01 (源 MAC)
Bytes 12-13:  08 00 (EtherType: IPv4)
Bytes 14-33:  (IP 头)
Bytes 34-41:  (UDP 头)
Bytes 42-297: (Payload 256 bytes)
```

### 问题 3: 图像显示但有问题

**调试脚本**:

```python
import numpy as np

# 检查单帧数据
frame = np.load('panel2_raw_xxx.npy')

print(f"形状: {frame.shape}")
print(f"最小值: {np.min(frame)}")
print(f"最大值: {np.max(frame)}")
print(f"均值: {np.mean(frame)}")
print(f"标准差: {np.std(frame)}")

# 检查是否有坏点
zero_count = np.sum(frame == 0)
max_count = np.sum(frame == 65535)
print(f"零值像素: {zero_count} ({zero_count/frame.size*100:.2f}%)")
print(f"饱和像素: {max_count} ({max_count/frame.size*100:.2f}%)")
```

---

## 八、性能优化

### 1. 网络优化

**增加接收缓冲区**:
```python
# 在 panel2_receiver.py 中修改
sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4*1024*1024)  # 4MB
```

**Windows 网卡优化**:
```
设备管理器 → 网络适配器 → 属性 → 高级
- 接收缓冲区: 最大
- 中断调节: 禁用
- 巨帧: 启用（如果支持）
```

### 2. 处理优化

**使用多线程**:
```python
import threading
import queue

# 接收线程
def receive_thread(receiver, frame_queue):
    receiver.receive_loop(callback=lambda f, s: frame_queue.put(f))

# 显示线程
def display_thread(frame_queue):
    while True:
        frame = frame_queue.get()
        # 处理和显示
```

### 3. 降低 CPU 占用

```python
# 降低显示刷新率
if frame_count % 5 == 0:  # 每 5 帧显示一次
    cv2.imshow('Image', frame_color)
```

---

## 九、下一步测试

完成单 Panel 测试后，可以进行：

1. **恢复双 Panel 拼接模式**
   - 修改 `ad71143_data_rx_dual.v`
   - 更新上位机软件解析双 Panel 数据

2. **性能测试**
   - 长时间稳定性测试（24 小时）
   - 不同光照条件测试
   - 温度漂移测试

3. **图像质量评估**
   - 信噪比（SNR）测量
   - 均匀性测试
   - 动态范围测试

---

## 十、技术支持

**相关文档**:
- `Panel2_Single_Channel_Test.md` - 硬件配置详解
- `NT39_State9_Final_Solution.md` - NT39 状态机修复
- `ILA_NT39_Setup_Instructions.md` - ILA 调试指南

**常见问题**:
- 如果遇到问题，先使用 Wireshark 确认是否收到数据包
- 使用 ILA 确认 FPGA 端是否正常发送
- 检查防火墙和网络配置

---

**创建时间**: 2026-07-27  
**适用硬件版本**: Panel 2 单通道测试模式  
**上位机软件**: panel2_receiver.py

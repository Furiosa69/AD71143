# AD71143 图像接收上位机

基于 Python + PyQt5 开发的 AD71143 AFE 图像接收和显示上位机软件。

## 功能特性

- ✅ **实时网络接收**: 通过 UDP 接收来自 FPGA 的图像数据
- ✅ **图像解析**: 自动解析双 Panel AD71143 数据格式
- ✅ **实时显示**: 实时显示接收到的图像
- ✅ **图像处理**: 支持伪彩色映射、对比度调整、直方图均衡化
- ✅ **数据保存**: 支持手动和自动保存图像
- ✅ **统计信息**: 实时显示接收速率、帧率等统计信息

## 系统要求

- Python 3.8 或更高版本
- Windows / Linux / macOS
- 网卡支持 UDP 接收（连接到 FPGA 的网口）

## 安装步骤

### 1. 安装 Python 依赖

```bash
cd host_pc
pip install -r requirements.txt
```

所需依赖包：
- numpy: 数值计算
- opencv-python: 图像处理
- PyQt5: GUI 界面
- scapy: 网络数据包处理（可选）
- pillow: 图像处理（可选）

### 2. 配置网络

#### Windows 系统
1. 打开"网络和共享中心"
2. 找到连接 FPGA 的网卡
3. 配置 IPv4 地址为 `192.168.1.1`
4. 子网掩码: `255.255.255.0`
5. 关闭防火墙或允许 UDP 1234 端口

#### Linux 系统
```bash
# 配置网卡 IP
sudo ifconfig eth0 192.168.1.1 netmask 255.255.255.0

# 或使用 ip 命令
sudo ip addr add 192.168.1.1/24 dev eth0

# 关闭防火墙
sudo ufw allow 1234/udp
```

### 3. 验证网络连接

```bash
# Windows
ping 192.168.1.2

# Linux
ping -c 4 192.168.1.2
```

如果能 ping 通，说明网络连接正常。

## 使用方法

### 启动图形界面

```bash
python main.py
```

### 界面操作说明

#### 1. 网络控制
- **监听IP**: 选择或输入本机网卡 IP（默认 0.0.0.0 监听所有网卡）
- **端口**: UDP 监听端口（默认 1234，与 FPGA 配置一致）
- **开始接收**: 点击开始接收图像数据
- **停止接收**: 点击停止接收

#### 2. 图像处理
- **启用伪彩色**: 将灰度图转换为伪彩色图像
- **颜色映射**: 选择不同的伪彩色方案
  - JET: 蓝-青-黄-红渐变（默认）
  - HOT: 黑-红-黄-白渐变
  - RAINBOW: 彩虹色
  - OCEAN: 海洋蓝
  - 其他: COOL, SPRING, SUMMER, AUTUMN, WINTER
- **直方图均衡化**: 增强图像对比度
- **对比度滑块**: 手动调整图像对比度（1.0 - 3.0）

#### 3. 保存设置
- **选择目录**: 选择图像保存路径
- **自动保存每帧**: 启用后自动保存每一帧图像
- **保存当前帧**: 手动保存当前显示的图像

保存文件格式：
- `frame_raw_YYYYMMDD_HHMMSS.npy`: 原始数据（4bit 像素值）
- `frame_img_YYYYMMDD_HHMMSS.png`: 处理后的图像（伪彩色/灰度）

#### 4. 统计信息
实时显示：
- 接收包数、字节数、丢包数
- 包速率（pps）、数据速率（Mbps）
- 完成帧数、当前行、完成度、帧率（fps）

## 硬件协议说明

### 网络协议
- **源 IP**: 192.168.1.2 (FPGA)
- **目标 IP**: 192.168.1.1 (PC)
- **协议**: UDP
- **端口**: 1234 (源) → 1234 (目标)
- **MAC 地址**: FF:FF:FF:FF:FF:FF (广播)

### 数据格式
每个 UDP 数据包 Payload: 32 bytes (256 bits)
```
merged_burst[255:0] = {Panel1[127:0], Panel0[127:0]}
```

- Panel 0: bytes[15:0] → 32 pixels (每像素 4bit)
- Panel 1: bytes[31:16] → 32 pixels (每像素 4bit)
- 总共: 64 pixels per burst

### 图像参数
- **分辨率**: 1024 × 541 (Panel0: 512px + Panel1: 512px)
- **每像素**: 4 bits (0-15)
- **每行**: 16 bursts (1024 / 64 = 16)
- **每帧**: 541 × 16 = 8656 个数据包

### 数据流
```
FPGA (AD71143) → LVDS → Data RX → RGMII Bridge → Ethernet
                                                      ↓
                                          PC (UDP Receiver)
                                                      ↓
                                          Frame Assembler
                                                      ↓
                                          Image Display
```

## 命令行测试工具

### 测试网络接收
```bash
python network_receiver.py
```

### 测试数据解析
```bash
python data_parser.py
```

### 测试完整流程
```bash
python test_receiver.py
```

## 故障排查

### 问题 1: 收不到数据包
**检查项**:
1. 网线是否连接正常
2. 网卡 IP 是否配置为 192.168.1.1
3. 防火墙是否阻止 UDP 1234 端口
4. FPGA 是否正常工作（检查 MDIO link_up 信号）

**解决方法**:
```bash
# Windows: 临时关闭防火墙测试
netsh advfirewall set allprofiles state off

# Linux: 检查 iptables
sudo iptables -L

# 查看网络接口
ipconfig    # Windows
ifconfig    # Linux
```

### 问题 2: 图像显示异常
**可能原因**:
1. 数据包丢失导致帧不完整
2. FPGA 数据格式错误
3. 网络拥塞

**解决方法**:
1. 查看统计信息中的丢包率
2. 检查 FPGA ILA 波形，验证 merged_burst 输出
3. 降低发送速率或增加 PC 接收缓冲区

### 问题 3: 帧率低
**可能原因**:
1. 网络带宽不足
2. PC 处理能力不足
3. FPGA 发送速率配置过低

**理论帧率计算**:
```
每帧数据量 = 8656 packets × 32 bytes = 277 KB
理论帧率 = 网络带宽 / 每帧数据量
例如: 100 Mbps / (277 KB × 8) ≈ 45 fps
```

### 问题 4: 内存占用过高
**解决方法**:
1. 关闭自动保存功能
2. 减少接收缓冲区大小
3. 定期清理保存目录

## 性能优化建议

### 1. 网络优化
- 使用千兆网卡
- 关闭网卡节能模式
- 增加接收缓冲区: `socket.setsockopt(socket.SO_RCVBUF, 1024*1024)`

### 2. 处理优化
- 使用多线程处理图像
- 降低显示刷新率
- 使用 GPU 加速（OpenCV CUDA）

### 3. 存储优化
- 使用 SSD 存储
- 批量写入而非逐帧写入
- 使用压缩格式（如 .npz）

## 开发说明

### 项目结构
```
host_pc/
├── main.py                 # 主程序（GUI）
├── data_parser.py          # 数据解析模块
├── network_receiver.py     # 网络接收模块
├── test_receiver.py        # 测试工具
├── requirements.txt        # Python 依赖
└── README.md              # 本文档
```

### 模块说明

#### data_parser.py
- `UDPPacketParser`: UDP 数据包解析器
- `FrameAssembler`: 帧组装器
- `ImageProcessor`: 图像处理器

#### network_receiver.py
- `UDPReceiver`: UDP 网络接收器（推荐）
- `NetworkReceiver`: 原始套接字接收器（需要管理员权限）

#### main.py
- `MainWindow`: 主窗口 GUI
- `ReceiveThread`: 接收线程

### 扩展开发

#### 添加新的图像处理算法
在 `ImageProcessor` 类中添加静态方法：
```python
@staticmethod
def custom_process(frame: np.ndarray) -> np.ndarray:
    # 自定义处理逻辑
    return processed_frame
```

#### 添加新的数据导出格式
在 `MainWindow.save_frame()` 中添加：
```python
# 导出为 CSV
csv_filename = os.path.join(self.save_dir, f"frame_{timestamp}.csv")
np.savetxt(csv_filename, frame, delimiter=',')
```

## 常见问题 (FAQ)

**Q: 为什么需要管理员权限？**
A: 使用原始套接字（Raw Socket）接收数据包需要管理员权限。建议使用 `UDPReceiver` 类（普通 UDP 套接字），不需要管理员权限。

**Q: 可以同时连接多个 FPGA 吗？**
A: 可以。为每个 FPGA 配置不同的源 IP，修改 `UDPPacketParser.parse_udp_packet()` 中的 IP 过滤逻辑。

**Q: 如何记录完整的原始数据流？**
A: 使用 Wireshark 或 tcpdump 抓包：
```bash
# Windows: 使用 Wireshark
# Linux: 使用 tcpdump
sudo tcpdump -i eth0 udp port 1234 -w capture.pcap
```

**Q: 如何离线分析保存的数据？**
A: 加载 .npy 文件：
```python
import numpy as np
frame = np.load('frame_raw_YYYYMMDD_HHMMSS.npy')
# 进行分析
```

## 技术支持

如有问题，请查看：
1. 硬件设计文档: `board/ILA_NT39_Setup_Instructions.md`
2. FPGA 源码: `board/project_1/project_1.srcs/sources_1/imports/src/`
3. 相关 Issue 和提交历史

## 更新日志

### v1.0.0 (2026-07-27)
- 初始版本
- 实现基本的 UDP 接收和图像显示功能
- 支持伪彩色映射和图像增强
- 支持手动和自动保存

## 许可证

请根据项目实际情况添加许可证信息。

---
**最后更新**: 2026-07-27

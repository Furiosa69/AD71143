# AD71143 FPGA 项目

## 当前状态

本仓库包含 AD71143 图像数据通路、NT39565D 栅极驱动、YT8531C 以太网 PHY，以及上位机接收程序。

当前硬件数据通路处于单 LVDS 测试配置：

- `ad71143_data_rx_dual` 当前只发送 Panel 1 数据。
- 当前单 LVDS 接收路径只使用 Lane A。
- 每个 UDP 负载对应一个 256 bit Burst，即 32 字节，按最高有效字节在前发送。
- 4 个有效的 16 bit 样本位于 UDP 负载的字节 0 至字节 7。
- UDP 负载的字节 8 至字节 31 是零填充。

上位机当前按 541 行、每行 256 像素、每行 64 个 Burst、每 Burst 4 个样本进行重建。

## 工程结构

```text
board/project_1/project_1.srcs/sources_1/imports/src/
  top.v                       板级集成与配置状态机
  ad71143_ctrl.v              AD71143 RESET、SYNC、ACLK 时序
  ad71143_spi.v               AD71143 寄存器写入引擎
  ad71143_data_rx.v           单 Panel LVDS Burst 接收
  ad71143_data_rx_dual.v      Panel 合并与单 Panel 测试路由
  nt39565d_ctrl.v             NT39565D 栅极驱动时序
  rgmii_bridge.v              CDC FIFO 与 UDP/以太网封装
  RGMII_tx.v                  RGMII 发送接口
  mdio_ctrl.v                 YT8531C PHY 配置

host_pc/
  main.py                     上位机入口
  network_receiver.py         UDP 接收
  data_parser.py              Burst 到图像的重建
  requirements.txt            Python 依赖

document/                     芯片规格书和参考资料
```

## 数据通路

```text
AD71143 DOUTA
  -> ad71143_data_rx（Panel 1）
  -> p1_merged_burst / p1_merged_valid
  -> panel1_hold
  -> merged_burst / merged_valid
  -> 异步 FIFO
  -> rgmii_bridge
  -> UDP 端口 1234
  -> host_pc/data_parser.py
```

`ad71143_data_rx_dual` 当前将发送 Burst 组装为 `{panel1_hold, 128'd0}`。因此上位机只读取负载前 8 字节，并按大端序还原为 4 个 16 bit 样本。

## 网络接口

FPGA 通过 UDP 将数据从 `192.168.1.2:1234` 发送至 `192.168.1.1:1234`。每个以太网帧携带 32 字节 UDP 负载。

## 最新抓包结论

`wireshark1.txt` 中有 46 个来自 FPGA 的 UDP 包。其传输层首部和固定的 32 字节负载长度均与设计一致；但所有包的负载字节均为 `0x00`，包括当前有效样本区的字节 0 至字节 7。

因此，此次抓包中的黑屏由零值源数据直接造成。上位机解析和以太网封装不是当前首要故障点。

下一次 ILA 应在 `clk_100m` 域依次观察：

1. `p1_merged_valid` 与 `p1_merged_burst`。
2. `panel1_hold`、`p1_captured`、`merged_valid` 与 `merged_burst`。
3. Panel 1 的 Lane A 原始输入和移位寄存器调试信号。

通过上述链路可判断零数据最先出现在 LVDS 接收端，还是出现在合并/FIFO 通路。

## 独立的栅极驱动问题

此前观测到的 CPV、STV、OE 时序暂按正常处理。`nt39565d_ctrl.v` 中的 `xao` 在复位后保持低电平；按 NT39565D 规格书，低电平 XAO 会将栅极输出强制到 VGG，并覆盖 OE。该问题已确认，但按当前调试安排暂不处理。

## 构建

使用 Vivado 打开 `board/project_1/project_1.xpr`，活动实现运行是 `impl_1`。修改 RTL 或 ILA 探针后，需重新生成 bitstream、下载 FPGA，再抓取新的波形或网络数据。

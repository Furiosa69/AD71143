# 模块状态记录

本文档只记录已确认正常的模块和已确认存在问题的模块。当前 RTL 是唯一依据。

## 已确认正常

| 模块 | 文件 | 已确认结果 |
|---|---|---|
| UDP/以太网发送通路 | `rgmii_bridge.v`、`RGMII_tx.v`、`mdio_ctrl.v` | Wireshark 已抓到 FPGA 发往 `192.168.1.1:1234` 的 46 个 UDP 包；每包负载长度为 32 字节，传输通路正常。 |
| 上位机 UDP 接收与数据格式 | `host_pc/network_receiver.py`、`host_pc/data_parser.py` | 上位机的单 LVDS 数据格式已与当前 FPGA 输出对齐：前 8 字节为 4 个 16 bit 大端样本，其余 24 字节为填充。 |
| NT39565D 基本时序 | `nt39565d_ctrl.v` | ILA 已确认 CPV、STV、OE 时序正常。 |

## 已确认有问题

| 模块 | 文件 | 现象与结论 |
|---|---|---|
| AD71143 真实数据接收通路 | `ad71143_data_rx.v`、`ad71143_data_rx_dual.v` | Wireshark 抓到的 46 个 UDP 负载均为全零，包含有效样本区字节 0 至字节 7；黑屏由 FPGA 送出的零数据造成。问题位于 AD 实际数据输出、LVDS 接收，或合并/FIFO 写入路径，尚未进一步定位。 |
| NT39565D XAO 控制 | `nt39565d_ctrl.v` | `xao` 复位后保持低电平且未释放。XAO 为低有效，低电平会将栅极输出强制到 VGG 并覆盖 OE。该问题已确认，暂未处理。 |

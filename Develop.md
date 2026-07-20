# 开发日志

## Vivado 自动化脚本

```tcl
# 综合 + 实现 + 生成 bitstream
reset_runs synth_1; launch_runs synth_1 impl_1 -jobs 4; wait_on_runs impl_1; launch_runs impl_1 -to_step write_bitstream -jobs 4; wait_on_run impl_1
```

```tcl
# 生成配置存储器文件 (MCS + BIN)
source board/TCL/write_cfgmem.tcl
```

---

## 时钟测试

| 项目 | 状态 |
|------|:----:|
| 示波器测量 `clk_100m` / `clk_125m` / `gate_clk` 频率 | ✓ |
| AFE 控制模块 `sync` / `aclk` 功能验证 | ✓ |
| MMCM 4 路输出: gate_clk(50M) / clk_100m(100M) / clk_125m(125M) / clk_125m_ph90 | ✓ |
| PHY 复位时序 (PLL 锁定后 100ms 拉低) | ✓ |

---

## SPI 测试

### 实测电压

| 信号 | 实测值 | 期望值 | 状态 |
|------|:------:|:------:|:----:|
| REF_TFT | 1.90 V | 2.60 V | 异常 |
| REF_INT | -1.90 V | — | — |
| REF_ADC | 4.07 V | — | — |
| AVDD2 | 2.50 V | 2.50 V | ✓ |
| AVDD5B | 5.03 V | 5.00 V | ✓ |
| DVDD5 | 5.03 V | 5.00 V | ✓ |
| DVDD2 | 2.49 V | 2.50 V | ✓ |

### 调试记录

- ILA 观察 SPI 波形：SCK = 25 MHz，SDI 有数据，CS 完整周期，但 SDO 始终为 0。
- Testbench 仿真复现：SDO 同样为 0。
- `cfg_state` 可正常到达 `CFG_DONE`；`SPI_TEST_Top` 独立测试通过。
- ILA 校验 SPI 帧格式及频率无误。
- IOSTANDARD = LVCMOS25，与 AD71143 手册要求一致。
- 供电在负载条件下均在额定范围内。
- ILA 确认 RESET 信号正常。
- 万用表蜂鸣档确认 SDO 走线连通。

### SPI 配置序列 (16 寄存器 LUT)

当前配置值已固化在 `top.v` 的 `cfg_data_lut` 中：

| Idx | Reg | Value | 说明 |
|-----|-----|-------|------|
| 0 | Reg3 | 0x020 | REFDAC=32 (~1.0V), AZEN=0 |
| 1 | Reg0 | 0x014 | PWR=Normal, IFS=20 |
| 2 | Reg1 | 0x0A0 | LPF=3.9μs, CDS2_RESETEN=1 |
| 3 | Reg2 | 0x027 | DOUTMODE=1, ECHOCLK=1, Pipeline=1, RNDOMIZE=1 |
| 4 | Reg4 | 0x082 | INTRST_C=8, INTRST_O=2 |
| 5 | Reg5 | 0x013 | CDS1_C=1, CDS1_O=3 |
| 6 | Reg6 | 0x046 | CDS2_C=4, CDS2_O=6 |
| 7 | Reg7 | 0x025 | FA_CDS1=2, FA_CDS2=5 |
| 8~15 | Reg8~15 | 0x000 | Reserved / 禁用 |

SPI 配置在 `ctrl_init_done` 且延迟 1s 后自动启动，双 Panel (Panel 0 + Panel 1) 并行写入。

### 结论

AD 芯片 SPI 接口失效，疑为上电时序不当导致损坏。

### 尝试方案

1. 维持原电压参数（AVDDI = 3.9 V, AVSSI = 1.9 V），需严格遵循上电时序（实现困难）。
2. AVSSI 接地 → 其他电源自然先于 AVSSI 建立。相应调整：AVDDI = 2.5 V, AVSSI = 0 V。
   - 测试结果：未解决。

排除了以下原因：AD 电源未稳定即写入 SPI、SPI 写间隔过短。当前 SDO 仅出现一次电平翻转，REF_TFT 实测为 0 V（期望 1.0 V），推测寄存器写入未完成。

| 状态 |
|:----:|
| ✓ |

### TODO

- [ ] 排查 REF_TFT 电压为 0 V 的原因。

---

## 网口测试 (RGMII / YT8531C)

**接口**: `enp0s13f0u2u1`

### PC 侧配置

```bash
sudo ip link set enp0s13f0u2u1 up
sudo ip addr add 192.168.1.1/24 dev enp0s13f0u2u1
ethtool enp0s13f0u2u1
```

### PC 侧抓包

```bash
sudo tcpdump -i enp0s13f0u2u1 -e -vv -c 5
# 或指定端口
sudo tcpdump -i enp0s13f0u2u1 'udp port 1234' -e -vv
```

### 调试记录

| 问题 | 状态 |
|------|:----:|
| Wireshark/tcpdump 无法捕获 `udp.port == 1234` | — |
| FPGA 侧网口 LED 不亮 | — |
| PHY 链路未建立（引脚未约束） | ✓ |
| MDIO 配置完成后仍无法抓包 | — |
| PHY 层通信建立 | ✓ |
| FCS (CRC-32) 字节序修正 | ✓ |
| IOSTANDARD: LVCMOS33（匹配 FPGA Bank Vcco，PHY 通过 `Cfg_ldo` 设为 3.3 V） | ✓ |
| DMAC/SMAC/EtherType/IP/UDP 全部正确 | ✓ |
| MDIO 初始化序列: Chip_Config(0x8040) + LED2_CFG(0x0644) + BMSR 轮询 + PkgTx 计数 | ✓ |
| RGMII TXC 90° 相移 (clk_125m_ph90 → TXC ODDR) | ✓ |
| rgmii_bridge 集成: FIFO CDC + CRC-32 + UDP/IP/MAC 封装 | ✓ |
| 测试模式: 无 AFE 数据时自动发送递增序号测试帧 | ✓ |

### MDIO 初始化序列

```
I_IDLE → I_WAIT (等待 PHY 上电) → I_SET_CHIP (ExtAddr=0xA001)
→ I_WR_CHIP (Chip_Config=0x8040: Rxc_dly_en=0, Cfg_ldo=3.3V)
→ I_SET_LED2 (ExtAddr=0xA00E)
→ I_WR_LED2 (LED2_CFG=0x0644: 1000M link ON + TX/RX blink)
→ I_RD_BCR (读 BCR 验证)
→ I_POLL (循环: BMSR → PkgTx 读取 → ExtAddr 清零)
```

### 帧格式

```
Ethernet (DMAC=Broadcast, SMAC=02:00:00:00:00:01, EtherType=0x0800)
→ IP (Src=192.168.1.2, Dst=192.168.1.1, Proto=UDP, TTL=64)
→ UDP (SrcPort=1234, DstPort=1234)
→ Payload (32 bytes = 256-bit burst, MSB first)
→ FCS (CRC-32, Ethernet polynomial 0xEDB88320)
```

### 当前状态

PHY 链路已协商至 1000Mbps Full，MDIO BMSR 确认 Link Up。FPGA 侧 ILA 确认测试帧正常发送。PC 端仍无法捕获 FPGA 发出的帧，疑似 RGMII 物理层信号质量问题，需示波器进一步诊断。

---

## 门控测试

> 底板需修改。

---

## 双 Panel 数据合并测试

- `ad71143_data_rx_dual` 模块封装两路 `ad71143_data_rx`，共享 SYNC/ACLK
- 输出对齐逻辑：capture+hold 方式等两 Panel 数据到齐后合并输出 `{Panel1[127:0], Panel0[127:0]}`
- 仿真通过

> 当前 TFT 板仅有一路 AD 芯片正常，硬件双 Panel 测试待 AD 芯片修复后进行。

---

## ILA 调试探针

`ila_0` 连接在 125MHz 域，观察 RGMII 发送路径状态：

| Probe | 信号 |
|-------|------|
| probe0 | `{rst_n_125m, startup_done, tx_sending, dbg_state[0]}` |
| probe1 | `{dbg_state[3:1], tx_fsm[2:0], crc_busy, tx_start_d, phy_rdy, PkgTx[1:0]}` |
| probe2 | `{phy_rst_n, cfg_done, link_up, pll_locked, BMSR[5:2]}` |
| probe3 | `tx_fsm[2:0]` (触发用) |

---

## 仿真

### Makefile 目标

```bash
make tb              # 顶层仿真 (tb_top)
make tb_data_rx      # 单 Panel 数据接收仿真
make tb_data_rx_dual # 双 Panel 数据接收仿真
make clean           # 清理输出文件
```

### 独立 Testbench (需手动运行)

```bash
# CRC-32 单元测试
iverilog -g2012 -o out/tb_crc32.out sim_models/xilinx_unisim.v src/RGMII_tx.v tb/tb_crc32.v
vvp out/tb_crc32.out

# MDIO 控制器测试
iverilog -g2012 -o out/tb_mdio.out sim_models/xilinx_unisim.v src/mdio_ctrl.v tb/tb_mdio.v
vvp out/tb_mdio.out

# RGMII 直连测试
iverilog -g2012 -o out/tb_rgmii_direct.out sim_models/xilinx_unisim.v src/RGMII_tx.v src/RGMII_rx.v tb/tb_rgmii_direct.v
vvp out/tb_rgmii_direct.out

# RGMII 全链路测试
iverilog -g2012 -o out/tb_rgmii_full.out sim_models/xilinx_unisim.v src/RGMII_tx.v src/RGMII_rx.v src/rgmii_bridge.v tb/tb_rgmii_full.v
vvp out/tb_rgmii_full.out
```

### 仿真输出示例

```
Simulation start at 1200000
Frame 1 done at 85330000
...
Frame 10 done at 852490000
Average frame rate: 369.35 fps
```

---

## 待完成工作

- [x] AD71143 SPI 配置模块 (`ad71143_spi.v`)
- [x] AD71143 控制信号发生器 (`ad71143_ctrl.v`)
- [x] AD71143 单 Panel LVDS 数据接收 (`ad71143_data_rx.v`)
- [x] AD71143 双 Panel 数据接收+合并 (`ad71143_data_rx_dual.v`)
- [x] NT39565D Gate Driver 控制 (`nt39565d_ctrl.v`)
- [x] RGMII 发送/接收模块 (`RGMII_tx.v`, `RGMII_rx.v`)
- [x] RGMII 桥接 (CDC + UDP/IP/MAC + CRC-32) (`rgmii_bridge.v`)
- [x] MDIO PHY 控制器 (`mdio_ctrl.v`)
- [x] 顶层集成: nt39565d + ad71143_ctrl + ad71143_spi + ad71143_data_rx_dual + rgmii_bridge + mdio_ctrl
- [x] 上电初始化 SPI 配置序列（自动写 16 个寄存器）
- [x] ILA 调试探针集成
- [ ] 两片 AFE 数据的 Bitslip/Deskew 对齐
- [ ] AD 芯片 SPI 修复 / 硬件更换
- [ ] RGMII 物理层信号质量诊断
- [ ] 数据缓存到 BRAM/FIFO（当前 FIFO IP 已集成）
- [ ] PC 端完整数据接收与图像重建
- [ ] 实际硬件全链路测试

# 开发日志

## Vivado 自动化脚本

```tcl
reset_runs synth_1; launch_runs synth_1 impl_1 -jobs 4; wait_on_runs impl_1; launch_runs impl_1 -to_step write_bitstream -jobs 4; wait_on_run impl_1
```

---

## 时钟测试

| 项目 | 状态 |
|------|:----:|
| 示波器测量 `clk_100m` / `clk_125m` / `gate_clk` 频率 | ✓ |
| AFE 控制模块 `sync` / `aclk` 功能验证 | ✓ |

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
| DMAC/SMAC/EtherType/IP/UDP全部正确 | ✓ | 

### 当前状态

PHY 链路已协商至 1000Mbps Full，MDIO BMSR 确认 Link Up。FPGA 侧 ILA 确认测试帧正常发送。PC 端仍无法捕获 FPGA 发出的帧，疑似 RGMII 物理层信号质量问题，需示波器进一步诊断。

---

## 门控测试

> 底板需修改。

---

## 双 Panel 数据合并测试

> 当前 TFT 板仅有一路 AD 芯片正常。

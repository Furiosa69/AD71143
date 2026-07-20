# 项目进度

## NT39565D 测试

仿真通过，可以稳定输出 10 帧或更多。实测硬件栅极驱动信号（CPV/STV/OE）正常。

## AD71143 测试

SPI 通过，两路数据组合通过。当前仅 Panel 0 的 AD 芯片正常工作。

- SPI 配置 FSM 可自动写入全部 16 个寄存器（Reg0~Reg15），按上电顺序排列
- 双 Panel SPI 并行配置（Panel 0 + Panel 1 各自独立 `ad71143_spi` 实例）
- LVDS 数据接收 (`ad71143_data_rx_dual`) 封装双 Panel，共享 SYNC/ACLK，独立 DCLK/DOUT

## RGMII / 以太网测试

- YT8531C PHY (MDIO) 配置完毕：Chip_Config（LDO=3.3V, Rxc_dly_en=0）、LED2_CFG
- PHY 链路协商至 1000Mbps Full，BMSR Link Up 确认
- RGMII 桥接 (`rgmii_bridge`) 集成 UDP/IP/MAC 协议栈，含 CRC-32 FCS
- FPGA 侧 ILA 确认测试帧正常发送，PC 端 `tcpdump` 可捕获 UDP:1234 帧
- 已知问题：PC 端偶有丢帧，疑似 RGMII 信号质量问题

## 时钟树

```
sys_clk (100 MHz, pin R4)
  │
  └─ MMCM (clk_wiz_0, VCO=???MHz)
      ├── CLKOUT0 → gate_clk  (50 MHz)
      │   ├── 顶层 FSM (TOP_POWERUP → WAIT_INIT → WAIT_CFG → IDLE → ...)
      │   └── nt39565d_gate_ctrl (栅极驱动 CPV/STV/OE)
      │
      ├── CLKOUT1 → clk_100m (100 MHz)
      │   ├── ad71143_ctrl (AFE 控制 FSM: RESET/SYNC/ACLK)
      │   ├── ad71143_spi × 2 (SPI 主机, SCK=25 MHz)
      │   ├── ad71143_data_rx × 2 (Panel 0 + Panel 1)
      │   │   ├── ODDR → DCLK 输出 @ 100 MHz (DDR 模式)
      │   │   └── clk_sys 直接作内部采样 (替代 DCLKO 回波)
      │   ├── mdio_ctrl (MDC=5 MHz)
      │   └── rgmii_bridge (100MHz 写 FIFO → CDC → 125MHz 读)
      │
      ├── CLKOUT2 → clk_125m (125 MHz)
      │   └── RGMII_tx (帧封装 + ODDR 发送)
      │
      └── CLKOUT3 → clk_125m_ph90 (125 MHz, 90° 相移)
          └── TXC ODDR (RGMII 规范要求 2ns 延迟)

  外部异步时钟:
    rgmii_rxc @ 125 MHz (PHY 输入 → RGMII_rx IDDR)
```

| | 现在 |
|---|---|
| 时钟域数量 | 50 / 100 / 125 MHz |
| MMCM 输出 | 4 路 (gate_clk, clk_100m, clk_125m, clk_125m_ph90) |
| DCLK 频率 | 100 MHz (DDR 模式) |
| ctrl ↔ data_rx | 同一 100 MHz 域，无需 CDC |
| data_rx → bridge | FIFO IP 异步 CDC (100→125 MHz) |
| 每 bit 捕获窗口 | 10 ns @ 100 MHz |

## 复位策略

- `rst_n_async = key & pll_locked`：PLL 锁定且按键释放后复位释放
- 每个时钟域独立复位同步器（2-FF 异步断言/同步释放）：`rst_n_50m`, `rst_n_100m`, `rst_n_125m`
- PHY 复位 (`rgmii_rst_n`)：PLL 锁定后保持低 ~100ms，满足 YT8531C 上电复位时序

## 模块清单

| 模块 | 文件 | 时钟域 | 功能 |
|------|------|--------|------|
| `top` | `src/top.v` | 50/100 MHz | 顶层集成 + SPI 配置 FSM + 帧控制 FSM |
| `nt39565d_gate_ctrl` | `src/nt39565d_ctrl.v` | 50 MHz | Gate Driver CPV/STV/OE 时序 |
| `ad71143_ctrl` | `src/ad71143_ctrl.v` | 100 MHz | AFE RESET/SYNC/ACLK 控制 |
| `ad71143_spi` | `src/ad71143_spi.v` | 100 MHz | AFE SPI 寄存器配置 (SCK=25MHz) |
| `ad71143_data_rx` | `src/ad71143_data_rx.v` | 100 MHz | 单 Panel LVDS 数据接收 |
| `ad71143_data_rx_dual` | `src/ad71143_data_rx_dual.v` | 100 MHz | 双 Panel 数据接收 + 对齐合并 |
| `rgmii_bridge` | `src/rgmii_bridge.v` | 100/125 MHz | FIFO CDC + UDP/IP/MAC 封装 + CRC-32 |
| `RGMII_tx` | `src/RGMII_tx.v` | 125 MHz | RGMII 发送 (ODDR DDR 输出) |
| `RGMII_rx` | `src/RGMII_rx.v` | 125 MHz | RGMII 接收 (IDDR DDR 输入) |
| `mdio_ctrl` | `src/mdio_ctrl.v` | 100 MHz | YT8531C PHY MDIO 配置 + BMSR 轮询 |
| (Vivado IP) | `clk_wiz_0` | — | MMCM 时钟生成 (4 路输出) |
| (Vivado IP) | `fifo_generator_0` | 100→125 MHz | 异步 CDC FIFO (256-bit × 512 deep) |
| (Vivado IP) | `ila_0` | 125 MHz | ILA 调试探针 (RGMII 发送诊断) |

## 状态机

### 1. `ad71143_spi.v` — 模块 `ad71143_spi`

| 状态 | 转移条件 |
|---|---|
| `S_IDLE` | `start` 有效 → `S_SETUP` |
| `S_SETUP` | `sck_toggle && sck_cnt == 0` → `S_SHIFT` |
| `S_SHIFT` | `bit_cnt == 15 && sck_toggle && sck_cnt == 0` → `S_DONE` |
| `S_DONE` | 无条件 → `S_IDLE` |

---

### 2. `ad71143_ctrl.v` — 模块 `ad71143_ctrl`

| 状态 | 转移条件 |
|---|---|
| `S_INIT_RESET` | `timer == RESET_CYCLES - 1` → `S_INIT_WAIT` |
| `S_INIT_WAIT` | `timer == INIT_WAIT_CYCLES - 1` → `S_IDLE`（`init_done=1`） |
| `S_IDLE` | `frame_start` → `S_SYNC_SETUP` |
| `S_SYNC_SETUP` | `timer == 1` → `S_ACLK_ACT` |
| `S_ACLK_ACT` | `timer == (ACLK_PULSES * 2) - 1` → `S_SYNC_HOLD` |
| `S_SYNC_HOLD` | `timer == 1` → `S_LINE_GAP` |
| `S_LINE_GAP` | `line_cnt >= FRAME_LINES - 1` → `S_IDLE`（`frame_done=1`）；否则 → `S_SYNC_SETUP`（下一行） |

---

### 3. `RGMII_rx.v` — 模块 `RGMII_rx`

| 状态 | 转移条件 |
|---|---|
| `IDLE` | `SFD_done` → `RECEIVE` |
| `RECEIVE` | `RX_DV_d` 有效 → 保持 `RECEIVE`；否则 → `IDLE` |

---

### 4. `RGMII_tx.v` — 模块 `RGMII_tx`

| 状态 | 转移条件 |
|---|---|
| `IDLE` | `tx_start` → `PREAMBLE` |
| `PREAMBLE` | `Preamble_cnt == PREAMBLE_NUM - 1` → `SFD_STATE` |
| `SFD_STATE` | 无条件 → `DATA` |
| `DATA` | `Byte_cnt == FRAME_SIZE - 1` → `IDLE` |

---

### 5. `nt39565d_ctrl.v` — 模块 `nt39565d_gate_ctrl`（10 状态 + XAO_SHUT）

| 状态 | 转移条件 |
|---|---|
| `IDLE` | `frame_start \|\| frame_pending \|\| (!PER_LINE_TRIG && line_start)` → `STV_SETUP_S` |
| `STV_SETUP_S` | `cnt >= STV_SETUP_CNT - 1`：若 `cfg_stv2_delay_1cpv` → `STV1_ONLY_S`，否则 → `STV_IDENT_S` |
| `STV_IDENT_S` | `cnt >= STV_PW_CNT - 1` → `CPV_LOW_S` |
| `STV1_ONLY_S` | `cnt >= STV_PW_CNT - 1` → `STV12_GAP_S` |
| `STV12_GAP_S` | `cnt >= (CPV_PERIOD_CNT - STV_PW_CNT) - 1` → `STV2_ONLY_S` |
| `STV2_ONLY_S` | `cnt >= STV_PW_CNT - 1` → `CPV_LOW_S` |
| `CPV_LOW_S` | `cnt >= CPV_LOW_CNT - 1` → `CPV_HIGH_S` |
| `CPV_HIGH_S` | `cnt >= CPV_PW_CNT - 1`：若 `shift_cnt+1 >= target_lines` → `FRAME_END_S`；若 `PER_LINE_TRIG` → `WAIT_LINE`；否则 → `CPV_LOW_S` |
| `WAIT_LINE` | `line_start` → `CPV_LOW_S` |
| `FRAME_END_S` | `cnt >= STV_PW_CNT - 1` → `IDLE` |
| `XAO_SHUT_S` | `!xao_emergency` → `IDLE` |

---

### 6. `ad71143_data_rx.v` — 模块 `ad71143_data_rx`

| 状态 | 转移条件 |
|---|---|
| `S_IDLE` | `sync_fall` → `S_WAIT` |
| `S_WAIT` | `aclk_done` → `S_ACT` |
| `S_ACT` | `capture_done_pulse_sys`：若 `burst_cnt == TOTAL_BURSTS-1` → `S_DONE`；否则 → `S_MUTE` |
| `S_MUTE` | `mute_cnt >= MUTE_MIN - 1` → `S_ACT` |
| `S_DONE` | 无条件 → `S_IDLE` |

---

### 7. `top.v` — SPI 配置 FSM（模块 `top` 内，100MHz 域）

| 状态 | 转移条件 |
|---|---|
| `CFG_IDLE` | `ctrl_init_done && cfg_delay_done (1s)` → `CFG_ISSUE` |
| `CFG_ISSUE` | 无条件 → `CFG_WAIT` |
| `CFG_WAIT` | `spi_done` → `CFG_DONE` |
| `CFG_DONE` | `cfg_reg_idx != 15 && cfg_gap_done` → `CFG_ISSUE`（循环写下一寄存器）；否则保持 `CFG_DONE` |

SPI 配置顺序 (16 寄存器 LUT)：
`Reg3(REFDAC)→Reg0(PWR)→Reg1(LPF)→Reg2(Mode)→Reg4~7(Timing)→Reg8~15`

---

### 8. `top.v` — 顶层帧控制 FSM（模块 `top` 内，50MHz 域）

| 状态 | 转移条件 |
|---|---|
| `TOP_POWERUP` | 无条件 → `TOP_WAIT_INIT` |
| `TOP_WAIT_INIT` | `init_done_synced` → `TOP_WAIT_CFG` |
| `TOP_WAIT_CFG` | `cfg_done_synced` → `TOP_IDLE` |
| `TOP_IDLE` | 无条件（1 周期后） → `TOP_START` |
| `TOP_START` | 发出 `frame_start=1` → `TOP_WAIT_FRAME` |
| `TOP_WAIT_FRAME` | `frame_done_rise` → `TOP_FRAME_GAP` |
| `TOP_FRAME_GAP` | `gap_cnt >= FRAME_GAP_CYCLES - 1` → `TOP_START` |

---

### 9. `mdio_ctrl.v` — 初始化序列 FSM

| 状态 | 动作 |
|---|---|
| `I_IDLE` | 等待上电延迟 (~16.7ms) |
| `I_WAIT` | 额外等待 → `I_SET_CHIP` |
| `I_SET_CHIP` | 写 ExtAddr=0xA001 → `I_WR_CHIP` |
| `I_WR_CHIP` | 写 Chip_Config=0x8040 → `I_SET_LED2` |
| `I_SET_LED2` | 写 ExtAddr=0xA00E → `I_WR_LED2` |
| `I_WR_LED2` | 写 LED2_CFG=0x0644 → `I_RD_BCR` |
| `I_RD_BCR` | 读 BCR → `I_POLL` (循环: BMSR→PkgTx→clrExt) |

### 10. `rgmii_bridge.v` — 帧组装流水线

无传统状态机，采用流水线控制：FIFO 读 (`fifo_rd_en`) → CRC-32 计算 (74 cycles) → 帧组装 (header+payload+FCS) → `tx_start` 脉冲 → `RGMII_tx` 发送

## CDC (跨时钟域) 策略

| 信号 | 源域 | 目标域 | 方法 |
|------|------|--------|------|
| `ctrl_init_done` | 100 MHz | 50 MHz | 2-FF level sync |
| `ctrl_line_start` | 100 MHz | 50 MHz | toggle + 3-FF + edge detect |
| `frame_start` | 50 MHz | 100 MHz | toggle + 3-FF + edge detect |
| `ctrl_frame_done` | 100 MHz | 50 MHz | toggle + 3-FF + edge detect |
| `spi_cfg_done` | 100 MHz | 50 MHz | 2-FF level sync |
| 数据 Burst | 100 MHz | 125 MHz | Xilinx FIFO IP (async) |

## 项目结构

```
AD71143/
├── src/
│   ├── top.v                    # 顶层模块
│   ├── nt39565d_ctrl.v          # Gate Driver 控制
│   ├── ad71143_ctrl.v           # AFE 控制信号发生器
│   ├── ad71143_spi.v            # AFE SPI 配置主机
│   ├── ad71143_data_rx.v        # 单 Panel LVDS 数据接收
│   ├── ad71143_data_rx_dual.v   # 双 Panel 数据接收+合并
│   ├── rgmii_bridge.v           # RGMII 桥接 (CDC + UDP/IP/MAC)
│   ├── RGMII_tx.v               # RGMII 发送 (ODDR)
│   ├── RGMII_rx.v               # RGMII 接收 (IDDR)
│   └── mdio_ctrl.v              # MDIO PHY 管理 (YT8531C)
├── tb/
│   ├── tb_top.v                 # 顶层 Testbench
│   ├── tb_ad71143_data_rx.v     # 单 Panel 数据接收 TB
│   ├── tb_ad71143_data_rx_dual.v# 双 Panel 数据接收 TB
│   ├── tb_crc32.v               # CRC-32 单元 TB
│   ├── tb_mdio.v                # MDIO 控制器 TB
│   ├── tb_rgmii_crc.v           # RGMII CRC TB
│   ├── tb_rgmii_direct.v        # RGMII 直连 TB
│   ├── tb_rgmii_full.v          # RGMII 全链路 TB
│   ├── spi_test_top.v           # SPI 模块 TB
│   └── xilinx_mocks.v           # Xilinx 原语 Mock
├── board/
│   ├── RTL/top.v                # 板级顶层 (仅 nt39565d)
│   ├── XDC/pin.xdc              # 引脚约束
│   ├── XDC/timing.xdc           # 时序约束
│   ├── TCL/bitgen_compress.tcl  # 位流压缩
│   ├── TCL/write_cfgmem.tcl     # 配置存储器写入
│   └── Project/                 # Vivado 项目文件
├── document/
│   ├── 3.AD71143 SPEC.pdf       # AD71143 芯片规格书
│   ├── 1.1 NT39565D_V01_20130219.pdf  # NT39565D 数据手册
│   └── *.pdf / *.jpg            # 其他参考文档
├── sim_models/
│   └── xilinx_unisim.v          # Xilinx UNISIM 仿真模型
├── Makefile                     # Icarus Verilog 仿真
├── Develop.md                   # 开发日志
└── README.md                    # 本文件
```

name: X-Ray TFT Driver
description: 3.99英寸 X射线平板探测器 TFT 驱动系统，包含 NT39565D Gate Driver 和 AD71143 AFE 的 FPGA 控制逻辑，含 RGMII 以太网数据上传
version: 3.0
author: Furiosa

# X-Ray TFT Driver 项目 Skill

## 项目概述

这是一个 **X射线平板探测器（FPD）** 的 FPGA 控制逻辑项目。系统包含四个核心芯片：

| 芯片 | 型号 | 功能 | 通道数 |
|------|------|------|--------|
| **Gate Driver** | NT39565D | 逐行打开 TFT 开关 | 541/513/385/361 可选 |
| **AFE (Readout)** | AD71143 × 2 | 电荷 → 数字信号转换 | 256 通道/片，共 2 片 (Panel 0 + Panel 1) |
| **Ethernet PHY** | YT8531C | RGMII 千兆以太网 | 1 路 |
| **TFT Sensor** | 3.99" IGZO | X射线感光面板 | 512 × 512 像素 |

### 信号链

```
X射线 → 闪烁体 → 可见光 → TFT传感器(电荷) → AFE(数字) → FPGA(处理) → PC(图像)
                                        ↑                         |
                                    Gate Driver              RGMII/UDP
                                    (逐行打开TFT)            以太网上传
```

---

## 项目结构

```
AD71143/
├── src/
│   ├── top.v                    # 顶层模块 (FSM + 例化)
│   ├── nt39565d_ctrl.v          # Gate Driver 控制模块
│   ├── ad71143_ctrl.v           # AD71143 控制信号发生器 (RESET + SYNC + ACLK)
│   ├── ad71143_spi.v            # AD71143 SPI 配置主机
│   ├── ad71143_data_rx.v        # AFE LVDS 单 Panel 数据接收模块
│   ├── ad71143_data_rx_dual.v   # AFE LVDS 双 Panel 数据接收+合并模块
│   ├── rgmii_bridge.v           # RGMII 桥接 (CDC + UDP/IP/MAC + CRC-32)
│   ├── RGMII_tx.v               # RGMII 发送模块 (ODDR)
│   ├── RGMII_rx.v               # RGMII 接收模块 (IDDR)
│   └── mdio_ctrl.v              # MDIO 控制器 (YT8531C PHY 管理)
├── tb/
│   ├── tb_top.v                 # 顶层 Testbench
│   ├── tb_ad71143_data_rx.v     # AFE 单 Panel 数据接收 Testbench
│   ├── tb_ad71143_data_rx_dual.v# AFE 双 Panel 数据接收 Testbench
│   ├── tb_crc32.v               # CRC-32 单元 Testbench
│   ├── tb_mdio.v                # MDIO 控制器 Testbench
│   ├── tb_rgmii_crc.v           # RGMII CRC Testbench
│   ├── tb_rgmii_direct.v        # RGMII 直连 Testbench
│   ├── tb_rgmii_full.v          # RGMII 全链路 Testbench
│   ├── spi_test_top.v           # SPI 模块 Testbench
│   └── xilinx_mocks.v           # Xilinx 原语 Mock (仿真用)
├── board/
│   ├── RTL/top.v                # 板级顶层 (仅 Gate Driver, 25MHz 简化版)
│   ├── XDC/pin.xdc              # 引脚约束 (完整 pinout)
│   ├── XDC/timing.xdc           # 时序约束
│   ├── TCL/bitgen_compress.tcl  # 位流压缩
│   ├── TCL/write_cfgmem.tcl     # 配置存储器写入 (MCS/BIN)
│   └── Project/                 # Vivado 2023.2 项目文件
├── document/
│   ├── 3.AD71143 SPEC.pdf       # AD71143 芯片规格书 (Rev. SpA, 34页)
│   └── 1.1 NT39565D_V01_20130219.pdf  # NT39565D 数据手册
├── sim_models/
│   └── xilinx_unisim.v          # Xilinx UNISIM 仿真模型
├── Makefile                     # Icarus Verilog 仿真
├── Develop.md                   # 开发日志
└── README.md                    # 项目进度 + 时钟树
```

---

## 模块详解

### 1. nt39565d_gate_ctrl（Gate Driver 控制）

**功能**：产生 NT39565D 所需的 CPV/STV/OE 时序。支持 Normal / 2G / 2G+LCS 模式。

**关键参数**（50MHz 时钟）：
```verilog
CLK_FREQ_MHZ      = 50     // 系统时钟 (gate_clk)
CPV_PERIOD_US     = 10     // CPV 周期 (10µs → 100kHz)
CPV_PW_US_X10     = 10     // CPV 脉宽 (1.0µs)
STV_SETUP_US_X10  = 3      // STV 建立时间 (0.3µs)
STV_HOLD_US_X10   = 4      // STV 保持时间 (0.4µs)
OE_PW_US_X10      = 10     // OE 脉宽 (1.0µs)
```

**状态机** (10 状态 + XAO_SHUT)：
```
IDLE → STV_SETUP_S → STV_IDENT_S / STV1_ONLY_S → STV12_GAP_S → STV2_ONLY_S → CPV_LOW_S → CPV_HIGH_S → WAIT_LINE / FRAME_END_S → IDLE
```

**输出信号**：
- `cpv`: 移位时钟（≤200kHz）
- `stv1/stv2`: 帧起始脉冲（支持双 STV 同步或延迟 1CPV 模式）
- `oe1/oe2`: 输出使能（低有效）
- `xao`: 全能输出（紧急关断）
- `ud/lr`: 扫描方向控制
- `mode1/mode2/sel/stv_mode/chip_sel1/chip_sel2/oepsn`: 模式配置输出
- `busy`: 帧进行中
- `line_done`: 单行扫描完成脉冲
- `frame_done`: 一帧扫描完成脉冲

**双 FPV 排线**：所有信号同时扇出到 `_r` 和 `_l` 两组物理引脚，支持左右两块 Gate Driver PCB。

---

### 2. ad71143_ctrl（AD71143 控制信号发生器）

**功能**：产生 AD71143 所需的 RESET、SYNC、ACLK 时序。实现 AD71143 SPEC Figure 22 (Pipeline Mode)。

**系统时钟**: 100MHz (10ns)

**关键参数**：
```verilog
ACLK_PULSES      = 9      // 每行 ACLK 脉冲数
LINE_CYCLES      = 6000   // 行周期 60µs @ 100MHz
RESET_CYCLES     = 10     // RESET 脉宽 10µs (实际配置)
INIT_WAIT_CYCLES = 100    // 初始化等待 100µs (实际配置)
```

**输出信号**：
- `roic_reset`: 异步复位（高有效，≥10ns → 本设计 10µs）
- `sync`: 转换同步（低有效），下降沿 = 新行开始
- `aclk`: AFE 时序时钟（50MHz, 20ns 周期），每行 9 个脉冲
- `aclk_idx`: 当前 ACLK 脉冲编号（0~8）
- `aclk_done`: ACLK 序列完成脉冲
- `init_done`: 初始化完成
- `line_start` / `line_done`: 行起止脉冲
- `line_cnt`: 行计数
- `frame_done`: 帧完成脉冲

**状态机**：
```
S_INIT_RESET → S_INIT_WAIT → S_IDLE → S_SYNC_SETUP → S_ACLK_ACT → S_SYNC_HOLD → S_LINE_GAP → S_SYNC_SETUP → ...
```

**时序（Pipeline Mode, 参照 SPEC Figure 22）**：
- `line_start` → SYNC↓ → (tSYNCACLK ≥ 20ns) → ACLK0↑ → ACLK1~8 → SYNC↑ → 行间隔 → 下一行
- RESET 释放后等待 100µs 再开始转换（tRESETCS ≥ 4000ns）

---

### 3. ad71143_spi（SPI 配置主机）

**功能**：4 线 SPI (CS, SCK, SDI, SDO)，16-bit 帧，MSB first，用于配置 AD71143 内部寄存器。

**SCK**: 25MHz（100MHz 系统时钟 4 分频），SPEC 要求 ≥ 50ns 周期 → OK

**SPI 帧格式**：
```
Bit[15]    = Write (1=写)
Bit[14]    = Read  (1=读)        // Write 和 Read 互斥
Bit[13:10] = Register Address (0~15)
Bit[9:0]   = Register Data
```

**操作流程**：
1. 设置 `reg_addr`, `reg_data`, `rw`
2. 给 `start` 一个脉冲
3. 等待 `done=1`
4. 读取操作时，从 `reg_rdback` 获取返回值

**SPEC 关键约束**（配置期间）：
- SYNC 和 DCLKx 必须保持低电平
- 转换期间 CS 必须保持低电平
- SCK 在转换期间也应保持低电平
- CS 下降沿时配置寄存器被更新（双缓冲）
- SDI 在 SCK 下降沿被采样
- SDO 在 SCK 上升沿输出

---

### 4. ad71143_data_rx（AFE LVDS 单 Panel 数据接收）

**功能**：接收单个 AD71143 的 LVDS 串行数据。
按 SPEC Figure 37/38 实现：
- DOUTMODE = 1（双 LVDS 输出模式）
- 内部用 `clk_sys` 替代 DCLKO 回波时钟采样 DOUTA/DOUTB
- 每个 Burst 采 64bit/lane，共 128bit
- 数据 Burst 内合并为 8 个 16-bit 样本

**接口定义**：
```verilog
// 系统
clk_sys         : 100MHz 系统时钟
rst_n           : 低有效复位

// 时序控制
sync_in         : SYNC 信号（下降沿 = 新行开始）
aclk_done       : ACLK 序列完成标志

// DCLK 输出
dclk_p/dclk_n   : LVDS 差分时钟（FPGA → AFE, DDR 模式）

// DOUT 输入
dout_p/n_A      : AFE Lane A（偶数通道: 0,2,4,...,254）
dout_p/n_B      : AFE Lane B（奇数通道: 1,3,5,...,255）

// 合并输出
merged_burst[127:0]     : 合并数据（64+64 bit，含 8 个 16-bit 通道）
merged_burst_index[6:0] : 0=Header, 1~32=数据通道
merged_valid            : 数据有效标志
line_done               : 一行完成脉冲
header_ok               : Header 同步字匹配 (0x0A)
```

**Burst 结构**（双 LVDS 模式，256 通道）：
```
Burst 0:  Header (128 bit = A 64bit + B 64bit)
Burst 1~32: Data — 每 Burst 含 8 个通道 × 16 bit（A: 4ch + B: 4ch）
Burst 33: Configuration Registers
共 34 Bursts (TOTAL_BURSTS = 34)
```

**Header 格式** (SPEC Table 11)：
```
[127:120] = A[63:56] = 0x0A 固定同步字
[119:115] = A[55:51] = 5'b0
[114]     = A[50]    = 工厂测试位
[113]     = A[49]    = READDOWN: 1=CH255→CH0, 0=CH0→CH255
[112]     = A[48]    = CDS 标识: 1=CDSxA, 0=CDSxB
[111:96]  = A[47:32] = 16'h0000
[95:80]   = A[31:16] = 16-bit 温度
[79:64]   = A[15:0]  = 16-bit VT
B[63:0]  = 与 A 相同的镜像
```

**MUTE_MIN 参数**：100MHz 时 tBURST(min)=1765ns → 177 cycles - 64 active = 113

**状态机**：
```
S_IDLE → S_WAIT（等待 aclk_done）→ S_ACT（收64bit）→ S_MUTE（静默期）→ S_ACT/MUTE 循环 → S_DONE → S_IDLE
```

**DCLKO 域**：`cap_start_tgl_sys` (clk_sys 域) → 2-FF CDC → DCLKO 域采样 `cap_start_tgl_d1/d2`，开始捕获。完成后 `cap_done_tgl_dclko` toggle → CDC 回 clk_sys 域检测边沿。

---

### 5. ad71143_data_rx_dual（AFE LVDS 双 Panel 数据接收）

**功能**：封装两个 `ad71143_data_rx` 实例，共享 `sync_in`/`aclk_done`/`clk_sys`，各自独立 LVDS 物理口。

**输出拼接**：
```verilog
merged_burst[255:0] = {panel1_burst[127:0], panel0_burst[127:0]}
```

**对齐逻辑**：两 Panel 共享 SYNC/ACLK，FSM 理论上同步。但 DCLKO 域 CDC 可能有 1~2 周期偏移 → 用 capture+hold 对齐。MUTE 期 (~113+ cycles) 远大于 CDC 偏移，不会丢 Burst。

---

### 6. RGMII_tx（RGMII 发送）

**功能**：RGMII 发送模块，含前导码+SFD+数据+ODDR 输出。

**状态机**：
```
IDLE → PREAMBLE (7×0x55) → SFD_STATE (0xD5) → DATA (FRAME_SIZE bytes) → IDLE
```

**时钟**: 125MHz TXC 域。数据路径：`tx_data` → 1 拍延迟 → `tx_byte` → ODDR (上升沿=低4bit, 下降沿=高4bit)。

**TX_CTL**: ODDR 上升沿=TX_EN, 下降沿=TX_EN xor TX_ER。

**输出握手**：`tx_req = (next_state == DATA)` 告知上层下一拍需要 `tx_data`。

---

### 7. RGMII_rx（RGMII 接收）

**功能**：RGMII 接收模块，含 IDDR 输入 + 前导码检测 + SFD 检测。

**状态机**：
```
IDLE → RECEIVE (RX_DV_d 有效) → IDLE (RX_DV_d 失效)
```

**输入**：4 路 IDDR (SAME_EDGE_PIPELINED) + RX_CTL IDDR → RX_DV + RX_ER 解码。

**前导码检测**：累计 3 次 0x55 视为前导码有效，然后检测 SFD (0xD5)。

---

### 8. rgmii_bridge（RGMII 桥接 + 协议栈）

**功能**：100MHz AFE 数据域 → 125MHz RGMII 域 CDC + UDP/IP/MAC 帧封装 + CRC-32 FCS。

**时钟域**：
- `clk_100m`: 100MHz — 写 FIFO (来自 ad71143_data_rx_dual)
- `clk_125m`: 125MHz — 读 FIFO + 帧封装 + RGMII_tx
- `clk_125m_ph90`: 125MHz 90°相移 — TXC ODDR

**数据通路**：
```
data_in (256-bit burst) → FIFO IP (100→125 CDC) → 帧组装 (DMAC+SMAC+IP+UDP+Payload) → CRC-32 → tx_start → RGMII_tx
```

**帧格式** (大端序)：
```
MAC Header (14B): DMAC=broadcast, SMAC=02:00:00:00:00:01, EtherType=0x0800
IP Header (20B):  Src=192.168.1.2, Dst=192.168.1.1, Proto=UDP, TTL=64
UDP Header (8B):  SrcPort=1234, DstPort=1234, Checksum=0
Payload (BURST_BYTES):  256-bit burst, MSB first
FCS (4B):         CRC-32 (Ethernet polynomial 0xEDB88320, LSB-first)
```

**CRC-32**：覆盖前 74 字节 (HDR_BYTES + BURST_BYTES)，反射算法，FCS 字节序为小端 (crc_reg[7:0] 先发)。

**测试模式** (`TEST_MODE=1`)：上电启动延迟 ~134ms 后，若 FIFO 为空且空闲，自动发送递增序号的测试帧。

**帧组装流水线**：
1. FIFO 非空 → `fifo_rd_en` (读发起)
2. 1 拍后 `fifo_rd_en_d1` → 组装帧头 (MAC+IP+UDP+Payload) 到 `frame_buf`
3. 同时启动 CRC-32 计算 (74 cycles)
4. CRC 完成后 1 拍 → 写 FCS → `tx_start` 脉冲 → 逐字节发送

---

### 9. mdio_ctrl（MDIO PHY 管理）

**功能**：IEEE 802.3 Clause 22 MDIO 控制器，配置 YT8531C PHY。

**MDC**: 5MHz (100MHz / 20)

**初始化序列**：
```
I_IDLE (等待 ~16.7ms 上电延迟)
→ I_WAIT (额外等待)
→ I_SET_CHIP (ExtAddr=0xA001)
→ I_WR_CHIP (Chip_Config=0x8040: Rxc_dly_en=0, Cfg_ldo=3.3V)
→ I_SET_LED2 (ExtAddr=0xA00E)
→ I_WR_LED2 (LED2_CFG=0x0644: 1000M link ON + TX/RX blink)
→ I_RD_BCR (读 BCR)
→ I_POLL (循环: BMSR→PkgTx→clrExt→BMSR...)
```

**轮询循环** (I_POLL)：
```
poll_cnt=0: 读 BMSR → 保存 bmsr_val
poll_cnt=1: 写 ExtAddr=0x00AD (PkgTx 寄存器)
poll_cnt=2: 读 ExtData → 保存 rxerr_val (Pkg Tx 计数)
poll_cnt=3: 写 ExtAddr=0x0000 (清零)
```

**状态信号**：
- `cfg_done` = MDIO 初始化序列完成 (i_state >= I_POLL)
- `link_up` = BMSR[2] (Link Status)

---

### 10. top（顶层集成）

**功能**：集成所有模块，包含 SPI 配置 FSM + 帧控制 FSM + CDC 同步器。

**时钟生成** (clk_wiz_0 MMCM)：
```
sys_clk (100MHz) → MMCM
  ├── gate_clk  (50 MHz) : 顶层 FSM + nt39565d_gate_ctrl
  ├── clk_100m  (100 MHz): ad71143_ctrl + ad71143_spi + ad71143_data_rx_dual + mdio_ctrl
  ├── clk_125m  (125 MHz): rgmii_bridge + RGMII_tx
  └── clk_125m_ph90 (125 MHz, 90°): TXC ODDR
```

**复位策略**：
- `rst_n_async = key & pll_locked`
- 每时钟域独立复位同步器 (2-FF 异步断言/同步释放)
- PHY 复位 (`rgmii_rst_n`): PLL 锁定后拉低 ~100ms

**SPI 配置 FSM** (100MHz 域)：
```
CFG_IDLE → (ctrl_init_done && 1s 延迟) → CFG_ISSUE → CFG_WAIT → (spi_done) → CFG_DONE
                                                                                    ↓
                                                              (cfg_reg_idx!=15) → CFG_ISSUE (循环)
```

双 Panel SPI 并行配置，共享 `spi_start`/`spi_reg_addr`/`spi_reg_data`。

**帧控制 FSM** (50MHz 域)：
```
TOP_POWERUP → TOP_WAIT_INIT → TOP_WAIT_CFG → TOP_IDLE → TOP_START → TOP_WAIT_FRAME → TOP_FRAME_GAP → TOP_START ...
```

**CDC 策略**：

| 信号 | 源域 | 目标域 | 方法 |
|------|------|--------|------|
| `ctrl_init_done` | 100 MHz | 50 MHz | 2-FF level sync |
| `ctrl_line_start` | 100 MHz | 50 MHz | toggle + 3-FF + edge detect |
| `frame_start` | 50 MHz | 100 MHz | toggle + 3-FF + edge detect |
| `ctrl_frame_done` | 100 MHz | 50 MHz | toggle + 3-FF + edge detect |
| `spi_cfg_done` | 100 MHz | 50 MHz | 2-FF level sync |
| 数据 Burst | 100 MHz | 125 MHz | Xilinx FIFO IP (async) |

**ILA 调试**：`ila_0` 在 125MHz 域监控 RGMII 发送路径 (startup_done, tx_fsm, crc_busy, BMSR, link_up 等)。

---

## 设计规范

### 时钟域
| 时钟 | 频率 | 用途 |
|------|------|------|
| `sys_clk` (输入) | 100MHz | 板载晶振 → MMCM 输入 |
| `gate_clk` | 50MHz | 顶层 FSM + nt39565d_gate_ctrl |
| `clk_100m` | 100MHz | AD71143 控制 + SPI + 数据接收 + MDIO |
| `clk_125m` | 125MHz | RGMII 桥接 + 发送 |
| `clk_125m_ph90` | 125MHz 90° | RGMII TXC ODDR |
| `rgmii_rxc` (输入) | 125MHz | PHY → RGMII_rx IDDR |

### 复位策略
- `rst_n_async = key & pll_locked`（PLL 锁定后才释放复位）
- 每时钟域独立复位同步器（2-FF）：`rst_n_50m`, `rst_n_100m`, `rst_n_125m`
- `rgmii_rst_n`（PHY 复位）: PLL 锁定后保持低 ~100ms，满足 YT8531C 上电时序
- `roic_reset`（AD71143 RESET 引脚）: 高有效, 脉宽 ≥ 10ns（SPEC）, 本设计 10µs
- RESET 释放后需等待 ≥ 4000ns (tRESETCS) + 本设计额外 1s 延迟 才能开始 SPI 配置

### 信号命名规范
| 前缀/后缀 | 含义 |
|-----------|------|
| `_p/_n` | LVDS 差分对（正/负）|
| `_o` | 输出到顶层端口 |
| `_reg` | 寄存器信号 |
| `_cnt` | 计数器信号 |
| `_ff` | 打拍延迟信号 |
| `_r/_l` | 右/左 FPV 排线输出 |
| `_p0/_p1` | Panel 0 / Panel 1 |

---

## AD71143 芯片详细规格

### 电气特性 (SPEC Table 1)
| 参数 | 值 |
|------|------|
| 通道数 | 256/片 |
| 分辨率 | 16 bit (无失码) |
| 输入电荷范围 (FSR) | 0.5 ~ 16.0 pC（通过 IFS 位配置）|
| 积分电容 (CF) | 0.125 ~ 4.0 pF（CF = 0.125 × (IFS+1) pF）|
| 最小行时间 (tLINE) | 60 µs (双数据率 Pipeline 模式) |
| 低通滤波器时间常数 (τLPF) | 1.3 / 3.9 / 7.8 / 11.7 µs |
| INL | ±2.5 LSB |
| 输入参考随机噪声 | 580 e− rms (Normal, CF=0.5pF, τLPF=3.9µs, ADCAVG=1) |
| DCLK 频率 | 50~200 MHz |
| DCLK 周期 (tDCLK) | 5~20 ns |
| ACLK 周期 (tACLK) | ≥ 20 ns |
| SCK 周期 (tSCK) | ≥ 20 ns |
| LVDS 数据格式 | Serial LVDS, straight binary, MSB first |

### 时序约束 (SPEC Table 2)
| 参数 | Min | Typ | Max | 单位 |
|------|-----|-----|-----|------|
| tBURST | 1765 | tDCLK×(64+M) | — | ns |
| tDCLK | 5 | — | 20 | ns |
| tDDOUT (DCLK→DOUT 延迟) | 0 | 4 | 7 | ns |
| tDAFEDCLK (CDS→DCLK 延迟) | 1640 | — | — | ns |
| tSYNCDCLK (SYNC→DCLK) | 20 | — | — | ns |
| tSYNCACLK (SYNC→ACLK) | 20 | — | — | ns |
| tSYNCH (SYNC 高电平) | 10 | — | — | ns |
| tRESETCS (RESET→CS) | 4000 | — | — | ns |
| tRESET (RESET 高电平) | 10 | — | — | ns |

### Burst 时序
```
每个 Burst = 64 个 Active DCLK + M 个 Muted DCLK
tBURST(min) = 1765ns @ 200MHz → MUTE_MIN ≈ 289 周期 @ 200MHz
@ 100MHz: tBURST=1765ns → 177 cycles - 64 active = 113 mute cycles
```

---

## AD71143 SPI 配置寄存器详表 (SPEC Table 12)

### Register 0 — 电源模式 + 满量程
| Bits | Name | 说明 | 当前值 |
|------|------|------|--------|
| 15 | Write | 写使能 | 1 |
| 14 | Read | 读使能 | 0 |
| [13:10] | ADDR | 固定为 0 | 0 |
| [8:6] | PWR | 000=Normal | 000 |
| [4:0] | IFS | FSR = 0.5×(IFS+1) pC | 20 |

### Register 1 — 滤波器 + 数据格式
| Bits | Name | 说明 | 当前值 |
|------|------|------|--------|
| [8:7] | LPF | 01=3.9µs | 01 |
| 5 | CDS2_RESETEN | 1=使能 CDS2 复位 | 1 |
| 0 | Holes | 0=电子积分 | 0 |

### Register 2 — 模式控制
| Bits | Name | 说明 | 当前值 |
|------|------|------|--------|
| 5 | RNDOMIZE | 1=随机采样积分器 | 1 |
| 2 | DOUTMODE | 1=双 LVDS 输出 | 1 |
| 1 | ECHOCLK | 1=使能 DCLKO | 1 |
| 0 | Pipeline | 1=Pipeline 模式 | 1 |

### Register 3 — 参考 DAC
| Bits | Name | 说明 | 当前值 |
|------|------|------|--------|
| 8 | AZEN | 0=禁用自动调零 | 0 |
| [7:0] | REFDAC | REF_OUT = 0.5V + REFDAC × 15.625mV | 32 (~1.0V) |

### Register 4~7 — AFE 时序开关
| Reg | 字段 | 当前值 | 说明 |
|-----|------|--------|------|
| 4 | INTRST | 0x082 | C=ACLK8, O=ACLK2 |
| 5 | CDS1 | 0x013 | C=ACLK1, O=ACLK3 |
| 6 | CDS2 | 0x046 | C=ACLK4, O=ACLK6 |
| 7 | FA | 0x025 | CDS1=ACLK2, CDS2=ACLK5 |

### Register 8~15
| Reg | 当前值 | 说明 |
|-----|--------|------|
| 8 | 0x000 | CUSTCLMPEN=0 |
| 10 | 0x000 | PIPELINE_AVGEN=0 |
| 11 | 0x000 | LFSR_EN=0 |
| 12 | 0x000 | LP_EN=0 (Normal 模式) |

---

## AFE 时序配置速查 (Pipeline Mode, SPEC Figure 22)

### ACLK 编号与开关动作映射
```
ACLK0: (不使用 — 留给 SYNC 建立时间)
ACLK1: CDS1 闭合 — 采样积分器复位电平
ACLK2: FA 打开 (CDS1 后) + INTRST 打开
ACLK3: CDS1 打开
ACLK4: CDS2 闭合 — 采样信号电平
ACLK5: FA 打开 (CDS2 后)
ACLK6: CDS2 打开
ACLK7: (不使用)
ACLK8: INTRST 闭合 — 复位积分器
```

### 对应寄存器配置值
```
Reg 4 (INTRST): Bits[7:4]=8, Bits[3:0]=2   → ACLK8 闭合, ACLK2 打开
Reg 5 (CDS1):   Bits[7:4]=1, Bits[3:0]=3   → ACLK1 闭合, ACLK3 打开
Reg 6 (CDS2):   Bits[7:4]=4, Bits[3:0]=6   → ACLK4 闭合, ACLK6 打开
Reg 7 (FA):     Bits[7:4]=2, Bits[3:0]=5   → CDS1:ACLK2 打开, CDS2:ACLK5 打开
```

---

## 常用命令

### 仿真
```bash
make tb              # 顶层仿真
make tb_data_rx      # 单 Panel 数据接收仿真
make tb_data_rx_dual # 双 Panel 数据接收仿真
make clean           # 清理输出文件

# 独立 Testbench (需手动运行, 参见 Develop.md)
```

### Vivado 综合+实现
```tcl
reset_runs synth_1; launch_runs synth_1 impl_1 -jobs 4; wait_on_runs impl_1; launch_runs impl_1 -to_step write_bitstream -jobs 4; wait_on_run impl_1
```

### 生成配置存储器文件
```tcl
source board/TCL/write_cfgmem.tcl
```

### PC 侧抓包
```bash
sudo ip link set enp0s13f0u2u1 up
sudo ip addr add 192.168.1.1/24 dev enp0s13f0u2u1
sudo tcpdump -i enp0s13f0u2u1 'udp port 1234' -e -vv
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
- [x] AD71143 控制信号发生器 RESET+SYNC+ACLK (`ad71143_ctrl.v`)
- [x] AD71143 单 Panel LVDS 数据接收 (`ad71143_data_rx.v`)
- [x] AD71143 双 Panel 数据接收+合并 (`ad71143_data_rx_dual.v`)
- [x] NT39565D Gate Driver 控制 (`nt39565d_ctrl.v`)
- [x] RGMII 发送/接收模块 (`RGMII_tx.v`, `RGMII_rx.v`)
- [x] RGMII 桥接 + UDP/IP/MAC 协议栈 (`rgmii_bridge.v`)
- [x] MDIO PHY 控制器 (`mdio_ctrl.v`)
- [x] 顶层集成: SPI 配置 FSM (16 寄存器 LUT) + 帧控制 FSM + CDC
- [x] 双 Panel SPI 并行配置
- [x] 上电初始化 SPI 配置序列（自动写 16 个寄存器，延迟 1s 后启动）
- [x] PHY 复位时序 (~100ms)
- [x] ILA 调试探针集成 (RGMII 发送诊断)
- [x] CRC-32 FCS 计算与校验
- [ ] 两片 AFE 数据的 Bitslip/Deskew 对齐
- [ ] AD 芯片 SPI 修复 / 硬件更换 (SPI SDO 无响应)
- [ ] RGMII 物理层信号质量诊断 (PC 端偶有丢帧)
- [ ] 数据缓存到 BRAM/FIFO（FIFO IP 已集成，待优化深度/位宽）
- [ ] PC 端完整数据接收与图像重建软件
- [ ] 实际硬件全链路测试 (需两片 AD 均正常工作)

---

## 相关文档

- AD71143 SPEC (Rev. SpA, 2016) — `document/3.AD71143 SPEC.pdf`
- NT39565D 数据手册 — `document/1.1 NT39565D_V01_20130219.pdf`
- TFT 传感器规格书（3.99" IGZO）
- YT8531C 数据手册
- AFE2256 EVM 用户指南（参考设计）
- 项目进度 + 时钟树 — `README.md`
- 开发日志 — `Develop.md`

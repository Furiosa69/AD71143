name: X-Ray TFT Driver
description: 3.99英寸 X射线平板探测器 TFT 驱动系统，包含 NT39565D Gate Driver 和 AD71143 AFE 的 FPGA 控制逻辑
version: 2.0
author: Furiosa

# X-Ray TFT Driver 项目 Skill

## 项目概述

这是一个 **X射线平板探测器（FPD）** 的 FPGA 控制逻辑项目。系统包含三个核心芯片：

| 芯片 | 型号 | 功能 | 通道数 |
|------|------|------|--------|
| **Gate Driver** | NT39565D | 逐行打开 TFT 开关 | 541/513/385/361 可选 |
| **AFE (Readout)** | AD71143 | 电荷 → 数字信号转换 | 256 通道/片，共 2 片 |
| **TFT Sensor** | 3.99" IGZO | X射线感光面板 | 512 × 512 像素 |

### 信号链

```
X射线 → 闪烁体 → 可见光 → TFT传感器(电荷) → AFE(数字) → FPGA(处理) → PC(图像)
                                        ↑
                                    Gate Driver
                                    (逐行打开TFT)
```

---

## 项目结构

```
ctrl/
├── src/
│   ├── nt39565d_ctrl.v          # Gate Driver 控制模块
│   ├── ad71143_ctrl.v           # AD71143 控制信号发生器 (RESET + SYNC + ACLK)
│   ├── ad71143_spi.v            # AD71143 SPI 配置主机
│   ├── ad71143_data_rx.v        # AFE LVDS 数据接收模块（双片合并）
│   └── top.v                    # 顶层模块（状态机 + 例化）
├── tb/
│   ├── tb_top.v                 # 顶层 Testbench
│   ├── tb_ad71143_data_rx.v     # AFE 数据接收 Testbench
│   └── spi_test_top.v           # SPI 模块 Testbench
├── Makefile                     # Icarus Verilog 仿真
├── document/
│   ├── 3.AD71143 SPEC.pdf       # AD71143 芯片规格书 (Rev. SpA, 34页)
│   └── 1.1 NT39565D_V01_20130219.pdf  # NT39565D 数据手册
└── .claude/skill/
    └── xray-tft-driver.md       # 本文件
```

---

## 模块详解

### 1. nt39565d_gate_ctrl（Gate Driver 控制）

**功能**：产生 NT39565D 所需的 CPV/STV/OE 时序

**关键参数**（25MHz 时钟）：
```verilog
CLK_FREQ_MHZ      = 25     // 系统时钟
CPV_PERIOD_US     = 10     // CPV 周期 (10µs → 100kHz)
CPV_PW_US_X10     = 10     // CPV 脉宽 (1.0µs)
STV_SETUP_US_X10  = 3      // STV 建立时间 (0.3µs)
STV_HOLD_US_X10   = 4      // STV 保持时间 (0.4µs)
OE_PW_US_X10      = 10     // OE 脉宽 (1.0µs)
```

**状态机**：
```
IDLE → STV_SETUP → STV1_ASSERT → STV_HOLD → CPV_LOW → CPV_HIGH → (循环) → FRAME_END → IDLE
```

**输出信号**：
- `cpv`: 移位时钟（≤200kHz）
- `stv1`: 帧起始脉冲
- `oe1/oe2`: 输出使能（高有效）
- `line_done`: 单行扫描完成脉冲
- `frame_done`: 一帧扫描完成脉冲

---

### 2. ad71143_ctrl（AD71143 控制信号发生器）

**功能**：产生 AD71143 所需的 RESET、SYNC、ACLK 时序。实现 AD71143 SPEC Figure 22 (Pipeline Mode) 的时序。

**系统时钟**: 100MHz (10ns)

**关键参数**：
```verilog
ACLK_PULSES      = 9      // 每行 ACLK 脉冲数
LINE_CYCLES      = 6000   // 行周期 60µs @ 100MHz
RESET_CYCLES     = 1000   // RESET 脉宽 10µs
INIT_WAIT_CYCLES = 10000  // 初始化等待 100µs
```

**输出信号**：
- `roic_reset`: 异步复位（高有效，≥10ns → 本设计 10µs）
- `sync`: 转换同步（低有效），下降沿 = 新行开始
- `aclk`: AFE 时序时钟（50MHz, 20ns 周期），每行 9 个脉冲
- `aclk_idx`: 当前 ACLK 脉冲编号（0~8）
- `init_done`: 初始化完成
- `line_start` / `line_done`: 行起止脉冲
- `line_cnt`: 行计数

**状态机**：
```
INIT_RESET → INIT_WAIT → SYNC_SETUP → ACLK_ACT → SYNC_HOLD → LINE_GAP → SYNC_SETUP → ...
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

### 4. ad71143_data_rx（AFE LVDS 数据接收）

**功能**：接收 AD71143 的 LVDS 串行数据，合并两片 AFE 的数据。
按 SPEC Figure 37/38 实现：
- DOUTMODE = 1（双 LVDS 输出模式）
- 用 DCLKO 上升沿采样 DOUTA/DOUTB
- 每个 Burst 采 64bit/lane，共 128bit
- 数据 Burst 内合并为 8 个 16-bit 样本

**接口定义**：
```verilog
// 系统
clk_sys         : 200MHz 系统时钟
rst_n           : 低有效复位

// 时序控制（两片共用）
sync_in         : SYNC 信号（下降沿 = 新行开始）
aclk_done       : ACLK 序列完成标志

// DCLK 输出（两片共用）
dclk_p/dclk_n   : LVDS 差分时钟（FPGA → AFE）

// DCLKO 输入（回波时钟，AFE → FPGA）
dclko_p/n_A     : 用 DCLKO 上升沿采样数据

// DOUT 输入（两片独立）
dout_p/n_A      : AFE A 数据（偶数通道: 0,2,4,...,254）
dout_p/n_B      : AFE B 数据（奇数通道: 1,3,5,...,255）

// 合并输出
merged_burst[127:0]     : 两片 AFE 合并数据（64+64 bit）
merged_burst_index[6:0] : 0=Header, 1~32=数据通道
merged_burst_valid      : 数据有效标志
line_done               : 一行完成脉冲
header_ok               : Header 同步字匹配
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

**数据合并格式**（READDOWN=0）:
```
merged_burst[127:0] = {A_word0, B_word0, A_word1, B_word1, A_word2, B_word2, A_word3, B_word3}
每个 word = 16 bit → 8 通道/Burst
Burst N 包含通道: N*8 ~ N*8+7
```

**状态机**：
```
IDLE → WAIT（等待 aclk_done）→ ACT（收64bit）→ MUTE（静默期）→ ACT/MUTE 循环 → DONE → IDLE
```

---

### 5. top（顶层状态机）

**功能**：控制帧扫描循环，自动触发多帧采集

**当前连接**：
- 仅例化了 `nt39565d_gate_ctrl`
- Gate Driver 产生 `line_done`/`frame_done` 反馈给 top 状态机
- AD71143 的 AFE 控制链 (ad71143_ctrl → ad71143_spi → ad71143_data_rx) 尚未集成到 top

**状态机**：
```
IDLE → START → WAIT_FRAME → (frame_done) → FRAME_GAP → (计数完成) → START
```

---

## 设计规范

### 时钟域
| 时钟 | 频率 | 用途 |
|------|------|------|
| `sys_clk` (输入) | 50MHz | 板载晶振 → top 状态机 |
| `clk_sys` (ad71143_ctrl) | 100MHz | AD71143 控制信号 + SPI |
| `clk_sys` (ad71143_data_rx) | 200MHz | LVDS 数据接收（DCLK 基频） |

### 复位策略
- `rst_n = key & locked`（PLL 锁定后才释放复位）
- `roic_reset`（AD71143 RESET 引脚）: 高有效, 脉宽 ≥ 10ns（SPEC）, 本设计 10µs
- RESET 释放后需等待 ≥ 4000ns (tRESETCS) 才能开始 SPI 配置

### 信号命名规范
| 前缀/后缀 | 含义 |
|-----------|------|
| `_p/_n` | LVDS 差分对（正/负）|
| `_o` | 输出到顶层端口 |
| `_reg` | 寄存器信号 |
| `_cnt` | 计数器信号 |
| `_ff` | 打拍延迟信号 |

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
转换期间连续时钟 DCLKx: 34 个 Burst 后可以连续输出
```

### 电源 (SPEC Table 1)
| 电源 | 电压 | 说明 |
|------|------|------|
| AVDD5F, AVDD5B, DVDD5 | 4.75~5.25V | 5V 模拟/数字供电 |
| AVDD2, DVDD2 | 2.375~2.625V | 2.5V 模拟/数字供电 |
| AVDDI | REF_TFT + 1.2V | 积分器高压供电 |
| AVSSI | REF_TFT - 0.6V (max) | 积分器低压供电 |
| AVDDI − AVSSI | 1.8~2.7V | 积分器供电差 |
| IOVDD | 2.3~2.7V | 数字 IO 供电 (推荐 2.5V) |

### 运行供电约束 (SPEC Figure 28)
- 0 ≤ AVDDI − AVSSI ≤ 2.7V
- |AVDDI − REF_TFT| ≤ 2.7V
- |AVSSI − REF_TFT| ≤ 2.7V
- AVDD5F − AVSSI ≥ 0.0V
- AVDD5Q − AVSSI ≥ 0.0V
- REF_TFT 必须 ≥ AVSSI + 0.6V 且 ≤ AVDDI − 1.2V

### 上电顺序 (SPEC Figure 29)
1. 施加 AVDD2, AVDD5B/5F/5Q, DVDD5, DVDD2, REF_ADC
2. REF_OUT 启动（默认 2.5V）→ REF_INT, REF_TFT 跟随
3. 通过 SPI 配置 REF_OUT 最终值
4. 使能 REF_OUT（设置 PDTFTEN 或选择其他电源模式）
5. 施加 AVDDI 到最终值
6. 施加 AVSSI 到最终值（必须在 AVDDI 之后或同时）
7. 如果 REF_TFT ≥ 2.7V，AVDDI 和 AVSSI 必须在 REF_TFT 到达最终值之前或同时到达

### 功耗模式 (SPEC Table 10)
| 模式 | PWR[2:0] | 功耗 | 说明 |
|------|----------|------|------|
| Normal | 0 | 363 mW (1.42 mW/ch) | 全速运行 |
| Low Power | 4 + LP_EN=1 | 260 mW (1.02 mW/ch) | 低功耗，噪声略高 |
| Sleep | 4 + LP_EN=0 | 56~61 mW | 积分器保持 REF_TFT |
| Power-Down | 5 | 1.2 mW | 最低功耗 (SPI 仅存活) |
| Power-Down + Panel Bias | 5 + PDTFTEN=1 | 16~21 mW | 断电但维持面板偏压 |

---

## AD71143 转换模式 (SPEC Figure 27)

### Pipeline Mode (PIPELINE=1)
- AFE 采样和数字转换**并行**进行
- 最小行时间 = max(tAFE, tDCONV)
- 双数据率: 最小 60µs
- 单数据率: 最小 70µs
- 推荐 Pipeline 模式下不使用 ACLK0 关闭 CDS1

### Serial Mode (PIPELINE=0)
- AFE 采样和数字转换**串行**进行
- 最小行时间 = tAFE + tDCONV

**共用约束**:
- 数据转换和数据输出总是同时进行（之间有 1 行的流水线延迟）
- Pipeline 模式下 DCLKx Burst 不能与 INTRST 开/关、CDS1 关、CDS2 关的 200ns 内重叠

---

## AD71143 SPI 配置寄存器详表 (SPEC Table 12)

**SPI 协议**: 16-bit 帧 = Bit[15] Write + Bit[14] Read + Bit[13:10] Address + Bit[9:0] Data
**基地址**: 寄存器地址编码在 Bit[13:10] 中
**双缓冲**: 寄存器在 CS 下降沿更新

### Register 0 — 电源模式 + 满量程
| Bits | Name | 说明 | Reset |
|------|------|------|-------|
| 15 | Write | 写使能 | 0 |
| 14 | Read | 读使能 | 0 |
| [13:10] | ADDR | 固定为 0 | 0 |
| 9 | — | 工厂保留，写 0 | 0 |
| [8:6] | PWR | 000=Normal, 100=Sleep/LP, 101=Power-Down | 101 |
| 5 | — | 工厂保留，写 0 | 1 |
| [4:0] | IFS | 积分器满量程: FSR = 0.5×(IFS+1) pC (max 16pC) | 0 |

### Register 1 — 滤波器 + 数据格式
| Bits | Name | 说明 | Reset |
|------|------|------|-------|
| [8:7] | LPF | 00=1.3, 01=3.9, 10=7.8, 11=11.7 µs | 0 |
| 5 | CDS2_RESETEN | 1=INTRST+CDS1 闭合时复位 CDS2 电容 | 0 |
| 4 | CMR_EN | 1=使能共模抑制 | 0 |
| 3 | READDOWN | 1=CH255→CH0, 0=CH0→CH255 | 0 |
| 2 | EXTRST | 1=外部 REF_INT, 0=REF_TFT | 0 |
| 1 | ADCAVG | 1=ADC 4次平均（需 PIPELINE_AVGEN=1 配合）| 0 |
| 0 | Holes | 1=空穴积分, 0=电子积分 | 0 |

### Register 2 — 模式控制
| Bits | Name | 说明 | Reset |
|------|------|------|-------|
| 8 | PDTFTEN | 1=Power-Down 时维持 REF_TFT 偏压 | 0 |
| 7 | REFDACDIS | 1=禁用内部参考 DAC (省 5mW) | 0 |
| 5 | RNDOMIZE | 1=随机采样积分器（减少模式噪声）, 0=顺序 | 1 |
| 3 | INTCLAMP | 1=使能积分器防饱和钳位 (antiblooming) | 0 |
| 2 | DOUTMODE | 1=双 LVDS 输出 (A偶数+B奇数), 0=单 LVDS | 0 |
| 1 | ECHOCLK | 1=使能 DCLKO 回波时钟 | 0 |
| 0 | Pipeline | 1=Pipeline 模式, 0=Serial 模式 | 0 |

### Register 3 — 参考 DAC + 自动调零
| Bits | Name | 说明 | Reset |
|------|------|------|-------|
| 8 | AZEN | 1=使能自动调零 (改善 1/f 噪声，无 VT/Temp 数据) | 0 |
| [7:0] | REFDAC | REF_OUT = 0.5V + REFDAC × 15.625mV (0.5~4.5V) | 128 (2.5V) |

**REFDAC 关键值**：
- Code 0 → 0.5V
- Code 128 → 2.5V (默认)
- Code 224 (0xE0) → 4.0V
- Code 255 → ~4.5V

### Register 4 — INTRST 开关时序
| Bits | Name | 说明 | Reset |
|------|------|------|-------|
| [7:4] | INTRST_C | 关闭时刻 (ACLK 编号 0x0~0xC) | 7 |
| [3:0] | INTRST_O | 打开时刻 (0xE=常开, 0xF=常闭) | 1 |

### Register 5 — CDS1 开关时序
| Bits | Name | 说明 | Reset |
|------|------|------|-------|
| [7:4] | CDS1_C | 关闭时刻 | 0 |
| [3:0] | CDS1_O | 打开时刻 | 3 |

### Register 6 — CDS2 开关时序
| Bits | Name | 说明 | Reset |
|------|------|------|-------|
| [7:4] | CDS2_C | 关闭时刻 | 4 |
| [3:0] | CDS2_O | 打开时刻 | 6 |

### Register 7 — FA (Filter Acceleration) 时序
| Bits | Name | 说明 | Reset |
|------|------|------|-------|
| [7:4] | FA_CDS1 | CDS1 后 FA 打开时刻 | 2 |
| [3:0] | FA_CDS2 | CDS2 后 FA 打开时刻 | 5 |

### Register 8 — 自定义钳位时序
| Bits | Name | 说明 | Reset |
|------|------|------|-------|
| 8 | CUSTCLMPEN | 1=使能自定义钳位窗口 | 0 |
| [7:4] | CUSTCLMP_C | 钳位窗口开启时刻 (ACLK 编号) | 0 |
| [3:0] | CUSTCLMP_O | 钳位窗口关闭时刻 (必须 > CDS2 关闭) | 0 |

### Register 10 — Pipeline 平均
| Bits | Name | 说明 | Reset |
|------|------|------|-------|
| 0 | PIPELINE_AVGEN | 1=使能 Pipeline 模式下的 ADC 平均 | 0 |

### Register 11 — LFSR 数字完整性检查
| Bits | Name | 说明 | Reset |
|------|------|------|-------|
| 6 | LFSR_EN | 1=使能 LFSR 数字接口完整性校验 | 0 |

### Register 12 — 低功耗使能
| Bits | Name | 说明 | Reset |
|------|------|------|-------|
| 8 | LP_EN | 1=使能低功耗模式 (需 PWR=4) | 0 |

### 典型配置序列（上电后）
```
1. RESET 高 → 等待 10µs → RESET 低 → 等待 ≥ 4µs (tRESETCS)
2. Reg 3: 配置 REFDAC → REF_OUT 目标电压
3. Reg 0: 设置 IFS (满量程) + PWR (退出 Power-Down)
4. Reg 1: 设置 LPF, READDOWN, EXTRST, Holes
5. Reg 2: 设置 DOUTMODE, ECHOCLK, Pipeline
6. Reg 4~7: 配置 AFE 时序开关 (INTRST/CDS1/CDS2/FA)
7. 等待电源稳定 → 开始转换
```

---

## AD71143 AFE 模拟信号链 (SPEC Figure 18)

```
ANx → [Integrator (CF可变, IFS配置)] → [LPF (τLPF可变)] → [CDS1/CDS2] → MUX → 16-bit ADC → LVDS输出
      ↑                                  ↑                    ↑
   INTRST 复位                       FA 加速              CDS 相关双采样
   (至 REF_TFT/REF_INT)             (短路LPF电阻)         (消除 offset + 1/f 噪声)
```

### AFE 采样时序（每行）
```
1. INTRST 闭合 → 积分器复位到 REF_TFT (或 REF_INT)
2. INTRST 打开 → 复位结束
3. CDS1 闭合 → 采样复位电平到 CDS1 电容
4. CDS1 打开
5. Gate Driver 打开 TFT → 电荷从面板转移到积分器
6. CDS2 闭合 → 采样信号电平到 CDS2 电容
7. CDS2 打开
8. ADC 转换 CDS1/CDS2 差分电压
```

### 积分器复位时间建议 (SPEC Table 6, Normal Mode)
| 面板电容 | CF ≤ 2pF | CF > 2pF |
|----------|---------|---------|
| 0~80 pF | 6.0 µs | 12.0 µs |
| 100 pF | 6.6 µs | 17.7 µs |
| 150 pF | 16.0 µs | 30.0 µs |
| 200 pF | 43.2 µs | 64.0 µs |

### CDS 时间建议
- tCDS1, tCDS2 ≥ 5 × τLPF（16-bit 完全建立）

---

## AD71143 数据传输接口

### 数据输出模式
| DOUTMODE | 说明 | Burst/行 | DOUTA | DOUTB |
|----------|------|---------|-------|-------|
| 0 (Single) | 单 LVDS | 67 (256ch) | CH0~255 串行 | 未用 |
| 1 (Double) | 双 LVDS | 34 | 偶数 CH: 0,2,4,...,254 | 奇数 CH: 1,3,5,...,255 |

### ADC 平均模式 (ADCAVG=1, PIPELINE_AVGEN=1)
- 内部 ADC 4次平均 → 降低 back-end 噪声 (109→82 µV rms)
- 需要 130 个 Bursts (128 Data + 1 VT/Temp + 1 CMR)
- 最短行时间: 229.45 µs
- τLPF 翻倍 (1.3→2.6, 3.9→7.8, ...)

### Echo Clock 模式 (ECHOCLK=1)
- DCLKOx 是 DCLKx 的缓冲副本
- 数据在 DCLKOx 上升沿更新 (tD = -1~+1 ns)
- 推荐用于简化 FPGA 数据同步

### 传递函数
```
LSB_SIZE = 0.125 pF × (IFS + 1) × 61.035 µV
Charge   = DATA_OUT × LSB_SIZE
FSRQ     = 65536 × LSB_SIZE
```

### VT 结果
```
VT = VTCODE × 61.035 µV + 0.5V
```

### 温度结果
```
0°C → ~4380 LSB, 灵敏度 = 17 LSB/°C
50°C → ~5230 LSB
```

---

## AFE 时序配置速查 (参照 SPEC Figure 22, Pipeline Mode)

### ACLK 编号与开关动作映射（Pipeline Mode 推荐值）
```
ACLK0: (不使用 — 留给 SYNC 建立时间)
ACLK1: CDS1 闭合 — 采样积分器复位电平
ACLK2: FA 打开 (CDS1 后) — 断开滤波加速
ACLK3: CDS1 打开
ACLK4: CDS2 闭合 — 采样信号电平
ACLK5: FA 打开 (CDS2 后)
ACLK6: CDS2 打开
ACLK7: INTRST 闭合 — 复位积分器
ACLK8: INTRST 打开
```

### 对应寄存器配置值
```
Reg 4 (INTRST): Bits[7:4]=8, Bits[3:0]=2   → ACLK8 闭合, ACLK2 打开
Reg 5 (CDS1):   Bits[7:4]=1, Bits[3:0]=3   → ACLK1 闭合, ACLK3 打开
Reg 6 (CDS2):   Bits[7:4]=4, Bits[3:0]=6   → ACLK4 闭合, ACLK6 打开
Reg 7 (FA):     Bits[7:4]=2, Bits[3:0]=5   → CDS1:ACLK2 打开, CDS2:ACLK5 打开
```

---

## 参考电压配置模式 (SPEC Figure 32-34)

### 模式 1: REF_TFT = REF_INT = REF_OUT（推荐）
- 内部 DAC 同时提供 REF_TFT 和 REF_INT
- EXTRST = 0
- 外部仅需 REF_ADC (4.096V ADR444)

### 模式 2: REF_TFT 外部, REF_INT = REF_OUT
- 用户提供外部 REF_TFT (0.6~2.7V)
- REF_OUT 提供 REF_INT
- EXTRST = 1

### 模式 3: REF_TFT 外部, REF_INT 外部
- 用户提供两者
- REFDAC 必须近似等于外部 REF_INT（偏差 = offset）
- EXTRST = 1

---

## 设计约束与注意事项

### DCLK/ACLK/SCK 互斥
- DCLKx 和 ACLK 活跃时，SCK 必须保持低电平
- 配置期间（CS=高）, SYNC 和 DCLKx 必须保持低电平
- 转换期间 CS 必须保持低电平

### Pipeline 模式 DCLK 禁区
- DCLKx Burst 不能与以下开关动作的 200ns 内重叠：
  - INTRST 打开
  - INTRST 闭合
  - CDS1 闭合
  - CDS2 闭合

### 数据完整性
- SYNC 脉冲若在最小 Burst 数之前出现 → 数据损坏
- 34 Burst 后可以连续时钟 DCLKx 以更快读取数据
- 4288 个 DCLK 后（Header+Data+Config）输出全 0

### Daisy-Chain SPI
- 多个 AD71143 可通过 SDI→SDO 级联
- SDI(ADC_N) = SDO(ADC_N-1)
- SCK, CS, RESET 共用
- 一次 CS 周期可写入链上所有器件

---

## 常用命令

### 仿真
```bash
make tb          # 编译 + 运行仿真
make clean       # 清理输出文件
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
- [ ] top 层集成: nt39565d + ad71143_ctrl + ad71143_spi + ad71143_data_rx
- [ ] 上电初始化 SPI 配置序列（自动写 16 个寄存器）
- [ ] 两片 AFE 数据的 Bitslip/Deskew 对齐
- [ ] 数据缓存到 BRAM/FIFO
- [ ] 数据上传到 PC（以太网口）
- [ ] 实际硬件测试

---

## 相关文档

- AD71143 SPEC (Rev. SpA, 2016) — `document/3.AD71143 SPEC.pdf`
- NT39565D 数据手册 — `document/1.1 NT39565D_V01_20130219.pdf`
- TFT 传感器规格书（3.99" IGZO）
- AFE2256 EVM 用户指南（参考设计）

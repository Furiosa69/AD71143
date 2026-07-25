# AD71143 LFSR 测试模式与 Reg11 详解

> 提取来源：`document/3.AD71143 SPEC.pdf` (Rev. SpA, 34 页)
> 提取页面：Page 28 (Digital Interface Integrity)、Page 33 (Configuration Register 11)

---

## 一、Configuration Register 11 (Reg11) 位定义

| Bit | 名称 | 说明 | 复位值 | 读回值 |
|-----|------|------|--------|--------|
| 15 | Write | 1: 在下一个 CS 下降沿写入后续 15 位；0: 忽略。写操作时必须为 1 | 0 | 0 |
| 14 | Read | 1: 在下一个 CS 上升沿后从 SDO 输出寄存器内容；写操作时必须为 0 | 0 | 0 |
| [13:10] | ADDR | 配置寄存器地址，Reg11 必须设为 `4'b1011` (0xB) | 0 | 11 |
| [9:7] | Not used | 工厂用，保持复位值 | 0 | 0 |
| **6** | **LFSR_EN** | **线性反馈移位寄存器使能。1=启用 LFSR 特性** | **0** | **LFSR_EN** |
| [5:0] | Not used | 工厂用，保持复位值 | 0 | 24 |

### 关键结论

- **LFSR 使能位是 Bit 6，不是 Bit 0。**
- 启用 LFSR：`Reg11[6] = 1`，即写入 `10'h040`。
- 关闭 LFSR：`Reg11[6] = 0`，即写入 `10'h000`。

完整 SPI 写帧（16-bit，MSB first）：

```
Bit[15]    Write = 1
Bit[14]    Read  = 0
Bit[13:10] ADDR  = 4'b1011 (Reg11)
Bit[9:0]   Data  = 10'b0001000000 = 10'h040 (启用 LFSR)
                       10'b0000000000 = 10'h000 (关闭 LFSR)
```

---

## 二、LFSR 测试模式说明

摘自数据手册 **Digital Interface Integrity** 章节（Page 28）：

> The AD71143 has an internal linear feedback shift register (LFSR) that verifies the integrity of the digital interface. The values of the LFSR are read on DOUTAx and DOUTBx in the same manner as conversion data (see Figure 36 and Figure 37). Each unique configuration of the AD71143 has a specific LFSR pattern, which allows the user to have integrity checks for different configurations.

### LFSR 复位方式

- 对 AD71143 施加 reset（RESET 引脚）
- 或向 SPI 端口写入 `0xFFFE`

### LFSR 禁用方式

- 向 SPI 端口写入 `0xAC00`

### LFSR 典型使用流程

1. 通过 SPI 按需求配置 AD71143。
2. 置位 LFSR_EN（Reg11[6] = 1），启用 LFSR。
3. 读取 N 行数据。
4. 将读取结果存入查找表（lookup table）。
5. 将查找表值与已知正常设置的读取结果进行对比。
6. （单芯片验证可选）复位 LFSR，然后重复步骤 1-4。

> 提示：LFSR 值通过 DOUTAx/DOUTBx 读取，读取方式与普通转换数据相同。不同配置下 LFSR 模式不同，可用于数字接口完整性检查。

---

## 三、当前项目配置核对

### 当前代码（LFSR 关闭）

文件：`board/Project/project_1/project_1.srcs/sources_1/imports/src/top.v`

```verilog
(cfg_reg_idx == 4'd11) ? 10'h000 :  // Reg11: LFSR_EN=0
```

此配置正确关闭 LFSR。

### 之前测试过的错误配置

```verilog
(cfg_reg_idx == 4'd11) ? 10'h001 :  // 错误：把 Bit 0 当作 LFSR_EN
```

**问题：** `10'h001` 只设置了 Bit 0，而真正的 LFSR_EN 是 Bit 6，因此 LFSR 实际上并未启用。这就是为什么 LFSR 开关前后抓包数据没有明显变化的原因。

### 正确启用 LFSR 的配置

```verilog
(cfg_reg_idx == 4'd11) ? 10'h040 :  // Reg11: LFSR_EN=1 (Bit 6)
```

---

## 四、SPI 帧格式参考

AD71143 采用 16-bit SPI 帧（MSB first）：

```
Bit[15]    R/W: 1=写，0=读
Bit[14]    RD:  1=读，0=写（与 Bit 15 互斥）
Bit[13:10] ADDR: 寄存器地址 0~15
Bit[9:0]   DATA: 寄存器数据
```

---

## 五、相关寄存器速查（当前项目默认值）

| Reg | 当前值 | 说明 |
|-----|--------|------|
| 0 | 0x014 | PWR=Normal, IFS=20 |
| 1 | 0x0A1 | LPF=3.9µs, CDS2_RESETEN=1 |
| 2 | 0x027 | RNDOMIZE=1, DOUTMODE=1, ECHOCLK=1, Pipeline=1 |
| 3 | 0x020 | REFDAC=32 (~1.0V) |
| 4 | 0x082 | INTRST: ACLK8 闭合, ACLK2 打开 |
| 5 | 0x013 | CDS1: ACLK1 闭合, ACLK3 打开 |
| 6 | 0x046 | CDS2: ACLK4 闭合, ACLK6 打开 |
| 7 | 0x025 | FA: CDS1=ACLK2, CDS2=ACLK5 |
| 8 | 0x000 | CUSTCLMPEN=0 |
| 10 | 0x000 | PIPELINE_AVGEN=0 |
| **11** | **0x000** | **LFSR_EN=0** |
| 12 | 0x000 | LP_EN=0 (Normal 模式) |

---

## 六、图片文件索引

PDF 已转换为 PNG 图片，保存在 `document/ad71143_spec_images/` 目录：

```
page_01.png ~ page_34.png
```

关键页面：

- `page_28.png` — Digital Interface Integrity（LFSR 说明）
- `page_33.png` — Configuration Register 11 完整位定义

---

*Generated for deepseek/LLM-readable format.*

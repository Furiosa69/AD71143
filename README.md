# 项目进度

## NT39565d 测试

仿真通过，可以稳定输出 10 帧或更多。

## AD71143 测试

SPI 通过，两路数据组合通过。

## 时钟树

```
sys_clk (50 MHz, pin R4)
  │
  ├─ gate_clk = sys_clk (直连, 50 MHz)
  │   ├── 顶层 FSM (TOP_POWERUP → WAIT_INIT → WAIT_CFG → IDLE → ...)
  │   └── nt39565d_gate_ctrl (栅极驱动 CPV/STV/OE)
  │
  ├─ PLLE2_BASE (VCO=1000 MHz)
  │   └── CLKOUT0 ÷10 → clk_100m (100 MHz)
  │       ├── ad71143_ctrl (AFE 控制 FSM, ACLK=50 MHz)
  │       ├── ad71143_spi × 2 (SPI 主机, SCK=25 MHz)
  │       ├── ad71143_data_rx_dual × 2 panel
  │       │   ├── ODDR → DCLK 输出 @ 100 MHz
  │       │   └── DCLKO 回波时钟域 (异步, 位捕获)
  │       └── rgmii_bridge (burst 捕获 + CDC)
  │
  └─ MMCME2_BASE (rgmii_bridge.v 内部, VCO=1250 MHz)
      └── CLKOUT0 ÷10 → clk_125m (125 MHz)
          └── RGMII_tx + CDC 同步器

  外部异步时钟：rgmii_rxc @ 125 MHz（PHY 输入 → RGMII_rx）
```

| | 现在 |
|---|---|
| 时钟域数量 | 50 / 100 / 125 MHz |
| PLL 输出 | CLKOUT0 (100M) 独用 |
| DCLK 频率 | 100 MHz |
| ctrl ↔ data_rx | 同一 100 MHz 域，无需 CDC |
| data_rx → bridge | 100↔125 CDC |
| 每 bit 捕获窗口 | 10 ns |

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

### 5. `nt39565d_ctrl.v` — 模块 `nt39565d_gate_ctrl`（11 状态，最复杂）

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

### 7. `top.v` — SPI 配置 FSM（模块 `top` 内）

| 状态 | 转移条件 |
|---|---|
| `CFG_IDLE` | `ctrl_init_done` → `CFG_ISSUE` |
| `CFG_ISSUE` | 无条件 → `CFG_WAIT` |
| `CFG_WAIT` | `spi_done` → `CFG_DONE` |
| `CFG_DONE` | `cfg_reg_idx != 15` → `CFG_ISSUE`（循环写下一寄存器）；否则保持 `CFG_DONE` |

---

### 8. `top.v` — 顶层帧控制 FSM（模块 `top` 内）

| 状态 | 转移条件 |
|---|---|
| `TOP_POWERUP` | 无条件 → `TOP_WAIT_INIT` |
| `TOP_WAIT_INIT` | `init_done_synced` → `TOP_WAIT_CFG` |
| `TOP_WAIT_CFG` | `cfg_done_synced` → `TOP_IDLE` |
| `TOP_IDLE` | 无条件（1 周期后） → `TOP_START` |
| `TOP_START` | 发出 `frame_start=1` → `TOP_WAIT_FRAME` |
| `TOP_WAIT_FRAME` | `frame_done_rise` → `TOP_FRAME_GAP` |
| `TOP_FRAME_GAP` | `gap_cnt >= FRAME_GAP_CYCLES - 1` → `TOP_START` |

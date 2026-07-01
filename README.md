# 项目进度
## NT39565d测试
仿真通过，可以稳定输出10帧或更多

## AD71143测试
SPI通过，两路数据组合通过

## 时钟树
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

  ┌──────────────────┬───────────────────────────┐
  │                  │           现在            │
  ├──────────────────┼───────────────────────────┤
  │ 时钟域数量       │ 50 / 100 / 125 MHz        │
  ├──────────────────┼───────────────────────────┤
  │ PLL 输出         │ CLKOUT0 (100M) 独用       │
  ├──────────────────┼───────────────────────────┤
  │ DCLK 频率        │ 100 MHz                   │
  ├──────────────────┼───────────────────────────┤
  │ ctrl ↔ data_rx   │ 同一 100 MHz 域，无需 CDC │
  ├──────────────────┼───────────────────────────┤
  │ data_rx → bridge │ 100↔125 CDC               │
  ├──────────────────┼───────────────────────────┤
  │ 每 bit 捕获窗口  │ 10 ns                     │
  └──────────────────┴───────────────────────────┘

//
//  AD71143 AFE + NT39565D Gate Driver 集成顶层
//
//  50MHz �?????????????: nt39565d_gate_ctrl, top FSM
//  100MHz �?????????????: ad71143_ctrl, ad71143_spi, SPI config FSM
//
module top #(
    parameter integer FRAME_LINES      = 541,
    parameter integer FRAME_GAP_CYCLES = 5000000,   // 50ms @ 100MHz (测试图像生成器运行在 clk_100m)
    parameter [1:0]   MODE_SELECT      = 2'b00,
    parameter [1:0]   STV_DELAY_SEL    = 2'b00,
    parameter         SCAN_DIRECTION   = 1'b0,
    parameter         OE_MASK_EN       = 1'b0,
    parameter         DATA_TEST_MODE   = 0  // 数据测试模式: 0=真实AFE数据, 1=测试图像
)(
    input  wire sys_clk,
    input  wire key,
    input  wire spi_sdo_p0,
    input  wire spi_sdo_p1,

    output wire roic_reset_p0,
    output wire roic_reset_p1,
    output wire sync_p0,
    output wire sync_p1,
    output wire aclk_p0,
    output wire aclk_p1,
    // SPI Panel 0
    output wire spi_cs_p0,
    output wire spi_sck_p0,
    output wire spi_sdi_p0,
    // SPI Panel 1
    output wire spi_cs_p1,
    output wire spi_sck_p1,
    output wire spi_sdi_p1,

    output wire cpv_r,
    output wire xao_r,
    output wire stv1_r,
    output wire stv2_r,
    output wire oe1_r,
    output wire oe2_r,
    output wire ud_r,
    output wire lr_r,
    output wire mode1_r,
    output wire mode2_r,
    output wire sel_r,
    output wire stv_mode_r,
    output wire chip_sel1_r,
    output wire chip_sel2_r,
    output wire oepsn_r,

    output wire cpv_l,
    output wire xao_l,
    output wire stv1_l,
    output wire stv2_l,
    output wire oe1_l,
    output wire oe2_l,
    output wire ud_l,
    output wire lr_l,
    output wire mode1_l,
    output wire mode2_l,
    output wire sel_l,
    output wire stv_mode_l,
    output wire chip_sel1_l,
    output wire chip_sel2_l,
    output wire oepsn_l,

    // ---- AD71143 LVDS 数据接口 ----
    // Panel 0
    output wire         dclk_p_A0,
    output wire         dclk_n_A0,
    input  wire         dout_p_A0,
    input  wire         dout_n_A0,
    // 单LVDS模式: Lane B未使�????????
    // input  wire         dout_p_B0,
    // input  wire         dout_n_B0,
    // Panel 1
    output wire         dclk_p_A1,
    output wire         dclk_n_A1,
    input  wire         dout_p_A1,
    input  wire         dout_n_A1,
    // 单LVDS模式: Lane B未使用（硬件故障�????????
    // input  wire         dout_p_B1,
    // input  wire         dout_n_B1,
    // ---- RGMII ----
    output wire         rgmii_rst_n,     // PHY 异步复位
    // TX
    output wire         rgmii_txc,
    output wire         rgmii_tx_ctl,
    output wire         rgmii_txd0,
    output wire         rgmii_txd1,
    output wire         rgmii_txd2,
    output wire         rgmii_txd3,
    // RX
    input  wire         rgmii_rxc,
    input  wire         rgmii_rx_ctl,
    input  wire         rgmii_rxd0,
    input  wire         rgmii_rxd1,
    input  wire         rgmii_rxd2,
    input  wire         rgmii_rxd3,
    // MDIO
    output wire         rgmii_mdc,
    inout  wire         rgmii_mdio

    // Test Pins
);

    // ---- MDIO 控制�???????????? ----
    wire        mdio_oe;
    wire        mdio_out;
    wire        mdio_in;
    wire        mdio_cfg_done;
    wire        mdio_link_up;
    wire [15:0] mdio_bmsr;
    wire [15:0] mdio_rgmii2;
    wire [15:0] mdio_rxerr;
    wire [2:0]  mdio_init_state;
    wire [3:0]  mdio_f_state;

    assign rgmii_mdio = mdio_oe ? mdio_out : 1'bz;
    assign mdio_in    = rgmii_mdio;

    mdio_ctrl u_mdio (
        .clk             (clk_100m),
        .rst_n           (pll_locked),
        .MDC             (rgmii_mdc),
        .MDIO_oe         (mdio_oe),
        .MDIO_out        (mdio_out),
        .MDIO_in         (mdio_in),
        .cfg_done        (mdio_cfg_done),
        .link_up         (mdio_link_up),
        .bmsr_val        (mdio_bmsr),
        .rgmii2_val      (mdio_rgmii2),
        .rxerr_val       (mdio_rxerr),
        .dbg_init_state  (mdio_init_state),
        .dbg_f_state     (mdio_f_state)
    );

    // ---- 内部调试信号 (不引�?????????????) ----
    wire [255:0] merged_burst;
    wire [6:0]   merged_burst_index;
    wire         merged_valid;
    wire         header_ok;
    wire         rx_line_done;
    wire         frame_active;
    wire         frame_done_o;
    wire         line_done_o;
    wire         ctrl_init_done_o;
 
    wire pll_locked;
    wire clk_100m;
    wire clk_125m;
    wire gate_clk;

    wire cpv;
    wire xao;
    wire stv1;
    wire stv2;
    wire oe1;
    wire oe2;
    wire ud;
    wire lr;
    wire mode1;
    wire mode2;
    wire sel;
    wire stv_mode;
    wire chip_sel1;
    wire chip_sel2;
    wire oepsn;
    wire clk_125m_ph90;
    
    // ------- FPV 排线�????????????�???????????? ---------
    assign cpv_r = cpv;
    assign xao_r = xao;
    assign stv1_r = stv1;
    assign stv2_r = stv2;
    assign oe1_r = oe1;
    assign oe2_r = oe2;
    assign ud_r = ud;
    assign lr_r = lr;
    assign mode1_r = mode1;
    assign mode2_r = mode2;
    assign sel_r = sel;
    assign stv_mode_r = stv_mode;
    assign chip_sel1_r = chip_sel1;
    assign chip_sel2_r = chip_sel2;
    assign oepsn_r = oepsn;

    assign cpv_l = cpv;
    assign xao_l = xao;
    assign stv1_l = stv1;
    assign stv2_l = stv2;
    assign oe1_l = oe1;
    assign oe2_l = oe2;
    assign ud_l = ud;
    assign lr_l = lr;
    assign mode1_l = mode1;
    assign mode2_l = mode2;
    assign sel_l = sel;
    assign stv_mode_l = stv_mode;
    assign chip_sel1_l = chip_sel1;
    assign chip_sel2_l = chip_sel2;
    assign oepsn_l = oepsn;

    clk_wiz_0 u_mmcm(
        .clk_in1    (sys_clk),
        .clk_out1   (gate_clk),
        .clk_out2   (clk_100m),
        .clk_out3   (clk_125m),
        .clk_out4   (clk_125m_ph90),
        .locked     (pll_locked)
    );

  // =========================================================================
  // IDELAYCTRL: IDELAYE2参�?�时钟控制器�????????200MHz�????????
  // 必须使用200MHz时钟作为REFCLK，用于IDELAYE2的延迟校�????????
  // =========================================================================
  wire clk_200m;

  // 临时方案：使用clk_100m�????????2倍频或独立生�????????200MHz
  // 如果MMCM有多余输出，可以配置�????????200MHz；否则用BUFG + PLL
  // 这里假设用clk_100m暂代（需要后续修改MMCM配置输出真正�????????200MHz�????????

  IDELAYCTRL u_idelayctrl (
      .REFCLK (clk_100m),     // 临时使用100MHz（理想应该是200MHz�????????
      .RST    (~pll_locked),  // 复位信号，PLL未锁定时复位
      .RDY    ()              // Ready输出（可选监测）
  );
   

  wire rst_n_async = key & pll_locked;

  // =========================================================================
  // 复位同步�???????????? (异步断言, 同步释放) - 每个时钟域独�????????????
  // 避免复位释放时的亚稳态导致各触发器在不可靠的时钟沿解除复�????????????
  // =========================================================================

  // ---- 50MHz �???????????? (gate_clk) ----
  reg rst_sync1_50m, rst_sync2_50m;
  wire rst_n_50m;

  always @(posedge gate_clk or negedge rst_n_async) begin
      if (!rst_n_async) begin
          rst_sync1_50m <= 1'b0;
          rst_sync2_50m <= 1'b0;
      end else begin
          rst_sync1_50m <= 1'b1;
          rst_sync2_50m <= rst_sync1_50m;
      end
  end

  assign rst_n_50m = rst_sync2_50m;

  // ---- 100MHz �???????????? (clk_100m) ----
  reg rst_sync1_100m, rst_sync2_100m;
  wire rst_n_100m;

  always @(posedge clk_100m or negedge rst_n_async) begin
      if (!rst_n_async) begin
          rst_sync1_100m <= 1'b0;
          rst_sync2_100m <= 1'b0;
      end else begin
          rst_sync1_100m <= 1'b1;
          rst_sync2_100m <= rst_sync1_100m;
      end
  end

  assign rst_n_100m = rst_sync2_100m;

  // ---- 125MHz �???????????? (clk_125m) ----
  reg rst_sync1_125m, rst_sync2_125m;
  wire rst_n_125m;

  always @(posedge clk_125m or negedge rst_n_async) begin
      if (!rst_n_async) begin
          rst_sync1_125m <= 1'b0;
          rst_sync2_125m <= 1'b0;
      end else begin
          rst_sync1_125m <= 1'b1;
          rst_sync2_125m <= rst_sync1_125m;
      end
  end

  assign rst_n_125m = rst_sync2_125m;

  // =========================================================================
  // RGMII PHY 复位生成 (YT8531C: 上电后需拉低 >=10ms)
  // =========================================================================
  // PLL 锁定后拉�???????????? ~100ms, 然后释放, 满足 YT8531C 的上电复位时序要�????????????
  reg [23:0] phy_rst_cnt;
  reg        phy_rst_n_reg;

  always @(posedge clk_125m) begin
      if (!pll_locked) begin
          phy_rst_cnt   <= 24'd0;
          phy_rst_n_reg <= 1'b0;
      end else if (phy_rst_cnt < 24'd12_500_000) begin  // 100ms @ 125MHz
          phy_rst_cnt   <= phy_rst_cnt + 24'd1;
          phy_rst_n_reg <= 1'b0;
      end else begin
          phy_rst_n_reg <= 1'b1;
      end
  end

  assign rgmii_rst_n = phy_rst_n_reg;
  
  // =========================================================================
  // 内部信号
  // =========================================================================
  
  // ---- 100MHz �????????????? (AFE control) ----
  wire        ctrl_init_done;
  wire        ctrl_line_start;
  wire        ctrl_line_done;
  wire        ctrl_frame_done;
  wire [9:0]  ctrl_line_cnt;
  wire        frame_start_100m;      // CDC 同步后的 frame_start (100MHz �?????????????)
  wire        aclk_done;             // ACLK 序列完成 (ad71143_ctrl �???????????? data_rx)
  wire [3:0]  ctrl_state;            // AFE 控制器状态机 (调试输出)

  // Panel 1 调试信号 (ILA 探针, clk_100m �????????????)
  wire        dbg_p1_line_done;
  wire        dbg_p1_burst_en;
  wire        dbg_p1_header_ok;
  wire        dbg_p1_merged_valid;
  wire [7:0]  dbg_p1_shift_hi;
  wire [7:0]  dbg_p1_shift_lo;
  wire [2:0]  dbg_p1_state;
  wire        dbg_p1_dout_a_raw;
  wire        dbg_p1_dout_b_raw;
  wire [63:0] dbg_p1_lane_a_shift;
  // AFE 控制信号 (内部 �????????????? �????????????? Panel 扇出)
  wire roic_reset_int;
  wire sync_int;
  wire aclk_int;
  assign roic_reset_p0 = roic_reset_int;
  assign roic_reset_p1 = roic_reset_int;
  assign sync_p0       = spi_cfg_done ? sync_int : 1'b0;
  assign sync_p1       = spi_cfg_done ? sync_int : 1'b0;
  // 配置期间禁用ACLK，避免干扰SPI写入
  assign aclk_p0       = spi_cfg_done ? aclk_int : 1'b0;
  assign aclk_p1       = spi_cfg_done ? aclk_int : 1'b0;
  
  // ---- 50MHz �????????????? (gate driver + top FSM) ----
  wire        busy;
  wire        line_done;
  wire        frame_done;
  reg         frame_start;           // top FSM 发出�????????????? frame_start 脉冲
  wire        init_done_synced;      // CDC 同步后的 init_done
  wire        cfg_done_synced;       // CDC 同步后的 spi_cfg_done
  wire        line_start_pulse;      // CDC 同步后的 line_start (toggle→pulse)
  
  // ---- SPI 配置 FSM (100MHz �?????????????) ----
  wire        spi_cfg_done;
  wire        spi_done_p0;
  wire        spi_done_p1;
  wire        spi_done;              // �????????????? Panel 均完�?????????????
  wire        spi_start;
  wire        spi_rw;                // 1=�??, 0=�??
  wire [3:0]  spi_reg_addr;
  wire [9:0]  spi_reg_data;
  wire [9:0]  spi_rdback_p0;
  wire [9:0]  spi_rdback_p1;
  assign spi_done = spi_done_p0 && spi_done_p1;
  
  // ---- frame_done CDC ----
  reg         frame_done_toggle_100m;
  wire        frame_done_rise;       // 50MHz �????????????? frame_done 边沿�?????????????�?????????????
  
  // =========================================================================
  // CDC: ctrl_init_done (100MHz �????????????? 50MHz, 2-FF level sync)
  // =========================================================================
  reg init_done_sync1, init_done_sync2;
  
  always @(posedge gate_clk or negedge rst_n_50m) begin
      if (!rst_n_50m) begin
          init_done_sync1 <= 1'b0;
          init_done_sync2 <= 1'b0;
      end else begin
          init_done_sync1 <= ctrl_init_done;
          init_done_sync2 <= init_done_sync1;
      end
  end
  
  assign init_done_synced = init_done_sync2;
  
  // =========================================================================
  // CDC: ctrl_line_start (100MHz �????????????? 50MHz, toggle + 2-FF + edge detect)
  // =========================================================================
  reg ctrl_line_start_toggle;
  
  always @(posedge clk_100m or negedge rst_n_100m) begin
      if (!rst_n_100m)
          ctrl_line_start_toggle <= 1'b0;
      else if (ctrl_line_start)
          ctrl_line_start_toggle <= ~ctrl_line_start_toggle;
  end
  
  reg line_start_sync1, line_start_sync2, line_start_sync3;
  
  always @(posedge gate_clk or negedge rst_n_50m) begin
      if (!rst_n_50m) begin
          line_start_sync1 <= 1'b0;
          line_start_sync2 <= 1'b0;
          line_start_sync3 <= 1'b0;
      end else begin
          line_start_sync1 <= ctrl_line_start_toggle;
          line_start_sync2 <= line_start_sync1;
          line_start_sync3 <= line_start_sync2;
      end
  end
  
  assign line_start_pulse = line_start_sync2 ^ line_start_sync3;
  
  // =========================================================================
  // CDC: frame_start (50MHz �????????????? 100MHz, toggle + 2-FF + edge detect)
  // =========================================================================
  reg frame_start_toggle_50m;
  
  always @(posedge gate_clk or negedge rst_n_50m) begin
      if (!rst_n_50m)
          frame_start_toggle_50m <= 1'b0;
      else if (frame_start)
          frame_start_toggle_50m <= ~frame_start_toggle_50m;
  end
  
  reg frame_start_sync1, frame_start_sync2, frame_start_sync3;
  
  always @(posedge clk_100m or negedge rst_n_100m) begin
      if (!rst_n_100m) begin
          frame_start_sync1 <= 1'b0;
          frame_start_sync2 <= 1'b0;
          frame_start_sync3 <= 1'b0;
      end else begin
          frame_start_sync1 <= frame_start_toggle_50m;
          frame_start_sync2 <= frame_start_sync1;
          frame_start_sync3 <= frame_start_sync2;
      end
  end
  
  assign frame_start_100m = frame_start_sync2 ^ frame_start_sync3;
  
  // =========================================================================
  // CDC: ctrl_frame_done (100MHz �????????????? 50MHz, toggle + 2-FF + edge detect)
  // =========================================================================
  always @(posedge clk_100m or negedge rst_n_100m) begin
      if (!rst_n_100m)
          frame_done_toggle_100m <= 1'b0;
      else if (ctrl_frame_done)
          frame_done_toggle_100m <= ~frame_done_toggle_100m;
  end
  
  reg frame_done_sync1, frame_done_sync2, frame_done_sync3;
  
  always @(posedge gate_clk or negedge rst_n_50m) begin
      if (!rst_n_50m) begin
          frame_done_sync1 <= 1'b0;
          frame_done_sync2 <= 1'b0;
          frame_done_sync3 <= 1'b0;
      end else begin
          frame_done_sync1 <= frame_done_toggle_100m;
          frame_done_sync2 <= frame_done_sync1;
          frame_done_sync3 <= frame_done_sync2;
      end
  end
  
  assign frame_done_rise = frame_done_sync2 ^ frame_done_sync3;
  
  // =========================================================================
  // CDC: spi_cfg_done (100MHz �????????????? 50MHz, 2-FF level sync)
  // =========================================================================
  reg cfg_done_sync1, cfg_done_sync2;
  
  always @(posedge gate_clk or negedge rst_n_50m) begin
      if (!rst_n_50m) begin
          cfg_done_sync1 <= 1'b0;
          cfg_done_sync2 <= 1'b0;
      end else begin
          cfg_done_sync1 <= spi_cfg_done;
          cfg_done_sync2 <= cfg_done_sync1;
      end
  end
  
  assign cfg_done_synced = cfg_done_sync2;
  
  // =========================================================================
  // SPI 配置 FSM (100MHz �??)
  //   写入全部 16 �?? AD71143 寄存�?? (ADDR 0-15)
  //   顺序: Reg3(REFDAC)→Reg0(PWR)→Reg1(LPF)→Reg2(Mode)→Reg4~7(Timing)→Reg8~15
  //   值来�??: AD71143 SPEC Table 12 + Figure 22 Pipeline Mode 推荐
  //   写入完成后读回Reg3验证REFDAC配置
  // =========================================================================
  localparam CFG_IDLE     = 3'd0;
  localparam CFG_ISSUE    = 3'd1;
  localparam CFG_WAIT     = 3'd2;
  localparam CFG_DONE     = 3'd3;
  localparam CFG_FINISHED = 3'd5;
  localparam CFG_DELAY    = 28'd100_000_000;  // 1s @ 100MHz
  localparam CFG_GAP      = 7'd100;           // 1μs between writes

  reg [2:0]  cfg_state, cfg_state_next;
  reg [3:0]  cfg_reg_idx;
  reg        cfg_spi_start;
  reg        cfg_spi_rw;          // 1=�??, 0=�??
  reg        cfg_all_done;
  reg [27:0] cfg_delay_cnt;
  reg [6:0]  cfg_gap_cnt;
  wire       cfg_delay_done;
  wire       cfg_gap_done;
  
  // SPI 配置寄存�????????????? LUT �????????????? 按推荐上电顺序排�?????????????
  wire [3:0] cfg_addr_lut;
  wire [9:0] cfg_data_lut;
  
  assign cfg_addr_lut =
      (cfg_reg_idx == 4'd0)  ? 4'd3  :   // Reg3: REFDAC
      (cfg_reg_idx == 4'd1)  ? 4'd0  :   // Reg0: PWR + IFS
      (cfg_reg_idx == 4'd2)  ? 4'd1  :   // Reg1: LPF + options
      (cfg_reg_idx == 4'd3)  ? 4'd2  :   // Reg2: Mode control
      (cfg_reg_idx == 4'd4)  ? 4'd4  :   // Reg4: INTRST timing
      (cfg_reg_idx == 4'd5)  ? 4'd5  :   // Reg5: CDS1 timing
      (cfg_reg_idx == 4'd6)  ? 4'd6  :   // Reg6: CDS2 timing
      (cfg_reg_idx == 4'd7)  ? 4'd7  :   // Reg7: FA timing
      (cfg_reg_idx == 4'd8)  ? 4'd8  :   // Reg8: Custom clamp
      (cfg_reg_idx == 4'd9)  ? 4'd9  :   // Reg9: Reserved
      (cfg_reg_idx == 4'd10) ? 4'd10 :   // Reg10: Pipeline average
      (cfg_reg_idx == 4'd11) ? 4'd11 :   // Reg11: LFSR
      (cfg_reg_idx == 4'd12) ? 4'd12 :   // Reg12: Low power
      (cfg_reg_idx == 4'd13) ? 4'd13 :   // Reg13: Reserved
      (cfg_reg_idx == 4'd14) ? 4'd14 :   // Reg14: Reserved
      (cfg_reg_idx == 4'd15) ? 4'd15 :   // Reg15: Reserved
      4'd0;
  
  assign cfg_data_lut =
      (cfg_reg_idx == 4'd0)  ? 10'h030 :  // Reg3:  AZEN=0, REFDAC=48, ~1.5V (修复: 32�????????48, 扩大ADC输入范围)
      (cfg_reg_idx == 4'd1)  ? 10'h007 :  // Reg0:  PWR=Normal(000), IFS=7 (增大增益以检测微弱信�????)
      (cfg_reg_idx == 4'd2)  ? 10'h0B0 :  // Reg1:  DM=1(单LVDS), LPF=3.9μs(01), CDS2_RESETEN=1 (修复: 0A0�????????0B0, bit4=1启用单�?�道模式)
      (cfg_reg_idx == 4'd3)  ? 10'h027 :  // Reg2:  RNDOMIZE=1, DOUTMODE=1, ECHOCLK=1, Pipeline=1
      (cfg_reg_idx == 4'd4)  ? 10'h082 :  // Reg4:  INTRST_C=8(ACLK8), INTRST_O=2(ACLK2)
      (cfg_reg_idx == 4'd5)  ? 10'h013 :  // Reg5:  CDS1_C=1(ACLK1), CDS1_O=3(ACLK3)
      (cfg_reg_idx == 4'd6)  ? 10'h046 :  // Reg6:  CDS2_C=4(ACLK4), CDS2_O=6(ACLK6)
      (cfg_reg_idx == 4'd7)  ? 10'h025 :  // Reg7:  FA_CDS1=2(ACLK2), FA_CDS2=5(ACLK5)
      (cfg_reg_idx == 4'd8)  ? 10'h000 :  // Reg8:  CUSTCLMPEN=0 (禁用自定义钳�????)
      (cfg_reg_idx == 4'd9)  ? 10'h001 :  // Reg9:  Reserved
      (cfg_reg_idx == 4'd10) ? 10'h000 :  // Reg10: PIPELINE_AVGEN=0
      (cfg_reg_idx == 4'd11) ? 10'h000 :  // Reg11: LFSR_EN=0 (禁用LFSR测试模式，输出真实ADC数据)
      (cfg_reg_idx == 4'd12) ? 10'h000 :  // Reg12: LP_EN=0 (Normal模式)
      (cfg_reg_idx == 4'd13) ? 10'h000 :  // Reg13: Reserved
      (cfg_reg_idx == 4'd14) ? 10'h000 :  // Reg14: Reserved
      (cfg_reg_idx == 4'd15) ? 10'h000 :  // Reg15: Reserved
      10'h000;
  assign cfg_delay_done = (cfg_delay_cnt == CFG_DELAY - 1);
  assign cfg_gap_done   = (cfg_gap_cnt  == CFG_GAP - 1);

  
  always @(posedge clk_100m or negedge rst_n_100m) begin
      if (!rst_n_100m)
          cfg_state <= CFG_IDLE;
      else
          cfg_state <= cfg_state_next;
  end

  always @(*) begin
      cfg_state_next = cfg_state;
      case (cfg_state)
          CFG_IDLE: begin
              if (ctrl_init_done && cfg_delay_done)
                  cfg_state_next = CFG_ISSUE;
          end
          CFG_ISSUE: cfg_state_next = CFG_WAIT;
          CFG_WAIT:  if (spi_done) cfg_state_next = CFG_DONE;
          CFG_DONE: begin
              if (cfg_reg_idx != 4'd15 && cfg_gap_done)
                  cfg_state_next = CFG_ISSUE;
              else if (cfg_reg_idx == 4'd15 && cfg_gap_done)
                  cfg_state_next = CFG_FINISHED;
              // else stay in CFG_DONE permanently (all 16 regs written)
          end
          CFG_FINISHED: cfg_state_next = CFG_FINISHED;
          default: cfg_state_next = CFG_IDLE;
      endcase
  end

  always @(posedge clk_100m or negedge rst_n_100m) begin
      if (!rst_n_100m) begin
          cfg_spi_start  <= 1'b0;
          cfg_spi_rw     <= 1'b1;
          cfg_reg_idx    <= 4'd0;
          cfg_all_done   <= 1'b0;
          cfg_delay_cnt  <= 28'd0;
          cfg_gap_cnt    <= 7'd0;
      end else begin
          cfg_spi_start <= 1'b0;

          case (cfg_state)
              CFG_IDLE: begin
                  cfg_reg_idx  <= 4'd0;
                  cfg_spi_rw   <= 1'b1;  // 默认写模�??
                  cfg_all_done <= 1'b0;
                  if (ctrl_init_done && !cfg_delay_done)
                      cfg_delay_cnt <= cfg_delay_cnt + 28'd1;
              end
              CFG_ISSUE: begin
                  cfg_spi_start <= 1'b1;
              end
              CFG_WAIT: begin
                  // wait for spi_done
              end
              CFG_DONE: begin
                  if (cfg_gap_done) begin
                      cfg_gap_cnt <= 7'd0;
                      if (cfg_reg_idx == 4'd15)
                          cfg_all_done <= 1'b1;
                      else
                          cfg_reg_idx <= cfg_reg_idx + 4'd1;
                  end else begin
                      cfg_gap_cnt <= cfg_gap_cnt + 7'd1;
                  end
              end
          endcase
      end
  end
  
  // SPI 控制信号来自配置 FSM
  assign spi_reg_addr = cfg_addr_lut;
  assign spi_reg_data = cfg_data_lut;
  assign spi_start    = cfg_spi_start;
  assign spi_rw       = cfg_spi_rw;
  assign spi_cfg_done = cfg_all_done;
  
  // AD71143 SPEC: 转换期间 CS 必须保持低电�??
  // 配置完成�??: 如果在READBACK状�?�则使用SPI模块CS，否则强制CS=0
  // SPI模块输出标准低有效CS，需要取反为高有�??
  wire spi_cs_raw_p0;
  wire spi_cs_raw_p1;
  wire spi_cs_active;  // 是否在进行SPI操作（写入或读回�??
  assign spi_cs_active = !cfg_all_done;
  assign spi_cs_p0 = spi_cs_active ? ~spi_cs_raw_p0 : 1'b0;
  assign spi_cs_p1 = spi_cs_active ? ~spi_cs_raw_p1 : 1'b0;
  
  // =========================================================================
  // Top FSM (50MHz �?????????????)
  //   POWERUP �????????????? WAIT_INIT �????????????? WAIT_CFG �????????????? IDLE �????????????? START �????????????? WAIT_FRAME �????????????? FRAME_GAP
  // =========================================================================
  localparam TOP_POWERUP    = 3'd0;
  localparam TOP_WAIT_INIT  = 3'd1;
  localparam TOP_WAIT_CFG   = 3'd2;
  localparam TOP_IDLE       = 3'd3;
  localparam TOP_START      = 3'd4;
  localparam TOP_WAIT_FRAME = 3'd5;
  localparam TOP_FRAME_GAP  = 3'd6;
  
  reg [2:0]  top_state;
  reg [31:0] gap_cnt;
  
  assign frame_active  = busy;
  assign frame_done_o  = frame_done_rise;
  assign line_done_o   = ctrl_line_done;
  assign ctrl_init_done_o = ctrl_init_done;
  
  always @(posedge gate_clk or negedge rst_n_50m) begin
      if (!rst_n_50m) begin
          top_state   <= TOP_POWERUP;
          frame_start <= 1'b0;
          gap_cnt     <= 32'd0;
      end else begin
          frame_start <= 1'b0;

          case (top_state)
              TOP_POWERUP: begin
                  top_state <= TOP_WAIT_INIT;
              end
  
              TOP_WAIT_INIT: begin
                  if (init_done_synced)
                      top_state <= TOP_WAIT_CFG;
              end
  
              TOP_WAIT_CFG: begin
                  if (cfg_done_synced)
                      top_state <= TOP_IDLE;
              end
  
              TOP_IDLE: begin
                  gap_cnt   <= 32'd0;
                  top_state <= TOP_START;
              end
  
              TOP_START: begin
                  frame_start <= 1'b1;
                  top_state   <= TOP_WAIT_FRAME;
              end
  
              TOP_WAIT_FRAME: begin
                  if (frame_done_rise) begin
                      gap_cnt   <= 32'd0;
                      top_state <= TOP_FRAME_GAP;
                  end
              end
  
              TOP_FRAME_GAP: begin
                  if (gap_cnt == 32'd0) begin
                      gap_cnt <= gap_cnt + 1'b1;
                  end else if (gap_cnt >= FRAME_GAP_CYCLES - 1) begin
                      gap_cnt   <= 32'd0;
                      top_state <= TOP_START;
                  end else begin
                      gap_cnt <= gap_cnt + 1'b1;
                  end
              end
  
              default: begin
                  top_state <= TOP_POWERUP;
              end
          endcase
      end
  end
  
  // =========================================================================
  // 模块例化
  // =========================================================================
  
  // AD71143 AFE 控制 (100MHz �?????????????)
  ad71143_ctrl #(
      .ACLK_PULSES      (9),        // 恢复正常：每�????????? 9 �????????? ACLK
      .LINE_CYCLES      (15000),    // 测试: 150μs @ 100MHz (继续增加，寻找临界点)
      .RESET_CYCLES     (1000),     // 10μs @ 100MHz = 1000 cycles (修复：原来是 10)
      .INIT_WAIT_CYCLES (10000),    // 100μs @ 100MHz = 10000 cycles (修复：原来是 100)
      .FRAME_LINES      (FRAME_LINES)
  ) u_ad71143_ctrl (
      .clk          (clk_100m),
      .rst_n        (rst_n_100m),
      .frame_start  (frame_start_100m),
      .roic_reset   (roic_reset_int),
      .sync         (sync_int),
      .aclk         (aclk_int),
      .init_done    (ctrl_init_done),
      .line_start   (ctrl_line_start),
      .line_done    (ctrl_line_done),
      .aclk_idx     (),
      .line_cnt     (ctrl_line_cnt),
      .frame_done   (ctrl_frame_done),
      .aclk_done    (aclk_done),
      .dbg_state    (ctrl_state)
  );
  
  
  	// AD71143 SPI Master Panel 0 (100MHz �?????????????)
  	ad71143_spi u_spi_p0 (
  	    .clk_sys    (clk_100m),
  	    .rst_n      (rst_n_100m),
  	    .start      (spi_start),
  	    .rw         (spi_rw),
  	    .reg_addr   (spi_reg_addr),
  	    .reg_data   (spi_reg_data),
  	    .done       (spi_done_p0),
  	    .reg_rdback (spi_rdback_p0),
  	    .spi_cs     (spi_cs_raw_p0),
  	    .spi_sck    (spi_sck_p0),
  	    .spi_sdi    (spi_sdi_p0),
  	    .spi_sdo    (spi_sdo_p0)
  	);

  	// AD71143 SPI Master Panel 1 (100MHz �?????????????, �????????????? Panel 0 并行配置)
  	ad71143_spi u_spi_p1 (
  	    .clk_sys    (clk_100m),
  	    .rst_n      (rst_n_100m),
  	    .start      (spi_start),
  	    .rw         (spi_rw),
  	    .reg_addr   (spi_reg_addr),
  	    .reg_data   (spi_reg_data),
  	    .done       (spi_done_p1),
  	    .reg_rdback (spi_rdback_p1),
  	    .spi_cs     (spi_cs_raw_p1),
  	    .spi_sck    (spi_sck_p1),
  	    .spi_sdi    (spi_sdi_p1),
  	    .spi_sdo    (spi_sdo_p1)
  	);

  // NT39565D 内部调试信号
  wire [3:0]  nt39_state;
  wire [15:0] nt39_cnt;
  wire [15:0] nt39_shift_cnt;
  wire [15:0] nt39_target_lines;

  // AD71143 �????????????? Panel LVDS 数据接收 (200MHz �?????????????)
  	ad71143_data_rx_dual #(
  	    .MUTE_MIN             (112)     // 100MHz: 177cyc-65=112 (ACTIVE=64+PRE_DELAY=1)
  	) u_data_rx_dual (
  	    .clk_sys              (clk_100m),
  	    .rst_n                (rst_n_100m),
  	    .sync_in              (sync_int),      // 修复: 使用 sync_int (SYNC信号) 而不�????? line_start_pulse (脉冲)
  	    .aclk_done            (aclk_done),
  	    .dclk_p_A0            (dclk_p_A0),
  	    .dclk_n_A0            (dclk_n_A0),
  
  	    .dout_p_A0            (dout_p_A0),
  	    .dout_n_A0            (dout_n_A0),
  	    // 单LVDS模式: Lane B未使�????????
  	    // .dout_p_B0            (dout_p_B0),
  	    // .dout_n_B0            (dout_n_B0),
  	    .dclk_p_A1            (dclk_p_A1),
  	    .dclk_n_A1            (dclk_n_A1),
  
  	    .dout_p_A1            (dout_p_A1),
  	    .dout_n_A1            (dout_n_A1),
  	    // 单LVDS模式: Lane B未使�????????
  	    // .dout_p_B1            (dout_p_B1),
  	    // .dout_n_B1            (dout_n_B1),
  	    .line_done            (rx_line_done),
  	    .header_ok            (header_ok),
  	    .merged_valid         (merged_valid),
  	    .merged_burst         (merged_burst),
  	    .merged_burst_index   (merged_burst_index),
  	    .state_debug_0        (),
  	    .state_debug_1        (dbg_p1_state),
  	    .burst_en_out         (),
  	    .dbg_p1_shift_hi     (dbg_p1_shift_hi),
  	    .dbg_p1_shift_lo     (dbg_p1_shift_lo),
  	    .dbg_p1_burst_en     (dbg_p1_burst_en),
  	    .dbg_p1_header_ok    (dbg_p1_header_ok),
  	    .dbg_p1_merged_valid (dbg_p1_merged_valid),
  	    .dbg_p1_line_done    (dbg_p1_line_done),
  	    .dbg_p1_dout_a_raw   (dbg_p1_dout_a_raw),
  	    .dbg_p1_dout_b_raw   (dbg_p1_dout_b_raw),
  	    .dbg_p1_lane_a_shift (dbg_p1_lane_a_shift)
  	);
  
  // NT39565D Gate Driver (50MHz �?????????????, 修复 CLK_FREQ_MHZ=50)
  // 关键修复�????????
  // 1. CPV_PERIOD_US: 10�????????6 (手册注释：实际支持最�????????2μs，用6μs保守)
  // 2. CPV_PW_US_X10: 10�????????30 (3μs, 50% duty cycle)
  // 3. OE_PW_US_X10: 10�????????45 (4.5μs, 75% duty扩大Gate输出窗口)
  nt39565d_gate_ctrl #(
      .CLK_FREQ_MHZ      (50  ),
      .CPV_PERIOD_US     (6   ),  // 修复: 6μs (Gout=12μs，手册实测可�???2μs)
      .CPV_PW_US_X10     (30  ),  // 修复: 3μs (50% duty cycle)
      .STV_SETUP_US_X10  (3   ),
      .STV_HOLD_US_X10   (4   ),
      .OE_PW_US_X10      (45  ),  // 修复: 4.5μs (75% duty，扩大Gate输出窗口)
      .XAO_DELAY_US      (20  ),
      .OUT_CH_NORMAL     (541 ),
      .OUT_CH_2G         (540 ),
      .DEFAULT_MODE_SEL  (0   ),
      .SCAN_DIRECTION    (1'b0),
      .USE_DUAL_STV      (1'b0),
      .PER_LINE_TRIG     (1   ),
      .TEST_HOLD_LINE    (0   ),  // 禁用测试模式：正常扫�???541�???
      .TEST_LINE_NUM     (270 )   // 测试行号（当TEST_HOLD_LINE=0时无效）
  ) u_nt39565d (
      .clk            (gate_clk       ),
      .rst_n          (rst_n_50m      ),
      .frame_start    (frame_start    ),
      .line_start     (line_start_pulse),
      .xao_emergency  (1'b0           ),
      .line_count     (FRAME_LINES[9:0]),
      .scan_direction (SCAN_DIRECTION ),
      .mode_select    (MODE_SELECT    ),
      .stv_delay_sel  (STV_DELAY_SEL  ),
      .oe_mask_en     (OE_MASK_EN     ),
      .cpv            (cpv            ),
      .xao            (xao            ),
      .stv1           (stv1           ),
      .stv2           (stv2           ),
      .oe1            (oe1            ),
      .oe2            (oe2            ),
      .ud             (ud             ),
      .lr             (lr             ),
      .mode1          (mode1          ),
      .mode2          (mode2          ),
      .sel            (sel            ),
      .stv_mode       (stv_mode       ),
      .chip_sel1      (chip_sel1      ),
      .chip_sel2      (chip_sel2      ),
      .oepsn          (oepsn          ),
      .busy           (busy           ),
      .line_done      (line_done      ),
      .frame_done     (frame_done     ),
      // 调试信号输出
      .dbg_state      (nt39_state     ),
      .dbg_cnt        (nt39_cnt       ),
      .dbg_shift_cnt  (nt39_shift_cnt ),
      .dbg_target_lines(nt39_target_lines)
  );
  
  // =========================================================================
  // 测试图像生成器：生成水平渐变图像
  // 每行的所有像素�?? = 行号
  // 这样可以清晰验证图像重建算法
  // =========================================================================
  reg [255:0] test_burst_data;
  reg         test_burst_valid;
  reg         test_frame_start;   // 帧起始标志：每帧第一�???? burst 时为�????
  reg [9:0]   test_line_cnt;      // 行计数器 (0-540)
  reg [6:0]   test_burst_cnt;     // burst 计数�???? (0-63)
  reg [15:0]  test_interval_cnt;  // 发�?�间隔计数器
  reg [15:0]  pixel_value;        // 当前像素�????
  reg [31:0]  test_gap_cnt;       // 帧间隔计数器
  reg         test_in_gap;        // 是否在帧间隔期间

  always @(posedge clk_100m or negedge rst_n_100m) begin
      if (!rst_n_100m) begin
          test_burst_data   <= 256'd0;
          test_burst_valid  <= 1'b0;
          test_frame_start  <= 1'b0;
          test_line_cnt     <= 10'd0;
          test_burst_cnt    <= 7'd0;
          test_interval_cnt <= 16'd0;
          pixel_value       <= 16'd0;
          test_gap_cnt      <= 32'd0;
          test_in_gap       <= 1'b0;
      end else begin
          test_burst_valid  <= 1'b0;
          test_frame_start  <= 1'b0;

          if (DATA_TEST_MODE) begin
              // �????查是否在帧间隔期�????
              if (test_in_gap) begin
                  // 帧间隔：停止发�?�数据，等待计数器到�????
                  if (test_gap_cnt >= FRAME_GAP_CYCLES) begin
                      // 间隔结束，开始新�????
                      test_in_gap <= 1'b0;
                      test_gap_cnt <= 32'd0;
                      test_line_cnt <= 10'd0;
                      test_burst_cnt <= 7'd0;
                  end else begin
                      test_gap_cnt <= test_gap_cnt + 32'd1;
                  end
              end else begin
                  // 正常发�?�数�????
                  // �???? 200 个周期发送一�???? burst (2μs @ 100MHz)
                  if (test_interval_cnt >= 16'd200) begin
                      test_interval_cnt <= 16'd0;

                      // 生成测试图像：水平渐�????
                      // 每行的所有像素�?? = 行号 × 121 (缩放�???? 16-bit 范围)
                      // 这样�???? 0 �???? = 全黑，第 540 �???? = 接近全白
                      // 注意：使用组合�?�辑立即计算，避免时序延�????

                      // 帧起始标志：每帧第一�???? burst (line=0, burst=0)
                      if (test_line_cnt == 10'd0 && test_burst_cnt == 7'd0) begin
                          test_frame_start <= 1'b1;
                          // 帧起�???? burst：最�???? 16-bit 设为魔数 0xAA55，用于帧同步
                          test_burst_data <= {
                              16'hAA55,     // [255:240] 魔数标记
                              16'd0,        // [239:224] Panel 1, 样本 6 (�????0�????=0)
                              16'd0,        // [223:208] Panel 1, 样本 5
                              16'd0,        // [207:192] Panel 1, 样本 4
                              16'd0,        // [191:176] Panel 1, 样本 3
                              16'd0,        // [175:160] Panel 1, 样本 2
                              16'd0,        // [159:144] Panel 1, 样本 1
                              16'd0,        // [143:128] Panel 1, 样本 0
                              16'd0,        // [127:112] Panel 0, 样本 7
                              16'd0,        // [111: 96] Panel 0, 样本 6
                              16'd0,        // [ 95: 80] Panel 0, 样本 5
                              16'd0,        // [ 79: 64] Panel 0, 样本 4
                              16'd0,        // [ 63: 48] Panel 0, 样本 3
                              16'd0,        // [ 47: 32] Panel 0, 样本 2
                              16'd0,        // [ 31: 16] Panel 0, 样本 1
                              16'd0         // [ 15:  0] Panel 0, 样本 0
                          };
                      end else begin
                          // 计算当前行的像素值（组合逻辑�????
                          pixel_value <= {6'd0, test_line_cnt} * 16'd121;

                          // 普�?? burst�????16 个样本，都使用相同的值（同一行的像素值相同）
                          test_burst_data <= {
                              ({6'd0, test_line_cnt} * 16'd121),  // [255:240] Panel 1, 样本 7
                              ({6'd0, test_line_cnt} * 16'd121),  // [239:224] Panel 1, 样本 6
                              ({6'd0, test_line_cnt} * 16'd121),  // [223:208] Panel 1, 样本 5
                              ({6'd0, test_line_cnt} * 16'd121),  // [207:192] Panel 1, 样本 4
                              ({6'd0, test_line_cnt} * 16'd121),  // [191:176] Panel 1, 样本 3
                              ({6'd0, test_line_cnt} * 16'd121),  // [175:160] Panel 1, 样本 2
                              ({6'd0, test_line_cnt} * 16'd121),  // [159:144] Panel 1, 样本 1
                              ({6'd0, test_line_cnt} * 16'd121),  // [143:128] Panel 1, 样本 0
                              ({6'd0, test_line_cnt} * 16'd121),  // [127:112] Panel 0, 样本 7
                              ({6'd0, test_line_cnt} * 16'd121),  // [111: 96] Panel 0, 样本 6
                              ({6'd0, test_line_cnt} * 16'd121),  // [ 95: 80] Panel 0, 样本 5
                              ({6'd0, test_line_cnt} * 16'd121),  // [ 79: 64] Panel 0, 样本 4
                              ({6'd0, test_line_cnt} * 16'd121),  // [ 63: 48] Panel 0, 样本 3
                              ({6'd0, test_line_cnt} * 16'd121),  // [ 47: 32] Panel 0, 样本 2
                              ({6'd0, test_line_cnt} * 16'd121),  // [ 31: 16] Panel 0, 样本 1
                              ({6'd0, test_line_cnt} * 16'd121)   // [ 15:  0] Panel 0, 样本 0
                          };
                      end
                      test_burst_valid <= 1'b1;

                      // 更新计数�????
                      if (test_burst_cnt < 7'd63) begin
                          test_burst_cnt <= test_burst_cnt + 7'd1;
                      end else begin
                          // �????行完�????
                          test_burst_cnt <= 7'd0;
                          if (test_line_cnt < FRAME_LINES - 1) begin
                              test_line_cnt <= test_line_cnt + 10'd1;
                          end else begin
                              // �????帧完成，进入帧间�????
                              test_in_gap <= 1'b1;
                              test_gap_cnt <= 32'd0;
                          end
                      end
                  end else begin
                      test_interval_cnt <= test_interval_cnt + 16'd1;
                  end
              end
          end
      end
  end

  // 选择数据源：测试数据 or 真实 AFE 数据
  wire [255:0] final_data_burst = DATA_TEST_MODE ? test_burst_data : merged_burst;
  wire         final_data_valid = DATA_TEST_MODE ? test_burst_valid : merged_valid;
  wire         final_frame_start = DATA_TEST_MODE ? test_frame_start : 1'b0;  // 真实数据暂时没有帧同�????

  // =========================================================================
  // RGMII 桥接: merged_burst �????????????? 字节 �????????????? RGMII_tx
  // =========================================================================
  // RGMII debug
  wire        rgmii_dbg_startup;
  wire        rgmii_dbg_phy_rdy;
  wire        rgmii_dbg_tx_send;
  wire [3:0]  rgmii_dbg_state;
  wire [2:0]  rgmii_dbg_tx_fsm;
  wire        rgmii_dbg_crc_busy;
  wire        rgmii_dbg_crc_done;
  wire        rgmii_dbg_crc_done_r;
  wire        rgmii_dbg_tx_start_d;
  wire        rgmii_dbg_fifo_full;    // FIFO满标�?????? - 新增
  wire        rgmii_dbg_fifo_empty;   // FIFO空标�?????? - 新增

  // RGMII Bridge - 使用测试数据或真实数�????
  rgmii_bridge #(
      .TEST_MODE     (0),           // 禁用 RGMII 内部测试模式，使用我们注入的数据
      .TEST_INTERVAL (10000)
  ) u_rgmii_bridge (
      .rst_n            (pll_locked          ),
      .clk_100m         (clk_100m            ),
      .clk_125m         (clk_125m            ),
      .clk_125m_ph90    (clk_125m_ph90       ),
      .data_in          (final_data_burst    ),   // 使用选择后的数据
      .data_valid       (final_data_valid    ),   // 使用选择后的 valid
      .frame_start      (final_frame_start   ),  // 帧起始信�????
      .TXC              (rgmii_txc           ),
      .TX_CTL           (rgmii_tx_ctl        ),
      .TXD0             (rgmii_txd0          ),
      .TXD1             (rgmii_txd1          ),
      .TXD2             (rgmii_txd2          ),
      .TXD3             (rgmii_txd3          ),
      .dbg_startup_done (rgmii_dbg_startup   ),
      .dbg_phy_ready    (rgmii_dbg_phy_rdy   ),
      .dbg_tx_sending   (rgmii_dbg_tx_send   ),
      .dbg_state        (rgmii_dbg_state     ),
      .dbg_tx_fsm       (rgmii_dbg_tx_fsm    ),
      .dbg_crc_busy     (rgmii_dbg_crc_busy  ),
      .dbg_crc_done     (rgmii_dbg_crc_done  ),
      .dbg_crc_done_r   (rgmii_dbg_crc_done_r),
      .dbg_tx_start_d   (rgmii_dbg_tx_start_d),
      .dbg_fifo_full    (rgmii_dbg_fifo_full ),     // 新增
      .dbg_fifo_empty   (rgmii_dbg_fifo_empty)     // 新增
  );

  // =========================================================================
  // CDC: mdio_rxerr (100MHz �????????????? mdio_ctrl) �???????????? mdio_rxerr_125m (125MHz �????????????? ILA)
  // 2-FF 同步�????????????, PkgTx 变化缓慢 (μs �????????????), 2-FF 足够
  // =========================================================================
  reg [15:0] mdio_rxerr_sync1;
  reg [15:0] mdio_rxerr_125m;

  always @(posedge clk_125m or negedge rst_n_125m) begin
      if (!rst_n_125m) begin
          mdio_rxerr_sync1 <= 16'd0;
          mdio_rxerr_125m  <= 16'd0;
      end else begin
          mdio_rxerr_sync1 <= mdio_rxerr;
          mdio_rxerr_125m  <= mdio_rxerr_sync1;
      end
  end
  

// =========================================================================
// ILA 调试探针 5 (SPI 读寄存器诊断, clk_100m �??)
// 监测 AD71143 SPI 读寄存器的完整时序和数据
// =========================================================================
/* AD71143 SPI readback probes retained here for later reference.
ila_1 u_ila_datapath (
    .clk    (clk_100m),

    // probe0 [7:0]: SPI控制信号 - 用于监控读写操作
    .probe0 ({
        cfg_all_done,          // [7] SPI 配置完成
        spi_rw,                // [6] SPI读写控制 (1=�??, 0=�??) - 关键�??
        spi_start,             // [5] SPI启动信号
        spi_done,              // [4] SPI完成信号
        spi_reg_addr[3:0]      // [3:0] SPI寄存器地�??
    }),

    // probe1 [2:0]: SPI配置FSM状�??
    .probe1 (cfg_state),


    // probe2 [9:0]: SPI读回Reg3的�?? Panel 1 - 对比验证
    .probe2 (spi_rdback_p1),

    // probe3 [3:0]: SPI物理信号 Panel 1
    .probe3 ({
        spi_cs_raw_p1,         // [3] 片�?�信号（低有效）
        spi_sck_p1,            // [2] SPI时钟
        spi_sdi_p1,            // [1] SDI数据输出到AD
        spi_sdo_p1             // [0] SDO数据从AD读回
    }),

    // probe4 [9:0]: 写入的寄存器数据 - 用于对比读回�??
    .probe4 (spi_reg_data),

    // probe5 [3:0]: AFE控制器状态机
    .probe5 (ctrl_state)
);

*/
ila_1 u_ila_datapath (
    .clk    (gate_clk),

    .probe0 ({
        nt39_state,
        busy,
        line_done,
        frame_done,
        frame_start
    }),

    .probe1 ({cpv, stv1, stv2}),

    .probe2 ({
        oe1, oe2, ud, lr, mode1, mode2, sel, stv_mode, chip_sel1, chip_sel2
    }),

    .probe3 ({oepsn, xao, line_start_pulse, frame_start}),

    .probe4 (nt39_cnt[9:0]),
    .probe5 (nt39_shift_cnt[3:0])
);

endmodule

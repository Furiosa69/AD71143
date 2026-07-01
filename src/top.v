//
//  AD71143 AFE + NT39565D Gate Driver 集成顶层
//
//  时钟架构:
//    HW  (`ifdef XILINX_PRIMITIVES):  sys_clk (50MHz pin) → PLL → clk_100m (100MHz)
//                                     gate_clk = sys_clk (50MHz)
//    SIM (`else):                     sys_clk = 100MHz from testbench
//                                     gate_clk = sys_clk / 2 divider (50MHz)
//
//  50MHz 域: nt39565d_gate_ctrl, top FSM
//  100MHz 域: ad71143_ctrl, ad71143_spi, SPI config FSM
//
module top #(
    parameter integer FRAME_LINES      = 541,
    parameter integer FRAME_GAP_CYCLES = 100,
    parameter [1:0]   MODE_SELECT      = 2'b00,
    parameter [1:0]   STV_DELAY_SEL    = 2'b00,
    parameter         SCAN_DIRECTION   = 1'b0,
    parameter         OE_MASK_EN       = 1'b0
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
    input  wire         dclko_p_A0,
    input  wire         dclko_n_A0,
    input  wire         dout_p_A0,
    input  wire         dout_n_A0,
    input  wire         dout_p_B0,
    input  wire         dout_n_B0,
    // Panel 1
    output wire         dclk_p_A1,
    output wire         dclk_n_A1,
    input  wire         dclko_p_A1,
    input  wire         dclko_n_A1,
    input  wire         dout_p_A1,
    input  wire         dout_n_A1,
    input  wire         dout_p_B1,
    input  wire         dout_n_B1,

    output wire [255:0] merged_burst,
    output wire [6:0]   merged_burst_index,
    output wire         merged_valid,
    output wire         header_ok,
    output wire         rx_line_done,

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
    // MDIO (共用)
    output wire         rgmii_mdc,
    inout  wire         rgmii_mdio
);
    wire clk_fb;
    wire pll_locked;
    wire clk_100m;

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

    PLLE2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT      (20),        // VCO = 50MHz × 20 = 1000MHz
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (20.0),      // 50MHz 输入
        .CLKOUT0_DIVIDE     (10),        // 1000 / 10 = 100MHz  (AFE ctrl + SPI)
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT1_DIVIDE     (1),
        .CLKOUT1_DUTY_CYCLE (0.5),
        .CLKOUT1_PHASE      (0.0),
        .CLKOUT2_DIVIDE     (1),
        .CLKOUT2_DUTY_CYCLE (0.5),
        .CLKOUT2_PHASE      (0.0),
        .CLKOUT3_DIVIDE     (1),
        .CLKOUT3_DUTY_CYCLE (0.5),
        .CLKOUT3_PHASE      (0.0),
        .CLKOUT4_DIVIDE     (1),
        .CLKOUT4_DUTY_CYCLE (0.5),
        .CLKOUT4_PHASE      (0.0),
        .CLKOUT5_DIVIDE     (1),
        .CLKOUT5_DUTY_CYCLE (0.5),
        .CLKOUT5_PHASE      (0.0),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) pll_inst (
        .CLKIN1             (sys_clk),
        .CLKOUT0            (clk_100m),
        .CLKOUT1            (),
        .CLKOUT2            (),
        .CLKOUT3            (),
        .CLKOUT4            (),
        .CLKOUT5            (),
        .CLKFBOUT           (clk_fb),
        .CLKFBIN            (clk_fb),
        .LOCKED             (pll_locked),
        .PWRDWN             (1'b0),
        .RST                (1'b0)
    );
   
wire gate_clk = sys_clk;
wire rst_n = key & pll_locked;

// RGMII PHY 异步复位 (与系统复位同步)
assign rgmii_rst_n = rst_n;

// =========================================================================
// 内部信号
// =========================================================================

// ---- 100MHz 域 (AFE control) ----
wire        ctrl_init_done;
wire        ctrl_line_start;
wire        ctrl_line_done;
wire        ctrl_frame_done;
wire [9:0]  ctrl_line_cnt;
wire        frame_start_100m;      // CDC 同步后的 frame_start (100MHz 域)
wire        aclk_done;             // ACLK 序列完成 (ad71143_ctrl → data_rx)
// AFE 控制信号 (内部 → 两 Panel 扇出)
wire roic_reset_int;
wire sync_int;
wire aclk_int;
assign roic_reset_p0 = roic_reset_int;
assign roic_reset_p1 = roic_reset_int;
assign sync_p0       = sync_int;
assign sync_p1       = sync_int;
assign aclk_p0       = aclk_int;
assign aclk_p1       = aclk_int;

// ---- 50MHz 域 (gate driver + top FSM) ----
wire        busy;
wire        line_done;
wire        frame_done;
reg         frame_start;           // top FSM 发出的 frame_start 脉冲
wire        init_done_synced;      // CDC 同步后的 init_done
wire        cfg_done_synced;       // CDC 同步后的 spi_cfg_done
wire        line_start_pulse;      // CDC 同步后的 line_start (toggle→pulse)

// ---- SPI 配置 FSM (100MHz 域) ----
wire        spi_cfg_done;
wire        spi_done_p0;
wire        spi_done_p1;
wire        spi_done;              // 两 Panel 均完成
wire        spi_start;
wire [3:0]  spi_reg_addr;
wire [9:0]  spi_reg_data;
wire [9:0]  spi_rdback_p0;
wire [9:0]  spi_rdback_p1;
assign spi_done = spi_done_p0 && spi_done_p1;

// ---- frame_done CDC ----
reg         frame_done_toggle_100m;
wire        frame_done_rise;       // 50MHz 域 frame_done 边沿检测

// =========================================================================
// CDC: ctrl_init_done (100MHz → 50MHz, 2-FF level sync)
// =========================================================================
reg init_done_sync1, init_done_sync2;

always @(posedge gate_clk or negedge rst_n) begin
    if (!rst_n) begin
        init_done_sync1 <= 1'b0;
        init_done_sync2 <= 1'b0;
    end else begin
        init_done_sync1 <= ctrl_init_done;
        init_done_sync2 <= init_done_sync1;
    end
end

assign init_done_synced = init_done_sync2;

// =========================================================================
// CDC: ctrl_line_start (100MHz → 50MHz, toggle + 2-FF + edge detect)
// =========================================================================
reg ctrl_line_start_toggle;

always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n)
        ctrl_line_start_toggle <= 1'b0;
    else if (ctrl_line_start)
        ctrl_line_start_toggle <= ~ctrl_line_start_toggle;
end

reg line_start_sync1, line_start_sync2, line_start_sync3;

always @(posedge gate_clk or negedge rst_n) begin
    if (!rst_n) begin
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
// CDC: frame_start (50MHz → 100MHz, toggle + 2-FF + edge detect)
// =========================================================================
reg frame_start_toggle_50m;

always @(posedge gate_clk or negedge rst_n) begin
    if (!rst_n)
        frame_start_toggle_50m <= 1'b0;
    else if (frame_start)
        frame_start_toggle_50m <= ~frame_start_toggle_50m;
end

reg frame_start_sync1, frame_start_sync2, frame_start_sync3;

always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
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
// CDC: ctrl_frame_done (100MHz → 50MHz, toggle + 2-FF + edge detect)
// =========================================================================
always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n)
        frame_done_toggle_100m <= 1'b0;
    else if (ctrl_frame_done)
        frame_done_toggle_100m <= ~frame_done_toggle_100m;
end

reg frame_done_sync1, frame_done_sync2, frame_done_sync3;

always @(posedge gate_clk or negedge rst_n) begin
    if (!rst_n) begin
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
// CDC: spi_cfg_done (100MHz → 50MHz, 2-FF level sync)
// =========================================================================
reg cfg_done_sync1, cfg_done_sync2;

always @(posedge gate_clk or negedge rst_n) begin
    if (!rst_n) begin
        cfg_done_sync1 <= 1'b0;
        cfg_done_sync2 <= 1'b0;
    end else begin
        cfg_done_sync1 <= spi_cfg_done;
        cfg_done_sync2 <= cfg_done_sync1;
    end
end

assign cfg_done_synced = cfg_done_sync2;

// =========================================================================
// SPI 配置 FSM (100MHz 域)
//   写入全部 16 个 AD71143 寄存器 (ADDR 0-15)
//   顺序: Reg3(REFDAC)→Reg0(PWR)→Reg1(LPF)→Reg2(Mode)→Reg4~7(Timing)→Reg8~15
//   值来源: AD71143 SPEC Table 12 + Figure 22 Pipeline Mode 推荐
// =========================================================================
localparam CFG_IDLE  = 2'd0;
localparam CFG_ISSUE = 2'd1;
localparam CFG_WAIT  = 2'd2;
localparam CFG_DONE  = 2'd3;

reg [1:0]  cfg_state, cfg_state_next;
reg [3:0]  cfg_reg_idx;
reg        cfg_spi_start;
reg        cfg_all_done;

// SPI 配置寄存器 LUT — 按推荐上电顺序排列
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
    (cfg_reg_idx == 4'd0)  ? 10'h040 :  // Reg3:  AZEN=0, REFDAC=64 → 1.5V
    (cfg_reg_idx == 4'd1)  ? 10'h014 :  // Reg0:  PWR=Normal(000), IFS=20
    (cfg_reg_idx == 4'd2)  ? 10'h0A0 :  // Reg1:  LPF=3.9μs(01), CDS2_RESETEN=1
    (cfg_reg_idx == 4'd3)  ? 10'h027 :  // Reg2:  RNDOMIZE=1, DOUTMODE=1, ECHOCLK=1, Pipeline=1
    (cfg_reg_idx == 4'd4)  ? 10'h082 :  // Reg4:  INTRST_C=8(ACLK8), INTRST_O=2(ACLK2)
    (cfg_reg_idx == 4'd5)  ? 10'h013 :  // Reg5:  CDS1_C=1(ACLK1), CDS1_O=3(ACLK3)
    (cfg_reg_idx == 4'd6)  ? 10'h046 :  // Reg6:  CDS2_C=4(ACLK4), CDS2_O=6(ACLK6)
    (cfg_reg_idx == 4'd7)  ? 10'h025 :  // Reg7:  FA_CDS1=2(ACLK2), FA_CDS2=5(ACLK5)
    (cfg_reg_idx == 4'd8)  ? 10'h000 :  // Reg8:  CUSTCLMPEN=0 (禁用自定义钳位)
    (cfg_reg_idx == 4'd9)  ? 10'h000 :  // Reg9:  Reserved
    (cfg_reg_idx == 4'd10) ? 10'h000 :  // Reg10: PIPELINE_AVGEN=0
    (cfg_reg_idx == 4'd11) ? 10'h000 :  // Reg11: LFSR_EN=0
    (cfg_reg_idx == 4'd12) ? 10'h000 :  // Reg12: LP_EN=0 (Normal模式)
    (cfg_reg_idx == 4'd13) ? 10'h000 :  // Reg13: Reserved
    (cfg_reg_idx == 4'd14) ? 10'h000 :  // Reg14: Reserved
    (cfg_reg_idx == 4'd15) ? 10'h000 :  // Reg15: Reserved
    10'h000;

always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n)
        cfg_state <= CFG_IDLE;
    else
        cfg_state <= cfg_state_next;
end

always @(*) begin
    cfg_state_next = cfg_state;
    case (cfg_state)
        CFG_IDLE: begin
            if (ctrl_init_done)
                cfg_state_next = CFG_ISSUE;
        end
        CFG_ISSUE: cfg_state_next = CFG_WAIT;
        CFG_WAIT:  if (spi_done) cfg_state_next = CFG_DONE;
        CFG_DONE: begin
            if (cfg_reg_idx != 4'd15)
                cfg_state_next = CFG_ISSUE;
            // else stay in CFG_DONE permanently (all 16 regs written)
        end
        default: cfg_state_next = CFG_IDLE;
    endcase
end

always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
        cfg_spi_start <= 1'b0;
        cfg_reg_idx   <= 4'd0;
        cfg_all_done  <= 1'b0;
    end else begin
        cfg_spi_start <= 1'b0;

        case (cfg_state)
            CFG_IDLE: begin
                cfg_reg_idx  <= 4'd0;
                cfg_all_done <= 1'b0;
            end
            CFG_ISSUE: begin
                cfg_spi_start <= 1'b1;
            end
            CFG_WAIT: begin
                // wait for spi_done
            end
            CFG_DONE: begin
                if (cfg_reg_idx == 4'd15)
                    cfg_all_done <= 1'b1;
                else
                    cfg_reg_idx <= cfg_reg_idx + 4'd1;
            end
        endcase
    end
end

// SPI 控制信号来自配置 FSM
assign spi_reg_addr = cfg_addr_lut;
assign spi_reg_data = cfg_data_lut;
assign spi_start    = cfg_spi_start;
assign spi_cfg_done = cfg_all_done;

// AD71143 SPEC: 转换期间 CS 必须保持低电平
// SPI 配置完成后强制 CS=0, 否则使用 SPI 模块的 CS 输出
wire spi_cs_raw_p0;
wire spi_cs_raw_p1;
assign spi_cs_p0 = spi_cfg_done ? 1'b0 : spi_cs_raw_p0;
assign spi_cs_p1 = spi_cfg_done ? 1'b0 : spi_cs_raw_p1;

// =========================================================================
// Top FSM (50MHz 域)
//   POWERUP → WAIT_INIT → WAIT_CFG → IDLE → START → WAIT_FRAME → FRAME_GAP
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

always @(posedge gate_clk or negedge rst_n) begin
    if (!rst_n) begin
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

// AD71143 AFE 控制 (100MHz 域)
ad71143_ctrl #(
    .ACLK_PULSES      (9),
    .LINE_CYCLES      (6000),
    .RESET_CYCLES     (1000),
    .INIT_WAIT_CYCLES (10000),
    .FRAME_LINES      (FRAME_LINES)
) u_ad71143_ctrl (
    .clk          (clk_100m),
    .rst_n        (rst_n),
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
    .aclk_done    (aclk_done)
);


	// AD71143 SPI Master Panel 0 (100MHz 域)
	ad71143_spi u_spi_p0 (
	    .clk_sys    (clk_100m),
	    .rst_n      (rst_n),
	    .start      (spi_start),
	    .rw         (1'b1),
	    .reg_addr   (spi_reg_addr),
	    .reg_data   (spi_reg_data),
	    .done       (spi_done_p0),
	    .reg_rdback (spi_rdback_p0),
	    .spi_cs     (spi_cs_raw_p0),
	    .spi_sck    (spi_sck_p0),
	    .spi_sdi    (spi_sdi_p0),
	    .spi_sdo    (spi_sdo_p0)
	);

	// AD71143 SPI Master Panel 1 (100MHz 域, 与 Panel 0 并行配置)
	ad71143_spi u_spi_p1 (
	    .clk_sys    (clk_100m),
	    .rst_n      (rst_n),
	    .start      (spi_start),
	    .rw         (1'b1),
	    .reg_addr   (spi_reg_addr),
	    .reg_data   (spi_reg_data),
	    .done       (spi_done_p1),
	    .reg_rdback (spi_rdback_p1),
	    .spi_cs     (spi_cs_raw_p1),
	    .spi_sck    (spi_sck_p1),
	    .spi_sdi    (spi_sdi_p1),
	    .spi_sdo    (spi_sdo_p1)
	);

// AD71143 双 Panel LVDS 数据接收 (100MHz 域)
	ad71143_data_rx_dual #(
	    .MUTE_MIN             (113)     // 100MHz: tBURST=1765ns, 177cyc-64=113
	) u_data_rx_dual (
	    .clk_sys              (clk_100m),
	    .rst_n                (rst_n),
	    .sync_in              (sync_int),
	    .aclk_done            (aclk_done),
	    .dclk_p_A0            (dclk_p_A0),
	    .dclk_n_A0            (dclk_n_A0),
	    .dclko_p_A0           (dclko_p_A0),
	    .dclko_n_A0           (dclko_n_A0),
	    .dout_p_A0            (dout_p_A0),
	    .dout_n_A0            (dout_n_A0),
	    .dout_p_B0            (dout_p_B0),
	    .dout_n_B0            (dout_n_B0),
	    .dclk_p_A1            (dclk_p_A1),
	    .dclk_n_A1            (dclk_n_A1),
	    .dclko_p_A1           (dclko_p_A1),
	    .dclko_n_A1           (dclko_n_A1),
	    .dout_p_A1            (dout_p_A1),
	    .dout_n_A1            (dout_n_A1),
	    .dout_p_B1            (dout_p_B1),
	    .dout_n_B1            (dout_n_B1),
	    .line_done            (rx_line_done),
	    .header_ok            (header_ok),
	    .merged_valid         (merged_valid),
	    .merged_burst         (merged_burst),
	    .merged_burst_index   (merged_burst_index),
	    .state_debug_0        (),
	    .state_debug_1        (),
	    .burst_en_out         ()
	);

// NT39565D Gate Driver (50MHz 域, 修复 CLK_FREQ_MHZ=50)
nt39565d_gate_ctrl #(
    .CLK_FREQ_MHZ      (50  ),
    .CPV_PERIOD_US     (10  ),
    .CPV_PW_US_X10     (10  ),
    .STV_SETUP_US_X10  (3   ),
    .STV_HOLD_US_X10   (4   ),
    .OE_PW_US_X10      (10  ),
    .XAO_DELAY_US      (20  ),
    .OUT_CH_NORMAL     (541 ),
    .OUT_CH_2G         (540 ),
    .DEFAULT_MODE_SEL  (0   ),
    .SCAN_DIRECTION    (1'b0),
    .USE_DUAL_STV      (1'b0),
    .PER_LINE_TRIG     (1   )
) u_nt39565d (
    .clk            (gate_clk       ),
    .rst_n          (rst_n          ),
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
    .frame_done     (frame_done     )
);

    // =========================================================================
    // RGMII 桥接: merged_burst → 字节 → RGMII_tx
    // =========================================================================
    rgmii_bridge #(
        .BURST_WIDTH (256),
        .BURST_BYTES (32),
        .FRAME_SIZE  (32)
    ) u_rgmii_bridge (
        .sys_clk    (sys_clk),
        .rst_n      (rst_n),
        .clk_100m   (clk_100m),
        .data_in    (merged_burst),
        .data_valid (merged_valid),
        .TXC        (rgmii_txc),
        .TX_CTL     (rgmii_tx_ctl),
        .TXD0       (rgmii_txd0),
        .TXD1       (rgmii_txd1),
        .TXD2       (rgmii_txd2),
        .TXD3       (rgmii_txd3)
    );

    // =========================================================================
    // RGMII 接收: PHY → FPGA
    // =========================================================================
    RGMII_rx #(
        .FRAME_SIZE(64)
    ) u_rgmii_rx (
        .rst_n      (rst_n),
        .RXC        (rgmii_rxc),
        .RX_CTL     (rgmii_rx_ctl),
        .RXD0       (rgmii_rxd0),
        .RXD1       (rgmii_rxd1),
        .RXD2       (rgmii_rxd2),
        .RXD3       (rgmii_rxd3),
        .MDC        (rgmii_mdc),
        .MDIO       (rgmii_mdio)
    );

endmodule

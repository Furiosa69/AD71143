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
    input  wire spi_sdo,

    output wire roic_reset,
    output wire sync,
    output wire aclk,
    output wire spi_cs,
    output wire spi_sck,
    output wire spi_sdi,

    output wire cpv,
    output wire stv1,
    output wire stv2,
    output wire oe1,
    output wire oe2,
    output wire ud,
    output wire lr,
    output wire mode1,
    output wire mode2,
    output wire sel,
    output wire stv_mode,
    output wire chip_sel1,
    output wire chip_sel2,
    output wire oepsn,

    output wire frame_active,
    output wire frame_done_o,
    output wire line_done_o,
    output wire ctrl_init_done_o
);

// =========================================================================
// 时钟架构
// =========================================================================
`ifdef XILINX_PRIMITIVES
    wire clk_fb;
    wire pll_locked;
    wire clk_100m;

    PLLE2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT      (20),
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (20.0),
        .CLKOUT0_DIVIDE     (10),
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
`else
    // 仿真: 测试台提供 100MHz sys_clk, gate_clk = 50MHz 分频
    wire clk_100m = sys_clk;
    reg  gate_clk;

    wire rst_n;
    assign rst_n = key;

    always @(posedge clk_100m or negedge rst_n) begin
        if (!rst_n)
            gate_clk <= 1'b0;
        else
            gate_clk <= ~gate_clk;
    end
`endif

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
wire        spi_done;
reg         spi_start;
reg  [3:0]  spi_reg_addr;
reg  [9:0]  spi_reg_data;
wire [9:0]  spi_rdback;

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
//   写入 8 个 AD71143 寄存器: Reg3→Reg0→Reg1→Reg2→Reg4→Reg5→Reg6→Reg7
// =========================================================================
localparam CFG_IDLE  = 2'd0;
localparam CFG_ISSUE = 2'd1;
localparam CFG_WAIT  = 2'd2;
localparam CFG_DONE  = 2'd3;

reg [1:0]  cfg_state, cfg_state_next;
reg [2:0]  cfg_reg_idx;
reg        cfg_spi_start;
reg        cfg_all_done;

// SPI 配置寄存器 LUT (与 spi_test_top.v 一致)
wire [3:0] cfg_addr_lut;
wire [9:0] cfg_data_lut;

assign cfg_addr_lut =
    (cfg_reg_idx == 3'd0) ? 4'd3  :
    (cfg_reg_idx == 3'd1) ? 4'd0  :
    (cfg_reg_idx == 3'd2) ? 4'd1  :
    (cfg_reg_idx == 3'd3) ? 4'd2  :
    (cfg_reg_idx == 3'd4) ? 4'd4  :
    (cfg_reg_idx == 3'd5) ? 4'd5  :
    (cfg_reg_idx == 3'd6) ? 4'd6  :
    (cfg_reg_idx == 3'd7) ? 4'd7  :
    4'd0;

assign cfg_data_lut =
    (cfg_reg_idx == 3'd0) ? 10'h040 :  // Reg3: REFDAC=64 → ~1.5V
    (cfg_reg_idx == 3'd1) ? 10'h014 :  // Reg0: PWR=Normal, IFS=20
    (cfg_reg_idx == 3'd2) ? 10'h230 :  // Reg1: LPF=3.9μs, CDS2_RESETEN
    (cfg_reg_idx == 3'd3) ? 10'h003 :  // Reg2: Pipeline=1, ECHOCLK=1
    (cfg_reg_idx == 3'd4) ? 10'h070 :  // Reg4: INTRST
    (cfg_reg_idx == 3'd5) ? 10'h001 :  // Reg5: CDS1
    (cfg_reg_idx == 3'd6) ? 10'h005 :  // Reg6: CDS2
    (cfg_reg_idx == 3'd7) ? 10'h002 :  // Reg7: FA
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
            if (cfg_reg_idx != 3'd7)
                cfg_state_next = CFG_ISSUE;
            // else stay in CFG_DONE permanently (all 8 regs written)
        end
        default: cfg_state_next = CFG_IDLE;
    endcase
end

always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
        cfg_spi_start <= 1'b0;
        cfg_reg_idx   <= 3'd0;
        cfg_all_done  <= 1'b0;
    end else begin
        cfg_spi_start <= 1'b0;

        case (cfg_state)
            CFG_IDLE: begin
                cfg_reg_idx  <= 3'd0;
                cfg_all_done <= 1'b0;
            end
            CFG_ISSUE: begin
                cfg_spi_start <= 1'b1;
            end
            CFG_WAIT: begin
                // wait for spi_done
            end
            CFG_DONE: begin
                if (cfg_reg_idx == 3'd7)
                    cfg_all_done <= 1'b1;
                else
                    cfg_reg_idx <= cfg_reg_idx + 3'd1;
            end
        endcase
    end
end

// SPI 控制信号来自配置 FSM
assign spi_reg_addr = cfg_addr_lut;
assign spi_reg_data = cfg_data_lut;
assign spi_start    = cfg_spi_start;
assign spi_cfg_done = cfg_all_done;

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
    .roic_reset   (roic_reset),
    .sync         (sync),
    .aclk         (aclk),
    .init_done    (ctrl_init_done),
    .line_start   (ctrl_line_start),
    .line_done    (ctrl_line_done),
    .aclk_idx     (),
    .line_cnt     (ctrl_line_cnt),
    .frame_done   (ctrl_frame_done)
);

// AD71143 SPI Master (100MHz 域)
ad71143_spi u_spi (
    .clk_sys    (clk_100m),
    .rst_n      (rst_n),
    .start      (spi_start),
    .rw         (1'b1),           // always write for config
    .reg_addr   (spi_reg_addr),
    .reg_data   (spi_reg_data),
    .done       (spi_done),
    .reg_rdback (spi_rdback),
    .spi_cs     (spi_cs),
    .spi_sck    (spi_sck),
    .spi_sdi    (spi_sdi),
    .spi_sdo    (spi_sdo)
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

endmodule

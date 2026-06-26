// =============================================================================
// AD71143 LVDS 数据接收 — 单通道最简测试版
// =============================================================================
`timescale 1ns / 1ps
// 仅测试 1 颗 ROIC, DOUTMODE=0 (单 LVDS), 200MHz DCLK, SDR (1bit/cycle)
// 不做数据缓存, 只校验 Header 0x0A 同步字 + 给出 line_done 指示
// =============================================================================

module ad71143_data_rx (
    // 系统
    input  wire         clk_sys,        // 200MHz
    input  wire         rst_n,          // 低复位

    // 时序发生器来
    input  wire         sync_in,        // SYNC, 低=新行
    input  wire         aclk_done,      // ACLK 序列完成

    // LVDS 物理口 — DCLK (出)
    output wire         dclk_p_A,
    output wire         dclk_n_A,

    // LVDS 物理口 — DOUT (入)
    input  wire         dout_p_A,
    input  wire         dout_n_A,

    // 测试输出
    output reg          line_done,      // 一行收完 (单周期脉冲)
    output reg          header_ok,      // Header 0x0A 匹配
    output reg  [7:0]   header_byte,    // Header 首字节 (应为 0x0A)
    output reg  [2:0]   state_debug,    // 状态机状态 (ILA看)
    output wire [7:0]   shift_hi,       // shift_reg[63:56] (debug)
    output wire [7:0]   shift_lo,       // shift_reg[7:0]  (debug)
    output wire         burst_en_out,   // burst_en (debug)
    output wire         burst_en_comb,  // 组合逻辑版 burst_en (ROIC模型用)
    output wire         roic_trigger    // ROIC 提前激活信号
);

    // =========================================================================
    // 状态机
    // =========================================================================
    localparam S_IDLE      = 3'd0;  // 等 SYNC 下降沿
    localparam S_WAIT      = 3'd1;  // 等 aclk_done
    localparam S_ACT       = 3'd2;  // DCLK active: 收 64 bit
    localparam S_MUTE      = 3'd3;  // DCLK mute
    localparam S_DONE      = 3'd4;  // 一行完成
    localparam MUTE_MIN    = 290;   // 1445ns @200MHz
    localparam ACTIVE_DCLK = 64;    // 每 Burst active DCLK 周期数

    reg [2:0] state, state_next;
    always @(posedge clk_sys or negedge rst_n)
        if (!rst_n) state <= S_IDLE;
        else        state <= state_next;

    // =========================================================================
    // SYNC 下降沿检测
    // =========================================================================
    reg sync_d1;
    wire sync_fall;
    always @(posedge clk_sys) sync_d1 <= sync_in;
    assign sync_fall = sync_d1 && !sync_in;   // 高→低 = 新行开始

    // =========================================================================
    // 计数器
    // =========================================================================

    reg [6:0]  bit_cnt;         // Burst 内 bit 计数 (0~64, 需计到64)
    reg [6:0]  burst_cnt;       // 当前是第几个 Burst (0=Header, 1~64=Data)
    reg [9:0]  mute_cnt;        // Mute 周期计数

    // =========================================================================
    // Burst 使能 (active=1, mute=0)
    //   用 state==S_ACT 且 bit_cnt<64 直接控制, 正好 64 个 DCLK 周期
    // =========================================================================
    reg burst_en;
    always @(posedge clk_sys)
        burst_en <= (state == S_ACT && bit_cnt < ACTIVE_DCLK);

    // =========================================================================
    // 状态转移
    // =========================================================================
    always @(*) begin
        state_next = state;
        case (state)
            S_IDLE: if (sync_fall)           state_next = S_WAIT;
            S_WAIT: if (aclk_done)           state_next = S_ACT;
            S_ACT:  if (bit_cnt == ACTIVE_DCLK) state_next = S_MUTE;
            S_MUTE: if (mute_cnt >= MUTE_MIN-1) begin
                        if (burst_cnt == 64) state_next = S_DONE;  // Header + 64 Data
                        else                 state_next = S_ACT;
                    end
            S_DONE:                          state_next = S_IDLE;
            default:                         state_next = S_IDLE;
        endcase
    end

    // =========================================================================
    // 计数器逻辑
    // =========================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt   <= 6'd0;
            burst_cnt <= 7'd0;
            mute_cnt  <= 10'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    bit_cnt   <= 6'd0;
                    burst_cnt <= 7'd0;
                    mute_cnt  <= 10'd0;
                end
                S_ACT: begin
                    bit_cnt   <= bit_cnt + 6'd1;   // 每周期收 1bit
                    mute_cnt  <= 10'd0;
                end
                S_MUTE: begin
                    bit_cnt   <= 6'd0;
                    mute_cnt  <= mute_cnt + 10'd1;
                    if (mute_cnt >= MUTE_MIN-1)
                        burst_cnt <= burst_cnt + 7'd1;
                end
                default: ;
            endcase
        end
    end

    // =========================================================================
    // 移位寄存器: 64bit, MSB first
    //   bit_cnt=0 时采到的 bit → reg[63], bit_cnt=63 时采到的 bit → reg[0]
    //
    // ⚠️ 用 negedge clk_sys 采样, 等效 180° (2.5ns @200MHz) 相位偏移
    //     原因: DCLK 在 posedge 发出 → ROIC tDDOUT(0~7ns) 后 DOUT 才有效
    //           在 negedge 采样给数据留传播时间, 实际硬件用 IDELAY 实现
    // =========================================================================
    // DOUT 输入线 (IBUFDS 输出)
    wire dout_i;

    reg [63:0] shift_reg;
    always @(negedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            shift_reg <= 64'd0;
        else if (state == S_ACT)
            shift_reg <= {shift_reg[62:0], dout_i};  // 左移, 新bit进LSB
    end

    // =========================================================================
    // Header 校验: 在刚进入 S_MUTE (离开 S_ACT) 且 burst_cnt==0 时触发
    //   shift_reg 已在 negedge 完成 64 次采样, [63:56] = header 首字节
    // =========================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            header_ok   <= 1'b0;
            header_byte <= 8'd0;
        end else if (state == S_MUTE && burst_cnt == 0) begin
            header_byte <= shift_reg[63:56];
            header_ok   <= (shift_reg[63:56] == 8'h0A);
        end
    end

    // =========================================================================
    // line_done 脉冲
    // =========================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            line_done <= 1'b0;
        else
            line_done <= (state == S_DONE);
    end

    // =========================================================================
    // 调试: 状态输出 (接 ILA)
    // =========================================================================
    always @(posedge clk_sys)
        state_debug <= state;

    // Debug outputs
    assign shift_hi     = shift_reg[63:56];
    assign shift_lo     = shift_reg[7:0];
    assign burst_en_out = burst_en;
    // 组合逻辑版 burst_en (TB 的 ROIC 模型用)
    assign burst_en_comb = (state == S_ACT && bit_cnt < ACTIVE_DCLK);
    // ROIC 触发: 提前一拍, state_next==S_ACT 时即激活
    assign roic_trigger = (state_next == S_ACT) || (state == S_ACT && bit_cnt < ACTIVE_DCLK);

    // =========================================================================
    // LVDS 原语
    // =========================================================================

    // --- DCLK 发送: ODDR + OBUFDS ---
    // D0=1, D1=0 → 每个 clk_sys 周期 DCLK 翻转一次 → 200MHz 方波
    wire dclk_pre;
    ODDR #(
        .DDR_CLK_EDGE("OPPOSITE_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) oddr_dclk (
        .Q  (dclk_pre),
        .C  (clk_sys),
        .CE (burst_en),     // 仅 active 时有脉冲
        .D1 (1'b1),
        .D2 (1'b0),
        .R  (1'b0),
        .S  (1'b0)
    );

    OBUFDS #(
        .IOSTANDARD("LVDS_33")
    ) obufds_dclk (
        .O  (dclk_p_A),
        .OB (dclk_n_A),
        .I  (dclk_pre)
    );

    // --- DOUT 接收: IBUFDS + 简单寄存器 ---
    // dout_i 在上面已声明, 此处仅例化 IBUFDS
    IBUFDS #(
        .DIFF_TERM("TRUE"),     // 启用内部 100Ω 终端
        .IOSTANDARD("LVDS_33")
    ) ibufds_dout (
        .O  (dout_i),
        .I  (dout_p_A),
        .IB (dout_n_A)
    );

endmodule

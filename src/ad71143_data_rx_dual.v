// =============================================================================
// AD71143 双 Panel LVDS 数据接收 — DDR 模式 (DOUTMODE=1)
// =============================================================================
// 封装两个 ad71143_data_rx 实例, 共享 sync_in/aclk_done, 各自独立 LVDS 物理口
// 每 Panel: 2 对 DOUT (Lane A/B) + 1 对 DCLK + 1 对 DCLKO → DDR 模式
// 两 Panel 共计: 4 对 DOUT + 2 对 DCLK + 2 对 DCLKO
//
// 输出拼接: merged_burst[255:0] = {panel1_burst[127:0], panel0_burst[127:0]}
// =============================================================================
`timescale 1ns / 1ps

module ad71143_data_rx_dual #(
    parameter integer MUTE_MIN = 290   // 200MHz: 353cyc - 64 = 289 → 290
) (
    // =========================================================================
    // 共享系统信号
    // =========================================================================
    input  wire         clk_sys,        // 200MHz
    input  wire         rst_n,

    input  wire         sync_in,        // SYNC, 低有效 = 新行
    input  wire         aclk_done,      // ACLK 序列完成脉冲

    // =========================================================================
    // Panel 0 LVDS 接口
    // =========================================================================
    // DCLK 输出 (FPGA → ROIC0)
    output wire         dclk_p_A0,
    output wire         dclk_n_A0,

    // DCLKO 输入 (ROIC0 → FPGA, Echo Clock)
    input  wire         dclko_p_A0,
    input  wire         dclko_n_A0,

    // DOUT Lane A 输入 (偶数通道)
    input  wire         dout_p_A0,
    input  wire         dout_n_A0,

    // DOUT Lane B 输入 (奇数通道)
    input  wire         dout_p_B0,
    input  wire         dout_n_B0,

    // =========================================================================
    // Panel 1 LVDS 接口
    // =========================================================================
    // DCLK 输出 (FPGA → ROIC1)
    output wire         dclk_p_A1,
    output wire         dclk_n_A1,

    // DCLKO 输入 (ROIC1 → FPGA, Echo Clock)
    input  wire         dclko_p_A1,
    input  wire         dclko_n_A1,

    // DOUT Lane A 输入 (偶数通道)
    input  wire         dout_p_A1,
    input  wire         dout_n_A1,

    // DOUT Lane B 输入 (奇数通道)
    input  wire         dout_p_B1,
    input  wire         dout_n_B1,

    // =========================================================================
    // 合并输出 (clk_sys 域)
    // =========================================================================
    output wire         line_done,          // 两 Panel 均完成一行
    output wire         header_ok,          // 两 Panel Header 均 0x0A
    output reg          merged_valid,       // 合并数据有效 (单周期脉冲)
    output reg  [255:0] merged_burst,       // {Panel1[127:0], Panel0[127:0]}
    output reg  [6:0]   merged_burst_index, // Burst 编号

    // =========================================================================
    // 调试
    // =========================================================================
    output wire [2:0]   state_debug_0,      // Panel 0 状态机
    output wire [2:0]   state_debug_1,      // Panel 1 状态机
    output wire         burst_en_out        // Panel 0 burst_en (TB 同步用)
);

    // =========================================================================
    // Panel 内部连线
    // =========================================================================
    wire [127:0] p0_merged_burst;
    wire [127:0] p1_merged_burst;
    wire         p0_merged_valid;
    wire         p1_merged_valid;
    wire         p0_line_done;
    wire         p1_line_done;
    wire         p0_header_ok;
    wire         p1_header_ok;
    wire [6:0]   p0_burst_index;
    wire [6:0]   p1_burst_index;
    wire [2:0]   p0_state;
    wire [2:0]   p1_state;
    wire         p0_burst_en;

    // =========================================================================
    // Panel 0 实例
    // =========================================================================
    ad71143_data_rx #(
        .MUTE_MIN(MUTE_MIN)
    ) u_panel0 (
        .clk_sys              (clk_sys),
        .rst_n                (rst_n),
        .sync_in              (sync_in),
        .aclk_done            (aclk_done),

        .dclk_p_A             (dclk_p_A0),
        .dclk_n_A             (dclk_n_A0),
        .dclko_p_A            (dclko_p_A0),
        .dclko_n_A            (dclko_n_A0),
        .dout_p_A             (dout_p_A0),
        .dout_n_A             (dout_n_A0),
        .dout_p_B             (dout_p_B0),
        .dout_n_B             (dout_n_B0),

        .line_done            (p0_line_done),
        .header_ok            (p0_header_ok),
        .header_byte          (),
        .header_readdown      (),
        .header_cds_id        (),
        .header_temp          (),
        .header_vt            (),
        .merged_valid         (p0_merged_valid),
        .merged_burst         (p0_merged_burst),
        .merged_first_channel (),
        .merged_last_channel  (),
        .merged_burst_index   (p0_burst_index),

        .state_debug          (p0_state),
        .shift_hi             (),
        .shift_lo             (),
        .burst_en_out         (p0_burst_en),
        .burst_en_comb        (),
        .roic_trigger         ()
    );

    // =========================================================================
    // Panel 1 实例
    // =========================================================================
    ad71143_data_rx #(
        .MUTE_MIN(MUTE_MIN)
    ) u_panel1 (
        .clk_sys              (clk_sys),
        .rst_n                (rst_n),
        .sync_in              (sync_in),
        .aclk_done            (aclk_done),

        .dclk_p_A             (dclk_p_A1),
        .dclk_n_A             (dclk_n_A1),
        .dclko_p_A            (dclko_p_A1),
        .dclko_n_A            (dclko_n_A1),
        .dout_p_A             (dout_p_A1),
        .dout_n_A             (dout_n_A1),
        .dout_p_B             (dout_p_B1),
        .dout_n_B             (dout_n_B1),

        .line_done            (p1_line_done),
        .header_ok            (p1_header_ok),
        .header_byte          (),
        .header_readdown      (),
        .header_cds_id        (),
        .header_temp          (),
        .header_vt            (),
        .merged_valid         (p1_merged_valid),
        .merged_burst         (p1_merged_burst),
        .merged_first_channel (),
        .merged_last_channel  (),
        .merged_burst_index   (p1_burst_index),

        .state_debug          (p1_state),
        .shift_hi             (),
        .shift_lo             (),
        .burst_en_out         (),
        .burst_en_comb        (),
        .roic_trigger         ()
    );

    // =========================================================================
    // 输出对齐逻辑
    //
    // 两 Panel 共享 sync_in/aclk_done/clk_sys → FSM 理论上同步
    // 但 DCLKO 域 CDC 可能有 1~2 周期偏移 → 用 capture+hold 对齐
    // MUTE 期 (~177 clk_sys) 远大于 CDC 偏移, 不会丢 Burst
    // =========================================================================
    reg [127:0] panel0_hold;
    reg [127:0] panel1_hold;
    reg         p0_captured;
    reg         p1_captured;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            panel0_hold        <= 128'd0;
            panel1_hold        <= 128'd0;
            p0_captured        <= 1'b0;
            p1_captured        <= 1'b0;
            merged_valid       <= 1'b0;
            merged_burst       <= 256'd0;
            merged_burst_index <= 7'd0;
        end else begin
            merged_valid <= 1'b0;  // 默认低, 仅对齐成功时发单周期脉冲

            // 捕获 Panel 0 数据
            if (p0_merged_valid) begin
                panel0_hold <= p0_merged_burst;
                p0_captured <= 1'b1;
            end

            // 捕获 Panel 1 数据
            if (p1_merged_valid) begin
                panel1_hold <= p1_merged_burst;
                p1_captured <= 1'b1;
            end

            // 两 Panel 数据都到齐 → 输出合并数据
            if (p0_captured && p1_captured) begin
                merged_burst       <= {panel1_hold, panel0_hold};
                merged_burst_index <= p0_burst_index;   // 两 Panel burst_index 相同
                merged_valid       <= 1'b1;
                p0_captured        <= 1'b0;
                p1_captured        <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 行级状态: 两 Panel 均完成才有效
    // =========================================================================
    assign line_done = p0_line_done && p1_line_done;
    assign header_ok = p0_header_ok  && p1_header_ok;

    // =========================================================================
    // 调试输出
    // =========================================================================
    assign state_debug_0 = p0_state;
    assign state_debug_1 = p1_state;
    assign burst_en_out  = p0_burst_en;   // Panel 0 的 burst_en, TB 用

endmodule

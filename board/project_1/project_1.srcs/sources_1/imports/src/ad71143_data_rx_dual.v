// =============================================================================
// AD71143 双 Panel LVDS 数据接收 — DDR 模式 (DOUTMODE=1)
// =============================================================================
// 封装两个 ad71143_data_rx 实例, 共享 sync_in/aclk_done, 各自独立 LVDS 物理口
// 每 Panel: 2 对 DOUT (Lane A/B) + 1 对 DCLK → DDR 模式
// 两 Panel 共计: 4 对 DOUT + 2 对 DCLK (内部回环采样, 无 DCLKO 引脚)
//
// 输出拼接: merged_burst[255:0] = {panel1_burst[127:0], panel0_burst[127:0]}
// =============================================================================

module ad71143_data_rx_dual #(
    parameter integer MUTE_MIN = 112   // 100MHz: 177cyc - 65 = 112 (ACTIVE=64 + PRE_DELAY=1)
) (
    // =========================================================================
    // 共享系统信号
    // =========================================================================
    input  wire         clk_sys,        // 100MHz
    input  wire         rst_n,

    input  wire         sync_in,        // SYNC, 低有效 = 新行
    input  wire         aclk_done,      // ACLK 序列完成脉冲

    // =========================================================================
    // Panel 0 LVDS 接口
    // =========================================================================
    // DCLK 输出 (FPGA → ROIC0)
    output wire         dclk_p_A0,
    output wire         dclk_n_A0,

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

    // DOUT Lane A 输入 (偶数通道)
    input  wire         dout_p_A1,
    input  wire         dout_n_A1,

    // DOUT Lane B 输入 (奇数通道)
    input  wire         dout_p_B1,
    input  wire         dout_n_B1,

    // =========================================================================
    // 合并输出 (clk_sys 域)
    // =========================================================================
    output wire         line_done,           // 两 Panel 均完成一行
    output wire         header_ok,           // 两 Panel Header 均 0x0A
    output reg          merged_valid = 1'b0, // 合并数据有效 (单周期脉冲)
    output reg  [255:0] merged_burst,        // {Panel1[127:0], Panel0[127:0]}
    output reg  [6:0]   merged_burst_index,  // Burst 编号

    // =========================================================================
    // 调试
    // =========================================================================
    output wire [2:0]   state_debug_0,      // Panel 0 状态机
    output wire [2:0]   state_debug_1,      // Panel 1 状态机
    output wire         burst_en_out,       // Panel 0 burst_en (TB 同步用)

    // Panel 1 调试信号 (ILA 探针)
    output wire [7:0]   dbg_p1_shift_hi,   // Panel 1 Lane A 移位寄存器首字节
    output wire [7:0]   dbg_p1_shift_lo,   // Panel 1 Lane B 移位寄存器首字节
    output wire         dbg_p1_burst_en,   // Panel 1 burst 使能
    output wire         dbg_p1_header_ok,  // Panel 1 Header 校验 (连续组合比较)
    output wire         dbg_p1_merged_valid, // Panel 1 合并数据有效
    output wire         dbg_p1_line_done,   // Panel 1 行完成
    output wire         dbg_p1_dout_a_raw,  // Panel 1 LVDS A原始输入
    output wire         dbg_p1_dout_b_raw   // Panel 1 LVDS B原始输入
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
    wire         p1_burst_en;
    wire [7:0]   p1_shift_hi;
    wire [7:0]   p1_shift_lo;
    wire         p1_dout_a_raw;
    wire         p1_dout_b_raw;

    // =========================================================================
    // Panel 0 实例
    // =========================================================================
    ad71143_data_rx #(
        .MUTE_MIN(MUTE_MIN)
    ) u_panel0 (
        .clk_sys              (clk_sys  ),
        .rst_n                (rst_n    ),
        .sync_in              (sync_in  ),
        .aclk_done            (aclk_done),

        .dclk_p_A             (dclk_p_A0),
        .dclk_n_A             (dclk_n_A0),
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
        .roic_trigger         (),
        .dbg_header_valid     (),
        .dbg_header_latched   ()
    );

    // =========================================================================
    // Panel 1 实例
    // =========================================================================
    ad71143_data_rx #(
        .MUTE_MIN(MUTE_MIN)
    ) u_panel1 (
        .clk_sys              (clk_sys  ),
        .rst_n                (rst_n    ),
        .sync_in              (sync_in  ),
        .aclk_done            (aclk_done),

        .dclk_p_A             (dclk_p_A1),
        .dclk_n_A             (dclk_n_A1),
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
        .shift_hi             (p1_shift_hi),
        .shift_lo             (p1_shift_lo),
        .burst_en_out         (p1_burst_en),
        .burst_en_comb        (),
        .roic_trigger         (),
        .dbg_header_valid     (),
        .dbg_header_latched   (),
        .dbg_dout_a_raw       (p1_dout_a_raw),
        .dbg_dout_b_raw       (p1_dout_b_raw)
    );

    // =========================================================================
    // 输出对齐逻辑 + 单 Panel 超时降级
    //
    // 【测试模式】：只输出 Panel 1 数据，不等待 Panel 0
    // Panel 0 数据位置补 0，简化调试
    // =========================================================================
    localparam integer CAP_TIMEOUT = 20;  // 单 Panel 超时周期数

    reg [127:0] panel0_hold;
    reg [127:0] panel1_hold;
    reg         p0_captured;
    reg         p1_captured;
    reg [7:0]   cap_timeout_cnt;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            panel0_hold        <= 128'd0;
            panel1_hold        <= 128'd0;
            p0_captured        <= 1'b0;
            p1_captured        <= 1'b0;
            merged_burst       <= 256'd0;
            merged_burst_index <= 7'd0;
            cap_timeout_cnt    <= 8'd0;
        end else begin
            merged_valid <= 1'b0;  // 默认低, 仅对齐成功时发单周期脉冲

            // 【测试模式】：忽略 Panel 0，只处理 Panel 1
            // 捕获 Panel 0 数据（保留逻辑但不使用）
            if (p0_merged_valid) begin
                panel0_hold <= p0_merged_burst;
                p0_captured <= 1'b1;
            end

            // 捕获 Panel 1 数据
            if (p1_merged_valid) begin
                panel1_hold <= p1_merged_burst;
                p1_captured <= 1'b1;
            end

            // 【测试模式】：只要 Panel 1 数据到达，立即输出
            // Panel 0 位置填充 0
            if (p1_captured) begin
                merged_burst       <= {panel1_hold, 128'd0};  // Panel 1 数据放在高 128 位
                merged_burst_index <= p1_burst_index;
                merged_valid       <= 1'b1;
                p0_captured        <= 1'b0;
                p1_captured        <= 1'b0;
                cap_timeout_cnt    <= 8'd0;
            end else if (p0_captured) begin
                // 如果只有 Panel 0 数据，清除标志（丢弃）
                p0_captured     <= 1'b0;
                cap_timeout_cnt <= 8'd0;
            end else begin
                cap_timeout_cnt <= 8'd0;
            end
        end
    end

    // =========================================================================
    // 行级状态: 两 Panel 均完成才有效 (单 Panel 模式取有数据的一路)
    // =========================================================================
    assign line_done = p0_line_done || p1_line_done;
    assign header_ok = p0_header_ok  || p1_header_ok;

    // =========================================================================
    // 调试输出
    // =========================================================================
    assign state_debug_0 = p0_state;
    assign state_debug_1 = p1_state;
    assign burst_en_out  = p0_burst_en;   // Panel 0 的 burst_en, TB 用
    
    // Panel 1 调试信号
    assign dbg_p1_shift_hi    = p1_shift_hi;
    assign dbg_p1_shift_lo    = p1_shift_lo;
    assign dbg_p1_burst_en    = p1_burst_en;
    assign dbg_p1_header_ok   = p1_header_ok;
    assign dbg_p1_merged_valid = p1_merged_valid;
    assign dbg_p1_line_done   = p1_line_done;
    assign dbg_p1_dout_a_raw  = p1_dout_a_raw;
    assign dbg_p1_dout_b_raw  = p1_dout_b_raw;

endmodule

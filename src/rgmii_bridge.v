`timescale 1ns / 1ps
// RGMII 桥接模块
//   从 200MHz 域接收 128-bit burst 数据
//   CDC → 125MHz 域 → 字节序列化 → RGMII_tx 发送
//   每个 burst 作为一帧发送 (FRAME_SIZE 字节, 默认 16)
//
//   时钟: 内置 MMCM 从 sys_clk(50MHz) 生成 125MHz RGMII TXC
//
module rgmii_bridge #(
    parameter BURST_WIDTH = 128,         // 输入 burst 位宽
    parameter BURST_BYTES = 16,          // burst 字节数 = 128/8
    parameter FRAME_SIZE   = 16          // 一帧数据字节数 (16 或 64)
) (
    input  wire         sys_clk,         // 50MHz 系统时钟
    input  wire         rst_n,           // 异步复位，低有效

    // ---- 200MHz 域输入 (来自 ad71143_data_rx) ----
    input  wire         clk_200m,
    input  wire [127:0] data_in,         // merged_burst
    input  wire         data_valid,      // merged_valid

    // ---- RGMII 输出 ----
    output wire         TXC,             // 125MHz RGMII 发送时钟
    output wire         TX_CTL,
    output wire         TXD0,
    output wire         TXD1,
    output wire         TXD2,
    output wire         TXD3
);

    // =====================================================================
    // MMCM: 50MHz → 125MHz
    // =====================================================================
    wire clk_125m;
    wire mmcm_locked;
    wire clk_fb;

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (25.0),         // VCO = 50MHz × 25 = 1250MHz
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (20.0),         // 50MHz = 20ns
        .CLKOUT0_DIVIDE_F   (10.0),         // 1250 / 10 = 125MHz
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT1_DIVIDE     (1),
        .CLKOUT2_DIVIDE     (1),
        .CLKOUT3_DIVIDE     (1),
        .CLKOUT4_DIVIDE     (1),
        .CLKOUT5_DIVIDE     (1),
        .CLKOUT6_DIVIDE     (1),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) mmcm_inst (
        .CLKIN1             (sys_clk),
        .CLKOUT0            (clk_125m),
        .CLKOUT1            (),
        .CLKOUT2            (),
        .CLKOUT3            (),
        .CLKOUT4            (),
        .CLKOUT5            (),
        .CLKOUT6            (),
        .CLKFBOUT           (clk_fb),
        .CLKFBIN            (clk_fb),
        .PWRDWN             (1'b0),
        .RST                (1'b0),
        .LOCKED             (mmcm_locked)
    );

    wire rgmii_rst_n = rst_n & mmcm_locked;

    // =====================================================================
    // 200MHz 域: 捕获 burst, 生成 CDC toggle
    // =====================================================================
    reg [127:0] burst_hold_200m;
    reg         valid_toggle_200m;

    always @(posedge clk_200m or negedge rst_n) begin
        if (!rst_n) begin
            burst_hold_200m   <= 128'd0;
            valid_toggle_200m <= 1'b0;
        end else if (data_valid) begin
            burst_hold_200m   <= data_in;
            valid_toggle_200m <= ~valid_toggle_200m;
        end
    end

    // =====================================================================
    // CDC: toggle → 125MHz 域 (2-FF + edge detect)
    // =====================================================================
    reg valid_sync1_125m, valid_sync2_125m, valid_sync3_125m;

    always @(posedge clk_125m or negedge rgmii_rst_n) begin
        if (!rgmii_rst_n) begin
            valid_sync1_125m <= 1'b0;
            valid_sync2_125m <= 1'b0;
            valid_sync3_125m <= 1'b0;
        end else begin
            valid_sync1_125m <= valid_toggle_200m;
            valid_sync2_125m <= valid_sync1_125m;
            valid_sync3_125m <= valid_sync2_125m;
        end
    end

    wire burst_ready_125m = valid_sync2_125m ^ valid_sync3_125m;

    // =====================================================================
    // 125MHz 域: 字节移位寄存器 + RGMII_tx 控制
    // =====================================================================
    reg [127:0] shift_reg;
    reg [7:0]   byte_cnt;
    reg         tx_start_125m;
    reg [7:0]   tx_data_125m;
    reg         sending;

    // 前导码 + SFD 期间保持 tx_data 不变，DATA 期间从 shift_reg 取字节
    // RGMII_tx 在 PREAMBLE/SFD_STATE 使用内部常量，在 DATA 状态采样 tx_data
    // 所以只需在 state==DATA 时提供正确的 tx_data 即可
    // 我们用 tx_start 脉冲触发发送，RGMII_tx 自动处理前导码和 SFD

    always @(posedge clk_125m or negedge rgmii_rst_n) begin
        if (!rgmii_rst_n) begin
            shift_reg     <= 128'd0;
            byte_cnt      <= 8'd0;
            tx_start_125m <= 1'b0;
            tx_data_125m  <= 8'd0;
            sending       <= 1'b0;
        end else begin
            tx_start_125m <= 1'b0;

            if (burst_ready_125m) begin
                // 新 burst 到达，锁存数据
                shift_reg <= burst_hold_200m;
                byte_cnt  <= 8'd0;
                sending   <= 1'b1;
            end

            if (sending) begin
                if (byte_cnt == BURST_BYTES) begin
                    // burst 数据全部载入完毕，发出发送脉冲
                    tx_start_125m <= 1'b1;
                    sending       <= 1'b0;
                end else begin
                    // 预加载 tx_data: 每个时钟从 shift_reg 取一字节
                    // shift_reg[127:120] 是第一个字节，[7:0] 是最后一个
                    tx_data_125m <= shift_reg[127 -: 8];
                    shift_reg    <= {shift_reg[119:0], 8'd0};
                    byte_cnt     <= byte_cnt + 1;
                end
            end else begin
                tx_data_125m <= 8'd0;
            end
        end
    end

    // =====================================================================
    // RGMII_tx 例化
    // =====================================================================
    RGMII_tx #(
        .FRAME_SIZE(FRAME_SIZE)
    ) u_rgmii_tx (
        .rst_n    (rgmii_rst_n),
        .TXC      (clk_125m),
        .tx_data  (tx_data_125m),
        .tx_start (tx_start_125m),
        .TX_CTL   (TX_CTL),
        .TXD0     (TXD0),
        .TXD1     (TXD1),
        .TXD2     (TXD2),
        .TXD3     (TXD3)
    );

    assign TXC = clk_125m;

endmodule

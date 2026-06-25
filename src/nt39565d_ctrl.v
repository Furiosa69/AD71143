//////////////////////////////////////////////////////////////////////////////
// Module Name    : nt39565d_gate_ctrl
// Description    : NT39565D TFT LCD Gate Driver 控制模块
//                  - 产生 CPV (移位时钟)
//                  - 产生 STV (起始脉冲)
//                  - 产生 OE  (输出使能, 低有效)
//                  - 支持 Normal / 2G / 2G+LCS 模式 (通过参数配置)
//                  - 支持双 STV 同步或延迟 1CPV
//                  - 双向扫描 (UD 控制)
//
// stv_delay_sel 编码:
//   2'b00 : identical STV, short STV
//   2'b01 : delay 1CPV between STV1/STV2, short STV
//   2'b10 : identical STV, long STV
//   2'b11 : delay 1CPV between STV1/STV2, long STV
//////////////////////////////////////////////////////////////////////////////

module nt39565d_gate_ctrl #(
    parameter integer CLK_FREQ_MHZ      = 20,
    parameter integer CPV_PERIOD_US     = 10,
    parameter integer CPV_PW_US_X10     = 10,
    parameter integer STV_SETUP_US_X10  = 3,
    parameter integer STV_HOLD_US_X10   = 4,
    parameter integer OE_PW_US_X10      = 10,
    parameter integer XAO_DELAY_US      = 20,
    parameter integer OUT_CH_NORMAL     = 541,
    parameter integer OUT_CH_2G         = 540,
    parameter integer DEFAULT_MODE_SEL  = 0,
    parameter         SCAN_DIRECTION    = 1'b0,
    parameter         USE_DUAL_STV      = 1'b0
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       frame_start,
    input  wire       line_start,
    input  wire       xao_emergency,
    input  wire [9:0] line_count,
    input  wire       scan_direction,
    input  wire [1:0] mode_select,
    input  wire [1:0] stv_delay_sel,
    input  wire       oe_mask_en,

    output reg        cpv,
    output reg        stv1,
    output reg        stv2,
    output reg        oe1,
    output reg        oe2,
    output reg        ud,
    output reg        lr,

    output reg        mode1,
    output reg        mode2,
    output reg        sel,
    output reg        stv_mode,
    output reg        chip_sel1,
    output reg        chip_sel2,
    output reg        oepsn,

    output reg        busy,
    output reg        line_done,
    output reg        frame_done
);

    localparam integer CPV_PERIOD_CNT = (CPV_PERIOD_US * CLK_FREQ_MHZ < 2) ? 2 : (CPV_PERIOD_US * CLK_FREQ_MHZ);
    localparam integer CPV_PW_CNT     = ((CPV_PW_US_X10 * CLK_FREQ_MHZ + 9) / 10 < 1) ? 1 : ((CPV_PW_US_X10 * CLK_FREQ_MHZ + 9) / 10);
    localparam integer STV_SETUP_CNT  = ((STV_SETUP_US_X10 * CLK_FREQ_MHZ + 9) / 10 < 1) ? 1 : ((STV_SETUP_US_X10 * CLK_FREQ_MHZ + 9) / 10);
    localparam integer STV_PW_CNT     = ((STV_HOLD_US_X10 * CLK_FREQ_MHZ + 9) / 10 < 1) ? 1 : ((STV_HOLD_US_X10 * CLK_FREQ_MHZ + 9) / 10);
    localparam integer OE_PW_CNT      = ((OE_PW_US_X10 * CLK_FREQ_MHZ + 9) / 10 < 1) ? 1 : ((OE_PW_US_X10 * CLK_FREQ_MHZ + 9) / 10);
    localparam integer XAO_DELAY_CNT  = (XAO_DELAY_US * CLK_FREQ_MHZ < 1) ? 1 : (XAO_DELAY_US * CLK_FREQ_MHZ);
    localparam integer CPV_LOW_CNT    = (CPV_PERIOD_CNT > CPV_PW_CNT) ? (CPV_PERIOD_CNT - CPV_PW_CNT) : 1;

    localparam [3:0] IDLE            = 4'd0;
    localparam [3:0] STV_SETUP_S     = 4'd1;
    localparam [3:0] STV_IDENT_S     = 4'd2;
    localparam [3:0] STV1_ONLY_S     = 4'd3;
    localparam [3:0] STV12_GAP_S     = 4'd4;
    localparam [3:0] STV2_ONLY_S     = 4'd5;
    localparam [3:0] CPV_LOW_S       = 4'd6;
    localparam [3:0] CPV_HIGH_S      = 4'd7;
    localparam [3:0] FRAME_END_S     = 4'd8;
    localparam [3:0] XAO_SHUT_S      = 4'd9;

    reg [3:0]  state;
    reg [15:0] cnt;
    reg [15:0] shift_cnt;
    reg [15:0] xao_cnt;
    reg [1:0]  mode_latched;
    reg [1:0]  stv_delay_latched;
    reg        scan_dir_latched;
    reg        oe_mask_latched;
    reg [15:0] target_lines;

    reg        cfg_dual_stv;
    reg        cfg_long_stv;
    reg        cfg_stv2_delay_1cpv;
    reg        cfg_lr;
    reg        cfg_mode1;
    reg        cfg_mode2;
    reg        cfg_sel;
    reg        cfg_stv_mode;
    reg        cfg_chip_sel1;
    reg        cfg_chip_sel2;
    reg        cfg_oepsn;
    reg [15:0] cfg_max_lines;

    wire [1:0] active_mode       = (state == IDLE) ? mode_select : mode_latched;
    wire [1:0] active_stv_delay  = (state == IDLE) ? stv_delay_sel : stv_delay_latched;
    wire       active_scan_dir   = (state == IDLE) ? scan_direction : scan_dir_latched;
    wire       active_oe_mask    = (state == IDLE) ? oe_mask_en : oe_mask_latched;

    wire oe_active_level   = 1'b0;
    wire oe_inactive_level = 1'b1;

    wire [15:0] requested_lines = (line_count != 10'd0) ? {6'd0, line_count} : cfg_max_lines;

    always @(*) begin
        cfg_dual_stv         = USE_DUAL_STV || (active_mode == 2'b10);
        cfg_long_stv         = active_stv_delay[1];
        cfg_stv2_delay_1cpv  = cfg_dual_stv && active_stv_delay[0];
        cfg_lr               = 1'b1;
        cfg_mode1            = 1'b0;
        cfg_mode2            = 1'b0;
        cfg_sel              = 1'b0;
        cfg_stv_mode         = cfg_long_stv;
        cfg_chip_sel1        = 1'b1;
        cfg_chip_sel2        = 1'b0;
        cfg_oepsn            = active_oe_mask;
        cfg_max_lines        = OUT_CH_NORMAL[15:0];

        case (active_mode)
            2'b00: begin
                cfg_mode1     = cfg_long_stv;
                cfg_mode2     = 1'b0;
                cfg_sel       = 1'b0;
                cfg_stv_mode  = cfg_long_stv;
                cfg_chip_sel1 = 1'b1;
                cfg_chip_sel2 = 1'b0;
                cfg_max_lines = OUT_CH_NORMAL[15:0];
            end
            2'b01: begin
                cfg_mode1     = cfg_long_stv;
                cfg_mode2     = 1'b1;
                cfg_sel       = 1'b1;
                cfg_stv_mode  = cfg_long_stv;
                cfg_chip_sel1 = 1'b0;
                cfg_chip_sel2 = 1'b1;
                cfg_max_lines = OUT_CH_2G[15:0];
            end
            2'b10: begin
                cfg_mode1     = 1'b1;
                cfg_mode2     = 1'b0;
                cfg_sel       = 1'b1;
                cfg_stv_mode  = cfg_long_stv;
                cfg_chip_sel1 = 1'b0;
                cfg_chip_sel2 = 1'b0;
                cfg_max_lines = OUT_CH_2G[15:0];
            end
            2'b11: begin
                cfg_mode1     = active_scan_dir ? 1'b0 : 1'b1;
                cfg_mode2     = cfg_long_stv;
                cfg_sel       = 1'b1;
                cfg_stv_mode  = cfg_long_stv;
                cfg_chip_sel1 = 1'b1;
                cfg_chip_sel2 = 1'b1;
                cfg_max_lines = OUT_CH_2G[15:0];
                cfg_lr        = 1'b1;
            end
            default: begin
                cfg_mode1     = cfg_long_stv;
                cfg_mode2     = 1'b0;
                cfg_sel       = 1'b0;
                cfg_stv_mode  = cfg_long_stv;
                cfg_chip_sel1 = 1'b1;
                cfg_chip_sel2 = 1'b0;
                cfg_max_lines = OUT_CH_NORMAL[15:0];
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= IDLE;
            cnt               <= 16'd0;
            shift_cnt         <= 16'd0;
            xao_cnt           <= 16'd0;
            mode_latched      <= DEFAULT_MODE_SEL[1:0];
            stv_delay_latched <= 2'b00;
            scan_dir_latched  <= SCAN_DIRECTION;
            oe_mask_latched   <= 1'b0;
            target_lines      <= OUT_CH_NORMAL[15:0];

            cpv               <= 1'b0;
            stv1              <= 1'b0;
            stv2              <= 1'b0;
            oe1               <= oe_inactive_level;
            oe2               <= oe_inactive_level;
            ud                <= SCAN_DIRECTION;
            lr                <= 1'b1;
            mode1             <= 1'b0;
            mode2             <= 1'b0;
            sel               <= 1'b0;
            stv_mode          <= 1'b0;
            chip_sel1         <= 1'b1;
            chip_sel2         <= 1'b0;
            oepsn             <= 1'b0;
            busy              <= 1'b0;
            line_done         <= 1'b0;
            frame_done        <= 1'b0;
        end else begin
            line_done  <= 1'b0;
            frame_done <= 1'b0;

            if (xao_emergency) begin
                state <= XAO_SHUT_S;
            end

            case (state)
                IDLE: begin
                    cnt        <= 16'd0;
                    shift_cnt  <= 16'd0;
                    xao_cnt    <= 16'd0;
                    busy       <= 1'b0;
                    cpv        <= 1'b0;
                    stv1       <= 1'b0;
                    stv2       <= 1'b0;
                    oe1        <= oe_inactive_level;
                    oe2        <= oe_inactive_level;
                    ud         <= active_scan_dir;
                    lr         <= cfg_lr;
                    mode1      <= cfg_mode1;
                    mode2      <= cfg_mode2;
                    sel        <= cfg_sel;
                    stv_mode   <= cfg_stv_mode;
                    chip_sel1  <= cfg_chip_sel1;
                    chip_sel2  <= cfg_chip_sel2;
                    oepsn      <= cfg_oepsn;

                    if (frame_start || line_start) begin
                        busy              <= 1'b1;
                        mode_latched      <= mode_select;
                        stv_delay_latched <= stv_delay_sel;
                        scan_dir_latched  <= scan_direction;
                        oe_mask_latched   <= oe_mask_en;
                        target_lines      <= (requested_lines > cfg_max_lines) ? cfg_max_lines : requested_lines;
                        state             <= STV_SETUP_S;
                    end
                end

                STV_SETUP_S: begin
                    cpv  <= 1'b0;
                    stv1 <= 1'b0;
                    stv2 <= 1'b0;
                    oe1  <= oe_inactive_level;
                    oe2  <= oe_inactive_level;
                    ud   <= active_scan_dir;
                    lr   <= cfg_lr;

                    if (cnt >= STV_SETUP_CNT - 1) begin
                        cnt <= 16'd0;
                        state <= cfg_stv2_delay_1cpv ? STV1_ONLY_S : STV_IDENT_S;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                STV_IDENT_S: begin
                    cpv  <= 1'b0;
                    stv1 <= 1'b1;
                    stv2 <= cfg_dual_stv ? 1'b1 : 1'b0;
                    oe1  <= oe_inactive_level;
                    oe2  <= oe_inactive_level;

                    if (cnt >= STV_PW_CNT - 1) begin
                        cnt <= 16'd0;
                        stv1 <= 1'b0;
                        stv2 <= 1'b0;
                        state <= CPV_LOW_S;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                STV1_ONLY_S: begin
                    cpv  <= 1'b0;
                    stv1 <= 1'b1;
                    stv2 <= 1'b0;
                    oe1  <= oe_inactive_level;
                    oe2  <= oe_inactive_level;

                    if (cnt >= STV_PW_CNT - 1) begin
                        cnt <= 16'd0;
                        stv1 <= 1'b0;
                        state <= STV12_GAP_S;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                STV12_GAP_S: begin
                    cpv  <= 1'b0;
                    stv1 <= 1'b0;
                    stv2 <= 1'b0;
                    oe1  <= oe_inactive_level;
                    oe2  <= oe_inactive_level;

                    if (cnt >= (CPV_PERIOD_CNT - STV_PW_CNT) - 1) begin
                        cnt <= 16'd0;
                        state <= STV2_ONLY_S;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                STV2_ONLY_S: begin
                    cpv  <= 1'b0;
                    stv1 <= 1'b0;
                    stv2 <= 1'b1;
                    oe1  <= oe_inactive_level;
                    oe2  <= oe_inactive_level;

                    if (cnt >= STV_PW_CNT - 1) begin
                        cnt <= 16'd0;
                        stv2 <= 1'b0;
                        state <= CPV_LOW_S;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                CPV_LOW_S: begin
                    cpv  <= 1'b0;
                    stv1 <= 1'b0;
                    stv2 <= 1'b0;
                    oe1  <= oe_inactive_level;
                    oe2  <= oe_inactive_level;

                    if (cnt >= CPV_LOW_CNT - 1) begin
                        cnt   <= 16'd0;
                        state <= CPV_HIGH_S;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                CPV_HIGH_S: begin
                    cpv  <= 1'b1;
                    stv1 <= 1'b0;
                    stv2 <= 1'b0;
                    oe1  <= (active_oe_mask || (cnt >= OE_PW_CNT)) ? oe_inactive_level : oe_active_level;
                    oe2  <= (active_oe_mask || (cnt >= OE_PW_CNT)) ? oe_inactive_level : oe_active_level;

                    if (cnt >= CPV_PW_CNT - 1) begin
                        cnt <= 16'd0;
                        cpv <= 1'b0;
                        line_done <= 1'b1;

                        if (shift_cnt + 16'd1 >= target_lines) begin
                            shift_cnt <= 16'd0;
                            state <= FRAME_END_S;
                        end else begin
                            shift_cnt <= shift_cnt + 16'd1;
                            state <= CPV_LOW_S;
                        end
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                FRAME_END_S: begin
                    cpv  <= 1'b0;
                    stv1 <= 1'b0;
                    stv2 <= 1'b0;
                    oe1  <= oe_inactive_level;
                    oe2  <= oe_inactive_level;

                    if (cnt >= STV_PW_CNT - 1) begin
                        cnt <= 16'd0;
                        frame_done <= 1'b1;
                        busy <= 1'b0;
                        state <= IDLE;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                XAO_SHUT_S: begin
                    cpv  <= 1'b0;
                    stv1 <= 1'b0;
                    stv2 <= 1'b0;
                    oe1  <= oe_inactive_level;
                    oe2  <= oe_inactive_level;
                    busy <= 1'b0;

                    if (xao_cnt < XAO_DELAY_CNT - 1) begin
                        xao_cnt <= xao_cnt + 1'b1;
                    end

                    if (!xao_emergency) begin
                        xao_cnt <= 16'd0;
                        cnt <= 16'd0;
                        shift_cnt <= 16'd0;
                        state <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule

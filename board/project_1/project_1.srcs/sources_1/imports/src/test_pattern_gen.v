// =============================================================================
// 测试图像生成器
// =============================================================================
// 生成规则的测试图像，用于验证数据传输链路和上位机解析
//
// 测试模式:
//   MODE 0: 水平渐变 - 每行像素值 = 行号
//   MODE 1: 垂直渐变 - 每列像素值 = 列号
//   MODE 2: 递增序列 - 像素值 = (行号 * 512 + 列号) & 0xFFFF
//   MODE 3: 棋盘格   - 交替的 0x0000 和 0xFFFF
//
module test_pattern_gen #(
    parameter FRAME_LINES = 541,
    parameter PIXELS_PER_LINE = 512,
    parameter SAMPLES_PER_BURST = 8,
    parameter BURSTS_PER_LINE = 64,
    parameter TEST_MODE = 0  // 测试模式选择
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         enable,          // 启用测试模式

    // 触发信号（来自外部，例如定时器）
    input  wire         frame_start,     // 帧开始信号

    // 输出接口（模拟 merged_burst 和 merged_valid）
    output reg          test_valid,      // 数据有效信号（单周期脉冲）
    output reg  [255:0] test_burst       // 256-bit burst 数据
);

    // 状态机
    localparam S_IDLE = 2'd0;
    localparam S_LINE = 2'd1;
    localparam S_GAP  = 2'd2;

    reg [1:0]  state;
    reg [9:0]  line_cnt;      // 行计数器 (0-540)
    reg [6:0]  burst_cnt;     // burst 计数器 (0-63)
    reg [15:0] gap_cnt;       // 行间隔计数器

    // 每个 burst 包含 8 个 16-bit 样本
    // burst[255:0] = {Panel1[127:0], Panel0[127:0]}
    // 每个 Panel: 4 个样本 × 16 bits

    wire [15:0] sample_value;

    // 根据测试模式生成样本值
    generate
        if (TEST_MODE == 0) begin : gen_horizontal_gradient
            // 水平渐变：每行像素值 = 行号
            assign sample_value = {6'd0, line_cnt};  // 扩展到 16 bits
        end else if (TEST_MODE == 1) begin : gen_vertical_gradient
            // 垂直渐变：每列像素值 = 列号
            wire [8:0] col_idx = burst_cnt * SAMPLES_PER_BURST;
            assign sample_value = {7'd0, col_idx};
        end else if (TEST_MODE == 2) begin : gen_incremental
            // 递增序列：像素值 = 行号 * 512 + 列号
            wire [18:0] pixel_idx = line_cnt * PIXELS_PER_LINE + burst_cnt * SAMPLES_PER_BURST;
            assign sample_value = pixel_idx[15:0];
        end else begin : gen_checkerboard
            // 棋盘格：交替 0x0000 和 0xFFFF
            wire checker = (line_cnt[0] ^ burst_cnt[0]);
            assign sample_value = checker ? 16'hFFFF : 16'h0000;
        end
    endgenerate

    // 状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            line_cnt   <= 10'd0;
            burst_cnt  <= 7'd0;
            gap_cnt    <= 16'd0;
            test_valid <= 1'b0;
            test_burst <= 256'd0;
        end else begin
            test_valid <= 1'b0;  // 默认为 0，仅在需要时产生单周期脉冲

            if (!enable) begin
                // 测试模式禁用
                state      <= S_IDLE;
                line_cnt   <= 10'd0;
                burst_cnt  <= 7'd0;
                gap_cnt    <= 16'd0;
            end else begin
                case (state)
                    S_IDLE: begin
                        if (frame_start) begin
                            state     <= S_LINE;
                            line_cnt  <= 10'd0;
                            burst_cnt <= 7'd0;
                        end
                    end

                    S_LINE: begin
                        // 生成一个 burst 的数据
                        // 每个 burst 包含 8 个样本（Panel0: 4个，Panel1: 4个）
                        // 为了简化，所有样本使用相同的值（基于行号和 burst 索引）

                        // 计算当前 burst 的起始列号
                        wire [8:0] col_start = burst_cnt * SAMPLES_PER_BURST;

                        // 生成 8 个样本（每个 16-bit）
                        // Panel 0: 样本 0-3
                        // Panel 1: 样本 4-7

                        integer j;
                        reg [15:0] samples [0:7];

                        // 根据模式生成样本值
                        if (TEST_MODE == 0) begin
                            // 水平渐变：所有样本值相同 = 行号
                            for (j = 0; j < 8; j = j + 1)
                                samples[j] = {6'd0, line_cnt};
                        end else if (TEST_MODE == 1) begin
                            // 垂直渐变：样本值 = 列号
                            for (j = 0; j < 8; j = j + 1)
                                samples[j] = {7'd0, col_start + j[8:0]};
                        end else if (TEST_MODE == 2) begin
                            // 递增序列：样本值 = 行号 * 512 + 列号
                            for (j = 0; j < 8; j = j + 1) begin
                                wire [18:0] pix_idx = line_cnt * PIXELS_PER_LINE + col_start + j[8:0];
                                samples[j] = pix_idx[15:0];
                            end
                        end else begin
                            // 棋盘格：交替 0x0000 和 0xFFFF
                            for (j = 0; j < 8; j = j + 1) begin
                                wire checker_bit = (line_cnt[0] ^ ((col_start + j[8:0]) >> 3));
                                samples[j] = checker_bit ? 16'hFFFF : 16'h0000;
                            end
                        end

                        // 组装 burst (大端序，MSB first)
                        // Panel 0: samples[0-3] → burst[127:0]
                        // Panel 1: samples[4-7] → burst[255:128]
                        test_burst <= {
                            samples[7], samples[6], samples[5], samples[4],  // Panel 1
                            samples[3], samples[2], samples[1], samples[0]   // Panel 0
                        };

                        test_valid <= 1'b1;  // 产生 valid 脉冲

                        // 更新 burst 计数器
                        if (burst_cnt < BURSTS_PER_LINE - 1) begin
                            burst_cnt <= burst_cnt + 7'd1;
                        end else begin
                            // 一行完成
                            burst_cnt <= 7'd0;
                            gap_cnt   <= 16'd0;
                            state     <= S_GAP;
                        end
                    end

                    S_GAP: begin
                        // 行间隔（模拟实际的行间隔时间）
                        if (gap_cnt < 16'd100) begin  // 1μs @ 100MHz
                            gap_cnt <= gap_cnt + 16'd1;
                        end else begin
                            gap_cnt <= 16'd0;

                            // 检查是否完成一帧
                            if (line_cnt < FRAME_LINES - 1) begin
                                line_cnt <= line_cnt + 10'd1;
                                state    <= S_LINE;
                            end else begin
                                // 一帧完成，回到 IDLE
                                line_cnt <= 10'd0;
                                state    <= S_IDLE;
                            end
                        end
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule

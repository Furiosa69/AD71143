// 按文�?? Figure 37 / Figure 38 实现:
//   - DOUTMODE = 1, �?? LVDS 输出 (DM=1, 仅使用DOUTA)
//   - �?? DCLKO 上升沿采�?? DOUTA
//   - 每个 burst �?? 64bit/lane, 单�?�道模式下每burst包含4�??16-bit样本
//   - READDOWN = 0 : 升序输出  ch_even, ch_odd, ch_even+2, ch_odd+2 ...
//   - READDOWN = 1 : 降序输出  ch_odd,  ch_even, ch_odd-2,  ch_even-2 ...
//
// 单LVDS模式下，每个burst只有64bit (4个样�??):
// lane_a_shift[63:48] -> �?? 1 个�?�道样本
// lane_a_shift[47:32] -> �?? 2 个�?�道样本
// lane_a_shift[31:16] -> �?? 3 个�?�道样本
// lane_a_shift[15:0]  -> �?? 4 个�?�道样本
// =============================================================================

module ad71143_data_rx (
    input  wire         clk_sys,
    input  wire         rst_n,

    input  wire         sync_in,
    input  wire         aclk_done,

    output wire         dclk_p_A,
    output wire         dclk_n_A,

    input  wire         dout_p_A,
    input  wire         dout_n_A,
    // Lane B未使用（单LVDS模式�??
    // input  wire         dout_p_B,
    // input  wire         dout_n_B,

    output reg          line_done,
    output wire         header_ok,
    output reg  [7:0]   header_byte,
    output reg          header_readdown,
    output reg          header_cds_id,
    output reg  [15:0]  header_temp,
    output reg  [15:0]  header_vt,
    output reg          merged_valid = 1'b0,
    output reg  [127:0] merged_burst,
    output reg  [7:0]   merged_first_channel,
    output reg  [7:0]   merged_last_channel,
    output reg  [6:0]   merged_burst_index,

    output reg  [2:0]   state_debug,
    output wire [7:0]   shift_hi,
    output wire [7:0]   shift_lo,
    output wire         burst_en_out,
    output wire         burst_en_comb,
    output wire         roic_trigger,
    output wire         dbg_header_valid,   // 组合: lane_a_shift[63:56]==0x0A
    output reg          dbg_header_latched, // 寄存: 首次捕获�?? header 后锁�??
    output wire         dbg_dout_a_raw,     // 调试: LVDS A原始输入
    output wire         dbg_dout_b_raw,      // 调试: LVDS B原始输入（单LVDS模式未使用，保留端口兼容性）,
    output wire         dbg_capture_active,
    output wire [63:0]  dbg_lane_a_shift    // 调试: Lane A移位寄存器完整数�?
);

    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_WAIT = 3'd1;
    localparam [2:0] S_ACT  = 3'd2;
    localparam [2:0] S_MUTE = 3'd3;
    localparam [2:0] S_DONE = 3'd4;

    localparam integer ACTIVE_DCLK = 64;    // �?? lane �?? 64bit (AD71143 规范: �?? burst 64 DCLK)
    localparam integer PRE_DELAY   = 1;     // DCLK 预延迟周�?? (1=跳过�??1个无效采�??)
    localparam integer TOTAL_CYCLES = ACTIVE_DCLK + PRE_DELAY; // 总采样周�??=65
    localparam integer DATA_BURSTS = 64;    // 单LVDS: 256ch * 16bit / 64bit-per-burst (双LVDS时为32)
    localparam integer TOTAL_BURSTS = 66;   // header + 64 data + config bursts (双LVDS时为34)
    parameter  integer MUTE_MIN    = 112;   // tBURST=1765ns: 177cyc-65=112 @ 100MHz (PRE_DELAY=1)

   (* MAX_FANOUT = "300" *) reg  [2:0] state;
    reg  [2:0] state_next;
    reg        sync_d1;
    reg  [9:0] mute_cnt;
    reg  [6:0] burst_cnt;
    reg        cap_start_tgl_sys;
    reg        cap_done_tgl_sys_d1;
    reg        cap_done_tgl_sys_d2;

    wire sync_fall;
    wire capture_done_pulse_sys;
    wire burst_en;

    reg  [63:0] lane_a_shift;
    // reg  [63:0] lane_b_shift;  // 单LVDS模式未使�??
    reg  [6:0]  cap_bit_cnt_dclko;
    reg         cap_active_dclko;
    reg         cap_start_tgl_d1;
    reg         cap_start_tgl_d2;
    reg         cap_done_tgl_dclko;
    reg  [6:0]  pre_delay_cnt;

    wire dclko_i;
    wire dout_a_i;
    // wire dout_b_i;  // 单LVDS模式未使�??
    // reg  dout_b_mid;   // 单LVDS模式未使�?
    // DOUT 直接在实际生成的 DCLK 上升沿采样，避免与系统时钟边沿错位。
    wire dclk_pre;

    wire [15:0] a_word0 = lane_a_shift[63:48];
    wire [15:0] a_word1 = lane_a_shift[47:32];
    wire [15:0] a_word2 = lane_a_shift[31:16];
    wire [15:0] a_word3 = lane_a_shift[15:0];
    // 单LVDS模式: Lane B未使�??
    // wire [15:0] b_word0 = lane_b_shift[63:48];
    // wire [15:0] b_word1 = lane_b_shift[47:32];
    // wire [15:0] b_word2 = lane_b_shift[31:16];
    // wire [15:0] b_word3 = lane_b_shift[15:0];

    reg  [127:0] merged_burst_next;
    reg  [7:0]   merged_first_channel_next;
    reg  [7:0]   merged_last_channel_next;

    // =========================================================================
    // 同步与状态机
    // =========================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            sync_d1 <= 1'b0;
        end else begin
            sync_d1 <= sync_in;
        end
    end

    assign sync_fall = sync_d1 && !sync_in;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
        end else begin
            state <= state_next;
        end
    end

    always @(*) begin
        state_next = state;
        case (state)
            S_IDLE: if (sync_fall)            state_next = S_WAIT;
            S_WAIT: if (aclk_done)            state_next = S_ACT;
            S_ACT : if (capture_done_pulse_sys) begin
                        if (burst_cnt == TOTAL_BURSTS - 1)
                            state_next = S_DONE;
                        else
                            state_next = S_MUTE;
                    end
            S_MUTE: if (mute_cnt >= MUTE_MIN - 1) state_next = S_ACT;
            S_DONE:                               state_next = S_IDLE;
            default:                              state_next = S_IDLE;
        endcase
    end

    // =========================================================================
    // DCLKO �?? -> clk_sys 域完成握�??
    // =========================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            cap_done_tgl_sys_d1 <= 1'b0;
            cap_done_tgl_sys_d2 <= 1'b0;
        end else begin
            cap_done_tgl_sys_d1 <= cap_done_tgl_dclko;
            cap_done_tgl_sys_d2 <= cap_done_tgl_sys_d1;
        end
    end

    assign capture_done_pulse_sys = cap_done_tgl_sys_d1 ^ cap_done_tgl_sys_d2;

    // =========================================================================
    // clk_sys 域计数与输出寄存
    // =========================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            mute_cnt              <= 10'd0;
            burst_cnt             <= 7'd0;
            cap_start_tgl_sys     <= 1'b0;
            dbg_header_latched    <= 1'b0;
            header_byte           <= 8'd0;
            header_readdown       <= 1'b0;
            header_cds_id         <= 1'b0;
            header_temp           <= 16'd0;
            header_vt             <= 16'd0;
            merged_burst          <= 128'd0;
            merged_first_channel  <= 8'd0;
            merged_last_channel   <= 8'd0;
            merged_burst_index    <= 7'd0;
            line_done             <= 1'b0;
            state_debug           <= S_IDLE;
        end else begin
            merged_valid <= 1'b0;
            line_done    <= 1'b0;
            state_debug  <= state;

            case (state)
                S_IDLE: begin
                    mute_cnt          <= 10'd0;
                    burst_cnt         <= 7'd0;
                    dbg_header_latched<= 1'b0;
                    merged_burst_index<= 7'd0;
                end

                S_WAIT: begin
                    mute_cnt <= 10'd0;
                    if (aclk_done)
                        cap_start_tgl_sys <= ~cap_start_tgl_sys;
                end

                S_ACT: begin
                    mute_cnt <= 10'd0;
                    if (capture_done_pulse_sys) begin
                        if (burst_cnt == 0) begin
                            header_byte     <= lane_a_shift[63:56];
                            dbg_header_latched <= (lane_a_shift[63:56] == 8'h0A);
                            header_readdown <= lane_a_shift[49];
                            header_cds_id   <= lane_a_shift[48];
                            header_temp     <= lane_a_shift[31:16];
                            header_vt       <= lane_a_shift[15:0];
                        end else if (burst_cnt <= DATA_BURSTS) begin
                            merged_burst         <= merged_burst_next;
                            merged_first_channel <= merged_first_channel_next;
                            merged_last_channel  <= merged_last_channel_next;
                            merged_burst_index   <= burst_cnt - 1'b1;
                            merged_valid         <= 1'b1;
                        end

                        if (burst_cnt < TOTAL_BURSTS - 1)
                            burst_cnt <= burst_cnt + 1'b1;
                    end
                end

                S_MUTE: begin
                    if (mute_cnt >= MUTE_MIN - 1) begin
                        mute_cnt          <= 10'd0;
                        cap_start_tgl_sys <= ~cap_start_tgl_sys;
                    end else begin
                        mute_cnt <= mute_cnt + 10'd1;
                    end
                end

                S_DONE: begin
                    line_done <= 1'b1;
                end

                default: begin
                    mute_cnt <= 10'd0;
                end
            endcase
        end
    end

    // =========================================================================
    // 单LVDS合并（只使用Lane A�??
    // =========================================================================
    always @(*) begin
        if (!header_readdown) begin
            // 单LVDS模式: 只使用Lane A，每个burst包含4个样本（64bit�??
            // READDOWN=0: 升序 CH0,1,2,3...
            merged_burst_next = {
                a_word0,         // [127:112] 通道0 = 实际CH0
                a_word1,         // [111:96]  通道1 = 实际CH1
                a_word2,         // [95:80]   通道2 = 实际CH2
                a_word3,         // [79:64]   通道3 = 实际CH3
                64'd0            // [63:0]    填充0（单LVDS只有4通道/burst）
            };
            merged_first_channel_next = ((burst_cnt - 1'b1) << 2);      // 每burst=4通道
            merged_last_channel_next  = ((burst_cnt - 1'b1) << 2) + 8'd3;
        end else begin
            // READDOWN=1: 降序
            merged_burst_next = {
                a_word3,         // [127:112] 通道0 = 实际CH3
                a_word2,         // [111:96]  通道1 = 实际CH2
                a_word1,         // [95:80]   通道2 = 实际CH1
                a_word0,         // [79:64]   通道3 = 实际CH0
                64'd0            // [63:0]    填充0（单LVDS只有4通道/burst）
            };
            merged_first_channel_next = 8'd255 - ((burst_cnt - 1'b1) << 2);
            merged_last_channel_next  = 8'd255 - ((burst_cnt - 1'b1) << 2) - 8'd3;
        end
    end

    // =========================================================================
    // DCLKO 域采�??
    // =========================================================================
    // DCLK 由 clk_sys 上升沿产生，DOUT 在传播延迟后稳定；在下降沿采样。
    always @(negedge dclko_i or negedge rst_n) begin
        if (!rst_n) begin
            cap_start_tgl_d1  <= 1'b0;
            cap_start_tgl_d2  <= 1'b0;
            cap_active_dclko  <= 1'b0;
            cap_bit_cnt_dclko <= 7'd0;
            lane_a_shift      <= 64'd0;
            // lane_b_shift      <= 64'd0;  // 单LVDS模式未使�??
            cap_done_tgl_dclko<= 1'b0;
            pre_delay_cnt     <= 7'd0;
        end else begin
            cap_start_tgl_d1 <= cap_start_tgl_sys;
            cap_start_tgl_d2 <= cap_start_tgl_d1;

            if ((cap_start_tgl_d1 ^ cap_start_tgl_d2) && !cap_active_dclko) begin
                cap_active_dclko  <= 1'b1;
                cap_bit_cnt_dclko <= 7'd0;
                pre_delay_cnt     <= PRE_DELAY;
                lane_a_shift      <= 64'd0;
                // lane_b_shift      <= 64'd0;  // 单LVDS模式未使�??
            end else if (cap_active_dclko) begin
                // 预延�??: 跳过 AD71143 初始输出延迟, 不采数据
                if (pre_delay_cnt > 0) begin
                    pre_delay_cnt <= pre_delay_cnt - 1'b1;
                end else begin
                    // 实际 64-bit 移位 (单LVDS模式只采样Lane A)
                    lane_a_shift <= {lane_a_shift[62:0], dout_a_i};
                    // lane_b_shift <= {lane_b_shift[62:0], dout_b_i};  // 单LVDS模式未使�??
                end

                // 总计�?? = PRE_DELAY + ACTIVE_DCLK
                if (cap_bit_cnt_dclko == TOTAL_CYCLES - 1) begin
                    cap_active_dclko   <= 1'b0;
                    cap_bit_cnt_dclko  <= 7'd0;
                    pre_delay_cnt      <= 7'd0;
                    cap_done_tgl_dclko <= ~cap_done_tgl_dclko;
                end else begin
                    cap_bit_cnt_dclko <= cap_bit_cnt_dclko + 1'b1;
                end
            end
        end
    end

    assign burst_en_comb = (state == S_ACT);       // 组合逻辑, 仅用于观�??
    reg  burst_en_reg;                              // 寄存器打�?? DCLK 反馈环路

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            burst_en_reg <= 1'b0;
        else
            burst_en_reg <= (state_next == S_ACT);  // 提前�??�??, �?? state 跳变同步
    end

    assign burst_en     = burst_en_reg;
    assign burst_en_out  = burst_en;
    assign roic_trigger  = (state_next == S_ACT) || (state == S_ACT);
    assign shift_hi        = lane_a_shift[63:56];
    assign shift_lo        = lane_a_shift[7:0];
    assign header_ok       = (lane_a_shift[63:56] == 8'h0A);
    assign dbg_header_valid = (lane_a_shift[63:56] == 8'h0A);
    assign dbg_dout_a_raw  = dout_a_i;  // 直接输出LVDS A输入
    assign dbg_dout_b_raw  = 1'b0;      // 单LVDS模式: Lane B未使用，输出固定0
    assign dbg_capture_active = cap_active_dclko;
    assign dbg_lane_a_shift = lane_a_shift;  // 输出完整�?64位移位寄存器

    // =========================================================================
    // LVDS I/O
    // =========================================================================
    ODDR #(
        .DDR_CLK_EDGE("OPPOSITE_EDGE"),  // 恢复原始配置
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) oddr_dclk (
        .Q  (dclk_pre),
        .C  (clk_sys),
        .CE (burst_en),
        .D1 (1'b1),
        .D2 (1'b0),
        .R  (1'b0),
        .S  (1'b0)
    );

    OBUFDS #(
        .IOSTANDARD("LVDS_25")
    ) obufds_dclk (
        .O  (dclk_p_A),
        .OB (dclk_n_A),
        .I  (dclk_pre)
    );

    // DCLKO 引脚不存在，�?? clk_sys 直接作内部采样时�??
    // clk_sys �?? dclk_pre (ODDR 输出) 同频同相, cap_active_dclko 门控实际采样
    // ODDR 输出只能连接输出缓冲器，不能作为内部时钟负载。
    // ODDR 在 clk_sys 上升沿产生 DCLK 上升沿，内部采样保持使用 clk_sys。
    assign dclko_i = clk_sys;

    IBUFDS #(
        .DIFF_TERM("TRUE"),
        .IOSTANDARD("LVDS_25")
    ) ibufds_dout_a (
        .O  (dout_a_i),
        .I  (dout_p_A),
        .IB (dout_n_A)
    );

    // 单LVDS模式: Lane B未使�??
    // IBUFDS #(
    //     .DIFF_TERM("TRUE"),
    //     .IOSTANDARD("LVDS_25")
    // ) ibufds_dout_b (
    //     .O  (dout_b_i),
    //     .I  (dout_p_B),
    //     .IB (dout_n_B)
    // );


endmodule

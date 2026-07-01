// 按文档 Figure 37 / Figure 38 实现:
//   - DOUTMODE = 1, 双 LVDS 输出
//   - 用 DCLKO 上升沿采样 DOUTA / DOUTB
//   - 每个 burst 采 64bit/lane, 共 128bit
//   - 数据 burst 内合并为 8 个 16-bit 样本
//   - READDOWN = 0 : 升序输出  ch_even, ch_odd, ch_even+2, ch_odd+2 ...
//   - READDOWN = 1 : 降序输出  ch_odd,  ch_even, ch_odd-2,  ch_even-2 ...
//
// merged_burst[127:112] -> 第 1 个通道样本
// merged_burst[111:96]  -> 第 2 个通道样本
// ...
// merged_burst[15:0]    -> 第 8 个通道样本
// =============================================================================

module ad71143_data_rx (
    input  wire         clk_sys,
    input  wire         rst_n,

    input  wire         sync_in,
    input  wire         aclk_done,

    output wire         dclk_p_A,
    output wire         dclk_n_A,

    input  wire         dclko_p_A,
    input  wire         dclko_n_A,

    input  wire         dout_p_A,
    input  wire         dout_n_A,
    input  wire         dout_p_B,
    input  wire         dout_n_B,

    output reg          line_done,
    output reg          header_ok,
    output reg  [7:0]   header_byte,
    output reg          header_readdown,
    output reg          header_cds_id,
    output reg  [15:0]  header_temp,
    output reg  [15:0]  header_vt,
    output reg          merged_valid,
    output reg  [127:0] merged_burst,
    output reg  [7:0]   merged_first_channel,
    output reg  [7:0]   merged_last_channel,
    output reg  [6:0]   merged_burst_index,

    output reg  [2:0]   state_debug,
    output wire [7:0]   shift_hi,
    output wire [7:0]   shift_lo,
    output wire         burst_en_out,
    output wire         burst_en_comb,
    output wire         roic_trigger
);

    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_WAIT = 3'd1;
    localparam [2:0] S_ACT  = 3'd2;
    localparam [2:0] S_MUTE = 3'd3;
    localparam [2:0] S_DONE = 3'd4;

    localparam integer ACTIVE_DCLK = 64;
    localparam integer DATA_BURSTS = 32;   // dual LVDS: 256ch * 16bit / 128bit-per-burst
    localparam integer TOTAL_BURSTS = 34;  // header + 32 data + config bursts
    parameter  integer MUTE_MIN    = 113;  // tBURST=1765ns: 177cyc-64=113 @ 100MHz

    reg  [2:0] state;
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
    reg  [63:0] lane_b_shift;
    reg  [6:0]  cap_bit_cnt_dclko;
    reg         cap_active_dclko;
    reg         cap_start_tgl_d1;
    reg         cap_start_tgl_d2;
    reg         cap_done_tgl_dclko;

    wire dclko_i;
    wire dout_a_i;
    wire dout_b_i;
    wire dclk_pre;

    wire [15:0] a_word0 = lane_a_shift[63:48];
    wire [15:0] a_word1 = lane_a_shift[47:32];
    wire [15:0] a_word2 = lane_a_shift[31:16];
    wire [15:0] a_word3 = lane_a_shift[15:0];
    wire [15:0] b_word0 = lane_b_shift[63:48];
    wire [15:0] b_word1 = lane_b_shift[47:32];
    wire [15:0] b_word2 = lane_b_shift[31:16];
    wire [15:0] b_word3 = lane_b_shift[15:0];

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
    // DCLKO 域 -> clk_sys 域完成握手
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
            header_ok             <= 1'b0;
            header_byte           <= 8'd0;
            header_readdown       <= 1'b0;
            header_cds_id         <= 1'b0;
            header_temp           <= 16'd0;
            header_vt             <= 16'd0;
            merged_valid          <= 1'b0;
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
                    header_ok         <= 1'b0;
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
                            header_ok       <= (lane_a_shift[63:56] == 8'h0A) &&
                                               (lane_a_shift[55:51] == 5'b0) &&
                                               (lane_a_shift[47:32] == 16'h0000);
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
    // 双路合并
    // =========================================================================
    always @(*) begin
        if (!header_readdown) begin
            merged_burst_next = {
                a_word0, b_word0,
                a_word1, b_word1,
                a_word2, b_word2,
                a_word3, b_word3
            };
            merged_first_channel_next = ((burst_cnt - 1'b1) << 3);
            merged_last_channel_next  = ((burst_cnt - 1'b1) << 3) + 8'd7;
        end else begin
            // READDOWN=1: Lane A=odd desc (CH7,5,3,1), Lane B=even desc (CH6,4,2,0)
            // Interleaving A,B gives CH7,6,5,4,3,2,1,0 within each burst
            // Same merge pattern as READDOWN=0 — lanes already carry correct channels
            merged_burst_next = {
                a_word0, b_word0,
                a_word1, b_word1,
                a_word2, b_word2,
                a_word3, b_word3
            };
            merged_first_channel_next = ((burst_cnt - 1'b1) << 3) + 8'd7;
            merged_last_channel_next  = ((burst_cnt - 1'b1) << 3);
        end
    end

    // =========================================================================
    // DCLKO 域采样
    // =========================================================================
    always @(posedge dclko_i or negedge rst_n) begin
        if (!rst_n) begin
            cap_start_tgl_d1  <= 1'b0;
            cap_start_tgl_d2  <= 1'b0;
            cap_active_dclko  <= 1'b0;
            cap_bit_cnt_dclko <= 7'd0;
            lane_a_shift      <= 64'd0;
            lane_b_shift      <= 64'd0;
            cap_done_tgl_dclko<= 1'b0;
        end else begin
            cap_start_tgl_d1 <= cap_start_tgl_sys;
            cap_start_tgl_d2 <= cap_start_tgl_d1;

            if ((cap_start_tgl_d1 ^ cap_start_tgl_d2) && !cap_active_dclko) begin
                cap_active_dclko  <= 1'b1;
                cap_bit_cnt_dclko <= 7'd0;
                lane_a_shift      <= 64'd0;
                lane_b_shift      <= 64'd0;
            end else if (cap_active_dclko) begin
                lane_a_shift <= {lane_a_shift[62:0], dout_a_i};
                lane_b_shift <= {lane_b_shift[62:0], dout_b_i};

                if (cap_bit_cnt_dclko == ACTIVE_DCLK - 1) begin
                    cap_active_dclko   <= 1'b0;
                    cap_bit_cnt_dclko  <= 7'd0;
                    cap_done_tgl_dclko <= ~cap_done_tgl_dclko;
                end else begin
                    cap_bit_cnt_dclko <= cap_bit_cnt_dclko + 1'b1;
                end
            end
        end
    end

    assign burst_en_comb = (state == S_ACT);       // 组合逻辑, 仅用于观察
    reg  burst_en_reg;                              // 寄存器打断 DCLK 反馈环路

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            burst_en_reg <= 1'b0;
        else
            burst_en_reg <= (state_next == S_ACT);  // 提前一拍, 与 state 跳变同步
    end

    assign burst_en     = burst_en_reg;
    assign burst_en_out  = burst_en;
    assign roic_trigger  = (state_next == S_ACT) || (state == S_ACT);
    assign shift_hi      = lane_a_shift[63:56];
    assign shift_lo      = lane_a_shift[7:0];

    // =========================================================================
    // LVDS I/O
    // =========================================================================
    ODDR #(
        .DDR_CLK_EDGE("OPPOSITE_EDGE"),
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
        .IOSTANDARD("LVDS_33")
    ) obufds_dclk (
        .O  (dclk_p_A),
        .OB (dclk_n_A),
        .I  (dclk_pre)
    );

    IBUFDS #(
        .DIFF_TERM("TRUE"),
        .IOSTANDARD("LVDS_33")
    ) ibufds_dclko (
        .O  (dclko_i),
        .I  (dclko_p_A),
        .IB (dclko_n_A)
    );

    IBUFDS #(
        .DIFF_TERM("TRUE"),
        .IOSTANDARD("LVDS_33")
    ) ibufds_dout_a (
        .O  (dout_a_i),
        .I  (dout_p_A),
        .IB (dout_n_A)
    );

    IBUFDS #(
        .DIFF_TERM("TRUE"),
        .IOSTANDARD("LVDS_33")
    ) ibufds_dout_b (
        .O  (dout_b_i),
        .I  (dout_p_B),
        .IB (dout_n_B)
    );


endmodule

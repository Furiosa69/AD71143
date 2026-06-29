// =============================================================================
// AD71143 控制信号发生器 — RESET + SYNC + ACLK
// =============================================================================
// 系统时钟: 100MHz (10ns)
// 时序 (参照 AD71143 SPEC Table 2 + Figure 22):
//   RESET: 高有效, 脉宽 10μs
//   初始化等待: RESET 释放后等 100μs → init_done=1
//   SYNC:  低有效, 每行开始前拉低
//   ACLK:  50MHz (20ns周期, 50%占空), 每行 9 个脉冲
//
// 每行时序 (Pipeline Mode, Figure 22):
//   line_start → SYNC↓ → (20ns) → ACLK0↑ → ACLK1~8 → SYNC↑ → 行间隔 → 下一行
// =============================================================================

`timescale 1ns / 1ps

module ad71143_ctrl #(
    parameter integer ACLK_PULSES      = 9,
    parameter integer LINE_CYCLES      = 6000,     // 60μs @ 100MHz
    parameter integer RESET_CYCLES     = 1000,     // 10μs
    parameter integer INIT_WAIT_CYCLES = 10000,    // 100μs
    parameter integer FRAME_LINES      = 541
) (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         frame_start,

    output wire         roic_reset,
    output wire         sync,
    output wire         aclk,

    output reg          init_done,
    output reg          line_start,
    output reg          line_done,
    output wire [3:0]   aclk_idx,
    output reg  [9:0]   line_cnt,

    output reg          frame_done,
    output reg          aclk_done
);

    // =========================================================================
    // 主状态机 (Mealy 型: 用时序状态 + 组合输出避免竞争)
    // =========================================================================
    localparam S_INIT_RESET  = 4'd0;
    localparam S_INIT_WAIT   = 4'd1;
    localparam S_IDLE        = 4'd2;    // wait for frame_start
    localparam S_SYNC_SETUP  = 4'd3;    // SYNC=0, 等 tSYNCACLK
    localparam S_ACLK_ACT    = 4'd4;    // ACLK 脉冲序列
    localparam S_SYNC_HOLD   = 4'd5;    // ACLK 完成后保持 SYNC=0
    localparam S_LINE_GAP    = 4'd6;    // 行间隔

    reg [3:0]  state, state_next;
    reg [15:0] timer, timer_next;
    reg        init_done_next;
    reg        line_start_next;
    reg        line_done_next;
    reg [9:0]  line_cnt_next;
    reg        frame_done_next;
    reg        aclk_done_next;

    // ---- 状态 + 定时器 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_INIT_RESET;
            timer      <= 16'd0;
            init_done  <= 1'b0;
            line_start <= 1'b0;
            line_done  <= 1'b0;
            line_cnt   <= 10'd0;
            frame_done <= 1'b0;
            aclk_done  <= 1'b0;
        end else begin
            state      <= state_next;
            timer      <= timer_next;
            init_done  <= init_done_next;
            line_start <= line_start_next;
            line_done  <= line_done_next;
            line_cnt   <= line_cnt_next;
            frame_done <= frame_done_next;
            aclk_done  <= aclk_done_next;
        end
    end

    // ---- 状态转移 + 输出(next) ----
    always @(*) begin
        // 默认保持
        state_next      = state;
        timer_next      = timer;
        init_done_next  = init_done;
        line_start_next = 1'b0;
        line_done_next  = 1'b0;
        line_cnt_next   = line_cnt;
        frame_done_next = 1'b0;
        aclk_done_next  = 1'b0;

        case (state)
            S_INIT_RESET: begin
                if (timer == RESET_CYCLES - 1) begin
                    state_next = S_INIT_WAIT;
                    timer_next = 16'd0;
                end else begin
                    timer_next = timer + 16'd1;
                end
            end

            S_INIT_WAIT: begin
                if (timer == INIT_WAIT_CYCLES - 1) begin
                    state_next     = S_IDLE;
                    timer_next     = 16'd0;
                    init_done_next = 1'b1;
                end else begin
                    timer_next = timer + 16'd1;
                end
            end

            S_IDLE: begin
                line_cnt_next = 10'd0;
                if (frame_start) begin
                    state_next = S_SYNC_SETUP;
                    timer_next = 16'd0;
                end
            end

            S_SYNC_SETUP: begin
                // SYNC 建立时间: 2 周期 = 20ns (tSYNCACLK min)
                // 本状态输出 line_start 脉冲
                if (timer == 0)
                    line_start_next = 1'b1;
                if (timer == 1) begin
                    state_next = S_ACLK_ACT;
                    timer_next = 16'd0;
                end else begin
                    timer_next = timer + 16'd1;
                end
            end

            S_ACLK_ACT: begin
                // ACLK 序列: 每 2 个 timer 计数值 = 1 个 ACLK 周期
                // timer 0,1 → pulse 0; timer 2,3 → pulse 1; ...
                // timer 0..17 → 9 个脉冲
                if (timer == (ACLK_PULSES * 2) - 1) begin
                    state_next     = S_SYNC_HOLD;
                    timer_next     = 16'd0;
                    aclk_done_next = 1'b1;
                end else begin
                    timer_next = timer + 16'd1;
                end
            end

            S_SYNC_HOLD: begin
                // ACLK 完成后保持 SYNC 低 2 周期 (20ns)
                if (timer == 1) begin
                    state_next = S_LINE_GAP;
                    timer_next = 16'd0;
                end else begin
                    timer_next = timer + 16'd1;
                end
            end

            S_LINE_GAP: begin
                // 行间隔
                // 已用: 2(S_SYNC_SETUP)+18(S_ACLK)+2(S_SYNC_HOLD)=22
                if (timer == 0) begin
                    line_done_next = 1'b1;
                    line_cnt_next  = line_cnt + 10'd1;
                end
                if (timer == LINE_CYCLES - 23) begin
                    if (line_cnt >= FRAME_LINES - 1) begin
                        state_next      = S_IDLE;
                        frame_done_next = 1'b1;
                    end else begin
                        state_next = S_SYNC_SETUP;
                    end
                    timer_next = 16'd0;
                end else begin
                    timer_next = timer + 16'd1;
                end
            end

            default: begin
                state_next = S_INIT_RESET;
                timer_next = 16'd0;
            end
        endcase
    end

    // =========================================================================
    // 寄存器输出 (消除组合逻辑毛刺, 加 1 周期延迟)
    // =========================================================================

    reg        roic_reset_reg;
    reg        sync_reg;
    reg        aclk_reg;
    reg [3:0]  aclk_idx_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            roic_reset_reg <= 1'b0;
            sync_reg       <= 1'b1;
            aclk_reg       <= 1'b0;
            aclk_idx_reg   <= 4'd0;
        end else begin
            // RESET
            roic_reset_reg <= (state_next == S_INIT_RESET);

            // SYNC
            sync_reg <= !(state_next == S_SYNC_SETUP ||
                          state_next == S_ACLK_ACT ||
                          state_next == S_SYNC_HOLD);

            // ACLK
            aclk_reg <= (state_next == S_ACLK_ACT) && (timer_next[0] == 1'b0);

            // ACLK 编号
            aclk_idx_reg <= (state_next == S_ACLK_ACT) ? (timer_next[4:0] >> 1) : 4'd0;
        end
    end

    assign roic_reset = roic_reset_reg;
    assign sync       = sync_reg;
    assign aclk       = aclk_reg;
    assign aclk_idx   = aclk_idx_reg;

endmodule

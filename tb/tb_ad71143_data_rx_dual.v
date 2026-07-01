// =============================================================================
// AD71143 双 Panel DDR 数据接收 — 仿真测试台
// =============================================================================
// 模拟两颗 ROIC (Panel 0 + Panel 1), 均 DDR 模式
// Panel 0: 测试数据模式 A
// Panel 1: 测试数据模式 B (与 Panel 0 不同, 便于区分)
// 验证 256-bit 合并输出 = {Panel1[127:0], Panel0[127:0]}
// =============================================================================
`timescale 1ns / 1ps

module tb_ad71143_data_rx_dual;

    // =========================================================================
    // 系统信号
    // =========================================================================
    reg         clk_sys;
    reg         rst_n;
    reg         sync_in;
    reg         aclk_done;

    // =========================================================================
    // Panel 0 LVDS
    // =========================================================================
    wire        dclk_p_A0;
    wire        dclk_n_A0;
    reg         dclko_p_A0;
    reg         dclko_n_A0;
    reg         dout_p_A0;
    reg         dout_n_A0;
    reg         dout_p_B0;
    reg         dout_n_B0;

    // =========================================================================
    // Panel 1 LVDS
    // =========================================================================
    wire        dclk_p_A1;
    wire        dclk_n_A1;
    reg         dclko_p_A1;
    reg         dclko_n_A1;
    reg         dout_p_A1;
    reg         dout_n_A1;
    reg         dout_p_B1;
    reg         dout_n_B1;

    // =========================================================================
    // DUT 输出
    // =========================================================================
    wire        line_done;
    wire        header_ok;
    wire        merged_valid;
    wire [255:0] merged_burst;
    wire [6:0]  merged_burst_index;
    wire [2:0]  state_debug_0;
    wire [2:0]  state_debug_1;
    wire        burst_en_out;

    // =========================================================================
    // 测试辅助
    // =========================================================================
    integer i;
    reg     merged_seen;
    reg     line_done_seen;

    // =========================================================================
    // DUT 实例化
    // =========================================================================
    ad71143_data_rx_dual #(
        .MUTE_MIN(113)    // 100MHz: tBURST=1765ns, 177cyc-64=113
    ) dut (
        .clk_sys            (clk_sys),
        .rst_n              (rst_n),
        .sync_in            (sync_in),
        .aclk_done          (aclk_done),

        .dclk_p_A0          (dclk_p_A0),
        .dclk_n_A0          (dclk_n_A0),
        .dclko_p_A0         (dclko_p_A0),
        .dclko_n_A0         (dclko_n_A0),
        .dout_p_A0          (dout_p_A0),
        .dout_n_A0          (dout_n_A0),
        .dout_p_B0          (dout_p_B0),
        .dout_n_B0          (dout_n_B0),

        .dclk_p_A1          (dclk_p_A1),
        .dclk_n_A1          (dclk_n_A1),
        .dclko_p_A1         (dclko_p_A1),
        .dclko_n_A1         (dclko_n_A1),
        .dout_p_A1          (dout_p_A1),
        .dout_n_A1          (dout_n_A1),
        .dout_p_B1          (dout_p_B1),
        .dout_n_B1          (dout_n_B1),

        .line_done          (line_done),
        .header_ok          (header_ok),
        .merged_valid       (merged_valid),
        .merged_burst       (merged_burst),
        .merged_burst_index (merged_burst_index),

        .state_debug_0      (state_debug_0),
        .state_debug_1      (state_debug_1),
        .burst_en_out       (burst_en_out)
    );

    // =========================================================================
    // 时钟: 100MHz (10ns 周期), 与单 Panel TB 一致
    // =========================================================================
    initial clk_sys = 1'b0;
    always #5 clk_sys = ~clk_sys;

    // =========================================================================
    // 监视合并输出
    // =========================================================================
    always @(posedge merged_valid) begin
        merged_seen = 1'b1;
        $display("[%0t] merged_valid burst_index=%0d data[127:0]_p0=%h data[255:128]_p1=%h",
                 $time, merged_burst_index, merged_burst[127:0], merged_burst[255:128]);
    end

    always @(posedge line_done) begin
        line_done_seen = 1'b1;
        $display("[%0t] line_done (dual panel)", $time);
    end

    // =========================================================================
    // SYNC + ACLK 驱动任务
    // =========================================================================
    task automatic drive_sync_and_aclk;
    begin
        sync_in = 1'b1;
        repeat (2) @(posedge clk_sys);
        #1 sync_in = 1'b0;           // SYNC 下降沿 = 新行开始
        repeat (2) @(posedge clk_sys);
        #1 aclk_done = 1'b1;         // ACLK 序列完成
        repeat (2) @(posedge clk_sys);
        #1 aclk_done = 1'b0;
    end
    endtask

    // =========================================================================
    // DCLKO 脉冲 (两 Panel 同时)
    // =========================================================================
    task automatic pulse_dclko_both;
    begin
        #5;
        dclko_p_A0 = 1'b1; dclko_n_A0 = 1'b0;
        dclko_p_A1 = 1'b1; dclko_n_A1 = 1'b0;
        #10;
        dclko_p_A0 = 1'b0; dclko_n_A0 = 1'b1;
        dclko_p_A1 = 1'b0; dclko_n_A1 = 1'b1;
        #10;
    end
    endtask

    // =========================================================================
    // 发送一个 Burst 到两 Panel (各 64 bit × 2 lane = 128 bit per panel)
    // =========================================================================
    task automatic send_burst64_dual;
        input [63:0] lane_a0, lane_b0;   // Panel 0: Lane A (even), Lane B (odd)
        input [63:0] lane_a1, lane_b1;   // Panel 1: Lane A (even), Lane B (odd)
        integer k;
    begin
        wait(burst_en_out === 1'b1);

        $display("[%0t] send_burst START p0_a=%h p0_b=%h p1_a=%h p1_b=%h",
                 $time, lane_a0, lane_b0, lane_a1, lane_b1);

        // 2 个预热 DCLKO: 让 DCLKO 域的 toggle 同步器传播 cap_start
        pulse_dclko_both();
        pulse_dclko_both();

        // 64 bit, MSB first
        for (k = 63; k >= 0; k = k - 1) begin
            dout_p_A0 = lane_a0[k]; dout_n_A0 = ~lane_a0[k];
            dout_p_B0 = lane_b0[k]; dout_n_B0 = ~lane_b0[k];
            dout_p_A1 = lane_a1[k]; dout_n_A1 = ~lane_a1[k];
            dout_p_B1 = lane_b1[k]; dout_n_B1 = ~lane_b1[k];
            pulse_dclko_both();
        end

        $display("[%0t] send_burst DONE  p0_a=%h p0_b=%h p1_a=%h p1_b=%h",
                 $time, lane_a0, lane_b0, lane_a1, lane_b1);
    end
    endtask

    // =========================================================================
    // 发送剩余 Burst (填充到 34 个总 Burst)
    // =========================================================================
    task automatic finish_remaining_bursts;
        input integer data_bursts_already_sent;
        integer n;
    begin
        for (n = data_bursts_already_sent; n < 32; n = n + 1) begin
            send_burst64_dual(
                64'h1000_2000_3000_4000 + n,   // p0 lane A
                64'h5000_6000_7000_8000 + n,   // p0 lane B
                64'hA000_B000_C000_D000 + n,   // p1 lane A
                64'hE000_F000_0000_1000 + n    // p1 lane B
            );
            @(negedge burst_en_out);
            wait(burst_en_out === 1'b1);
        end
        // 最后一个 Burst: 配置寄存器
        send_burst64_dual(
            64'hDEAD_BEEF_CAFE_1234, 64'h0123_4567_89AB_CDEF,  // p0
            64'hF00D_F00D_F00D_F00D, 64'hBEEF_BEEF_BEEF_BEEF   // p1
        );
    end
    endtask

    // =========================================================================
    // 测试用例 1: READDOWN=0 (正常顺序)
    // =========================================================================
    task automatic check_readdown0_dual;
        reg [63:0] header_a0, header_b0;
        reg [63:0] header_a1, header_b1;
        reg [63:0] data_a0, data_b0;
        reg [63:0] data_a1, data_b1;
        reg [255:0] expect_merge;
    begin
        // Panel 0 header: READDOWN=0, CDS_ID=1
        header_a0 = {8'h0A, 5'b00000, 1'b0, 1'b0, 1'b1, 16'h0000, 16'h1357, 16'h2468};
        header_b0 = 64'h0000_0000_0000_0000;
        // Panel 1 header: READDOWN=0, CDS_ID=1, 不同温度/VT
        header_a1 = {8'h0A, 5'b00000, 1'b0, 1'b0, 1'b1, 16'h0000, 16'hAAAA, 16'h5555};
        header_b1 = 64'h0000_0000_0000_0000;

        // Panel 0 data: ch0=0x1000, ch1=0x1001, ... ch7=0x1007
        data_a0 = {16'h1000, 16'h1002, 16'h1004, 16'h1006};
        data_b0 = {16'h1001, 16'h1003, 16'h1005, 16'h1007};
        // Panel 1 data: ch256=0x2000, ch257=0x2001, ... ch263=0x2007
        data_a1 = {16'h2000, 16'h2002, 16'h2004, 16'h2006};
        data_b1 = {16'h2001, 16'h2003, 16'h2005, 16'h2007};

        // 期望合并 (merge 格式: A_word0,B_word0, A_word1,B_word1, ...):
        // Panel0 = {1000,1001, 1002,1003, 1004,1005, 1006,1007}
        // Panel1 = {2000,2001, 2002,2003, 2004,2005, 2006,2007}
        expect_merge = {
            16'h2000, 16'h2001, 16'h2002, 16'h2003,
            16'h2004, 16'h2005, 16'h2006, 16'h2007,
            16'h1000, 16'h1001, 16'h1002, 16'h1003,
            16'h1004, 16'h1005, 16'h1006, 16'h1007
        };

        $display("=== READDOWN=0 DUAL ===");
        $display("Panel0 header: byte=%h readdown=%b cds=%b temp=%h vt=%h",
                 header_a0[63:56], header_a0[49], header_a0[48], header_a0[31:16], header_a0[15:0]);
        $display("Panel1 header: byte=%h readdown=%b cds=%b temp=%h vt=%h",
                 header_a1[63:56], header_a1[49], header_a1[48], header_a1[31:16], header_a1[15:0]);
        $display("EXPECT merge=%h", expect_merge);

        drive_sync_and_aclk();
        merged_seen    = 1'b0;
        line_done_seen = 1'b0;

        // Burst 0: Header
        send_burst64_dual(header_a0, header_b0, header_a1, header_b1);
        // Burst 1: 第一个数据 Burst
        send_burst64_dual(data_a0, data_b0, data_a1, data_b1);
        #50;

        $display("RESULT: header_ok=%0b merged[127:0]=%h merged[255:128]=%h idx=%0d",
                 header_ok, merged_burst[127:0], merged_burst[255:128], merged_burst_index);

        // 验证合并数据
        if (!merged_seen)
            $fatal(1, "READDOWN=0: merged_valid not seen");
        if (!header_ok)
            $fatal(1, "READDOWN=0: header_ok failed (one panel header mismatch)");
        if (merged_burst !== expect_merge)
            $fatal(2, "READDOWN=0: merged_burst mismatch. Got %h, expected %h",
                   merged_burst, expect_merge);
        if (merged_burst_index !== 7'd0)
            $fatal(1, "READDOWN=0: burst index mismatch (expected 0, got %0d)",
                   merged_burst_index);

        // 发送剩余 Burst 并验证 line_done
        finish_remaining_bursts(1);
        #200;
        if (!line_done_seen)
            $fatal(1, "READDOWN=0: line_done not seen after full line");
        @(posedge clk_sys);
    end
    endtask

    // =========================================================================
    // 测试用例 2: READDOWN=1 (反向顺序)
    // =========================================================================
    task automatic check_readdown1_dual;
        reg [63:0] header_a0, header_b0;
        reg [63:0] header_a1, header_b1;
        reg [63:0] data_a0, data_b0;
        reg [63:0] data_a1, data_b1;
        reg [255:0] expect_merge;
    begin
        // Panel 0 header: READDOWN=1, CDS_ID=0
        header_a0 = {8'h0A, 5'b00000, 1'b0, 1'b1, 1'b0, 16'h0000, 16'hAAAA, 16'h5555};
        header_b0 = 64'h0000_0000_0000_0000;
        // Panel 1 header: READDOWN=1, CDS_ID=0
        header_a1 = {8'h0A, 5'b00000, 1'b0, 1'b1, 1'b0, 16'h0000, 16'hBBBB, 16'h6666};
        header_b1 = 64'h0000_0000_0000_0000;

        // READDOWN=1: Lane A = odd desc, Lane B = even desc
        // Panel 0: ch7=0x3007, ch6=0x3006, ... ch0=0x3000
        data_a0 = {16'h3007, 16'h3005, 16'h3003, 16'h3001};
        data_b0 = {16'h3006, 16'h3004, 16'h3002, 16'h3000};
        // Panel 1: ch263=0x4007, ch262=0x4006, ... ch256=0x4000
        data_a1 = {16'h4007, 16'h4005, 16'h4003, 16'h4001};
        data_b1 = {16'h4006, 16'h4004, 16'h4002, 16'h4000};

        // 期望合并 (merge 格式: A_word0,B_word0, A_word1,B_word1, ...):
        // Panel0 = {3007,3006, 3005,3004, 3003,3002, 3001,3000}
        // Panel1 = {4007,4006, 4005,4004, 4003,4002, 4001,4000}
        expect_merge = {
            16'h4007, 16'h4006, 16'h4005, 16'h4004,
            16'h4003, 16'h4002, 16'h4001, 16'h4000,
            16'h3007, 16'h3006, 16'h3005, 16'h3004,
            16'h3003, 16'h3002, 16'h3001, 16'h3000
        };

        $display("=== READDOWN=1 DUAL ===");
        $display("Panel0 header: byte=%h readdown=%b cds=%b temp=%h vt=%h",
                 header_a0[63:56], header_a0[49], header_a0[48], header_a0[31:16], header_a0[15:0]);
        $display("Panel1 header: byte=%h readdown=%b cds=%b temp=%h vt=%h",
                 header_a1[63:56], header_a1[49], header_a1[48], header_a1[31:16], header_a1[15:0]);
        $display("EXPECT merge=%h", expect_merge);

        drive_sync_and_aclk();
        merged_seen    = 1'b0;
        line_done_seen = 1'b0;

        send_burst64_dual(header_a0, header_b0, header_a1, header_b1);
        send_burst64_dual(data_a0, data_b0, data_a1, data_b1);
        #50;

        $display("RESULT: header_ok=%0b merged[127:0]=%h merged[255:128]=%h idx=%0d",
                 header_ok, merged_burst[127:0], merged_burst[255:128], merged_burst_index);

        if (!merged_seen)
            $fatal(1, "READDOWN=1: merged_valid not seen");
        if (!header_ok)
            $fatal(1, "READDOWN=1: header_ok failed");
        if (merged_burst !== expect_merge)
            $fatal(2, "READDOWN=1: merged_burst mismatch. Got %h, expected %h",
                   merged_burst, expect_merge);
        // READDOWN=1 时 channel 反向, 但 burst_index 仍然是 0
        if (merged_burst_index !== 7'd0)
            $fatal(1, "READDOWN=1: burst index mismatch (expected 0, got %0d)",
                   merged_burst_index);

        finish_remaining_bursts(1);
        #200;
        if (!line_done_seen)
            $fatal(1, "READDOWN=1: line_done not seen");
        @(posedge clk_sys);
    end
    endtask

    // =========================================================================
    // 主测试流程
    // =========================================================================
    initial begin
        $dumpfile("tb_ad71143_data_rx_dual.vcd");
        $dumpvars(0, tb_ad71143_data_rx_dual);

        // ---- 初始化 ----
        rst_n       = 1'b0;
        sync_in     = 1'b1;
        aclk_done   = 1'b0;
        dclko_p_A0  = 1'b0; dclko_n_A0 = 1'b1;
        dout_p_A0   = 1'b0; dout_n_A0  = 1'b1;
        dout_p_B0   = 1'b0; dout_n_B0  = 1'b1;
        dclko_p_A1  = 1'b0; dclko_n_A1 = 1'b1;
        dout_p_A1   = 1'b0; dout_n_A1  = 1'b1;
        dout_p_B1   = 1'b0; dout_n_B1  = 1'b1;

        repeat (5) @(posedge clk_sys);
        rst_n = 1'b1;
        repeat (5) @(posedge clk_sys);

        // ---- Test 1: READDOWN=0 ----
        check_readdown0_dual();
        $display("[%0t] check_readdown0_dual PASSED", $time);

        // ---- 复位重新初始化 ----
        rst_n       = 1'b0;
        repeat (5) @(posedge clk_sys);
        rst_n       = 1'b1;
        sync_in     = 1'b1;
        aclk_done   = 1'b0;
        dclko_p_A0  = 1'b0; dclko_n_A0 = 1'b1;
        dout_p_A0   = 1'b0; dout_n_A0  = 1'b1;
        dout_p_B0   = 1'b0; dout_n_B0  = 1'b1;
        dclko_p_A1  = 1'b0; dclko_n_A1 = 1'b1;
        dout_p_A1   = 1'b0; dout_n_A1  = 1'b1;
        dout_p_B1   = 1'b0; dout_n_B1  = 1'b1;
        repeat (5) @(posedge clk_sys);

        // ---- Test 2: READDOWN=1 ----
        check_readdown1_dual();
        $display("[%0t] check_readdown1_dual PASSED", $time);

        // ---- 全部通过 ----
        $display("========================================");
        $display("tb_ad71143_data_rx_dual PASS");
        $display("========================================");
        $finish;
    end

    // =========================================================================
    // 超时保护
    // =========================================================================
    initial begin
        #800000;   // 800μs 超时
        $display("TIMEOUT: state_0=%0d state_1=%0d merged_seen=%0b line_done_seen=%0b merged_valid=%0b line_done=%0b burst_en=%0b header_ok=%0b idx=%0d",
                 state_debug_0, state_debug_1, merged_seen, line_done_seen,
                 merged_valid, line_done, burst_en_out, header_ok, merged_burst_index);
        $fatal(1, "TIMEOUT: tb_ad71143_data_rx_dual did not finish");
    end

endmodule

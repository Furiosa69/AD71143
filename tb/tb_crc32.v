// CRC-32 验证 testbench — 无 VCD, 纯 printf 输出
//   复现 rgmii_bridge.v 的帧组装 + CRC 计算 + FCS 写入逻辑

`timescale 1ns / 1ps

module tb_crc32;

    localparam HDR_MAC     = 14;
    localparam HDR_IP      = 20;
    localparam HDR_UDP     = 8;
    localparam HDR_BYTES   = 42;
    localparam BURST_BYTES = 32;
    localparam FCS_BYTES   = 4;
    localparam FRAME_BYTES = 78;
    localparam FCS_OFFSET  = 74;

    reg         clk;
    reg         rst_n;
    reg         trig;
    reg [31:0]  test_seq_num;

    reg [31:0]  crc_reg;
    reg [6:0]   crc_idx;
    reg         crc_busy;
    reg         crc_done_r;
    wire        crc_done = (crc_idx == 7'd73) && crc_busy;

    reg [7:0]   frame_buf [0:FRAME_BYTES-1];

    reg         fcs_written;

    integer     pass_cnt, fail_cnt;
    integer     i, k;

    // =====================================================================
    //  CRC-32 (与 rgmii_bridge.v 一致)
    // =====================================================================
    function [31:0] crc32_byte;
        input [31:0] crc;
        input [7:0]  data;
        integer j;
        reg [31:0] tmp;
        begin
            tmp = crc ^ {24'd0, data};
            for (j = 0; j < 8; j = j + 1)
                tmp = (tmp[0]) ? (tmp >> 1) ^ 32'hEDB88320 : (tmp >> 1);
            crc32_byte = tmp;
        end
    endfunction

    // =====================================================================
    //  软件 CRC-32 — 用 flat array index
    // =====================================================================
    function [31:0] sw_crc;
        input integer start, nbytes;
        reg [31:0] c;
        begin
            c = 32'hFFFFFFFF;
            for (k = start; k < start + nbytes; k = k + 1)
                c = crc32_byte(c, frame_buf[k]);
            sw_crc = c;
        end
    endfunction

    // =====================================================================
    //  时钟
    // =====================================================================
    always #4 clk = ~clk;   // 125MHz

    // =====================================================================
    //  CRC 管线 + FCS 写入 (修复后)
    // =====================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_reg    <= 32'd0;
            crc_idx    <= 7'd0;
            crc_busy   <= 1'b0;
            crc_done_r <= 1'b0;
            fcs_written <= 1'b0;
        end else begin
            if (trig) begin
                crc_reg    <= 32'hFFFFFFFF;
                crc_idx    <= 7'd0;
                crc_busy   <= 1'b1;
            end

            if (crc_busy) begin
                crc_reg <= crc32_byte(crc_reg, frame_buf[crc_idx]);
                if (crc_idx == 7'd73)
                    crc_busy <= 1'b0;
                else
                    crc_idx <= crc_idx + 7'd1;
            end

            if (crc_done_r) begin
                // crc_reg 已更新 — 包含全部 74 字节
                frame_buf[FCS_OFFSET + 0] <= ~crc_reg[31:24];
                frame_buf[FCS_OFFSET + 1] <= ~crc_reg[23:16];
                frame_buf[FCS_OFFSET + 2] <= ~crc_reg[15:8];
                frame_buf[FCS_OFFSET + 3] <= ~crc_reg[7:0];
                fcs_written <= 1'b1;
                crc_done_r  <= 1'b0;
            end else if (crc_done) begin
                crc_done_r <= 1'b1;
            end
        end
    end

    // =====================================================================
    //  task 定义
    // =====================================================================
    task build_test_frame;
        input [31:0] seq;
        integer j;
        begin
            frame_buf[0]  = 8'hFF; frame_buf[1]  = 8'hFF;
            frame_buf[2]  = 8'hFF; frame_buf[3]  = 8'hFF;
            frame_buf[4]  = 8'hFF; frame_buf[5]  = 8'hFF;
            frame_buf[6]  = 8'h02; frame_buf[7]  = 8'h00;
            frame_buf[8]  = 8'h00; frame_buf[9]  = 8'h00;
            frame_buf[10] = 8'h00; frame_buf[11] = 8'h01;
            frame_buf[12] = 8'h08; frame_buf[13] = 8'h00;
            // IP
            frame_buf[14] = 8'h45; frame_buf[15] = 8'h00;
            frame_buf[16] = 8'h00; frame_buf[17] = 8'h3C;
            frame_buf[18] = 8'h00; frame_buf[19] = 8'h00;
            frame_buf[20] = 8'h00; frame_buf[21] = 8'h00;
            frame_buf[22] = 8'h40; frame_buf[23] = 8'h11;
            frame_buf[24] = 8'hF7; frame_buf[25] = 8'h5D;
            frame_buf[26] = 8'hC0; frame_buf[27] = 8'hA8;
            frame_buf[28] = 8'h01; frame_buf[29] = 8'h02;
            frame_buf[30] = 8'hC0; frame_buf[31] = 8'hA8;
            frame_buf[32] = 8'h01; frame_buf[33] = 8'h01;
            // UDP
            frame_buf[34] = 8'h04; frame_buf[35] = 8'hD2;
            frame_buf[36] = 8'h04; frame_buf[37] = 8'hD2;
            frame_buf[38] = 8'h00; frame_buf[39] = 8'h28;
            frame_buf[40] = 8'h00; frame_buf[41] = 8'h00;
            // Payload
            frame_buf[42] = seq[31:24]; frame_buf[43] = seq[23:16];
            frame_buf[44] = seq[15: 8]; frame_buf[45] = seq[ 7: 0];
            for (j = 4; j < BURST_BYTES; j = j + 1)
                frame_buf[HDR_BYTES + j] = j[7:0];
            // FCS placeholder
            frame_buf[74] = 8'h00; frame_buf[75] = 8'h00;
            frame_buf[76] = 8'h00; frame_buf[77] = 8'h00;
        end
    endtask

    task print_frame;
        begin
            for (i = 0; i < FRAME_BYTES; i = i + 1) begin
                if (i % 16 == 0) $write("\n  %2d:", i);
                if (i == FCS_OFFSET) $write(" [FCS]");
                $write(" %02X", frame_buf[i]);
            end
            $display("");
        end
    endtask

    task print_crc_trace;
        reg [31:0] c;
        begin
            $display("  CRC 逐字节跟踪:");
            c = 32'hFFFFFFFF;
            for (i = 0; i < 74; i = i + 1) begin
                c = crc32_byte(c, frame_buf[i]);
                if (i == 73 || i < 5 || i == 41)
                    $display("    byte[%2d]=0x%02X  CRC=0x%08X", i, frame_buf[i], c);
            end
            $display("  最终 CRC(74B)  = 0x%08X", c);
            $display("  期望 FCS (~CRC)= 0x%08X  = [%02X %02X %02X %02X]",
                     ~c, ~c[31:24], ~c[23:16], ~c[15:8], ~c[7:0]);
        end
    endtask

    task verify_magic;
        reg [31:0] v;
        begin
            v = sw_crc(0, FRAME_BYTES);
            $display("  CRC(全帧 78B) = 0x%08X (期望 0xDEBB20E3, 反射算法)", v);
            if (v == 32'hDEBB20E3) begin
                $display("  ==> PASS: FCS 正确!");
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  ==> FAIL: FCS 错误!");
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // =====================================================================
    //  主测试
    // =====================================================================
    initial begin
        clk = 0;
        rst_n = 0;
        trig = 0;
        pass_cnt = 0;
        fail_cnt = 0;

        #20 rst_n = 1;
        #20;
        @(posedge clk);

        // ========== Test 1: seq_num=0 ==========
        $display("\n========================================");
        $display(" TEST 1: seq_num = 0");
        $display("========================================");

        build_test_frame(32'd0);
        $display("帧内容 (FCS 填入前):");
        print_frame;
        print_crc_trace;

        @(posedge clk); trig <= 1'b1;
        @(posedge clk); trig <= 1'b0;

        wait(fcs_written);
        @(posedge clk);

        $display("\n帧内容 (FCS 填入后):");
        print_frame;
        $display("硬件 FCS: %02X %02X %02X %02X",
                 frame_buf[74], frame_buf[75], frame_buf[76], frame_buf[77]);
        verify_magic;

        // ========== Bug 复现 ==========
        $display("\n----------------------------------------");
        $display(" [BUG 复现] FCS 用 crc_idx=72 的旧值 (漏 byte[73])");
        begin
            reg [31:0] old_crc;
            reg [31:0] bug_fcs;
            reg [7:0]  saved [74:77];

            old_crc = sw_crc(0, 73);   // 只覆盖 byte 0~72 = 73 字节
            $display("  旧 CRC(73B)  = 0x%08X", old_crc);
            $display("  最终 CRC(74B) = 0x%08X", sw_crc(0, 74));
            bug_fcs = ~old_crc;
            $display("  Bug FCS = 0x%08X", bug_fcs);

            // 保存原 FCS, 换 bug FCS
            saved[74] = frame_buf[74]; saved[75] = frame_buf[75];
            saved[76] = frame_buf[76]; saved[77] = frame_buf[77];
            frame_buf[74] = bug_fcs[31:24];
            frame_buf[75] = bug_fcs[23:16];
            frame_buf[76] = bug_fcs[15:8];
            frame_buf[77] = bug_fcs[7:0];

            $display("  CRC(全帧, bug FCS) = 0x%08X", sw_crc(0, FRAME_BYTES));
            $display("  ==> PC 网卡 CRC 校验失败, 丢弃帧! 这就是收不到包的原因.");

            // 恢复
            frame_buf[74] = saved[74]; frame_buf[75] = saved[75];
            frame_buf[76] = saved[76]; frame_buf[77] = saved[77];
        end

        // ========== Test 2: seq_num=1 ==========
        $display("\n========================================");
        $display(" TEST 2: seq_num = 1");
        $display("========================================");

        fcs_written <= 1'b0;
        @(posedge clk);
        build_test_frame(32'd1);
        $display("帧内容 (FCS 填入前):");
        print_frame;
        print_crc_trace;

        @(posedge clk); trig <= 1'b1;
        @(posedge clk); trig <= 1'b0;

        wait(fcs_written);
        @(posedge clk);

        $display("\n帧内容 (FCS 填入后):");
        print_frame;
        $display("硬件 FCS: %02X %02X %02X %02X",
                 frame_buf[74], frame_buf[75], frame_buf[76], frame_buf[77]);
        verify_magic;

        // ========== Result ==========
        $display("\n========================================");
        $display(" RESULT: pass=%0d  fail=%0d", pass_cnt, fail_cnt);
        if (fail_cnt > 0)
            $display(" FAIL — CRC 实现有 bug");
        else
            $display(" PASS — CRC 实现正确");
        $display("========================================");

        #100 $finish;
    end

endmodule

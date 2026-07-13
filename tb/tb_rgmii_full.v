// RGMII 完整链路仿真 + 逐周期信号追踪
//   验证 rgmii_bridge + RGMII_tx 的帧输出

`timescale 1ns / 1ps

module ODDR #(parameter DDR_CLK_EDGE="OPPOSITE_EDGE", INIT=1'b0, SRTYPE="SYNC") (
    output reg Q, input C, CE, D1, D2, R, S
);
    initial Q = INIT;
    always @(posedge C) if (R) Q<=0; else if (S) Q<=1; else if (CE) Q<=D1;
    always @(negedge C) if (!R && !S && CE) Q<=D2;
endmodule

module fifo_generator_0 (
    input wire wr_clk, rd_clk, input wire [255:0] din,
    input wire wr_en, rd_en, output wire [255:0] dout,
    output wire full, empty
);
    assign empty = 1'b1; assign full  = 1'b0; assign dout = 256'd0;
endmodule

module tb_rgmii_full;

    localparam HDR_BYTES   = 42;
    localparam BURST_BYTES = 32;
    localparam FCS_BYTES   = 4;
    localparam FRAME_BYTES = HDR_BYTES + BURST_BYTES + FCS_BYTES;

    reg clk_125m, clk_125m_ph90, clk_100m, rst_n;
    wire TXC_out, TX_CTL, TXD0, TXD1, TXD2, TXD3;
    wire dbg_startup_done, dbg_tx_sending;
    wire [3:0] dbg_state;
    wire [2:0] dbg_tx_fsm;

    initial begin
        clk_125m = 0; clk_125m_ph90 = 0; clk_100m = 0;
    end
    always #4  clk_125m      = ~clk_125m;
    always #4  clk_125m_ph90 = ~clk_125m_ph90;
    initial #6 clk_125m_ph90 = 1;  // ph90 lags 2ns
    always #5  clk_100m      = ~clk_100m;

    rgmii_bridge #(
        .BURST_WIDTH(256), .BURST_BYTES(32), .TEST_MODE(1), .TEST_INTERVAL(1000)
    ) u_bridge (
        .rst_n, .clk_100m, .clk_125m, .clk_125m_ph90,
        .data_in(256'd0), .data_valid(1'b0),
        .TXC(TXC_out), .TX_CTL(TX_CTL), .TXD0(TXD0), .TXD1(TXD1), .TXD2(TXD2), .TXD3(TXD3),
        .dbg_startup_done(dbg_startup_done), .dbg_phy_ready(), .dbg_tx_sending(dbg_tx_sending),
        .dbg_state(dbg_state), .dbg_tx_fsm(dbg_tx_fsm),
        .dbg_crc_busy(), .dbg_tx_start_d()
    );

    // ---- CRC-32 参考 ----
    function [31:0] crc32_byte;
        input [31:0] crc; input [7:0] data; integer j; reg [31:0] tmp;
        begin
            tmp = crc ^ {24'd0, data};
            for (j=0; j<8; j=j+1) tmp = (tmp[0]) ? (tmp>>1)^32'hEDB88320 : (tmp>>1);
            crc32_byte = tmp;
        end
    endfunction

    // ---- RGMII 接收端: 从 DDR 信号重建字节流 ----
    reg [3:0]  nibble_lo;     // posedge 捕获的低 nibble
    reg        ctl_r;          // posedge 捕获的 TX_CTL
    reg        cap_done;       // 已捕获一帧
    reg [7:0]  cap_bytes [0:511];
    integer    cap_idx;

    always @(posedge TXC_out) begin
        if (rst_n) begin
            nibble_lo <= {TXD3, TXD2, TXD1, TXD0};
            ctl_r     <= TX_CTL;
        end
    end

    // RGMII DDR: TX_CTL=(1,1) 表示 (posedge, negedge) 都有数据
    // 必须两个边沿都检查, 否则 nibble 对齐会偏移
    always @(negedge TXC_out) begin
        if (rst_n && ctl_r && TX_CTL) begin
            cap_bytes[cap_idx] <= {TXD3, TXD2, TXD1, TXD0, nibble_lo};
            cap_idx <= cap_idx + 1;
        end
        if (rst_n && !TX_CTL && cap_idx > 0) begin
            cap_done <= 1'b1;
        end
    end

    // ---- 参考 CRC ----
    function [31:0] sw_crc;
        input integer start, nbytes; reg [31:0] c; integer k;
        begin c = 32'hFFFFFFFF; for (k=start; k<start+nbytes; k=k+1) c = crc32_byte(c, cap_bytes[k]); sw_crc = c; end
    endfunction

    // ====== 主测试 ======
    integer i;
    reg [31:0] ref_crc, exp_fcs, act_fcs;
    reg pass_preamble, pass_sfd, pass_dmac, pass_smac, pass_etype, pass_fcs;
    reg fail_any;

    initial begin
        rst_n = 0; cap_idx = 0; cap_done = 0;
        #200 rst_n = 1;

        $display("\n========================================");
        $display(" RGMII 帧输出验证");
        $display("========================================");
        $display("等待 startup_done..."); wait(dbg_startup_done);
        $display("等待 tx_sending...");   wait(dbg_tx_sending);
        $display("等待捕获完成...");      wait(cap_done);
        #40;

        $display("\n捕获 %0d 字节 (不含前导码/SFD):", cap_idx);
        fail_any = 0;

        // ---- 检查 cap_idx > 8 以确保有足够数据 ----
        if (cap_idx < 86) begin
            $display("ERROR: 捕获字节不足 (got %0d, 期望 >= 86)", cap_idx);
            $finish;
        end

        // ---- 前导码 (cap_bytes[0:6]) + SFD (cap_bytes[7]) ----
        $display("\n--- 前导码 ---");
        pass_preamble = 1;
        for (i = 0; i < 7; i = i + 1) begin
            if (cap_bytes[i] != 8'h55) begin
                $display("  preamble[%0d] = 0x%02X (expect 0x55)  FAIL", i, cap_bytes[i]);
                pass_preamble = 0;
            end
        end
        pass_sfd = (cap_bytes[7] == 8'hD5);
        if (!pass_sfd)
            $display("  SFD[7] = 0x%02X (expect 0xD5)  FAIL", cap_bytes[7]);
        if (pass_preamble && pass_sfd)
            $display("  PASS: 7 x 0x55 + 0xD5");

        // ---- 帧数据 (从 byte 8 开始) ----
        $display("\n--- 帧头 (%0d 数据字节) ---", cap_idx - 8);
        $write("  ");
        for (i = 8; i < cap_idx && i < 90; i = i + 1) begin
            if ((i-8) % 16 == 0 && i > 8) $write("\n  ");
            if (i == 8 + HDR_BYTES + BURST_BYTES) $write("[FCS]");
            $write("%02X ", cap_bytes[i]);
        end
        $display("");

        // ---- DMAC ----
        pass_dmac = 1;
        for (i = 0; i < 6; i = i + 1)
            if (cap_bytes[8+i] != 8'hFF) pass_dmac = 0;
        $display("  DMAC: %s", pass_dmac ? "PASS (FF:FF:FF:FF:FF:FF)" : "FAIL");

        // ---- SMAC ----
        pass_smac = (cap_bytes[14]==8'h02 && cap_bytes[15]==8'h00 && cap_bytes[16]==8'h00 &&
                     cap_bytes[17]==8'h00 && cap_bytes[18]==8'h00 && cap_bytes[19]==8'h01);
        $display("  SMAC: %s", pass_smac ? "PASS (02:00:00:00:00:01)" : "FAIL");

        // ---- EtherType ----
        pass_etype = (cap_bytes[20]==8'h08 && cap_bytes[21]==8'h00);
        $display("  EtherType: %s", pass_etype ? "PASS (0x0800)" : "FAIL");

        // ---- CRC/FCS ----
        $display("\n--- CRC/FCS ---");
        ref_crc  = sw_crc(8, 74);  // 74 字节 = header + payload
        exp_fcs  = ~ref_crc;
        act_fcs  = {cap_bytes[85], cap_bytes[84], cap_bytes[83], cap_bytes[82]};

        $display("  Ref CRC(74B)   = 0x%08X", ref_crc);
        $display("  Expected FCS    = 0x%08X  LSB-first: %02X %02X %02X %02X",
                 exp_fcs, exp_fcs[7:0], exp_fcs[15:8], exp_fcs[23:16], exp_fcs[31:24]);
        $display("  Actual FCS      = 0x%08X  bytes: %02X %02X %02X %02X",
                 act_fcs, cap_bytes[82], cap_bytes[83], cap_bytes[84], cap_bytes[85]);

        pass_fcs = (exp_fcs[7:0]==cap_bytes[82] && exp_fcs[15:8]==cap_bytes[83] &&
                    exp_fcs[23:16]==cap_bytes[84] && exp_fcs[31:24]==cap_bytes[85]);
        $display("  FCS: %s", pass_fcs ? "PASS" : "FAIL");

        // ---- Magic number check ----
        $display("\n--- Magic Number ---");
        $display("  CRC(全帧+前导+SFD) = 0x%08X  (期望 0xDEBB20E3)", sw_crc(8, 78));

        // ---- 全帧逐字节打印 ----
        $display("\n--- 全帧 dump (含 preamble/SFD) ---");
        for (i = 0; i < cap_idx && i < 90; i = i + 1) begin
            if (i % 16 == 0) $write("  %3d:", i);
            if (i >= 8 + HDR_BYTES + BURST_BYTES) $write(" [FCS]");
            $write(" %02X", cap_bytes[i]);
            if (i % 16 == 15) $display("");
        end
        $display("");

        // ---- SUMMARY ----
        $display("\n========================================");
        $display(" RESULT");
        $display("  Preamble/SFD: %s", pass_preamble && pass_sfd ? "PASS" : "FAIL");
        $display("  DMAC:         %s", pass_dmac  ? "PASS" : "FAIL");
        $display("  SMAC:         %s", pass_smac  ? "PASS" : "FAIL");
        $display("  EtherType:    %s", pass_etype ? "PASS" : "FAIL");
        $display("  FCS:          %s", pass_fcs   ? "PASS" : "FAIL");
        $display("========================================");

        fail_any = !(pass_preamble && pass_sfd && pass_dmac && pass_smac && pass_etype && pass_fcs);
        if (!fail_any)
            $display(" ALL PASS");
        else begin
            $display(" FAIL — 帧格式有误");

            // ---- 诊断: 只打印前几个字节分析错位 ----
            $display("\n--- 前 20 字节分析 ---");
            for (i = 0; i < 20; i = i + 1) begin
                $write("  [%0d]=0x%02X", i, cap_bytes[i]);
                case (i)
                    0,1,2,3,4,5,6: $display(" (preamble, expect 0x55)");
                    7: $display(" (SFD, expect 0xD5)");
                    8,9,10,11,12,13: $display(" (DMAC, expect 0xFF)");
                    14,15,16,17,18,19: $display(" (SMAC)");
                    default: $display("");
                endcase
            end
        end

        #100 $finish;
    end

endmodule

// RGMII 桥接模块 (带 UDP/IP/MAC 协议栈)
//   100MHz 域接收 burst → Xilinx FIFO IP (异步 CDC) → 125MHz 域封装帧 → RGMII_tx 发送
//
//   帧格式 (大端序):
//     MAC 头  14B:  DMAC(6) + SMAC(6) + EtherType=0x0800(2)
//     IP 头   20B:  固定字段 + 预计算校验和
//     UDP 头   8B:  SrcPort/DstPort=1234 + Length + Checksum=0
//     Payload  N B:  burst 原始数据 (MSB first)
//
//   时钟:
//     clk_100m: 100MHz AFE 数据域 (data_in/data_valid)
//     clk_125m: 125MHz RGMII TXC 域 (帧封装 + RGMII_tx)
//
module rgmii_bridge #(
    parameter BURST_WIDTH = 256,         // 输入 burst 位宽
    parameter BURST_BYTES = 32,          // burst 字节数 = 256/8
    parameter TEST_MODE   = 1,           // 测试模式: 1=使能测试数据生成
    parameter TEST_INTERVAL = 1000      // 测试发包间隔 (1000 = 8μs @ 125MHz)
) (
    input  wire         rst_n,           // 异步复位，低有效

    input  wire         clk_100m,        // 100MHz: data 输入域
    input  wire         clk_125m,        // 125MHz: 内部逻辑 + TXD ODDR
    input  wire         clk_125m_ph90,   // 125MHz 90°相移: TXC ODDR

    // ---- (来自 ad71143_data_rx_dual) ----
    input  wire [BURST_WIDTH-1:0] data_in,  // merged_burst
    input  wire         data_valid,      // merged_valid

    // ---- RGMII 输出 ----
    output wire         TXC,             // 125MHz RGMII 发送时钟
    output wire         TX_CTL,
    output wire         TXD0,
    output wire         TXD1,
    output wire         TXD2,
    output wire         TXD3,

    // ---- Debug 输出 ----
    output wire         dbg_startup_done,
    output wire         dbg_phy_ready,
    output wire         dbg_tx_sending,
    output wire [3:0]   dbg_state,
    output wire [2:0]   dbg_tx_fsm,       // RGMII_tx 状态机状态
    output wire         dbg_crc_busy,      // CRC 计算中
    output wire         dbg_tx_start_d     // tx_start 延迟1拍 (帧数据发送中)
);

    // =====================================================================
    // 帧参数
    // =====================================================================
    localparam HDR_MAC     = 14;          // DMAC(6) + SMAC(6) + EtherType(2)
    localparam HDR_IP      = 20;          // IP 头
    localparam HDR_UDP     = 8;           // UDP 头
    localparam HDR_BYTES   = HDR_MAC + HDR_IP + HDR_UDP;  // 42
    localparam FCS_BYTES   = 4;
    localparam FRAME_BYTES = HDR_BYTES + BURST_BYTES + FCS_BYTES;  // 78
    localparam FCS_OFFSET  = HDR_BYTES + BURST_BYTES;              // 74


    reg [7:0]   frame_buf [0:FRAME_BYTES-1];  // 帧缓冲区 (78 bytes)
    reg [6:0]   frame_idx;                     // 当前输出字节索引
    reg         tx_start;
    reg [7:0]   tx_data;
    reg         preloaded;                      // 首字节已预装 / 帧发送中标志

    // =====================================================================
    // 测试模式: 无 AFE 数据时自动产生递增测试数据
    // =====================================================================
    reg [31:0]  test_seq_num;                // 测试包序号 (每包递增)
    reg [16:0]  interval_cnt;                // 发包间隔计数器
    reg         test_trig;                   // 测试触发 (同 fifo_rd_en_d1 语义)
    reg [23:0]  startup_cnt;                 // 上电启动延迟 (~134ms @ 125MHz)
    reg         startup_done;                // 启动延迟完成标志

    // =====================================================================
    // Xilinx FIFO IP: 100MHz (写) → 125MHz (读)
    // =====================================================================
    wire                fifo_full;
    wire                fifo_empty;
    wire [BURST_WIDTH-1:0] fifo_dout;
    reg                 fifo_rd_en = 1'b0;

    // 写侧 (100MHz 域): data_valid 且 FIFO 未满时写入
    wire fifo_wr_en;
    assign fifo_wr_en = data_valid && !fifo_full;

    fifo_generator_0 fifo_generator_0_inst (
        .wr_clk   (clk_100m),
        .rd_clk   (clk_125m),
        .din      (data_in),
        .wr_en    (fifo_wr_en),
        .rd_en    (fifo_rd_en),
        .dout     (fifo_dout),
        .full     (fifo_full),
        .empty    (fifo_empty)
    );

    // ---- 读侧 (125MHz 域) + 帧封装 + RGMII_tx 控制 ----
    // IP 非 FWFT + Embedded Register: rd_en 有效后 2 拍 dout 数据有效.
    // fifo_rd_en_d1 直接触发帧组装, fifo_dout 直接参与 payload 组帧.
    //
    // 时序:
    //   Cycle 0: rd_en = 1 (发起读)
    //   Cycle 1: rd_en_d1 = 1 → 组装帧, 预装首字节, tx_start=1
    //   Cycle 2-8: preamble (7×0x55), tx_data 保持首字节
    //   Cycle 9: tx_req=1, tx_byte ← frame_buf[0], 加载 frame_buf[1]
    //   ...
    //   Cycle 9+N-1: tx_req=0, 最后一字节, preloaded=0
    //
    reg fifo_rd_en_d1 = 1'b0;  // rd_en 延迟 1 拍, 对齐 dout (Embedded Register)

    integer     i;

    wire        tx_req;

    // ---- IP 头常量 ----
    // IP Total Length = IP头(20) + UDP头(8) + Payload(BURST_BYTES)
    //                 = 20 + 8 + 32 = 60 = 0x003C
    // IP 头校验和 (预计算, Total Length=0x003C 时):
    //   Sum = 0x4500 + 0x003C + 0x0000 + 0x0000 + 0x4011 + 0x0000
    //       + 0xC0A8 + 0x0102 + 0xC0A8 + 0x0101 = 0x08A2
    //   Checksum = ~0x08A2 = 0xF75D
    localparam [15:0] IP_TOTAL_LEN = 20 + 8 + BURST_BYTES;  // 60
    localparam [15:0] IP_CHECKSUM  = 16'hF75D;

    // ---- UDP 头常量 ----
    // UDP Length = UDP头(8) + Payload(BURST_BYTES) = 8 + 32 = 40
    localparam [15:0] UDP_LENGTH = 8 + BURST_BYTES;  // 40

    reg  test_trig_d1;   // test_trig 延迟 1 拍, 对齐帧组装时序

    // ---- 内部调试线 ----
    wire [2:0] tx_fsm_state;
    reg        tx_start_d;        // tx_start 延迟 1 拍 (表示帧数据正在发送)

    // =====================================================================
    // CRC-32 (Ethernet FCS)
    // =====================================================================
    reg [31:0] crc_reg;
    reg [6:0]  crc_idx;
    reg        crc_busy;
    reg        crc_done_r;         // crc_done 延迟 1 拍 (等待 crc_reg 更新)
    wire       crc_done = (crc_idx == 7'd73) && crc_busy;  // 组合逻辑脉冲

    // CRC-32 next: polynomial 0xEDB88320 (reversed, for LSB-first)
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

    always @(posedge clk_125m or negedge rst_n) begin
        if (!rst_n) begin
            crc_reg    <= 32'd0;
            crc_idx    <= 7'd0;
            crc_busy   <= 1'b0;
            crc_done_r <= 1'b0;
        end else begin
            if (fifo_rd_en_d1 || test_trig_d1) begin
                crc_reg  <= 32'hFFFFFFFF;
                crc_idx  <= 7'd0;
                crc_busy <= 1'b1;
            end

            if (crc_busy) begin
                crc_reg <= crc32_byte(crc_reg, frame_buf[crc_idx]);
                if (crc_idx == 7'd73) begin
                    crc_busy <= 1'b0;
                    // FCS 写入延迟到 crc_done_r 周期, 等待 crc_reg 更新为最终值
                end else begin
                    crc_idx <= crc_idx + 7'd1;
                end
            end
        end
    end

    always @(posedge clk_125m or negedge rst_n) begin
        if (!rst_n) begin
            fifo_rd_en_d1   <= 1'b0;
            test_trig       <= 1'b0;
            test_trig_d1    <= 1'b0;
            tx_data          <= 8'd0;
            tx_start         <= 1'b0;
            tx_start_d       <= 1'b0;
            frame_idx        <= 7'd0;
            preloaded        <= 1'b0;
            test_seq_num    <= 32'd0;
            interval_cnt    <= 17'd0;
            startup_cnt     <= 24'd0;
            startup_done    <= 1'b0;
            for (i = 0; i < FRAME_BYTES; i = i + 1)
                frame_buf[i] <= 8'd0;
        end else begin
            tx_start       <= 1'b0;
            tx_start_d     <= tx_start;
            fifo_rd_en_d1  <= fifo_rd_en;
            test_trig_d1   <= test_trig;
            if (test_trig) test_trig <= 1'b0;  // 脉冲信号, 自动清除

            // ---- FIFO 读控制: 空闲且 FIFO 非空 → 发起读 ----
            if (!fifo_empty && !preloaded && !fifo_rd_en && !test_trig) begin
                fifo_rd_en <= 1'b1;
            end else begin
                fifo_rd_en <= 1'b0;
            end

            // ---- 上电启动延迟: 等待 PHY 完成自协商 (IDELAYCTRL 也需要) ----
`ifdef SIM_FAST
            if (!startup_done) begin
                if (startup_cnt >= 24'd500) begin
                    startup_done <= 1'b1;
                end else begin
                    startup_cnt <= startup_cnt + 24'd1;
                end
            end
`else
            if (!startup_done) begin
                // 计数到约 134ms (2^24 / 125MHz), 超过 1000BASE-T 自协商时间
                if (startup_cnt >= 24'hFFFFFF) begin
                    startup_done <= 1'b1;
                end else begin
                    startup_cnt <= startup_cnt + 24'd1;
                end
            end
`endif

            // ---- 测试模式间隔计数器 (启动延迟完成后才运行) ----
            if (TEST_MODE && startup_done) begin
                if (interval_cnt >= TEST_INTERVAL - 1) begin
                    interval_cnt <= 17'd0;
                    // FIFO 为空且当前空闲时, 产生测试触发
                    if (fifo_empty && !preloaded && !fifo_rd_en && !test_trig) begin
                        test_trig    <= 1'b1;
                        test_seq_num <= test_seq_num + 32'd1;
                    end
                end else begin
                    interval_cnt <= interval_cnt + 17'd1;
                end
            end

            // ---- 帧组装触发 (FIFO 数据 或 测试触发) ----
            if (fifo_rd_en_d1 || test_trig_d1) begin
                // MAC 头 (14 bytes)
                frame_buf[0]  <= 8'hFF;    // DMAC[0]  broadcast
                frame_buf[1]  <= 8'hFF;    // DMAC[1]
                frame_buf[2]  <= 8'hFF;    // DMAC[2]
                frame_buf[3]  <= 8'hFF;    // DMAC[3]
                frame_buf[4]  <= 8'hFF;    // DMAC[4]
                frame_buf[5]  <= 8'hFF;    // DMAC[5]
                frame_buf[6]  <= 8'h02;    // SMAC[0]
                frame_buf[7]  <= 8'h00;    // SMAC[1]
                frame_buf[8]  <= 8'h00;    // SMAC[2]
                frame_buf[9]  <= 8'h00;    // SMAC[3]
                frame_buf[10] <= 8'h00;    // SMAC[4]
                frame_buf[11] <= 8'h01;    // SMAC[5]
                frame_buf[12] <= 8'h08;    // EtherType = 0x0800 (IPv4)
                frame_buf[13] <= 8'h00;

                // IP 头 (20 bytes)
                frame_buf[14] <= 8'h45;                     // Ver=4, IHL=5
                frame_buf[15] <= 8'h00;                     // DSCP/ECN
                frame_buf[16] <= IP_TOTAL_LEN[15:8];
                frame_buf[17] <= IP_TOTAL_LEN[7:0];
                frame_buf[18] <= 8'h00;                     // ID
                frame_buf[19] <= 8'h00;
                frame_buf[20] <= 8'h00;                     // Flags/Frag
                frame_buf[21] <= 8'h00;
                frame_buf[22] <= 8'h40;                     // TTL = 64
                frame_buf[23] <= 8'h11;                     // Protocol = UDP
                frame_buf[24] <= IP_CHECKSUM[15:8];
                frame_buf[25] <= IP_CHECKSUM[7:0];
                frame_buf[26] <= 8'hC0;                     // Src IP = 192.168.1.2
                frame_buf[27] <= 8'hA8;
                frame_buf[28] <= 8'h01;
                frame_buf[29] <= 8'h02;
                frame_buf[30] <= 8'hC0;                     // Dst IP = 192.168.1.1
                frame_buf[31] <= 8'hA8;
                frame_buf[32] <= 8'h01;
                frame_buf[33] <= 8'h01;

                // UDP 头 (8 bytes)
                frame_buf[34] <= 8'h04;                     // Src Port = 1234
                frame_buf[35] <= 8'hD2;
                frame_buf[36] <= 8'h04;                     // Dst Port = 1234
                frame_buf[37] <= 8'hD2;
                frame_buf[38] <= UDP_LENGTH[15:8];
                frame_buf[39] <= UDP_LENGTH[7:0];
                frame_buf[40] <= 8'h00;                     // Checksum = 0
                frame_buf[41] <= 8'h00;

                // 首字节必须是 DMAC[0] = 0xFF (广播 MAC 第一字节)
                tx_data  <= 8'hFF;

                // Payload: test_trig 用测试数据, 否则用 FIFO 数据
                if (test_trig_d1) begin
                    // 测试模式: Payload[0:3] = 32bit 序号, Payload[4:31] = 递增字节
                    frame_buf[HDR_BYTES + 0] <= test_seq_num[31:24];
                    frame_buf[HDR_BYTES + 1] <= test_seq_num[23:16];
                    frame_buf[HDR_BYTES + 2] <= test_seq_num[15: 8];
                    frame_buf[HDR_BYTES + 3] <= test_seq_num[ 7: 0];
                    for (i = 4; i < BURST_BYTES; i = i + 1) begin
                        frame_buf[HDR_BYTES + i] <= i[7:0];
                    end
                end else begin
                    // 真实数据: 直接取自 fifo_dout (MSB first)
                    for (i = 0; i < BURST_BYTES; i = i + 1) begin
                        frame_buf[HDR_BYTES + i] <=
                            fifo_dout[(BURST_BYTES - 1 - i) * 8 +: 8];
                    end
                end

                // tx_start 延迟到 CRC 计算完成后
                // frame_ready 会在 74 拍后自动变高
            end

            // ---- CRC 完成 (crc_done) → 延迟 1 拍到 crc_done_r, 等 crc_reg 更新 ----
            // 在 crc_done_r 周期: crc_reg 已更新为最终 CRC (覆盖全部 74 字节)
            // 写入 FCS, 然后触发 RGMII_tx 发送
            if (crc_done_r) begin
                // FCS 字节序: LSB first (反射算法下 crc_reg[0]=x^31 项, 应在第一字节 bit0)
                frame_buf[FCS_OFFSET + 0] <= ~crc_reg[7:0];
                frame_buf[FCS_OFFSET + 1] <= ~crc_reg[15:8];
                frame_buf[FCS_OFFSET + 2] <= ~crc_reg[23:16];
                frame_buf[FCS_OFFSET + 3] <= ~crc_reg[31:24];
                tx_data   <= frame_buf[0];   // DMAC[0] = 0xFF
                tx_start  <= 1'b1;
                frame_idx <= 7'd1;
                preloaded <= 1'b1;
                crc_done_r <= 1'b0;
            end else if (crc_done) begin
                crc_done_r <= 1'b1;
            end

            // ---- DATA 阶段: tx_req 每拍推进一字节 ----
            if (tx_req && preloaded) begin
                tx_data <= frame_buf[frame_idx];
                if (frame_idx < FRAME_BYTES - 1)
                    frame_idx <= frame_idx + 7'd1;
                else
                    preloaded <= 1'b0;
            end
        end
    end

    // =====================================================================
    // RGMII_tx 例化 (125MHz 域)
    // =====================================================================
    RGMII_tx #(
        .FRAME_SIZE(FRAME_BYTES)
    ) u_rgmii_tx (
        .rst_n    (rst_n),
        .TXC      (clk_125m),
        .tx_data  (tx_data),
        .tx_start (tx_start),
        .tx_req   (tx_req),
        .TX_CTL   (TX_CTL),
        .TXD0     (TXD0),
        .TXD1     (TXD1),
        .TXD2     (TXD2),
        .TXD3     (TXD3),
        .dbg_state(tx_fsm_state)
    );

    // TXC 90°相移: FPGA 提供 2ns 延迟
    ODDR #(
        .DDR_CLK_EDGE("OPPOSITE_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) ODDR_txc (
        .Q  (TXC),
        .C  (clk_125m_ph90),
        .CE (1'b1),
        .D1 (1'b1),
        .D2 (1'b0),
        .R  (1'b0),
        .S  (1'b0)
    );

    // =====================================================================
    // Debug 输出
    // =====================================================================
    assign dbg_startup_done = startup_done;
    assign dbg_phy_ready    = interval_cnt[16];       // 每 524ms 翻转, 表示定时器运行
    assign dbg_tx_sending   = preloaded;              // 正在发送帧
    assign dbg_state        = {test_trig, test_trig_d1, fifo_empty, fifo_rd_en};
    assign dbg_tx_fsm       = tx_fsm_state;           // RGMII_tx FSM 状态
    assign dbg_crc_busy     = crc_busy;               // CRC 计算中
    assign dbg_tx_start_d   = tx_start_d;             // tx_start 延迟 1 拍

endmodule

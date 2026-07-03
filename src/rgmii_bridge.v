`timescale 1ns / 1ps
// RGMII 桥接模块 (带 UDP/IP/MAC 协议栈)
//   100MHz 域接收 burst → 异步 FIFO (Gray CDC) → 125MHz 域封装帧 → RGMII_tx 发送
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
    parameter BURST_BYTES = 32           // burst 字节数 = 256/8
) (
    input  wire         rst_n,           // 异步复位，低有效

    input  wire         clk_100m,        // 100MHz: data 输入域
    input  wire         clk_125m,        // 125MHz: RGMII TXC 域

    // ---- (来自 ad71143_data_rx_dual) ----
    input  wire [BURST_WIDTH-1:0] data_in,  // merged_burst
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
    // 帧参数
    // =====================================================================
    localparam HDR_MAC     = 14;          // DMAC(6) + SMAC(6) + EtherType(2)
    localparam HDR_IP      = 20;          // IP 头
    localparam HDR_UDP     = 8;           // UDP 头
    localparam HDR_BYTES   = HDR_MAC + HDR_IP + HDR_UDP;  // 42
    localparam FRAME_BYTES = HDR_BYTES + BURST_BYTES;      // 74

    // =====================================================================
    // 异步 FIFO: 100MHz (写) → 125MHz (读)
    //
    // 使用 Gray 码指针跨时钟域同步, 消除多 bit 总线 CDC 的亚稳态风险.
    // 深度 4, 足以覆盖 burst 到达速率 (每 ~1.7us) 与帧发送速率 (每 592ns) 的差异.
    // =====================================================================
    localparam FIFO_DEPTH = 4;
    localparam FIFO_AW    = 2;            // log2(FIFO_DEPTH)

    // FIFO 存储器 (distributed RAM)
    reg [BURST_WIDTH-1:0] fifo_mem [0:FIFO_DEPTH-1];

    // ---- 写域 (100MHz) ----
    reg  [FIFO_AW:0] wptr_bin;           // 写指针 (二进制, 多 1bit 区分满/空)
    reg  [FIFO_AW:0] wptr_gray;          // 写指针 (Gray 码, 输出给读域)
    reg  [FIFO_AW:0] rptr_sync_w1;       // 读指针同步到写域 (2-FF stage 1)
    reg  [FIFO_AW:0] rptr_sync_w2;       // 读指针同步到写域 (2-FF stage 2)

    wire             fifo_full;
    wire             fifo_wr_en;
    assign fifo_wr_en = data_valid && !fifo_full;

    // 写指针 Gray 码转换函数
    function [FIFO_AW:0] bin2gray;
        input [FIFO_AW:0] bin;
        begin
            bin2gray = bin ^ (bin >> 1);
        end
    endfunction

    always @(posedge clk_100m or negedge rst_n) begin
        if (!rst_n) begin
            wptr_bin  <= 0;
            wptr_gray <= 0;
        end else if (fifo_wr_en) begin
            fifo_mem[wptr_bin[FIFO_AW-1:0]] <= data_in;
            wptr_bin  <= wptr_bin + 1'b1;
            wptr_gray <= bin2gray(wptr_bin + 1'b1);
        end
    end

    // 读指针 (Gray) 同步到写域: 2-FF
    always @(posedge clk_100m) begin
        rptr_sync_w1 <= rptr_gray;
        rptr_sync_w2 <= rptr_sync_w1;
    end

    // FIFO 满判断:
    //   写指针 Gray 码与同步后读指针 Gray 码: MSB 和 MSB-1 相反, 其余位相同
    assign fifo_full = (wptr_gray[FIFO_AW]   != rptr_sync_w2[FIFO_AW])   &&
                       (wptr_gray[FIFO_AW-1] != rptr_sync_w2[FIFO_AW-1]) &&
                       (wptr_gray[FIFO_AW-2:0] == rptr_sync_w2[FIFO_AW-2:0]);

    // ---- 读域 (125MHz) ----
    reg  [FIFO_AW:0] rptr_bin;           // 读指针 (二进制)
    reg  [FIFO_AW:0] rptr_gray;          // 读指针 (Gray 码, 输出给写域)
    reg  [FIFO_AW:0] wptr_sync_r1;       // 写指针同步到读域 (2-FF stage 1)
    reg  [FIFO_AW:0] wptr_sync_r2;       // 写指针同步到读域 (2-FF stage 2)

    wire             fifo_empty;
    wire [BURST_WIDTH-1:0] fifo_rdata;   // FIFO 读出数据 (组合逻辑)
    assign fifo_rdata = fifo_mem[rptr_bin[FIFO_AW-1:0]];

    // FIFO 读出后寄存器打一拍 (125MHz 域), 切断组合逻辑长路径
    reg [BURST_WIDTH-1:0] burst_hold;

    always @(posedge clk_125m or negedge rst_n) begin
        if (!rst_n) begin
            rptr_bin    <= 0;
            rptr_gray   <= 0;
            burst_hold  <= {BURST_WIDTH{1'b0}};
        end else if (!fifo_empty && !preloaded && !fifo_rd_req_d1) begin
            // 125MHz 域空闲且 FIFO 非空时读出, 同时寄存数据
            // fifo_rd_req_d1 门控防止流水线未排空时重复读取
            burst_hold <= fifo_rdata;
            rptr_bin   <= rptr_bin + 1'b1;
            rptr_gray  <= bin2gray(rptr_bin + 1'b1);
        end
    end

    // 写指针 (Gray) 同步到读域: 2-FF
    always @(posedge clk_125m) begin
        wptr_sync_r1 <= wptr_gray;
        wptr_sync_r2 <= wptr_sync_r1;
    end

    // FIFO 空判断: 同步后写指针与读指针 Gray 码完全相同
    assign fifo_empty = (wptr_sync_r2 == rptr_gray);

    // =====================================================================
    // 125MHz 域: 帧封装 + RGMII_tx 控制
    // =====================================================================
    //
    // 原理:
    //   tx_req = (next_state == DATA), 在 RGMII_tx 即将进入 DATA 状态时
    //   提前一拍拉高。bridge 预装帧首字节，在 tx_req 每拍推进一字节。
    //
    // 时序:
    //   Cycle 0: tx_start=1, 预装 frame_buf[0] → tx_data
    //   Cycle 1-7: preamble (7×0x55), tx_data 保持 frame_buf[0]
    //   Cycle 8: tx_req=1, tx_byte ← frame_buf[0], 同时加载 frame_buf[1]
    //   Cycle 9: tx_req=1, tx_byte ← frame_buf[1], 加载 frame_buf[2]
    //   ...
    //   Cycle 8+N-1: tx_req=0, tx_byte ← 最后字节, 帧结束
    //

    reg [7:0]   frame_buf [0:FRAME_BYTES-1];  // 帧缓冲区 (74 bytes)
    reg [6:0]   frame_idx;                     // 当前输出字节索引
    reg         tx_start;
    reg [7:0]   tx_data;
    reg         preloaded;                      // 首字节已预装 / 帧发送中标志
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

    // 从 FIFO 读取新 burst 的条件: FIFO 非空 且 上一帧发送已完成
    wire fifo_rd_req;
    assign fifo_rd_req = !fifo_empty && !preloaded;

    // fifo_rd_req 延迟 1 拍, 对齐 burst_hold (同一周期写入, 下一周期可用)
    reg fifo_rd_req_d1;

    always @(posedge clk_125m or negedge rst_n) begin
        if (!rst_n)
            fifo_rd_req_d1 <= 1'b0;
        else
            fifo_rd_req_d1 <= fifo_rd_req;
    end

    always @(posedge clk_125m or negedge rst_n) begin
        if (!rst_n) begin
            tx_data    <= 8'd0;
            tx_start   <= 1'b0;
            frame_idx  <= 7'd0;
            preloaded  <= 1'b0;
            for (i = 0; i < FRAME_BYTES; i = i + 1)
                frame_buf[i] <= 8'd0;
        end else begin
            tx_start <= 1'b0;

            // ---- burst_hold 就绪: 组装帧 + 发送 ----
            if (fifo_rd_req_d1) begin
                // MAC 头 (14 bytes)
                frame_buf[0]  <= 8'hFF;    // DMAC[0]  broadcast
                frame_buf[1]  <= 8'hFF;    // DMAC[1]
                frame_buf[2]  <= 8'hFF;    // DMAC[2]
                frame_buf[3]  <= 8'hFF;    // DMAC[3]
                frame_buf[4]  <= 8'hFF;    // DMAC[4]
                frame_buf[5]  <= 8'hFF;    // DMAC[5]
                frame_buf[6]  <= 8'h02;    // SMAC[0]  02:00:00:00:00:01
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
                frame_buf[16] <= IP_TOTAL_LEN[15:8];        // Total Length hi
                frame_buf[17] <= IP_TOTAL_LEN[7:0];         // Total Length lo
                frame_buf[18] <= 8'h00;                     // ID
                frame_buf[19] <= 8'h00;
                frame_buf[20] <= 8'h00;                     // Flags/Frag
                frame_buf[21] <= 8'h00;
                frame_buf[22] <= 8'h40;                     // TTL = 64
                frame_buf[23] <= 8'h11;                     // Protocol = UDP
                frame_buf[24] <= IP_CHECKSUM[15:8];         // Header Checksum hi
                frame_buf[25] <= IP_CHECKSUM[7:0];          // Header Checksum lo
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
                frame_buf[38] <= UDP_LENGTH[15:8];          // UDP Length hi
                frame_buf[39] <= UDP_LENGTH[7:0];           // UDP Length lo
                frame_buf[40] <= 8'h00;                     // Checksum = 0
                frame_buf[41] <= 8'h00;

                // Payload: 来自 burst_hold (FIFO 读出后已寄存) (MSB first)
                for (i = 0; i < BURST_BYTES; i = i + 1) begin
                    frame_buf[HDR_BYTES + i] <=
                        burst_hold[(BURST_BYTES - 1 - i) * 8 +: 8];
                end

                // 预装首字节, 触发发送
                tx_data    <= burst_hold[BURST_WIDTH-1 -: 8];
                tx_start   <= 1'b1;
                frame_idx  <= 7'd1;
                preloaded  <= 1'b1;
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
        .TXD3     (TXD3)
    );

    assign TXC = clk_125m;

endmodule

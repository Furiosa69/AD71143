`timescale 1ns / 1ps
module RGMII_tx (
    input  wire         rst_n,      //异步复位，低有效
    input  wire         TXC,        //125MHz

    input  wire [7:0]   tx_data,    //待发送数据字节
    input  wire         tx_start,   //发送开始脉冲，高有效

    output wire         TX_CTL,     //RGMII 发送控制
    output wire         TXD0,       //RGMII 发送数据 bit0
    output wire         TXD1,       //RGMII 发送数据 bit1
    output wire         TXD2,       //RGMII 发送数据 bit2
    output wire         TXD3        //RGMII 发送数据 bit3
);

    parameter FRAME_SIZE   = 64;        //一帧数据字节数
    parameter PREAMBLE_NUM = 7;         //前导码个数
    parameter Preamble     = 8'h55;     //前导码
    parameter SFD          = 8'hD5;     //帧开始定界符
    parameter IDLE         = 3'd0;      //空闲状态，等待 tx_start
    parameter PREAMBLE     = 3'd1;      //发送前导码
    parameter SFD_STATE    = 3'd2;      //发送 SFD
    parameter DATA         = 3'd3;      //发送数据

    // ============ 内部信号 ============
    reg  [2:0]      state;
    reg  [2:0]      next_state;
    reg  [2:0]      Preamble_cnt;       //前导码计数 (0 ~ 6)
    reg  [31:0]     Byte_cnt;           //数据字节计数

    reg  [7:0]      tx_byte;            //当前发送字节
    reg             tx_en;              //当前发送使能
    reg             tx_er;              //当前发送错误

    // ============ 状态寄存器 ============
    always @(posedge TXC) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // ============ 状态机组合逻辑 ============
    always @(*) begin
        case (state)
            IDLE:       next_state = tx_start ? PREAMBLE : IDLE;
            PREAMBLE:   next_state = (Preamble_cnt == PREAMBLE_NUM - 1) ? SFD_STATE : PREAMBLE;
            SFD_STATE:  next_state = DATA;
            DATA:       next_state = (Byte_cnt == FRAME_SIZE - 1) ? IDLE : DATA;
            default:    next_state = IDLE;
        endcase
    end

    // ============ 前导码计数器 ============
    always @(posedge TXC) begin
        if (!rst_n) begin
            Preamble_cnt <= 0;
        end else if (state == PREAMBLE) begin
            if (Preamble_cnt == PREAMBLE_NUM - 1)
                Preamble_cnt <= 0;
            else
                Preamble_cnt <= Preamble_cnt + 1;
        end
    end

    // ============ 数据字节计数器 ============
    always @(posedge TXC) begin
        if (!rst_n) begin
            Byte_cnt <= 0;
        end else if (state == DATA) begin
            if (Byte_cnt == FRAME_SIZE - 1)
                Byte_cnt <= 0;
            else
                Byte_cnt <= Byte_cnt + 1;
        end
    end

    // ============ 发送字节选择 ============
    always @(posedge TXC) begin
        if (!rst_n) begin
            tx_byte <= 8'h00;
            tx_en   <= 1'b0;
            tx_er   <= 1'b0;
        end else begin
            case (next_state)
                PREAMBLE: begin
                    tx_byte <= Preamble;
                    tx_en   <= 1'b1;
                    tx_er   <= 1'b0;
                end
                SFD_STATE: begin
                    tx_byte <= SFD;
                    tx_en   <= 1'b1;
                    tx_er   <= 1'b0;
                end
                DATA: begin
                    tx_byte <= tx_data;
                    tx_en   <= 1'b1;
                    tx_er   <= 1'b0;
                end
                default: begin
                    tx_byte <= 8'h00;
                    tx_en   <= 1'b0;
                    tx_er   <= 1'b0;
                end
            endcase
        end
    end

    // ============ ODDR 原语例化 ============
    // TX_CTL: 上升沿 = TX_EN, 下降沿 = TX_EN xor TX_ER
    // TXD:   上升沿 = tx_byte[3:0], 下降沿 = tx_byte[7:4]

    ODDR #(
        .DDR_CLK_EDGE("OPPOSITE_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) ODDR_inst_0 (
        .Q (TXD0),
        .C (TXC),
        .CE(1'b1),
        .D1(tx_byte[0]),
        .D2(tx_byte[4]),
        .R (1'b0),
        .S (1'b0)
    );

    ODDR #(
        .DDR_CLK_EDGE("OPPOSITE_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) ODDR_inst_1 (
        .Q (TXD1),
        .C (TXC),
        .CE(1'b1),
        .D1(tx_byte[1]),
        .D2(tx_byte[5]),
        .R (1'b0),
        .S (1'b0)
    );

    ODDR #(
        .DDR_CLK_EDGE("OPPOSITE_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) ODDR_inst_2 (
        .Q (TXD2),
        .C (TXC),
        .CE(1'b1),
        .D1(tx_byte[2]),
        .D2(tx_byte[6]),
        .R (1'b0),
        .S (1'b0)
    );

    ODDR #(
        .DDR_CLK_EDGE("OPPOSITE_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) ODDR_inst_3 (
        .Q (TXD3),
        .C (TXC),
        .CE(1'b1),
        .D1(tx_byte[3]),
        .D2(tx_byte[7]),
        .R (1'b0),
        .S (1'b0)
    );

    ODDR #(
        .DDR_CLK_EDGE("OPPOSITE_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) ODDR_inst_ctl (
        .Q (TX_CTL),
        .C (TXC),
        .CE(1'b1),
        .D1(tx_en),
        .D2(tx_en ^ tx_er),
        .R (1'b0),
        .S (1'b0)
    );

endmodule

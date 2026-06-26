// =============================================================================
// AD71143 SPI Master - 配置 ROIC 寄存器
// =============================================================================
// 标准 4 线 SPI (CS, SCK, SDI, SDO), 16-bit 帧, MSB first
// SCK = 25MHz (从 100MHz 系统时钟 4 分频)
//
// 帧格式:
//   Bit[15]    = Write (1=写)
//   Bit[14]    = Read  (1=读)
//   Bit[13:10] = Register Address (0~15)
//   Bit[9:0]   = Register Data
//
// 用法:
//   1. 设置 reg_addr, reg_data, rw
//   2. 拉 start 一个周期
//   3. 等 done=1
//   4. 如果是读操作, 读 reg_rdback
// =============================================================================

`timescale 1ns / 1ps

module ad71143_spi (
    input  wire         clk_sys,        // 系统时钟 (100MHz)
    input  wire         rst_n,          // 异步复位, 低有效

    // ---- 控制接口 ----
    input  wire         start,          // 开始一次 SPI 传输 (单周期脉冲)
    input  wire         rw,             // 1=写, 0=读
    input  wire [3:0]   reg_addr,       // 寄存器地址 0~15
    input  wire [9:0]   reg_data,       // 写入数据 (读操作时忽略)
    output reg          done,           // 传输完成 (单周期脉冲)
    output reg  [9:0]   reg_rdback,     // 读回数据 (仅读操作有效)

    // ---- SPI 物理口 ----
    output reg          spi_cs,         // 片选 (低有效)
    output reg          spi_sck,        // 时钟
    output reg          spi_sdi,        // 数据输出 (FPGA→ROIC)
    input  wire         spi_sdo         // 数据输入 (ROIC→FPGA)
);

    // =========================================================================
    // SCK 生成 (clk_sys 4 分频 → 25MHz)
    // =========================================================================
    localparam SCK_DIV = 2;             // 100MHz / (2*2) = 25MHz

    reg [1:0] sck_cnt;
    reg       sck_toggle;
    reg       spi_active;
    reg [3:0] bit_cnt;     // 已发送 bit 数 (0~15)
    reg [15:0] shift_reg;  // 发送移位寄存器
    reg [9:0] rdback_buf;  // SDO 读回缓冲

    // =========================================================================
    // 状态机
    // =========================================================================
    localparam S_IDLE   = 2'd0;
    localparam S_SETUP  = 2'd1;         // CS 拉低后等待
    localparam S_SHIFT  = 2'd2;         // 16-bit 移位
    localparam S_DONE   = 2'd3;

    reg [1:0] state, state_next;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= state_next;
    end

    // =========================================================================
    // 状态转移
    // =========================================================================
    always @(*) begin
        state_next = state;
        case (state)
            S_IDLE:  if (start) state_next = S_SETUP;
            S_SETUP: if (sck_toggle && sck_cnt == 0)
                         state_next = S_SHIFT;
            S_SHIFT: if (bit_cnt == 15 && sck_toggle && sck_cnt == 0)
                         state_next = S_DONE;
            S_DONE:  state_next = S_IDLE;
            default: state_next = S_IDLE;
        endcase
    end

    // =========================================================================
    // SCK 计数器 (仅在 SPI 传输期间运行)
    // =========================================================================
    wire spi_busy;
    assign spi_busy = (state == S_SETUP || state == S_SHIFT);

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            sck_cnt   <= 2'd0;
            sck_toggle <= 1'b0;
        end else if (spi_busy) begin
            if (sck_cnt == SCK_DIV - 1) begin
                sck_cnt   <= 2'd0;
                sck_toggle <= ~sck_toggle;
            end else begin
                sck_cnt <= sck_cnt + 2'd1;
            end
        end else begin
            sck_cnt   <= 2'd0;
            sck_toggle <= 1'b0;
        end
    end

    // =========================================================================
    // 移位逻辑
    // =========================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 16'd0;
            bit_cnt   <= 4'd0;
        end else if (state == S_IDLE && start) begin
            // 装载帧: {W, R, Addr[3:0], Data[9:0]}
            shift_reg <= {rw, ~rw, reg_addr, reg_data};
            bit_cnt   <= 4'd0;
        end else if (state == S_SHIFT && sck_toggle && sck_cnt == 0) begin
            // SCK 上升沿: 输出下一个 bit (MSB first)
            shift_reg <= {shift_reg[14:0], 1'b0};
            bit_cnt   <= bit_cnt + 4'd1;
        end
    end

    // =========================================================================
    // SPI 信号输出
    // =========================================================================
    // SDI: 在 SCK 上升沿更新, 保持稳定到下一个上升沿
    // SDI 应在 SCK 下降沿被 ROIC 采样, 所以在非 SCK 边沿时更新
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            spi_sdi <= 1'b0;
        end else if (state == S_SETUP) begin
            spi_sdi <= shift_reg[15];   // MSB 先出
        end else if (state == S_SHIFT && !sck_toggle && sck_cnt == 0) begin
            // SCK 低电平期间更新 SDI (给 ROIC 在 SCK 下降沿采样留 setup 时间)
            spi_sdi <= shift_reg[15];
        end
    end

    // SCK
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            spi_sck <= 1'b0;
        else if (spi_busy)
            spi_sck <= sck_toggle;
        else
            spi_sck <= 1'b0;
    end

    // CS
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            spi_cs <= 1'b1;
        else if (state == S_IDLE && start)
            spi_cs <= 1'b0;
        else if (state == S_DONE)
            spi_cs <= 1'b1;
    end

    // =========================================================================
    // SDO 采样 + 读回
    // =========================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            rdback_buf <= 10'd0;
            reg_rdback <= 10'd0;
        end else if (state == S_SHIFT && !sck_toggle && sck_cnt == SCK_DIV-1) begin
            // 在内部 sck_toggle 下降沿采样 (此时 spi_sck 实际已稳定在高)
            // 等效于 SCK 上升沿后半个 SCK 周期采样
            rdback_buf <= {rdback_buf[8:0], spi_sdo};
        end
    end

    // =========================================================================
    // done 输出
    // =========================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            done       <= 1'b0;
            reg_rdback <= 10'd0;
        end else if (state == S_DONE) begin
            done       <= 1'b1;
            reg_rdback <= rdback_buf;  // 始终捕获 (读数据在下一帧返回)
        end else begin
            done <= 1'b0;
        end
    end

endmodule

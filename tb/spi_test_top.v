// =============================================================================
// SPI Test Top — 黑鹰A704 上板测试 AD71143 SPI 模块
// =============================================================================
// 功能:
//   1. 板载 50MHz 晶振 → PLL 倍频到 100MHz → 驱动 SPI 模块
//   2. 内部状态机自动生成 SPI 测试序列 (写8个寄存器 → 回读验证 → 循环)
//   3. SPI 信号输出到 J1 排针, 方便逻辑分析仪抓取
//   4. LED0 心跳 (每完成一次 SPI 传输翻转), LED1 周期指示
//
// 逻辑分析仪接线:
//   J1 pin 9  (M22) = spi_cs  → 逻辑分析仪 CH0
//   J1 pin 10 (N22) = spi_sck → 逻辑分析仪 CH1
//   J1 pin 11 (M20) = spi_sdi → 逻辑分析仪 CH2
//   J1 pin 12 (N20) = spi_sdo → 逻辑分析仪 CH3 (用跳线短接到 J1 pin 11 做回环测试)
//
// 按键:
//   KEY (T3) = 复位 (按下=低电平复位, 松开=运行)
// =============================================================================

`timescale 1ns / 1ps

module spi_test_top (
    input  wire         sys_clk_50m,    // 板载 50MHz 晶振 → FPGA pin R4
    input  wire         key_n,          // 按键, 低有效, FPGA pin T3 (10K 上拉)
    output wire         spi_cs,         // SPI 片选 → J1 pin 9  (M22)
    output wire         spi_sck,        // SPI 时钟 → J1 pin 10 (N22)
    output wire         spi_sdi,        // SPI 数据 → J1 pin 11 (M20)
    input  wire         spi_sdo,        // SPI 数据 ← J1 pin 12 (N20), 跳线到 J1-11
    output wire         led0,           // LED0 心跳 (T1), 低有效
    output wire         led1            // LED1 状态 (U1), 低有效
);

    // =========================================================================
    // 内部信号
    // =========================================================================
    wire        clk_100m;       // PLL 输出 100MHz
    wire        pll_locked;     // PLL 锁定指示
    wire        rst_n;          // 内部复位 (PLL 锁定 + 按键)

    // 复位: PLL 锁定后, 按键释放 = 运行
    assign rst_n = pll_locked && key_n;

    // =========================================================================
    // PLLE2_BASE: 50MHz → 100MHz
    //   CLKIN1 = 50MHz (周期 20ns)
    //   VCO = 50 * 20 / 1 = 1000MHz (在 Artix-7 -2 允许范围 800~1600MHz 内)
    //   CLKOUT0 = 1000 / 10 = 100MHz
    // =========================================================================
    wire clk_fb;

    PLLE2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT      (20),           // VCO = 50 * 20 / 1 = 1000 MHz
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (20.0),         // 50 MHz 输入
        .CLKOUT0_DIVIDE     (10),           // 1000 / 10 = 100 MHz
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT1_DIVIDE     (1),
        .CLKOUT1_DUTY_CYCLE (0.5),
        .CLKOUT1_PHASE      (0.0),
        .CLKOUT2_DIVIDE     (1),
        .CLKOUT2_DUTY_CYCLE (0.5),
        .CLKOUT2_PHASE      (0.0),
        .CLKOUT3_DIVIDE     (1),
        .CLKOUT3_DUTY_CYCLE (0.5),
        .CLKOUT3_PHASE      (0.0),
        .CLKOUT4_DIVIDE     (1),
        .CLKOUT4_DUTY_CYCLE (0.5),
        .CLKOUT4_PHASE      (0.0),
        .CLKOUT5_DIVIDE     (1),
        .CLKOUT5_DUTY_CYCLE (0.5),
        .CLKOUT5_PHASE      (0.0),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) pll_inst (
        .CLKIN1             (sys_clk_50m),
        .CLKOUT0            (clk_100m),
        .CLKOUT1            (),
        .CLKOUT2            (),
        .CLKOUT3            (),
        .CLKOUT4            (),
        .CLKOUT5            (),
        .CLKFBOUT           (clk_fb),
        .CLKFBIN            (clk_fb),
        .LOCKED             (pll_locked),
        .PWRDWN             (1'b0),
        .RST                (1'b0)
    );

    // =========================================================================
    // SPI 模块控制信号
    // =========================================================================
    reg         spi_start;
    reg         spi_rw;
    reg  [3:0]  spi_reg_addr;
    reg  [9:0]  spi_reg_data;
    wire        spi_done;
    wire [9:0]  spi_rdback;

    // =========================================================================
    // AD71143 SPI Master 例化 (原始模块, 不做修改)
    // =========================================================================
    ad71143_spi u_spi (
        .clk_sys    (clk_100m),
        .rst_n      (rst_n),
        .start      (spi_start),
        .rw         (spi_rw),
        .reg_addr   (spi_reg_addr),
        .reg_data   (spi_reg_data),
        .done       (spi_done),
        .reg_rdback (spi_rdback),
        .spi_cs     (spi_cs),
        .spi_sck    (spi_sck),
        .spi_sdi    (spi_sdi),
        .spi_sdo    (spi_sdo)
    );

    // =========================================================================
    // 配置寄存器 ROM (可综合的组合逻辑查找表)
    // 与 AD71143 参考配置一致
    // =========================================================================
    wire [3:0]  cfg_addr_lut;
    wire [9:0]  cfg_data_lut;

    assign cfg_addr_lut =
        (reg_index == 3'd0) ? 4'd3  :
        (reg_index == 3'd1) ? 4'd0  :
        (reg_index == 3'd2) ? 4'd1  :
        (reg_index == 3'd3) ? 4'd2  :
        (reg_index == 3'd4) ? 4'd4  :
        (reg_index == 3'd5) ? 4'd5  :
        (reg_index == 3'd6) ? 4'd6  :
        (reg_index == 3'd7) ? 4'd7  :
        4'd0;

    assign cfg_data_lut =
        (reg_index == 3'd0) ? 10'h040 :  // REFDAC=64 → ~1.5V
        (reg_index == 3'd1) ? 10'h014 :  // PWR=Normal, IFS=20
        (reg_index == 3'd2) ? 10'h230 :  // LPF=3.9μs, CDS2_RESETEN
        (reg_index == 3'd3) ? 10'h003 :  // Pipeline=1, ECHOCLK=1
        (reg_index == 3'd4) ? 10'h070 :  // INTRST
        (reg_index == 3'd5) ? 10'h001 :  // CDS1
        (reg_index == 3'd6) ? 10'h005 :  // CDS2
        (reg_index == 3'd7) ? 10'h002 :  // FA
        10'h000;

    // =========================================================================
    // 测试状态定义
    // =========================================================================
    localparam T_IDLE        = 4'd0;   // 等待复位释放
    localparam T_WRITE_REQ   = 4'd1;   // 发起写请求
    localparam T_WRITE_WAIT  = 4'd2;   // 等待写完成
    localparam T_WRITE_NEXT  = 4'd3;   // 下一个写寄存器
    localparam T_READ_REQ1   = 4'd4;   // 发起读命令 (第一帧)
    localparam T_READ_WAIT1  = 4'd5;   // 等待读命令完成
    localparam T_READ_GAP    = 4'd6;   // 帧间隔
    localparam T_READ_REQ2   = 4'd7;   // 发起读数据帧 (第二帧)
    localparam T_READ_WAIT2  = 4'd8;   // 等待读数据完成
    localparam T_READ_NEXT   = 4'd9;   // 下一个读寄存器
    localparam T_CYCLE_DONE  = 4'd10;  // 一轮测试完成
    localparam T_GAP         = 4'd11;  // 间隔等待 (方便逻辑分析仪区分帧)

    reg [3:0]  test_state, test_state_next;
    reg [2:0]  reg_index;          // 0~7 寄存器索引
    reg [15:0] gap_timer;          // 帧间隔计数器
    reg [23:0] cycle_count;        // 测试轮数计数器

    always @(posedge clk_100m or negedge rst_n) begin
        if (!rst_n)
            test_state <= T_IDLE;
        else
            test_state <= test_state_next;
    end

    always @(*) begin
        test_state_next = test_state;
        case (test_state)
            T_IDLE: begin
                // 复位释放后自动开始 (等 256 个周期让 PLL 稳定)
                if (gap_timer == 16'd255)
                    test_state_next = T_WRITE_REQ;
            end

            // ---- 写寄存器序列 ----
            T_WRITE_REQ:  test_state_next = T_WRITE_WAIT;
            T_WRITE_WAIT: if (spi_done) test_state_next = T_WRITE_NEXT;
            T_WRITE_NEXT: begin
                if (reg_index == 3'd7)
                    test_state_next = T_GAP;    // 写完 8 个, 准备读
                else
                    test_state_next = T_WRITE_REQ;
            end

            // ---- 帧间隔 ----
            T_GAP: if (gap_timer == 16'd1023) test_state_next = T_READ_REQ1;

            // ---- 读寄存器序列 (两帧: 读命令 + 读数据) ----
            T_READ_REQ1:  test_state_next = T_READ_WAIT1;
            T_READ_WAIT1: if (spi_done) test_state_next = T_READ_GAP;
            T_READ_GAP:   if (gap_timer == 16'd127) test_state_next = T_READ_REQ2;
            T_READ_REQ2:  test_state_next = T_READ_WAIT2;
            T_READ_WAIT2: if (spi_done) test_state_next = T_READ_NEXT;
            T_READ_NEXT: begin
                if (reg_index == 3'd7)
                    test_state_next = T_CYCLE_DONE;
                else
                    test_state_next = T_READ_REQ1;
            end

            // ---- 一轮完成, 重新开始 ----
            T_CYCLE_DONE: if (gap_timer == 16'd2047) test_state_next = T_WRITE_REQ;

            default: test_state_next = T_IDLE;
        endcase
    end

    // =========================================================================
    // 数据通路: 控制 SPI 模块输入
    // =========================================================================
    always @(posedge clk_100m or negedge rst_n) begin
        if (!rst_n) begin
            spi_start    <= 1'b0;
            spi_rw       <= 1'b0;
            spi_reg_addr <= 4'd0;
            spi_reg_data <= 10'd0;
            reg_index    <= 3'd0;
            gap_timer    <= 16'd0;
            cycle_count  <= 24'd0;
        end else begin
            case (test_state)
                T_IDLE: begin
                    gap_timer <= gap_timer + 16'd1;
                    reg_index <= 3'd0;
                end

                // 发起写操作: rw=1 (Bit[15]=1=写, Bit[14]=0)
                T_WRITE_REQ: begin
                    spi_start    <= 1'b1;
                    spi_rw       <= 1'b1;    // 写操作
                    spi_reg_addr <= cfg_addr_lut;
                    spi_reg_data <= cfg_data_lut;
                end
                T_WRITE_WAIT: begin
                    spi_start <= 1'b0;
                end
                T_WRITE_NEXT: begin
                    reg_index <= reg_index + 3'd1;
                end

                // 帧间隔
                T_GAP: begin
                    gap_timer <= gap_timer + 16'd1;
                end

                // 读操作帧1: rw=0 (Bit[15]=0, Bit[14]=1=读)
                T_READ_REQ1: begin
                    spi_start    <= 1'b1;
                    spi_rw       <= 1'b0;    // 读命令
                    spi_reg_addr <= cfg_addr_lut;
                    spi_reg_data <= 10'd0;
                    gap_timer    <= 16'd0;
                end
                T_READ_WAIT1: begin
                    spi_start <= 1'b0;
                end
                T_READ_GAP: begin
                    gap_timer <= gap_timer + 16'd1;
                end

                // 读操作帧2: 虚拟写 (返回 SDO 数据)
                T_READ_REQ2: begin
                    spi_start    <= 1'b1;
                    spi_rw       <= 1'b1;    // 写操作 (让 ROIC 在 SDO 上输出数据)
                    spi_reg_addr <= cfg_addr_lut;
                    spi_reg_data <= cfg_data_lut;  // 写回原值
                    gap_timer    <= 16'd0;
                end
                T_READ_WAIT2: begin
                    spi_start <= 1'b0;
                end
                T_READ_NEXT: begin
                    reg_index <= reg_index + 3'd1;
                end

                // 一轮完成
                T_CYCLE_DONE: begin
                    reg_index   <= 3'd0;
                    gap_timer   <= gap_timer + 16'd1;
                    cycle_count <= cycle_count + 24'd1;
                end

                default: begin
                    spi_start <= 1'b0;
                end
            endcase
        end
    end

    // =========================================================================
    // LED 指示
    // LED0: SPI done 翻转 → 每次传输闪烁一次 (心跳)
    // LED1: 每轮测试完成翻转 (周期指示)
    // 注意: 黑鹰A704 LED 低电平点亮
    // =========================================================================
    reg led0_reg, led1_reg;
    reg old_spi_done;
    reg old_cycle_state;

    always @(posedge clk_100m or negedge rst_n) begin
        if (!rst_n) begin
            led0_reg         <= 1'b1;   // 灭
            led1_reg         <= 1'b1;   // 灭
            old_spi_done     <= 1'b0;
            old_cycle_state  <= 1'b0;
        end else begin
            old_spi_done    <= spi_done;
            old_cycle_state <= (test_state == T_CYCLE_DONE);

            // LED0: spi_done 上升沿翻转
            if (spi_done && !old_spi_done)
                led0_reg <= ~led0_reg;

            // LED1: 进入 T_CYCLE_DONE 时翻转
            if ((test_state == T_CYCLE_DONE) && !old_cycle_state)
                led1_reg <= ~led1_reg;
        end
    end

    assign led0 = led0_reg;
    assign led1 = led1_reg;

endmodule

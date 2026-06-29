`timescale 1ns/1ps

module tb_top;

reg         sys_clk;
reg         key;
reg         spi_sdo;

wire        roic_reset;
wire        sync;
wire        aclk;
wire        spi_cs;
wire        spi_sck;
wire        spi_sdi;
wire        cpv;
wire        stv1;
wire        stv2;
wire        oe1;
wire        oe2;
wire        ud;
wire        lr;
wire        mode1;
wire        mode2;
wire        sel;
wire        stv_mode;
wire        chip_sel1;
wire        chip_sel2;
wire        oepsn;
wire        frame_active;
wire        frame_done_o;
wire        line_done_o;
wire        ctrl_init_done_o;

wire        dclk_p;
wire        dclk_n;
wire        dclko_p_A;
wire        dclko_n_A;
wire        dout_p_A;
wire        dout_n_A;
wire        dout_p_B;
wire        dout_n_B;
wire [127:0] merged_burst;
wire [6:0]   merged_burst_index;
wire         merged_valid;
wire         header_ok;
wire         rx_line_done;

initial begin
    sys_clk = 1'b0;
    forever #5 sys_clk = ~sys_clk;  // 5ns 半周期 → 10ns 周期 → 100MHz
end

initial begin
    spi_sdo = 1'b0;     // placeholder: ROIC 未连接时读回 0
end

initial begin
    key = 1'b0;         // 按键按下（复位有效）
    #200;               // 保持 200ns
    key = 1'b1;         // 释放按键（复位释放）
    #1000;              // 等待稳定
    $display("Simulation start at %t", $time);
end

real sim_time_sec;
real frame_rate_sim;
integer total_frames = 2;
integer frame_cnt_display;

initial begin
    frame_cnt_display = 0;

    repeat (total_frames) begin
        @(posedge frame_done_o);
        frame_cnt_display = frame_cnt_display + 1;
        $display("Frame %d done at %t", frame_cnt_display, $time);
    end

    #500;

    sim_time_sec = $time / 1_000_000_000.0;
    frame_rate_sim = total_frames / sim_time_sec;

    $display("========================================");
    $display("Simulation finished at %t", $time);
    $display("Total frames: %d", total_frames);
    $display("Total simulation time: %.6f seconds", sim_time_sec);
    $display("Average frame rate: %.2f fps", frame_rate_sim);
    $display("========================================");
    $finish;
end

initial begin
    #10_000_000_000;   // 10s 超时
    $display("ERROR: Simulation timeout at %t", $time);
    $finish;
end

top #(
    .FRAME_LINES      (541  ),      // Normal模式最大541行
    .FRAME_GAP_CYCLES (100  ),      // 间隙 100 个时钟周期（100 × 20ns = 2µs @ 50MHz）
    .MODE_SELECT      (2'b00),      // Normal 模式
    .STV_DELAY_SEL    (2'b00),      // Short STV
    .SCAN_DIRECTION   (1'b0 ),      // 下移
    .OE_MASK_EN       (1'b0 )       // 无 OE 掩码
) u_top (
    .sys_clk           (sys_clk         ),
    .key               (key             ),
    .spi_sdo           (spi_sdo         ),
    .roic_reset        (roic_reset      ),
    .sync              (sync            ),
    .aclk              (aclk            ),
    .spi_cs            (spi_cs          ),
    .spi_sck           (spi_sck         ),
    .spi_sdi           (spi_sdi         ),
    .cpv               (cpv             ),
    .stv1              (stv1            ),
    .stv2              (stv2            ),
    .oe1               (oe1             ),
    .oe2               (oe2             ),
    .ud                (ud              ),
    .lr                (lr              ),
    .mode1             (mode1           ),
    .mode2             (mode2           ),
    .sel               (sel             ),
    .stv_mode          (stv_mode        ),
    .chip_sel1         (chip_sel1       ),
    .chip_sel2         (chip_sel2       ),
    .oepsn             (oepsn           ),
    .frame_active      (frame_active    ),
    .frame_done_o      (frame_done_o    ),
    .line_done_o       (line_done_o     ),
    .ctrl_init_done_o  (ctrl_init_done_o),
    .dclk_p            (dclk_p),
    .dclk_n            (dclk_n),
    .dclko_p_A         (dclko_p_A),
    .dclko_n_A         (dclko_n_A),
    .dout_p_A          (dout_p_A),
    .dout_n_A          (dout_n_A),
    .dout_p_B          (dout_p_B),
    .dout_n_B          (dout_n_B),
    .merged_burst      (merged_burst),
    .merged_burst_index(merged_burst_index),
    .merged_valid      (merged_valid),
    .header_ok         (header_ok),
    .rx_line_done      (rx_line_done)
);

// =========================================================================
// AFE LVDS echo clock loopback (DCLK → DCLKO, 模拟 AD71143 回波)
// =========================================================================
assign dclko_p_A = dclk_p;
assign dclko_n_A = dclk_n;

// DOUT = 0 (无 AFE 仿真模型, 数据读回全零)
assign dout_p_A = 1'b0;
assign dout_n_A = 1'b1;
assign dout_p_B = 1'b0;
assign dout_n_B = 1'b1;

endmodule

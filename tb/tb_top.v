`timescale 1ns/1ps

module tb_top;

reg         sys_clk;
reg         key;
reg         spi_sdo_p0;
reg         spi_sdo_p1;

wire        roic_reset_p0;
wire        roic_reset_p1;
wire        sync_p0;
wire        sync_p1;
wire        aclk_p0;
wire        aclk_p1;
wire        spi_cs_p0;
wire        spi_sck_p0;
wire        spi_sdi_p0;
wire        spi_cs_p1;
wire        spi_sck_p1;
wire        spi_sdi_p1;
wire        cpv;
wire        xao;
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

wire        dclk_p_A0;
wire        dclk_n_A0;
wire        dclko_p_A0;
wire        dclko_n_A0;
wire        dout_p_A0;
wire        dout_n_A0;
wire        dout_p_B0;
wire        dout_n_B0;
wire        dclk_p_A1;
wire        dclk_n_A1;
wire        dclko_p_A1;
wire        dclko_n_A1;
wire        dout_p_A1;
wire        dout_n_A1;
wire        dout_p_B1;
wire        dout_n_B1;
wire [255:0] merged_burst;
wire [6:0]   merged_burst_index;
wire         merged_valid;
wire         header_ok;
wire         rx_line_done;

initial begin
    sys_clk = 1'b0;
    forever #5 sys_clk = ~sys_clk;  // 5ns 半周期 → 10ns 周期 → 100MHz
end

initial begin
    spi_sdo_p0 = 1'b0;
    spi_sdo_p1 = 1'b0;     // placeholder: ROIC 未连接时读回 0
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
    .sys_clk            (sys_clk        ),
    .key                (key            ),
    .spi_sdo_p1         (spi_sdo_p1     ),
    .spi_sdo_p0         (spi_sdo_p0     ),
    .roic_reset_p0      (roic_reset_p0  ),
    .roic_reset_p1      (roic_reset_p1  ),
    .sync_p0            (sync_p0        ),
    .sync_p1            (sync_p1        ),
    .aclk_p0            (aclk_p0        ),
    .aclk_p1            (aclk_p1        ),
    .spi_cs_p1          (spi_cs_p1      ),
    .spi_cs_p0          (spi_cs_p0      ),
    .spi_sck_p1         (spi_sck_p1     ),
    .spi_sck_p0         (spi_sck_p0     ),
    .spi_sdi_p1         (spi_sdi_p1     ),
    .spi_sdi_p0         (spi_sdi_p0     ),
    .cpv_r              (cpv            ),
    .xao_r              (xao            ),
    .stv1_r             (stv1           ),
    .stv2_r             (stv2           ),
    .oe1_r              (oe1            ),
    .oe2_r              (oe2            ),
    .ud_r               (ud             ),
    .lr_r               (lr             ),
    .mode1_r            (mode1          ),
    .mode2_r            (mode2          ),
    .sel_r              (sel            ),
    .stv_mode_r         (stv_mode       ),
    .chip_sel1_r        (chip_sel1      ),
    .chip_sel2_r        (chip_sel2      ),
    .oepsn_r            (oepsn          ),
    .cpv_l              (cpv            ),
    .xao_l              (xao            ),
    .stv1_l             (stv1           ),
    .stv2_l             (stv2           ),
    .oe1_l              (oe1            ),
    .oe2_l              (oe2            ),
    .ud_l               (ud             ),
    .lr_l               (lr             ),
    .mode1_l            (mode1          ),
    .mode2_l            (mode2          ),
    .sel_l              (sel            ),
    .stv_mode_l         (stv_mode       ),
    .chip_sel1_l        (chip_sel1      ),
    .chip_sel2_l        (chip_sel2      ),
    .oepsn_l            (oepsn          ),
    .dclk_p_A0          (dclk_p_A0      ),
    .dclk_n_A0          (dclk_n_A0      ),
    .dclko_p_A0         (dclko_p_A0     ),
    .dclko_n_A0         (dclko_n_A0     ),
    .dout_p_A0          (dout_p_A0      ),
    .dout_n_A0          (dout_n_A0      ),
    .dout_p_B0          (dout_p_B0      ),
    .dout_n_B0          (dout_n_B0      ),
    .dclk_p_A1          (dclk_p_A1      ),
    .dclk_n_A1          (dclk_n_A1      ),
    .dclko_p_A1         (dclko_p_A1     ),
    .dclko_n_A1         (dclko_n_A1     ),
    .dout_p_A1          (dout_p_A1      ),
    .dout_n_A1          (dout_n_A1      ),
    .dout_p_B1          (dout_p_B1      ),
    .dout_n_B1          (dout_n_B1      ),
    .merged_burst       (merged_burst   ),
    .merged_burst_index (merged_burst_index),
    .merged_valid       (merged_valid   ),
    .header_ok          (header_ok      ),
    .rx_line_done       (rx_line_done   )
);

// =========================================================================
// AFE LVDS echo clock loopback (DCLK → DCLKO, 模拟 AD71143 回波)
// =========================================================================
assign dclko_p_A0 = dclk_p_A0;
assign dclko_n_A0 = dclk_n_A0;
assign dclko_p_A1 = dclk_p_A1;
assign dclko_n_A1 = dclk_n_A1;

// DOUT = 0 (无 AFE 仿真模型, 数据读回全零)
assign dout_p_A0 = 1'b0;
assign dout_n_A0 = 1'b1;
assign dout_p_B0 = 1'b0;
assign dout_n_B0 = 1'b1;
assign dout_p_A1 = 1'b0;
assign dout_n_A1 = 1'b1;
assign dout_p_B1 = 1'b0;
assign dout_n_B1 = 1'b1;

endmodule

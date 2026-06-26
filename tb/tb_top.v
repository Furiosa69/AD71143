`timescale 1ns/1ps

module tb_top;

reg         sys_clk;
reg         key;

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

initial begin
    sys_clk = 1'b0;
    forever #10 sys_clk = ~sys_clk;  // 10ns 半周期 → 20ns 周期 → 50MHz
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
integer total_frames = 10;
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
    #10_000_000_000;   // 10ms 超时（50MHz 下 10ms = 500,000 个周期）
    $display("ERROR: Simulation timeout at %t", $time);
    $finish;
end

top #(
    .FRAME_LINES      (541  ),      // Normal模式最大541行
    .FRAME_GAP_CYCLES (100  ),      // 间隙 100 个时钟周期（100 × 40ns = 4µs）
    .MODE_SELECT      (2'b00),      // Normal 模式
    .STV_DELAY_SEL    (2'b00),      // Short STV
    .SCAN_DIRECTION   (1'b0 ),      // 下移
    .OE_MASK_EN       (1'b0 )       // 无 OE 掩码
) u_top (
    .sys_clk        (sys_clk     ),
    .key            (key         ),
    .cpv            (cpv         ),
    .stv1           (stv1        ),
    .stv2           (stv2        ),
    .oe1            (oe1         ),
    .oe2            (oe2         ),
    .ud             (ud          ),
    .lr             (lr          ),
    .mode1          (mode1       ),
    .mode2          (mode2       ),
    .sel            (sel         ),
    .stv_mode       (stv_mode    ),
    .chip_sel1      (chip_sel1   ),
    .chip_sel2      (chip_sel2   ),
    .oepsn          (oepsn       ),
    .frame_active   (frame_active),
    .frame_done_o   (frame_done_o),
    .line_done_o    (line_done_o )
);

endmodule

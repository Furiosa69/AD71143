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
    forever #20 sys_clk = ~sys_clk;  // 20ns 周期 → 25MHz
end

initial begin
    key = 1'b0;         // 按键按下（复位有效）
    #100;               // 保持 100ns
    key = 1'b1;         // 释放按键（复位释放）
    #1000;              // 等待稳定
    $display("Simulation start at %t", $time);
end

initial begin
    // 等待 10 帧结束后退出
    repeat (10) begin
        @(posedge frame_done_o);
        $display("Frame done at %t", $time);
    end
    #500;
    $display("Simulation finished at %t", $time);
    $finish;
end

initial begin
    #1_000_000;   // 1ms 超时
    $display("ERROR: Simulation timeout at %t", $time);
    $finish;
end

top #(
    .FRAME_LINES      (8    ),      // 用 8 行快速仿真验证
    .FRAME_GAP_CYCLES (100  ),      // 间隙 100 个时钟周期
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

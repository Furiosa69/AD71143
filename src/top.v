module top #(
    parameter integer FRAME_LINES      = 541,
    parameter integer FRAME_GAP_CYCLES = 25_000,
    parameter [1:0]   MODE_SELECT      = 2'b00,
    parameter [1:0]   STV_DELAY_SEL    = 2'b00,
    parameter         SCAN_DIRECTION   = 1'b0,
    parameter         OE_MASK_EN       = 1'b0
)(
    input  wire sys_clk,
    input  wire key,

    output wire cpv,
    output wire stv1,
    output wire stv2,
    output wire oe1,
    output wire oe2,
    output wire ud,
    output wire lr,
    output wire mode1,
    output wire mode2,
    output wire sel,
    output wire stv_mode,
    output wire chip_sel1,
    output wire chip_sel2,
    output wire oepsn,

    output wire frame_active,
    output wire frame_done_o,
    output wire line_done_o
);

// ============================================================
// 复位信号（低有效）
// ============================================================
wire rst_n;
assign rst_n = key;

// ============================================================
// 状态机定义
// ============================================================
localparam [1:0] TOP_IDLE       = 2'd0;
localparam [1:0] TOP_START      = 2'd1;
localparam [1:0] TOP_WAIT_FRAME = 2'd2;
localparam [1:0] TOP_FRAME_GAP  = 2'd3;

reg [1:0]  top_state;
reg        frame_start;
reg        line_start;
reg [31:0] gap_cnt;

wire busy;
wire line_done;
wire frame_done;

assign frame_active  = busy;
assign frame_done_o  = frame_done;
assign line_done_o   = line_done;

// ============================================================
// 主状态机
// 顶层只负责发起一帧、等待驱动器完成整帧、插入帧间隔
// 行扫描循环由 nt39565d_gate_ctrl 内部完成
// ============================================================
always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        top_state   <= TOP_IDLE;
        frame_start <= 1'b0;
        line_start  <= 1'b0;
        gap_cnt     <= 32'd0;
    end else begin
        frame_start <= 1'b0;
        line_start  <= 1'b0;

        case (top_state)
            TOP_IDLE: begin
                gap_cnt    <= 32'd0;
                top_state  <= TOP_START;
            end

            TOP_START: begin
                frame_start <= 1'b1;
                top_state   <= TOP_WAIT_FRAME;
            end

            TOP_WAIT_FRAME: begin
                if (frame_done) begin
                    gap_cnt   <= 32'd0;
                    top_state <= TOP_FRAME_GAP;
                end
            end

            TOP_FRAME_GAP: begin
                if (gap_cnt >= FRAME_GAP_CYCLES - 1) begin
                    gap_cnt   <= 32'd0;
                    top_state <= TOP_START;
                end else begin
                    gap_cnt <= gap_cnt + 1'b1;
                end
            end

            default: top_state <= TOP_IDLE;
        endcase
    end
end

// ============================================================
// NT39565D Gate Driver 控制模块
// ============================================================
nt39565d_gate_ctrl u_nt39565d (
    .clk            (sys_clk),
    .rst_n          (rst_n),
    .frame_start    (frame_start),
    .line_start     (line_start),
    .xao_emergency  (1'b0),               // 先固定为0（不触发紧急关断）
    .line_count     (FRAME_LINES[9:0]),   // 直接传参数给模块
    .scan_direction (SCAN_DIRECTION),
    .mode_select    (MODE_SELECT),
    .stv_delay_sel  (STV_DELAY_SEL),
    .oe_mask_en     (OE_MASK_EN),
    .cpv            (cpv),
    .stv1           (stv1),
    .stv2           (stv2),
    .oe1            (oe1),
    .oe2            (oe2),
    .ud             (ud),
    .lr             (lr),
    .mode1          (mode1),
    .mode2          (mode2),
    .sel            (sel),
    .stv_mode       (stv_mode),
    .chip_sel1      (chip_sel1),
    .chip_sel2      (chip_sel2),
    .oepsn          (oepsn),
    .busy           (busy),
    .line_done      (line_done),
    .frame_done     (frame_done)
);

endmodule

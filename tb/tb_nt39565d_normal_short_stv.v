`timescale 1ns/1ps

module tb_nt39565d_normal_short_stv;
    reg        clk;
    reg        rst_n;
    reg        frame_start;
    reg        line_start;
    reg        xao_emergency;
    reg [9:0]  line_count;
    reg        scan_direction;
    reg [1:0]  mode_select;
    reg [1:0]  stv_delay_sel;
    reg        oe_mask_en;

    wire cpv;
    wire stv1;
    wire stv2;
    wire oe1;
    wire oe2;
    wire ud;
    wire lr;
    wire mode1;
    wire mode2;
    wire sel;
    wire stv_mode;
    wire chip_sel1;
    wire chip_sel2;
    wire oepsn;
    wire busy;
    wire line_done;
    wire frame_done;

    nt39565d_gate_ctrl #(
        .CLK_FREQ_MHZ(100),
        .CPV_PERIOD_US(1),
        .CPV_PW_US_X10(2),
        .STV_SETUP_US_X10(2),
        .STV_HOLD_US_X10(2),
        .OE_PW_US_X10(1),
        .XAO_DELAY_US(1),
        .OUT_CH_NORMAL(8),
        .OUT_CH_2G(8),
        .DEFAULT_MODE_SEL(0),
        .SCAN_DIRECTION(1'b0),
        .USE_DUAL_STV(1'b0)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .frame_start(frame_start),
        .line_start(line_start),
        .xao_emergency(xao_emergency),
        .line_count(line_count),
        .scan_direction(scan_direction),
        .mode_select(mode_select),
        .stv_delay_sel(stv_delay_sel),
        .oe_mask_en(oe_mask_en),
        .cpv(cpv),
        .stv1(stv1),
        .stv2(stv2),
        .oe1(oe1),
        .oe2(oe2),
        .ud(ud),
        .lr(lr),
        .mode1(mode1),
        .mode2(mode2),
        .sel(sel),
        .stv_mode(stv_mode),
        .chip_sel1(chip_sel1),
        .chip_sel2(chip_sel2),
        .oepsn(oepsn),
        .busy(busy),
        .line_done(line_done),
        .frame_done(frame_done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("tb_nt39565d_normal_short_stv.vcd");
        $dumpvars(0, tb_nt39565d_normal_short_stv);

        rst_n = 1'b0;
        frame_start = 1'b0;
        line_start = 1'b0;
        xao_emergency = 1'b0;
        line_count = 10'd4;
        scan_direction = 1'b0;
        mode_select = 2'b00;
        stv_delay_sel = 2'b00;
        oe_mask_en = 1'b0;

        #40;
        rst_n = 1'b1;
        #20;

        frame_start = 1'b1;
        #10;
        frame_start = 1'b0;


        wait(frame_done);
        #40;
        $finish;
    end

    initial begin
        #7000;
        $fatal(1, "Timeout: normal short STV simulation did not finish");
    end
endmodule

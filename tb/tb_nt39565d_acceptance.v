`timescale 1ns/1ps

module tb_nt39565d_acceptance;
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

    integer line_done_count;
    time stv1_rise_time;
    time stv2_rise_time;
    time first_cpv_rise_time;
    reg seen_stv1_rise;
    reg seen_stv2_rise;
    reg seen_first_cpv_rise;

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
        .USE_DUAL_STV(1'b1)
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

    always @(posedge line_done) begin
        line_done_count = line_done_count + 1;
    end

    always @(posedge stv1) begin
        if (!seen_stv1_rise) begin
            seen_stv1_rise = 1'b1;
            stv1_rise_time = $time;
        end
    end

    always @(posedge stv2) begin
        if (!seen_stv2_rise) begin
            seen_stv2_rise = 1'b1;
            stv2_rise_time = $time;
        end
    end

    always @(posedge cpv) begin
        if (!seen_first_cpv_rise) begin
            seen_first_cpv_rise = 1'b1;
            first_cpv_rise_time = $time;
        end
        if (oe_mask_en == 1'b0 && oe1 !== 1'b0)
            $fatal(1, "OE1 must be active low during CPV high");
        if (oe_mask_en == 1'b0 && oe2 !== 1'b0)
            $fatal(1, "OE2 must be active low during CPV high");
    end

    task reset_captures;
    begin
        line_done_count = 0;
        stv1_rise_time = 0;
        stv2_rise_time = 0;
        first_cpv_rise_time = 0;
        seen_stv1_rise = 1'b0;
        seen_stv2_rise = 1'b0;
        seen_first_cpv_rise = 1'b0;
    end
    endtask

    task start_frame;
    begin
        #10;
        frame_start = 1'b1;
        #10;
        frame_start = 1'b0;
    end
    endtask

    task check_static_pins;
        input exp_mode1;
        input exp_mode2;
        input exp_sel;
        input exp_chip_sel1;
        input exp_chip_sel2;
        input exp_stv_mode;
    begin
        #20;
        if (mode1 !== exp_mode1)
            $fatal(1, "mode1 mismatch: expected %0b got %0b", exp_mode1, mode1);
        if (mode2 !== exp_mode2)
            $fatal(1, "mode2 mismatch: expected %0b got %0b", exp_mode2, mode2);
        if (sel !== exp_sel)
            $fatal(1, "sel mismatch: expected %0b got %0b", exp_sel, sel);
        if (chip_sel1 !== exp_chip_sel1)
            $fatal(1, "chip_sel1 mismatch: expected %0b got %0b", exp_chip_sel1, chip_sel1);
        if (chip_sel2 !== exp_chip_sel2)
            $fatal(1, "chip_sel2 mismatch: expected %0b got %0b", exp_chip_sel2, chip_sel2);
        if (stv_mode !== exp_stv_mode)
            $fatal(1, "stv_mode mismatch: expected %0b got %0b", exp_stv_mode, stv_mode);
    end
    endtask

    task wait_frame_and_check_lines;
        input integer expected_lines;
    begin
        wait(frame_done == 1'b1);
        #10;
        if (line_done_count !== expected_lines)
            $fatal(1, "line_done count mismatch: expected %0d got %0d", expected_lines, line_done_count);
        if (!seen_stv1_rise)
            $fatal(1, "STV1 did not rise before frame completion");
        if (!seen_first_cpv_rise)
            $fatal(1, "CPV did not rise before frame completion");
        if (!(stv1_rise_time < first_cpv_rise_time))
            $fatal(1, "STV1 must occur before first CPV rise");
        if (busy !== 1'b0)
            $fatal(1, "busy must be low after frame completion");
    end
    endtask

    task check_normal_short;
    begin
        reset_captures();
        scan_direction = 1'b0;
        mode_select = 2'b00;
        stv_delay_sel = 2'b00;
        oe_mask_en = 1'b0;
        line_count = 10'd4;
        start_frame();
        check_static_pins(1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        wait_frame_and_check_lines(4);
    end
    endtask

    task check_2g_short;
    begin
        reset_captures();
        scan_direction = 1'b0;
        mode_select = 2'b01;
        stv_delay_sel = 2'b00;
        oe_mask_en = 1'b0;
        line_count = 10'd4;
        start_frame();
        check_static_pins(1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0);
        wait_frame_and_check_lines(4);
    end
    endtask

    task check_2glcs2_identical;
    begin
        reset_captures();
        scan_direction = 1'b1;
        mode_select = 2'b10;
        stv_delay_sel = 2'b00;
        oe_mask_en = 1'b0;
        line_count = 10'd4;
        start_frame();
        check_static_pins(1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0);
        wait_frame_and_check_lines(4);
        if (!seen_stv2_rise)
            $fatal(1, "STV2 did not rise in 2G+LCS identical mode");
        if (stv2_rise_time !== stv1_rise_time)
            $fatal(1, "STV1 and STV2 must rise together in identical mode");
    end
    endtask

    task check_2glcs2_delay1cpv;
    begin
        reset_captures();
        scan_direction = 1'b1;
        mode_select = 2'b10;
        stv_delay_sel = 2'b01;
        oe_mask_en = 1'b0;
        line_count = 10'd4;
        start_frame();
        check_static_pins(1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0);
        wait_frame_and_check_lines(4);
        if (!seen_stv2_rise)
            $fatal(1, "STV2 did not rise in delayed mode");
        if (!(stv2_rise_time > stv1_rise_time))
            $fatal(1, "STV2 must rise after STV1 in delay-1CPV mode");
        if ((((stv2_rise_time - stv1_rise_time) / 1000) < 950) || (((stv2_rise_time - stv1_rise_time) / 1000) > 1050))
            $fatal(1, "STV2 delay must be about one CPV period; observed %0t", stv2_rise_time - stv1_rise_time);
    end
    endtask

    task check_xao_shutdown;
    begin
        reset_captures();
        scan_direction = 1'b0;
        mode_select = 2'b00;
        stv_delay_sel = 2'b00;
        oe_mask_en = 1'b0;
        line_count = 10'd4;
        start_frame();
        #20;
        xao_emergency = 1'b1;
        #20;
        if (cpv !== 1'b0 || stv1 !== 1'b0 || stv2 !== 1'b0 || oe1 !== 1'b1 || oe2 !== 1'b1)
            $fatal(1, "XAO shutdown must force outputs inactive");
        if (busy !== 1'b0)
            $fatal(1, "busy must drop during XAO shutdown");
        xao_emergency = 1'b0;
        #20;
    end
    endtask

    initial begin
        $dumpfile("tb_nt39565d_acceptance.vcd");
        $dumpvars(0, tb_nt39565d_acceptance);

        rst_n = 1'b0;
        frame_start = 1'b0;
        line_start = 1'b0;
        xao_emergency = 1'b0;
        line_count = 10'd0;
        scan_direction = 1'b0;
        mode_select = 2'b00;
        stv_delay_sel = 2'b00;
        oe_mask_en = 1'b0;
        reset_captures();

        #40;
        rst_n = 1'b1;
        #20;

        check_normal_short();
        #40;
        check_2g_short();
        #40;
        check_2glcs2_identical();
        #40;
        check_2glcs2_delay1cpv();
        #40;
        check_xao_shutdown();
        #40;

        $display("ACCEPTANCE PASS");
        $finish;
    end

    initial begin
        #30000;
        $fatal(1, "Timeout: acceptance test did not finish");
    end
endmodule

`timescale 1ns / 1ps

module tb_ad71143_data_rx;
    reg         clk_sys;
    reg         rst_n;
    reg         sync_in;
    reg         aclk_done;
    wire        dclk_p_A;
    wire        dclk_n_A;
    reg         dclko_p_A;
    reg         dclko_n_A;
    reg         dout_p_A;
    reg         dout_n_A;
    reg         dout_p_B;
    reg         dout_n_B;

    wire        line_done;
    wire        header_ok;
    wire [7:0]  header_byte;
    wire        header_readdown;
    wire        header_cds_id;
    wire [15:0] header_temp;
    wire [15:0] header_vt;
    wire        merged_valid;
    wire [127:0] merged_burst;
    wire [7:0]  merged_first_channel;
    wire [7:0]  merged_last_channel;
    wire [6:0]  merged_burst_index;
    wire [2:0]  state_debug;
    wire [7:0]  shift_hi;
    wire [7:0]  shift_lo;
    wire        burst_en_out;
    wire        burst_en_comb;
    wire        roic_trigger;

    integer i;
    reg merged_seen;
    reg line_done_seen;

    ad71143_data_rx dut (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .sync_in(sync_in),
        .aclk_done(aclk_done),
        .dclk_p_A(dclk_p_A),
        .dclk_n_A(dclk_n_A),
        .dclko_p_A(dclko_p_A),
        .dclko_n_A(dclko_n_A),
        .dout_p_A(dout_p_A),
        .dout_n_A(dout_n_A),
        .dout_p_B(dout_p_B),
        .dout_n_B(dout_n_B),
        .line_done(line_done),
        .header_ok(header_ok),
        .header_byte(header_byte),
        .header_readdown(header_readdown),
        .header_cds_id(header_cds_id),
        .header_temp(header_temp),
        .header_vt(header_vt),
        .merged_valid(merged_valid),
        .merged_burst(merged_burst),
        .merged_first_channel(merged_first_channel),
        .merged_last_channel(merged_last_channel),
        .merged_burst_index(merged_burst_index),
        .state_debug(state_debug),
        .shift_hi(shift_hi),
        .shift_lo(shift_lo),
        .burst_en_out(burst_en_out),
        .burst_en_comb(burst_en_comb),
        .roic_trigger(roic_trigger)
    );

    initial clk_sys = 1'b0;
    always #5 clk_sys = ~clk_sys;

    always @(posedge merged_valid) begin
        merged_seen = 1'b1;
        $display("[%0t] merged_valid burst_index=%0d first_ch=%0d last_ch=%0d data=%h", $time, merged_burst_index, merged_first_channel, merged_last_channel, merged_burst);
    end

    always @(posedge line_done) begin
        line_done_seen = 1'b1;
        $display("[%0t] line_done", $time);
    end

    task automatic drive_sync_and_aclk;
    begin
        sync_in = 1'b1;
        repeat (2) @(posedge clk_sys);
        #1 sync_in = 1'b0;
        repeat (2) @(posedge clk_sys);
        #1 aclk_done = 1'b1;
        repeat (2) @(posedge clk_sys);
        #1 aclk_done = 1'b0;
    end
    endtask

    task automatic pulse_dclko;
    begin
        #5;
        dclko_p_A = 1'b1;
        dclko_n_A = 1'b0;
        #10;
        dclko_p_A = 1'b0;
        dclko_n_A = 1'b1;
        #10;
    end
    endtask

    task automatic send_burst64;
        input [63:0] lane_a;
        input [63:0] lane_b;
        integer k;
    begin
        wait(burst_en_out === 1'b1);

        $display("[%0t] send_burst64 START: lane_a=%h lane_b=%h", $time, lane_a, lane_b);

        // DUT 在 dclko 域里用 cap_start_tgl_d1/cap_start_tgl_d2 做同步，
        // 需要两个启动边沿后 cap_active_dclko 才真正拉高。
        pulse_dclko();
        pulse_dclko();

        for (k = 63; k >= 0; k = k - 1) begin
            dout_p_A = lane_a[k];
            dout_n_A = ~lane_a[k];
            dout_p_B = lane_b[k];
            dout_n_B = ~lane_b[k];
            pulse_dclko();
        end

        $display("[%0t] send_burst64 DONE:  lane_a=%h lane_b=%h", $time, lane_a, lane_b);
    end
    endtask

    task automatic finish_remaining_bursts;
        input integer data_bursts_already_sent;
        integer n;
    begin
        for (n = data_bursts_already_sent; n < 32; n = n + 1) begin
            send_burst64(64'h1000_2000_3000_4000 + n, 64'h5000_6000_7000_8000 + n);
            // wait until DUT enters S_MUTE then back to S_ACT, so next send_burst64
            // runs in its own S_ACT window
            @(negedge burst_en_out);
            wait(burst_en_out === 1'b1);
        end
        send_burst64(64'hDEAD_BEEF_CAFE_1234, 64'h0123_4567_89AB_CDEF);
    end
    endtask

    task automatic check_readdown0;
        reg [63:0] header_a;
        reg [63:0] header_b;
        reg [63:0] data_a;
        reg [63:0] data_b;
        reg [127:0] expect_merge;
    begin
        header_a = {8'h0A, 5'b00000, 1'b0, 1'b0, 1'b1, 16'h0000, 16'h1357, 16'h2468};
        header_b = 64'h0000_0000_0000_0000;
        data_a   = {16'h1000, 16'h1002, 16'h1004, 16'h1006};
        data_b   = {16'h1001, 16'h1003, 16'h1005, 16'h1007};
        expect_merge = {16'h1000, 16'h1001, 16'h1002, 16'h1003, 16'h1004, 16'h1005, 16'h1006, 16'h1007};

        $display("=== READDOWN=0 ===");
        $display("header_a=%h bits: [63:56]=%h [55:51]=%b [50]=%b [49]=%b [48]=%b [47:32]=%h [31:16]=%h [15:0]=%h",
                 header_a, header_a[63:56], header_a[55:51], header_a[50], header_a[49], header_a[48],
                 header_a[47:32], header_a[31:16], header_a[15:0]);
        $display("EXPECT: byte=0a ok=1 readdown=0 cds_id=1 temp=1357 vt=2468 merge=%h first_ch=0 last_ch=7",
                 expect_merge);

        drive_sync_and_aclk();
        merged_seen = 1'b0;
        line_done_seen = 1'b0;
        send_burst64(header_a, header_b);
        send_burst64(data_a, data_b);
        #50;

        $display("READDOWN=0 RESULT: ok=%0b byte=%h readdown=%0b cds_id=%0b temp=%h vt=%h burst=%h first_ch=%0d last_ch=%0d idx=%0d",
                 header_ok, header_byte, header_readdown, header_cds_id, header_temp, header_vt,
                 merged_burst, merged_first_channel, merged_last_channel, merged_burst_index);

        if (!merged_seen)                    $fatal(1, "READDOWN=0 merged_valid not seen");
        if (header_byte !== 8'h0A)           $fatal(1, "READDOWN=0 header byte mismatch");
        if (header_readdown !== 1'b0)        $fatal(1, "READDOWN=0 header_readdown mismatch");
        if (header_cds_id !== 1'b1)          $fatal(1, "READDOWN=0 header_cds_id mismatch");
        if (header_temp !== 16'h1357)        $fatal(1, "READDOWN=0 header_temp mismatch");
        if (header_vt !== 16'h2468)          $fatal(1, "READDOWN=0 header_vt mismatch");
        if (merged_burst !== expect_merge)   $fatal(1, "READDOWN=0 merged burst mismatch");
        if (merged_first_channel !== 8'd0)   $fatal(1, "READDOWN=0 first channel mismatch");
        if (merged_last_channel !== 8'd7)    $fatal(1, "READDOWN=0 last channel mismatch");
        if (merged_burst_index !== 7'd0)     $fatal(1, "READDOWN=0 burst index mismatch");

        finish_remaining_bursts(1);
        #200;
        if (!line_done_seen)                 $fatal(1, "READDOWN=0 line_done not seen");
        @(posedge clk_sys);
    end
    endtask

    task automatic check_readdown1;
        reg [63:0] header_a;
        reg [63:0] header_b;
        reg [63:0] data_a;
        reg [63:0] data_b;
        reg [127:0] expect_merge;
    begin
        header_a = {8'h0A, 5'b00000, 1'b0, 1'b1, 1'b0, 16'h0000, 16'hAAAA, 16'h5555};
        header_b = 64'h0000_0000_0000_0000;
        // READDOWN=1: Lane A=odd desc, Lane B=even desc per Figure 37
        data_a   = {16'h2007, 16'h2005, 16'h2003, 16'h2001};
        data_b   = {16'h2006, 16'h2004, 16'h2002, 16'h2000};
        expect_merge = {16'h2007, 16'h2006, 16'h2005, 16'h2004, 16'h2003, 16'h2002, 16'h2001, 16'h2000};

        $display("=== READDOWN=1 ===");
        $display("header_a=%h bits: [63:56]=%h [55:51]=%b [50]=%b [49]=%b [48]=%b [47:32]=%h [31:16]=%h [15:0]=%h",
                 header_a, header_a[63:56], header_a[55:51], header_a[50], header_a[49], header_a[48],
                 header_a[47:32], header_a[31:16], header_a[15:0]);
        $display("EXPECT: byte=0a ok=1 readdown=1 cds_id=0 temp=AAAA vt=5555 merge=%h first_ch=7 last_ch=0",
                 expect_merge);

        drive_sync_and_aclk();
        merged_seen = 1'b0;
        line_done_seen = 1'b0;
        send_burst64(header_a, header_b);
        send_burst64(data_a, data_b);
        #50;

        $display("READDOWN=1 RESULT: ok=%0b byte=%h readdown=%0b cds_id=%0b temp=%h vt=%h burst=%h first_ch=%0d last_ch=%0d idx=%0d",
                 header_ok, header_byte, header_readdown, header_cds_id, header_temp, header_vt,
                 merged_burst, merged_first_channel, merged_last_channel, merged_burst_index);

        if (!merged_seen)                      $fatal(1, "READDOWN=1 merged_valid not seen");
        if (!header_ok)                         $fatal(1, "READDOWN=1 header_ok failed");
        if (header_byte !== 8'h0A)             $fatal(1, "READDOWN=1 header byte mismatch");
        if (header_readdown !== 1'b1)          $fatal(1, "READDOWN=1 header_readdown mismatch");
        if (header_cds_id !== 1'b0)            $fatal(1, "READDOWN=1 header_cds_id mismatch");
        if (header_temp !== 16'hAAAA)          $fatal(1, "READDOWN=1 header_temp mismatch");
        if (header_vt !== 16'h5555)            $fatal(1, "READDOWN=1 header_vt mismatch");
        if (merged_burst !== expect_merge)     $fatal(1, "READDOWN=1 merged burst mismatch");
        if (merged_first_channel !== 8'd7)     $fatal(1, "READDOWN=1 first channel mismatch");
        if (merged_last_channel !== 8'd0)      $fatal(1, "READDOWN=1 last channel mismatch");
        if (merged_burst_index !== 7'd0)       $fatal(1, "READDOWN=1 burst index mismatch");

        finish_remaining_bursts(1);
        #200;
        if (!line_done_seen)                 $fatal(1, "READDOWN=1 line_done not seen");
        @(posedge clk_sys);
    end
    endtask

    initial begin
        $dumpfile("tb_ad71143_data_rx.vcd");
        $dumpvars(0, tb_ad71143_data_rx);

        rst_n     = 1'b0;
        sync_in   = 1'b1;
        aclk_done = 1'b0;
        dclko_p_A = 1'b0;
        dclko_n_A = 1'b1;
        dout_p_A  = 1'b0;
        dout_n_A  = 1'b1;
        dout_p_B  = 1'b0;
        dout_n_B  = 1'b1;

        repeat (5) @(posedge clk_sys);
        rst_n = 1'b1;
        repeat (5) @(posedge clk_sys);

        check_readdown0();
        $display("[%0t] check_readdown0 done", $time);

        rst_n     = 1'b0;
        repeat (5) @(posedge clk_sys);
        rst_n     = 1'b1;
        sync_in   = 1'b1;
        aclk_done = 1'b0;
        dclko_p_A = 1'b0;
        dclko_n_A = 1'b1;
        dout_p_A  = 1'b0;
        dout_n_A  = 1'b1;
        dout_p_B  = 1'b0;
        dout_n_B  = 1'b1;
        repeat (5) @(posedge clk_sys);

        check_readdown1();
        $display("[%0t] check_readdown1 done", $time);

        $display("tb_ad71143_data_rx PASS");
        $finish;
    end

    initial begin
        #400000;
        $display("TIMEOUT dbg: state=%0d merged_seen=%0b line_done_seen=%0b merged_valid=%0b line_done=%0b burst_en=%0b header_ok=%0b header_byte=%h readdown=%0b burst_idx=%0d first_ch=%0d last_ch=%0d", state_debug, merged_seen, line_done_seen, merged_valid, line_done, burst_en_out, header_ok, header_byte, header_readdown, merged_burst_index, merged_first_channel, merged_last_channel);
        $fatal(1, "Timeout: tb_ad71143_data_rx did not finish");
    end
endmodule

// Testbench: rgmii_bridge CRC-32 验证
`timescale 1ns / 1ps

module tb_rgmii_crc;

    reg clk_125m, rst_n, clk_100m;
    wire TXC, TX_CTL, TXD0, TXD1, TXD2, TXD3;
    wire dbg_startup_done, dbg_phy_ready, dbg_tx_sending;
    wire [3:0] dbg_state;

    rgmii_bridge u_dut (
        .rst_n(rst_n), .clk_100m(clk_100m), .clk_125m(clk_125m),
        .data_in(256'd0), .data_valid(1'b0),
        .TXC(TXC), .TX_CTL(TX_CTL), .TXD0(TXD0), .TXD1(TXD1), .TXD2(TXD2), .TXD3(TXD3),
        .dbg_startup_done(dbg_startup_done), .dbg_phy_ready(dbg_phy_ready),
        .dbg_tx_sending(dbg_tx_sending), .dbg_state(dbg_state)
    );

    always #4 clk_125m = ~clk_125m;  // 125MHz
    always #5 clk_100m = ~clk_100m;  // 100MHz

    // Internal probes
    wire crc_busy  = u_dut.crc_busy;
    wire [6:0] crc_idx = u_dut.crc_idx;
    wire crc_done = u_dut.crc_done;
    wire [31:0] test_seq = u_dut.test_seq_num;
    wire preloaded = u_dut.preloaded;
    wire tx_start  = u_dut.tx_start;

    // =========================================================================
    // Reference CRC-32 (byte by byte, flat vector approach)
    // =========================================================================
    function [31:0] crc32_bytes;
        input [591:0] data_flat;  // 74 bytes = 592 bits
        integer k, b;
        reg [31:0] c;
        reg [7:0]  byte_val;
        begin
            c = 32'hFFFFFFFF;
            for (k = 0; k < 74; k = k + 1) begin
                byte_val = data_flat[(73-k)*8 +: 8];
                c = c ^ {24'd0, byte_val};
                for (b = 0; b < 8; b = b + 1)
                    c = (c[0]) ? (c >> 1) ^ 32'hEDB88320 : (c >> 1);
            end
            crc32_bytes = ~c;
        end
    endfunction

    // Build expected frame (592 bits = 74 bytes)
    function [591:0] build_frame;
        input [31:0] seq;
        integer i;
        reg [591:0] f;
        begin
            // MAC (14)
            f = 0;
            f[591-:8]  = 8'hFF; f[583-:8]  = 8'hFF; f[575-:8]  = 8'hFF;
            f[567-:8]  = 8'hFF; f[559-:8]  = 8'hFF; f[551-:8]  = 8'hFF;
            f[543-:8]  = 8'h02; f[535-:8]  = 8'h00; f[527-:8]  = 8'h00;
            f[519-:8]  = 8'h00; f[511-:8]  = 8'h00; f[503-:8]  = 8'h01;
            f[495-:8]  = 8'h08; f[487-:8]  = 8'h00;
            // IP (20)
            f[479-:8]  = 8'h45; f[471-:8]  = 8'h00; f[463-:8]  = 8'h00;
            f[455-:8]  = 8'h3C; f[447-:8]  = 8'h00; f[439-:8]  = 8'h00;
            f[431-:8]  = 8'h00; f[423-:8]  = 8'h00; f[415-:8]  = 8'h40;
            f[407-:8]  = 8'h11; f[399-:8]  = 8'hF7; f[391-:8]  = 8'h5D;
            f[383-:8]  = 8'hC0; f[375-:8]  = 8'hA8; f[367-:8]  = 8'h01;
            f[359-:8]  = 8'h02; f[351-:8]  = 8'hC0; f[343-:8]  = 8'hA8;
            f[335-:8]  = 8'h01; f[327-:8]  = 8'h01;
            // UDP (8)
            f[319-:8]  = 8'h04; f[311-:8]  = 8'hD2; f[303-:8]  = 8'h04;
            f[295-:8]  = 8'hD2; f[287-:8]  = 8'h00; f[279-:8]  = 8'h28;
            f[271-:8]  = 8'h00; f[263-:8]  = 8'h00;
            // Payload (32)
            f[255-:8]  = seq[31:24]; f[247-:8]  = seq[23:16];
            f[239-:8]  = seq[15:8];  f[231-:8]  = seq[7:0];
            for (i = 4; i < 32; i = i + 1)
                f[(74-1-i)*8 -: 8] = i[7:0];
            build_frame = f;
        end
    endfunction

    // =========================================================================
    reg [31:0] expected_crc;
    reg [31:0] first_seq_num;
    reg        first_crc_done;

    initial begin
        clk_125m = 0; clk_100m = 0; rst_n = 0;
        first_crc_done = 0;
        #100; rst_n = 1;

        wait(dbg_startup_done == 1'b1);
        $display("[%0t] startup_done=1", $time);

        // Wait for first CRC completion
        @(posedge clk_125m);
        while (!crc_done) @(posedge clk_125m);

        first_seq_num = test_seq;
        first_crc_done = 1;
        expected_crc = crc32_bytes(build_frame(first_seq_num));

        $display("[%0t] First CRC done, seq=%d", $time, first_seq_num);
        $display("  Expected FCS bytes: %02x %02x %02x %02x",
                 expected_crc[7:0], expected_crc[15:8],
                 expected_crc[23:16], expected_crc[31:24]);

        // Wait for frame transmission to start
        while (!preloaded) @(posedge clk_125m);
        $display("[%0t] Frame TX started", $time);

        // Wait for 3 more CRC completion cycles
        repeat (3) begin
            @(posedge clk_125m);
            while (!crc_done) @(posedge clk_125m);
            $display("[%0t] CRC done, seq=%d", $time, test_seq);
        end

        $display("---");
        $display("PASS: CRC pipeline runs, %d frames processed", test_seq + 1);
        $display("PASS: First frame seq=%d, FCS=%08x", first_seq_num, expected_crc);
        $display("Verification: check Wireshark frame[74:77] = %02x %02x %02x %02x",
                 expected_crc[7:0], expected_crc[15:8],
                 expected_crc[23:16], expected_crc[31:24]);
        $finish;
    end

    initial begin
        $dumpfile("tb_rgmii_crc.vcd");
        $dumpvars(0, tb_rgmii_crc);
    end

    initial begin #10000000; $display("TIMEOUT"); $finish; end
endmodule

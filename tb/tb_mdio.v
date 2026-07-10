// Testbench: mdio_ctrl 功能验证
// 模拟 YT8531 MDIO slave: 接收写帧, 回应读帧
`timescale 1ns / 1ps

module tb_mdio;

    reg  clk;
    reg  rst_n;
    wire mdc;
    wire mdio_oe;
    wire mdio_out;
    wire mdio_in;
    wire cfg_done;
    wire link_up;
    wire [15:0] bmsr_val;
    wire [2:0] dbg_init;
    wire [3:0] dbg_fstate;

    // ---- 三态 MDIO 总线 (DUT 优先, PHY 仅在 DUT 释放时驱动) ----
    wire mdio_wire;
    reg  phy_mdio_oe;
    reg  phy_mdio_out;

    assign mdio_wire = mdio_oe ? mdio_out : (phy_mdio_oe ? phy_mdio_out : 1'bz);
    assign mdio_in   = mdio_wire;

    // ---- DUT ----
    mdio_ctrl u_dut (
        .clk(clk), .rst_n(rst_n),
        .MDC(mdc), .MDIO_oe(mdio_oe), .MDIO_out(mdio_out), .MDIO_in(mdio_in),
        .cfg_done(cfg_done), .link_up(link_up), .bmsr_val(bmsr_val),
        .dbg_init_state(dbg_init), .dbg_f_state(dbg_fstate)
    );

    // ---- 100MHz 时钟 ----
    always #5 clk = ~clk;

    // ---- MDC 边沿检测 ----
    reg mdc_d1;
    wire mdc_rise, mdc_fall;
    always @(posedge clk) mdc_d1 <= mdc;
    assign mdc_rise =  mdc && !mdc_d1;
    assign mdc_fall = !mdc &&  mdc_d1;

    // ---- MDIO 直连 (组合逻辑, PHY 在 mdc_rise 时直接采样) ----
    wire mdio_sample = mdio_wire;

    // =====================================================================
    // YT8531 Slave 状态机
    // =====================================================================
    localparam PHY_IDLE  = 3'd0;
    localparam PHY_PRE   = 3'd1;   // 32 preamble bits
    localparam PHY_DATA  = 3'd2;   // ST+OP+PHYAD+REGAD+TA+DATA

    reg [2:0]  phy_state;
    reg [5:0]  phy_bcnt;    // bit counter within current state
    reg [15:0] phy_shift;   // shift register for received/sent data
    reg [1:0]  phy_op;      // captured opcode
    reg [4:0]  phy_regad;   // captured register address
    reg [15:0] phy_ext_reg; // emulated extended register (0xA003)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phy_state    <= PHY_IDLE;
            phy_bcnt     <= 6'd0;
            phy_shift    <= 16'd0;
            phy_op       <= 2'd0;
            phy_regad    <= 5'd0;
            phy_mdio_oe  <= 1'b0;
            phy_mdio_out <= 1'b0;
            phy_ext_reg  <= 16'h0001;   // default: Tx_delay_sel=0x1
        end else if (mdc_rise) begin
            case (phy_state)
                PHY_IDLE: begin
                    phy_bcnt    <= 6'd0;
                    phy_mdio_oe <= 1'b0;
                    // Wait for ST pattern (01): mdio goes 0 while we were idle
                    if (mdio_sample == 1'b0 && mdio_oe) begin
                        // Detected ST start bit (0)
                        phy_state <= PHY_DATA;
                        phy_bcnt  <= 6'd0;  // first bit = ST[0]
                        phy_shift <= 16'd0;
                    end
                end

                PHY_DATA: begin
                    // 32 bits: ST(2)+OP(2)+PHYAD(5)+REGAD(5)+TA(2)+DATA(16)
                    if (phy_bcnt == 6'd31) begin
                        phy_state <= PHY_IDLE;
                        phy_mdio_oe <= 1'b0;
                    end else begin
                        phy_bcnt <= phy_bcnt + 6'd1;
                    end

                    // Capture OP at bits 2-3
                    if (phy_bcnt == 6'd2) phy_op[1] <= mdio_sample;
                    if (phy_bcnt == 6'd3) phy_op[0] <= mdio_sample;

                    // Capture REGAD at bits 6-10 (ST=2 + OP=2 + PHYAD=5, so REGAD starts at bit 9)
                    // Actually: ST[0:1]=bits0-1, OP[0:1]=bits2-3, PHYAD[0:4]=bits4-8, REGAD[0:4]=bits9-13
                    if (phy_bcnt >= 6'd9 && phy_bcnt <= 6'd13)
                        phy_regad <= {phy_regad[3:0], mdio_sample};

                    // For WRITE (OP=01): capture DATA at bits 16-31
                    if (phy_op == 2'b01 && phy_bcnt >= 6'd16 && phy_bcnt <= 6'd31)
                        phy_shift <= {phy_shift[14:0], mdio_sample};

                    // For READ (OP=10): drive DATA at bits 16-31
                    if (phy_op == 2'b10) begin
                        // TA bits 14-15
                        if (phy_bcnt == 6'd15) begin
                            // Drive acknowledge (0) on second TA bit
                            phy_mdio_oe <= 1'b1;
                            phy_mdio_out <= 1'b0;
                            // Pre-load shift register with read data
                            phy_shift <= (phy_regad == 5'h1E) ? {8'd0, phy_ext_reg[7:0]} :
                                         (phy_regad == 5'h1F) ? phy_ext_reg :
                                         (phy_regad == 5'h01) ? 16'h002D :  // BMSR: link down
                                         16'h0000;
                        end
                        // DATA bits 16-31
                        if (phy_bcnt >= 6'd16 && phy_bcnt <= 6'd31) begin
                            phy_mdio_oe <= 1'b1;
                            phy_mdio_out <= phy_shift[15];
                            phy_shift <= {phy_shift[14:0], 1'b0};
                        end
                    end

                    // Handle extended register: write to 0x1E updates address
                    if (phy_bcnt == 6'd31 && phy_op == 2'b01 && phy_regad == 5'h1E) begin
                        // Store extended register address
                    end
                    // Write to 0x1F writes to extended register
                    if (phy_bcnt == 6'd31 && phy_op == 2'b01 && phy_regad == 5'h1F) begin
                        phy_ext_reg <= phy_shift;
                    end
                end

                default: phy_state <= PHY_IDLE;
            endcase
        end
    end

    // =====================================================================
    // Test
    // =====================================================================
    reg [15:0] final_bmsr;
    reg [15:0] final_ext_reg;

    initial begin
        clk = 0; rst_n = 0;
        #200 rst_n = 1;

        // Wait for MDIO init complete (~210ms @ 100MHz)
        wait(cfg_done == 1'b1);
        $display("[%0t ns] *** cfg_done = 1 ***", $time);
        $display("  bmsr_val = 0x%04x, link_up = %b", bmsr_val, link_up);
        $display("  phy_ext_reg (0xA003) = 0x%04x", phy_ext_reg);

        final_bmsr     = bmsr_val;
        final_ext_reg  = phy_ext_reg;

        // Verify
        if (final_ext_reg == 16'h00FD) begin
            $display("  PASS: RGMII_Config1 (0xA003) written to 0x00FD (Tx_delay=0xD)");
        end else begin
            $display("  FAIL: Expected 0x00FD, got 0x%04x", final_ext_reg);
        end

        if (final_bmsr !== 16'hxxxx && final_bmsr !== 16'h0000) begin
            $display("  PASS: BMSR readback non-zero (0x%04x)", final_bmsr);
        end else begin
            $display("  FAIL: BMSR readback is 0x%04x", final_bmsr);
        end

        #500000;
        $display("[%0t ns] Test done.", $time);
        $finish;
    end

    // Timeout
    initial begin
        #300_000_000;  // 300ms
        if (!cfg_done) begin
            $display("[%0t ns] TIMEOUT: cfg_done never asserted!", $time);
            $display("  dbg_init=%d, dbg_fstate=%d", dbg_init, dbg_fstate);
        end
        $finish;
    end

    // Waveform
    initial begin
        $dumpfile("tb_mdio.vcd");
        $dumpvars(0, tb_mdio);
    end

endmodule

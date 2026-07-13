// MDIO 控制器 (IEEE 802.3 Clause 22) — YT8531
//   上电后: 写 TX delay, 回读验证, 轮询 BMSR
//   MDC = 5MHz (clk_100m / 20)
//
module mdio_ctrl (
    input  wire         clk,           // 100MHz
    input  wire         rst_n,

    output wire         MDC,
    output reg          MDIO_oe,
    output reg          MDIO_out,
    input  wire         MDIO_in,

    output wire         cfg_done,
    output wire         link_up,
    output reg  [15:0]  bmsr_val,
    output reg  [15:0]  rgmii2_val,    // RGMII_Config2
    output reg  [15:0]  rxerr_val,     // Rx Error Counter (0=no errors)
    output wire [2:0]   dbg_init_state,
    output wire [3:0]   dbg_f_state
);

    // =====================================================================
    // MDC: 5MHz
    // =====================================================================
    reg [4:0] mdc_cnt;
    reg       MDC_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mdc_cnt <= 5'd0;
            MDC_reg <= 1'b0;
        end else if (mdc_cnt == 5'd19) begin
            mdc_cnt <= 5'd0;
            MDC_reg <= 1'b1;
        end else if (mdc_cnt == 5'd9) begin
            mdc_cnt <= mdc_cnt + 5'd1;
            MDC_reg <= 1'b0;
        end else begin
            mdc_cnt <= mdc_cnt + 5'd1;
        end
    end

    assign MDC = MDC_reg;
    wire mdc_rise = (mdc_cnt == 5'd19);
    wire mdc_fall = (mdc_cnt == 5'd9);

    // =====================================================================
    // 常量
    // =====================================================================
    localparam PHY_ADDR    = 5'd0;
    localparam REG_EXTAD   = 5'h1E;
    localparam REG_EXTDT   = 5'h1F;
    localparam REG_BMSR    = 5'h01;
    localparam REG_PKGTX   = 5'h1E;     // ext reg pointer port
    localparam REG_RGMII2  = 5'h04;     // 0xA004 via ext -> RGMII_Config2
    localparam EXTAD_CHIPCFG = 16'hA001;  // Chip_Config
    localparam EXTAD_CFG1    = 16'hA003;  // RGMII_Config1
    localparam EXTAD_CFG2    = 16'hA004;  // RGMII_Config2
    localparam EXTAD_PKGTX   = 16'h00AD;  // Pkg Tx Valid counter (low)
    // Chip_Config (0xA001) = 0x0040: 清 bit8 Rxc_dly_en, 保留 bit6 En_ldo=1
    localparam DATA_CHIPCFG  = 16'h0040;
    // RGMII_Config1 (0xA003) = 0x0000: FPGA 90°相移提供 2ns, PHY 不加延迟
    localparam DATA_TXDLY    = 16'h0000;

    // =====================================================================
    // 帧 FSM 状态
    // =====================================================================
    localparam F_IDLE = 3'd0;
    localparam F_PRE  = 3'd1;
    localparam F_BODY = 3'd2;

    reg [2:0]  f_state;
    reg [5:0]  bit_cnt;
    reg [15:0] rdata_shift;

    // =====================================================================
    // 初始化序列
    // =====================================================================
    localparam I_IDLE       = 3'd0;
    localparam I_WAIT       = 3'd1;
    localparam I_SET_CHIP   = 3'd2;   // 写 ext addr = 0xA001 (Chip_Config)
    localparam I_WR_CHIP    = 3'd3;   // 写 Chip_Config = 0x0040 (关 Rxc_dly_en)
    localparam I_SET_RGMII  = 3'd4;   // 写 ext addr = 0xA003 (RGMII_Config1)
    localparam I_WR_RGMII   = 3'd5;   // 写 RGMII_Config1 = 0x0000
    localparam I_CLR_EXTAD  = 3'd6;   // 清除 ext addr
    localparam I_POLL_BMSR  = 3'd7;   // 轮询 BMSR

    reg [2:0]   i_state;
    reg [23:0]  init_delay;
    reg         req_start;
    reg         req_rw;
    reg [4:0]   req_regad;
    reg [15:0]  req_wdata;

`ifdef SIM_FAST
    wire init_ready = (init_delay >= 24'd200);
    wire init_wait  = (init_delay >= 24'd500);
    wire delay_lim  = (init_delay <  24'd1000);
`else
    wire init_ready = (init_delay >= 24'hFFFF00);
    wire init_wait  = (init_delay >= 24'hFFFFF0);
    wire delay_lim  = 1'b1;
`endif

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            init_delay <= 24'd0;
        else if (delay_lim)
            init_delay <= init_delay + 24'd1;
    end

    // req_done edge
    reg req_done_d1;
    wire req_done = (f_state == F_BODY && bit_cnt == 6'd31 && mdc_rise);
    wire req_done_rise;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            req_done_d1 <= 1'b0;
        else
            req_done_d1 <= req_done;
    end
    assign req_done_rise = req_done && !req_done_d1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_state     <= I_IDLE;
            req_start   <= 1'b0;
            rgmii2_val  <= 16'd0;
            req_rw    <= 1'b0;
            req_regad <= 5'd0;
            req_wdata <= 16'd0;
        end else begin
            if (req_start && f_state != F_IDLE)
                req_start <= 1'b0;

            case (i_state)
                I_IDLE:     if (init_ready)  i_state <= I_WAIT;
                I_WAIT:     if (init_wait)   begin i_state <= I_SET_CHIP; req_start <= 1'b1; req_rw <= 1'b0; req_regad <= REG_EXTAD; req_wdata <= EXTAD_CHIPCFG; end
                // Step 1: 写 Chip_Config = 0x0040 (关 Rxc_dly_en, 保留 En_ldo=1)
                I_SET_CHIP: if (req_done_rise) begin i_state <= I_WR_CHIP;  req_start <= 1'b1; req_rw <= 1'b0; req_regad <= REG_EXTDT; req_wdata <= DATA_CHIPCFG; end
                // Step 2: 写 RGMII_Config1 = 0x0000
                I_WR_CHIP:  if (req_done_rise) begin i_state <= I_SET_RGMII;req_start <= 1'b1; req_rw <= 1'b0; req_regad <= REG_EXTAD; req_wdata <= EXTAD_CFG1; end
                I_SET_RGMII:if (req_done_rise) begin i_state <= I_WR_RGMII; req_start <= 1'b1; req_rw <= 1'b0; req_regad <= REG_EXTDT; req_wdata <= DATA_TXDLY; end
                // Step 3: 清除 ext addr, 开始轮询 BMSR
                I_WR_RGMII: if (req_done_rise) begin i_state <= I_CLR_EXTAD;req_start <= 1'b1; req_rw <= 1'b0; req_regad <= REG_EXTAD; req_wdata <= 16'h0000; end
                I_CLR_EXTAD:if (req_done_rise) begin i_state <= I_POLL_BMSR; req_start <= 1'b1; req_rw <= 1'b1; req_regad <= REG_BMSR; end
                // 轮询 BMSR
                I_POLL_BMSR:if (req_done_rise) begin bmsr_val <= rdata_shift;  req_start <= 1'b1; req_rw <= 1'b1; req_regad <= REG_BMSR; end
                default: i_state <= I_IDLE;
            endcase
        end
    end

    assign cfg_done = (i_state >= I_POLL_BMSR);
    assign link_up  = (bmsr_val[2] == 1'b1);

    // =====================================================================
    // Frame FSM
    // =====================================================================
    reg        f_rw_latch;
    reg [4:0]  f_regad_latch;
    reg [15:0] f_wdata_latch;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            f_rw_latch    <= 1'b0;
            f_regad_latch <= 5'd0;
            f_wdata_latch <= 16'd0;
        end else if (f_state == F_IDLE && req_start) begin
            f_rw_latch    <= req_rw;
            f_regad_latch <= req_regad;
            f_wdata_latch <= req_wdata;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            f_state <= F_IDLE;
            bit_cnt <= 6'd0;
        end else if (mdc_rise) begin
            case (f_state)
                F_IDLE: if (req_start) begin f_state <= F_PRE; bit_cnt <= 6'd0; end
                F_PRE:  if (bit_cnt == 6'd31) begin f_state <= F_BODY; bit_cnt <= 6'd0; end
                        else bit_cnt <= bit_cnt + 6'd1;
                F_BODY: if (bit_cnt == 6'd31) begin f_state <= F_IDLE; bit_cnt <= 6'd0; end
                        else bit_cnt <= bit_cnt + 6'd1;
                default: f_state <= F_IDLE;
            endcase
        end
    end

    // =====================================================================
    // 数据移位
    // =====================================================================
    reg [15:0] wdata_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata_shift <= 16'd0;
            wdata_shift <= 16'd0;
        end else begin
            if (mdc_rise && f_state == F_PRE && bit_cnt == 6'd31) begin
                wdata_shift <= f_wdata_latch;
                rdata_shift <= 16'd0;
            end
            if (mdc_fall && f_state == F_BODY && bit_cnt >= 6'd16 && bit_cnt <= 6'd31) begin
                if (f_rw_latch)
                    rdata_shift <= {rdata_shift[14:0], MDIO_in};
                else
                    wdata_shift <= {wdata_shift[14:0], 1'b0};
            end
        end
    end

    // =====================================================================
    // MDIO 输出
    // =====================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            MDIO_oe  <= 1'b0;
            MDIO_out <= 1'b0;
        end else if (mdc_fall) begin
            case (f_state)
                F_PRE: begin MDIO_oe <= 1'b1; MDIO_out <= 1'b1; end
                F_BODY: begin
                    case (bit_cnt)
                        // ST: 01
                        6'd0:  begin MDIO_oe <= 1'b1; MDIO_out <= 1'b0; end
                        6'd1:  begin MDIO_oe <= 1'b1; MDIO_out <= 1'b1; end
                        // OP
                        6'd2:  begin MDIO_oe <= 1'b1; MDIO_out <= f_rw_latch; end
                        6'd3:  begin MDIO_oe <= 1'b1; MDIO_out <= ~f_rw_latch; end
                        // PHYAD
                        6'd4:  begin MDIO_oe <= 1'b1; MDIO_out <= PHY_ADDR[4]; end
                        6'd5:  begin MDIO_oe <= 1'b1; MDIO_out <= PHY_ADDR[3]; end
                        6'd6:  begin MDIO_oe <= 1'b1; MDIO_out <= PHY_ADDR[2]; end
                        6'd7:  begin MDIO_oe <= 1'b1; MDIO_out <= PHY_ADDR[1]; end
                        6'd8:  begin MDIO_oe <= 1'b1; MDIO_out <= PHY_ADDR[0]; end
                        // REGAD
                        6'd9:  begin MDIO_oe <= 1'b1; MDIO_out <= f_regad_latch[4]; end
                        6'd10: begin MDIO_oe <= 1'b1; MDIO_out <= f_regad_latch[3]; end
                        6'd11: begin MDIO_oe <= 1'b1; MDIO_out <= f_regad_latch[2]; end
                        6'd12: begin MDIO_oe <= 1'b1; MDIO_out <= f_regad_latch[1]; end
                        6'd13: begin MDIO_oe <= 1'b1; MDIO_out <= f_regad_latch[0]; end
                        // TA
                        6'd14: begin MDIO_oe <= f_rw_latch ? 1'b0 : 1'b1; MDIO_out <= f_rw_latch ? 1'b0 : 1'b1; end
                        6'd15: begin MDIO_oe <= 1'b0; MDIO_out <= 1'b0; end
                        // DATA
                        default: begin
                            MDIO_oe <= f_rw_latch ? 1'b0 : 1'b1;
                            MDIO_out <= wdata_shift[15];
                        end
                    endcase
                end
                default: begin MDIO_oe <= 1'b0; MDIO_out <= 1'b0; end
            endcase
        end
    end

    // =====================================================================
    // Debug
    // =====================================================================
    assign dbg_init_state = i_state;
    assign dbg_f_state    = {1'b0, f_state};

endmodule

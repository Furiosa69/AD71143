// =============================================================================
// Xilinx 7-Series Unisim Behavioral Models for Icarus Verilog Simulation
// =============================================================================
// 简化行为模型, 用于 iverilog 功能仿真
// Vivado synthesis 时使用真实 unisim 库
// =============================================================================

// =============================================================================
// BUFIO — IO Clock Buffer
// =============================================================================
module BUFIO (
    input  wire I,
    output wire O
);
    assign O = I;
endmodule

// =============================================================================
// BUFR — Regional Clock Buffer with Divide
// =============================================================================
module BUFR #(
    parameter BUFR_DIVIDE = "4",
    parameter SIM_DEVICE  = "7SERIES"
) (
    input  wire I,
    output wire O,
    input  wire CE,
    input  wire CLR
);
    // Convert divide string to integer
    localparam integer DIV_VAL =
        (BUFR_DIVIDE == "BYPASS") ? 1 :
        (BUFR_DIVIDE == "1") ? 1 :
        (BUFR_DIVIDE == "2") ? 2 :
        (BUFR_DIVIDE == "3") ? 3 :
        (BUFR_DIVIDE == "4") ? 4 :
        (BUFR_DIVIDE == "5") ? 5 :
        (BUFR_DIVIDE == "6") ? 6 :
        (BUFR_DIVIDE == "7") ? 7 :
        (BUFR_DIVIDE == "8") ? 8 : 4;

    // BUFR divide by N: output toggles every N/2 input cycles
    localparam integer HALF_N = (DIV_VAL / 2);
    reg [15:0] counter = 0;
    reg clk_out = 0;

    always @(posedge I or posedge CLR) begin
        if (CLR) begin
            counter <= 0;
            clk_out <= 0;
        end else if (CE) begin
            if (counter >= HALF_N - 1) begin
                counter <= 0;
                clk_out <= ~clk_out;
            end else begin
                counter <= counter + 1'b1;
            end
        end
    end

    assign O = clk_out;
endmodule

// =============================================================================
// BUFG — Global Clock Buffer (iverilog has built-in, but provide for safety)
// =============================================================================
module BUFG (
    input  wire I,
    output wire O
);
    assign O = I;
endmodule

// =============================================================================
// IBUFDS — Differential Input Buffer
// =============================================================================
module IBUFDS #(
    parameter DIFF_TERM  = "FALSE",
    parameter IOSTANDARD = "DEFAULT"
) (
    output wire O,
    input  wire I,
    input  wire IB
);
    // Simplified: O = I (single-ended from positive terminal)
    assign O = I;
endmodule

// =============================================================================
// OBUFDS — Differential Output Buffer
// =============================================================================
module OBUFDS #(
    parameter IOSTANDARD = "DEFAULT"
) (
    output wire O,
    output wire OB,
    input  wire I
);
    assign O  = I;
    assign OB = ~I;
endmodule

// =============================================================================
// ODDR — DDR Output Register
// =============================================================================
module ODDR #(
    parameter DDR_CLK_EDGE = "OPPOSITE_EDGE",
    parameter INIT         = 1'b0,
    parameter SRTYPE       = "SYNC"
) (
    output reg  Q,
    input  wire C,
    input  wire CE,
    input  wire D1,
    input  wire D2,
    input  wire R,
    input  wire S
);
    wire clk_rise = C;
    wire clk_fall = ~C;

    always @(posedge C or posedge R) begin
        if (R)    Q <= 1'b0;
        else if (CE) Q <= D1;
    end

    // Note: D2 on falling edge is approximated
    always @(negedge C or posedge R) begin
        if (R)    Q <= 1'b0;
        else if (CE) Q <= D2;
    end
endmodule

// =============================================================================
// IDELAYCTRL — Delay Control for IDELAYE2
// =============================================================================
module IDELAYCTRL (
    output wire RDY,
    input  wire REFCLK,
    input  wire RST
);
    // After reset release, RDY goes high after a few cycles
    reg [3:0] rst_cnt = 0;
    reg rdy_reg = 0;

    always @(posedge REFCLK or posedge RST) begin
        if (RST) begin
            rst_cnt <= 0;
            rdy_reg <= 0;
        end else begin
            if (rst_cnt < 4'd10) begin
                rst_cnt <= rst_cnt + 1;
            end else begin
                rdy_reg <= 1;
            end
        end
    end

    assign RDY = rdy_reg;
endmodule

// =============================================================================
// IDELAYE2 — Input Delay Element
// =============================================================================
module IDELAYE2 #(
    parameter CINVCTRL_SEL           = "FALSE",
    parameter DELAY_SRC              = "IDATAIN",
    parameter HIGH_PERFORMANCE_MODE  = "FALSE",
    parameter IDELAY_TYPE            = "FIXED",
    parameter IDELAY_VALUE           = 0,
    parameter PIPE_SEL               = "FALSE",
    parameter REFCLK_FREQUENCY       = 200.0,
    parameter SIGNAL_PATTERN         = "DATA"
) (
    output wire       CNTVALUEOUT,
    output wire       DATAOUT,
    input  wire       C,
    input  wire       CE,
    input  wire       CINVCTRL,
    input  wire [4:0] CNTVALUEIN,
    input  wire       DATAIN,
    input  wire       IDATAIN,
    input  wire       INC,
    input  wire       LD,
    input  wire       LDPIPEEN,
    input  wire       REGRST
);
    reg        tap_value = IDELAY_VALUE;

    always @(posedge C) begin
        if (LD) begin
            tap_value <= CNTVALUEIN;
        end else if (CE && INC) begin
            tap_value <= (tap_value < 31) ? tap_value + 1 : tap_value;
        end
    end

    // Simplified: pass-through (no actual delay modeling)
    wire data_in_src;
    assign data_in_src = (DELAY_SRC == "IDATAIN") ? IDATAIN : DATAIN;
    assign DATAOUT     = data_in_src;
    assign CNTVALUEOUT = tap_value;
endmodule

// =============================================================================
// ISERDESE2 — Input Serial-to-Parallel Converter (Behavioral Model)
//
// DDR 1:8 with BITSLIP support
// CLK:    high-speed serial clock (200MHz from BUFIO)
// CLKDIV: divided clock (50MHz = CLK/4)
// DDLY:   serial data from IDELAYE2
// Q1..Q8: parallel output (Q8=MSB=first received, Q1=LSB=last received)
// BITSLIP: pulse-high shifts alignment by 1 bit (8 positions total)
// =============================================================================
module ISERDESE2 #(
    parameter DATA_RATE          = "DDR",
    parameter DATA_WIDTH         = 8,
    parameter INTERFACE_TYPE     = "NETWORKING",
    parameter IOBDELAY           = "IFD",
    parameter NUM_CE             = 1,
    parameter SERDES_MODE        = "MASTER",
    parameter BITSLIP_ENABLE     = "TRUE",
    parameter OFB_USED           = "FALSE",
    parameter DYN_CLKDIV_INV_EN  = "FALSE",
    parameter DYN_CLK_INV_EN     = "FALSE",
    parameter INIT_Q1            = 1'b0,
    parameter INIT_Q2            = 1'b0,
    parameter INIT_Q3            = 1'b0,
    parameter INIT_Q4            = 1'b0,
    parameter SRVAL_Q1           = 1'b0,
    parameter SRVAL_Q2           = 1'b0,
    parameter SRVAL_Q3           = 1'b0,
    parameter SRVAL_Q4           = 1'b0
) (
    output reg  Q1,
    output reg  Q2,
    output reg  Q3,
    output reg  Q4,
    output reg  Q5,
    output reg  Q6,
    output reg  Q7,
    output reg  Q8,
    output wire SHIFTOUT1,
    output wire SHIFTOUT2,
    input  wire BITSLIP,
    input  wire CE1,
    input  wire CE2,
    input  wire CLK,
    input  wire CLKB,
    input  wire CLKDIV,
    input  wire CLKDIVP,
    input  wire D,
    input  wire DDLY,
    input  wire DYNCLKDIVSEL,
    input  wire DYNCLKSEL,
    input  wire OFB,
    input  wire OCLK,
    input  wire OCLKB,
    input  wire RST,
    input  wire SHIFTIN1,
    input  wire SHIFTIN2
);
    wire serial_in = (INTERFACE_TYPE == "NETWORKING") ? DDLY : D;

    // Dual-edge sampling: use CLK edges with delayed sampling to avoid race
    reg [7:0] shift_reg;
    reg [7:0] output_reg;
    reg [2:0] bitslip_ofs;
    reg       prev_clk;
    reg       clkdiv_d1, clkdiv_d2, clkdiv_d3;
    reg       bitslip_d1, bitslip_d2;
    wire      clkdiv_rise, bitslip_rise;

    // Single always block using CLK for both edges (any change on CLK)
    always @(CLK or posedge RST) begin
        if (RST) begin
            shift_reg    <= 8'd0;
            output_reg   <= 8'd0;
            bitslip_ofs  <= 3'd0;
            prev_clk     <= 1'b0;
            clkdiv_d1    <= 1'b0;
            clkdiv_d2    <= 1'b0;
            clkdiv_d3    <= 1'b0;
            bitslip_d1   <= 1'b0;
            bitslip_d2   <= 1'b0;
        end else begin
            prev_clk    <= CLK;

            clkdiv_d1  <= CLKDIV;
            clkdiv_d2  <= clkdiv_d1;
            clkdiv_d3  <= clkdiv_d2;
            bitslip_d1 <= BITSLIP;
            bitslip_d2 <= bitslip_d1;

            // DDR: sample on both edges
            // CLK change = edge (either rising or falling)
            shift_reg <= {shift_reg[6:0], serial_in};

            // CLKDIV rising edge → latch output word
            if (clkdiv_rise) begin
                output_reg <= shift_reg;
            end

            // BITSLIP rising edge → increment offset
            if (bitslip_rise && BITSLIP_ENABLE == "TRUE") begin
                bitslip_ofs <= (bitslip_ofs < 7) ? bitslip_ofs + 1 : 3'd0;
            end
        end
    end

    assign clkdiv_rise  = clkdiv_d2 && !clkdiv_d3;
    assign bitslip_rise = bitslip_d1 && !bitslip_d2;

    // Output with bitslip rotation
    function [7:0] rotate_left;
        input [7:0] data;
        input [2:0] n;
        case (n)
            3'd0: rotate_left = data;
            3'd1: rotate_left = {data[6:0], data[7]};
            3'd2: rotate_left = {data[5:0], data[7:6]};
            3'd3: rotate_left = {data[4:0], data[7:5]};
            3'd4: rotate_left = {data[3:0], data[7:4]};
            3'd5: rotate_left = {data[2:0], data[7:3]};
            3'd6: rotate_left = {data[1:0], data[7:2]};
            3'd7: rotate_left = {data[0],   data[7:1]};
        endcase
    endfunction

    wire [7:0] result;
    assign result = rotate_left(output_reg, bitslip_ofs);
    assign {Q8, Q7, Q6, Q5, Q4, Q3, Q2, Q1} = result;

    assign SHIFTOUT1 = 1'b0;
    assign SHIFTOUT2 = 1'b0;
endmodule

// =============================================================================
// PLLE2_BASE — PLL (simplified for simulation, passes through)
// (already exists in the old code; provided here for completeness)
// =============================================================================
module PLLE2_BASE #(
    parameter BANDWIDTH           = "OPTIMIZED",
    parameter CLKFBOUT_MULT       = 20,
    parameter CLKFBOUT_PHASE      = 0.0,
    parameter CLKIN1_PERIOD       = 20.0,
    parameter CLKOUT0_DIVIDE      = 10,
    parameter CLKOUT0_DUTY_CYCLE  = 0.5,
    parameter CLKOUT0_PHASE       = 0.0,
    parameter CLKOUT1_DIVIDE      = 5,
    parameter CLKOUT1_DUTY_CYCLE  = 0.5,
    parameter CLKOUT1_PHASE       = 0.0,
    parameter CLKOUT2_DIVIDE      = 1,
    parameter CLKOUT2_DUTY_CYCLE  = 0.5,
    parameter CLKOUT2_PHASE       = 0.0,
    parameter CLKOUT3_DIVIDE      = 1,
    parameter CLKOUT3_DUTY_CYCLE  = 0.5,
    parameter CLKOUT3_PHASE       = 0.0,
    parameter CLKOUT4_DIVIDE      = 1,
    parameter CLKOUT4_DUTY_CYCLE  = 0.5,
    parameter CLKOUT4_PHASE       = 0.0,
    parameter CLKOUT5_DIVIDE      = 1,
    parameter CLKOUT5_DUTY_CYCLE  = 0.5,
    parameter CLKOUT5_PHASE       = 0.0,
    parameter DIVCLK_DIVIDE       = 1,
    parameter REF_JITTER1         = 0.010,
    parameter STARTUP_WAIT        = "FALSE"
) (
    input  wire CLKIN1,
    output wire CLKOUT0,
    output wire CLKOUT1,
    output wire CLKOUT2,
    output wire CLKOUT3,
    output wire CLKOUT4,
    output wire CLKOUT5,
    output wire CLKFBOUT,
    input  wire CLKFBIN,
    output wire LOCKED,
    input  wire PWRDWN,
    input  wire RST
);
    // Simplified: VCO = CLKIN * CLKFBOUT_MULT / 1
    // CLKOUT0 = VCO / CLKOUT0_DIVIDE
    // CLKOUT1 = VCO / CLKOUT1_DIVIDE

    localparam real VCO_MULT = real'(CLKFBOUT_MULT);
    localparam real CLK0_DIV = real'(CLKOUT0_DIVIDE);
    localparam real CLK1_DIV = real'(CLKOUT1_DIVIDE);

    localparam real CLK0_PERIOD = CLKIN1_PERIOD / VCO_MULT * CLK0_DIV;
    localparam real CLK1_PERIOD = CLKIN1_PERIOD / VCO_MULT * CLK1_DIV;

    reg clk0 = 0, clk1 = 0;
    reg locked_reg = 0;
    reg [3:0] lock_cnt = 0;

    // CLKOUT0 generation
    always #(CLK0_PERIOD / 2.0) clk0 <= (locked_reg) ? ~clk0 : 0;

    // CLKOUT1 generation
    always #(CLK1_PERIOD / 2.0) clk1 <= (locked_reg) ? ~clk1 : 0;

    // Lock after startup
    always @(posedge CLKIN1 or posedge RST) begin
        if (RST) begin
            lock_cnt <= 0;
            locked_reg <= 0;
        end else if (!locked_reg) begin
            if (lock_cnt < 10) lock_cnt <= lock_cnt + 1;
            else locked_reg <= 1;
        end
    end

    assign CLKOUT0  = clk0;
    assign CLKOUT1  = clk1;
    assign CLKOUT2  = 1'b0;
    assign CLKOUT3  = 1'b0;
    assign CLKOUT4  = 1'b0;
    assign CLKOUT5  = 1'b0;
    assign CLKFBOUT = clk0;
    assign LOCKED   = locked_reg;
endmodule

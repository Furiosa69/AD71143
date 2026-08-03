module ad71143_spi (
    input  wire         clk_sys,
    input  wire         rst_n,
    input  wire         start,
    input  wire         rw,
    input  wire [3:0]   reg_addr,
    input  wire [9:0]   reg_data,
    output reg          done,
    output reg  [9:0]   reg_rdback,
    output reg          spi_cs,
    output reg          spi_sck,
    output reg          spi_sdi,
    input  wire         spi_sdo
);

    localparam integer SCK_DIV = 4;
    // The AD71143 requires at least two SCK pulses with CS low between read phases.
    localparam integer READ_GAP_SCK_CYCLES = 3;
    localparam S_IDLE            = 4'd0;
    localparam S_SETUP           = 4'd1;
    localparam S_SHIFT           = 4'd2;
    localparam S_READ_HOLD       = 4'd3;
    localparam S_READ_GAP        = 4'd4;
    localparam S_READ_GAP_FINISH = 4'd5;
    localparam S_READ_SETUP      = 4'd6;
    localparam S_READ_SHIFT      = 4'd7;
    localparam S_READ_FINISH     = 4'd8;
    localparam S_FINISH          = 4'd9;
    localparam S_DONE            = 4'd10;

    reg [3:0]  state, state_next;
    reg [1:0]  sck_cnt;
    reg        sck_toggle;
    reg [4:0]  bit_cnt;
    reg [15:0] shift_reg;
    reg [9:0]  rdback_buf;
    reg [1:0]  read_gap_cnt;

    wire spi_busy;
    assign spi_busy = (state == S_SHIFT) ||
                      (state == S_READ_GAP) ||
                      (state == S_READ_SHIFT);

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= state_next;
    end

    always @(*) begin
        state_next = state;
        case (state)
            S_IDLE: if (start) state_next = S_SETUP;
            S_SETUP: state_next = S_SHIFT;
            S_SHIFT: if (bit_cnt == 5'd16 && sck_toggle && sck_cnt == SCK_DIV - 1)
                         state_next = rw ? S_FINISH : S_READ_HOLD;
            S_READ_HOLD:       state_next = S_READ_GAP;
            S_READ_GAP: if ((read_gap_cnt == READ_GAP_SCK_CYCLES - 1) &&
                            sck_toggle && sck_cnt == SCK_DIV - 1)
                            state_next = S_READ_GAP_FINISH;
            S_READ_GAP_FINISH: state_next = S_READ_SETUP;
            S_READ_SETUP: state_next = S_READ_SHIFT;
            S_READ_SHIFT: if (bit_cnt == 5'd16 && sck_toggle && sck_cnt == SCK_DIV - 1)
                            state_next = S_READ_FINISH;
            S_READ_FINISH: state_next = S_DONE;
            S_FINISH:      state_next = S_DONE;
            S_DONE: state_next = S_IDLE;
            default: state_next = S_IDLE;
        endcase
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            sck_cnt    <= 2'd0;
            sck_toggle <= 1'b0;
        end else if (spi_busy) begin
            if (sck_cnt == SCK_DIV - 1) begin
                sck_cnt    <= 2'd0;
                sck_toggle <= ~sck_toggle;
            end else begin
                sck_cnt <= sck_cnt + 2'd1;
            end
        end else begin
            sck_cnt    <= 2'd0;
            sck_toggle <= 1'b0;
        end
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            read_gap_cnt <= 2'd0;
        else if (state == S_READ_GAP &&
                 sck_toggle && sck_cnt == SCK_DIV - 1)
            read_gap_cnt <= read_gap_cnt + 2'd1;
        else
            read_gap_cnt <= (state == S_READ_GAP) ? read_gap_cnt : 2'd0;
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 16'd0;
            bit_cnt   <= 5'd0;
        end else if (state == S_IDLE && start) begin
            shift_reg <= {rw, ~rw, reg_addr, reg_data};
            bit_cnt   <= 5'd0;
        end else if (state == S_READ_SETUP) begin
            shift_reg <= 16'd0;
            bit_cnt   <= 5'd0;
        end else if ((state == S_SHIFT || state == S_READ_SHIFT) &&
                     sck_toggle && sck_cnt == 0) begin
            shift_reg <= {shift_reg[14:0], 1'b0};
            bit_cnt   <= bit_cnt + 5'd1;
        end
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            spi_sdi <= 1'b0;
        else if (state == S_SETUP)
            spi_sdi <= shift_reg[15];
        else if (state == S_READ_HOLD || state == S_READ_GAP_FINISH ||
                 state == S_READ_GAP || state == S_READ_SETUP)
            spi_sdi <= 1'b0;
        else if ((state == S_SHIFT || state == S_READ_SHIFT) &&
                 !sck_toggle && sck_cnt == 1)
            spi_sdi <= shift_reg[15];
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            spi_sck <= 1'b0;
        else if (spi_busy)
            spi_sck <= sck_toggle;
        else
            spi_sck <= 1'b0;
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            spi_cs <= 1'b1;
        else if ((state == S_IDLE && start) || state == S_READ_SETUP)
            spi_cs <= 1'b0;
        else if (state == S_READ_GAP || state == S_DONE)
            spi_cs <= 1'b1;
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            rdback_buf <= 10'd0;
        else if (state == S_IDLE && start && !rw)
            rdback_buf <= 10'd0;
        else if (!rw && state == S_READ_SHIFT && sck_toggle && sck_cnt == SCK_DIV - 1)
            rdback_buf <= {rdback_buf[8:0], spi_sdo};
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            done       <= 1'b0;
            reg_rdback <= 10'd0;
        end else begin
            done <= 1'b0;
            if (state == S_DONE) begin
                done <= 1'b1;
                if (!rw)
                    reg_rdback <= rdback_buf;
            end
        end
    end

endmodule

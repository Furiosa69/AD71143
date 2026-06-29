// =============================================================================
// AD71143 SPI Master - ���� ROIC �Ĵ���
// =============================================================================
// ��׼ 4 �� SPI (CS, SCK, SDI, SDO), 16-bit ֡, MSB first
// SCK = 25MHz (�� 100MHz ϵͳʱ�� 4 ��Ƶ)
//
// ֡��ʽ:
//   Bit[15]    = Write (1=д)
//   Bit[14]    = Read  (1=��)
//   Bit[13:10] = Register Address (0~15)
//   Bit[9:0]   = Register Data
//
// �÷�:
//   1. ���� reg_addr, reg_data, rw
//   2. �� start һ������
//   3. �� done=1
//   4. ����Ƕ�����, �� reg_rdback
// =============================================================================

`timescale 1ns / 1ps

module ad71143_spi (
    input  wire         clk_sys,        // ϵͳʱ�� (100MHz)
    input  wire         rst_n,          // �첽��λ, ����Ч

    // ---- ���ƽӿ� ----
    input  wire         start,          // ��ʼһ�� SPI ���� (����������)
    input  wire         rw,             // 1=д, 0=��
    input  wire [3:0]   reg_addr,       // �Ĵ�����ַ 0~15
    input  wire [9:0]   reg_data,       // д������ (������ʱ����)
    output reg          done,           // ������� (����������)
    output reg  [9:0]   reg_rdback,     // �������� (����������Ч)

    // ---- SPI ������ ----
    output reg          spi_cs,         // Ƭѡ (����Ч)
    output reg          spi_sck,        // ʱ��
    output reg          spi_sdi,        // ������� (FPGA��ROIC)
    input  wire         spi_sdo         // �������� (ROIC��FPGA)
);

    // =========================================================================
    // SCK ���� (clk_sys 4 ��Ƶ �� 25MHz)
    // =========================================================================
    localparam SCK_DIV = 2;             // 100MHz / (2*2) = 25MHz

    reg [1:0] sck_cnt;
    reg       sck_toggle;
    reg       spi_active;
    reg [3:0] bit_cnt;     // �ѷ��� bit �� (0~15)
    reg [15:0] shift_reg;  // ������λ�Ĵ���
    reg [9:0] rdback_buf;  // SDO ���ػ���

    // =========================================================================
    // ״̬��
    // =========================================================================
    localparam S_IDLE   = 2'd0;
    localparam S_SETUP  = 2'd1;         // CS ���ͺ�ȴ�
    localparam S_SHIFT  = 2'd2;         // 16-bit ��λ
    localparam S_DONE   = 2'd3;

    reg [1:0] state, state_next;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= state_next;
    end

    // =========================================================================
    // ״̬ת��
    // =========================================================================
    always @(*) begin
        state_next = state;
        case (state)
            S_IDLE:  if (start) state_next = S_SETUP;
            S_SETUP: if (sck_toggle && sck_cnt == 0)
                         state_next = S_SHIFT;
            S_SHIFT: if (bit_cnt == 15 && sck_toggle && sck_cnt == 0)
                         state_next = S_DONE;
            S_DONE:  state_next = S_IDLE;
            default: state_next = S_IDLE;
        endcase
    end

    // =========================================================================
    // SCK ������ (���� SPI �����ڼ�����)
    // =========================================================================
    wire spi_busy;
    assign spi_busy = (state == S_SETUP || state == S_SHIFT);

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            sck_cnt   <= 2'd0;
            sck_toggle <= 1'b0;
        end else if (spi_busy) begin
            if (sck_cnt == SCK_DIV - 1) begin
                sck_cnt   <= 2'd0;
                sck_toggle <= ~sck_toggle;
            end else begin
                sck_cnt <= sck_cnt + 2'd1;
            end
        end else begin
            sck_cnt   <= 2'd0;
            sck_toggle <= 1'b0;
        end
    end

    // =========================================================================
    // ��λ�߼�
    // =========================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 16'd0;
            bit_cnt   <= 4'd0;
        end else if (state == S_IDLE && start) begin
            // װ��֡: {W, R, Addr[3:0], Data[9:0]}
            shift_reg <= {rw, ~rw, reg_addr, reg_data};
            bit_cnt   <= 4'd0;
        end else if (state == S_SHIFT && sck_toggle && sck_cnt == 0) begin
            // SCK ������: �����һ�� bit (MSB first)
            shift_reg <= {shift_reg[14:0], 1'b0};
            bit_cnt   <= bit_cnt + 4'd1;
        end
    end

    // =========================================================================
    // SPI �ź����
    // =========================================================================
    // SDI: �� SCK �����ظ���, �����ȶ�����һ��������
    // SDI Ӧ�� SCK �½��ر� ROIC ����, �����ڷ� SCK ����ʱ����
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            spi_sdi <= 1'b0;
        end else if (state == S_SETUP) begin
            spi_sdi <= shift_reg[15];   // MSB �ȳ�
        end else if (state == S_SHIFT && !sck_toggle && sck_cnt == 0) begin
            // SCK �͵�ƽ�ڼ���� SDI (�� ROIC �� SCK �½��ز����� setup ʱ��)
            spi_sdi <= shift_reg[15];
        end
    end

    // SCK
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            spi_sck <= 1'b0;
        else if (spi_busy)
            spi_sck <= sck_toggle;
        else
            spi_sck <= 1'b0;
    end

    // CS
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            spi_cs <= 1'b1;
        else if (state == S_IDLE && start)
            spi_cs <= 1'b0;
        else if (state == S_DONE)
            spi_cs <= 1'b1;
    end

    // =========================================================================
    // SDO 读回捕获 (SCK 上升沿后, sck_toggle=1 期间采样)
    // AD71143 SPEC: SDO 在 SCK 上升沿输出
    // =========================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            rdback_buf <= 10'd0;
        end else if (state == S_SHIFT && sck_toggle && sck_cnt == SCK_DIV-1) begin
            // SCK 高电平末尾采样 SDO (最大建立时间)
            rdback_buf <= {rdback_buf[8:0], spi_sdo};
        end
    end

    // =========================================================================
    // done 输出 + 读回值锁存
    // =========================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            done       <= 1'b0;
            reg_rdback <= 10'd0;
        end else if (state == S_DONE) begin
            done       <= 1'b1;
            reg_rdback <= rdback_buf;
        end else begin
            done <= 1'b0;
        end
    end

endmodule

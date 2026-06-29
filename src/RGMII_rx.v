`timescale 1ns / 1ps
module RGMII_rx (
    input  wire         rst_n,  //异步复位，低有效
    input  wire         RXC,    //125MHz
    input  wire         RX_CTL,
    input  wire         RXD0,
    input  wire         RXD1,
    input  wire         RXD2,
    input  wire         RXD3,

    output wire         MDC,    //管理数据时钟
    inout  wire         MDIO   //管理数据输入输出

);

parameter FRAME_SIZE = 64; //一帧数据字节数
parameter Preamble = 8'h55; //前导码
parameter SFD = 8'hD5; //帧开始定界符
parameter IDLE = 2'b00; //空闲状态，等待DV拉高开始接收数据
parameter RECEIVE = 2'b01; //接收状态，DV拉高，接收数据



wire [3:0]      RXD_IDDR_r;
wire [3:0]      RXD_IDDR_f;
reg  [3:0]      RXD_IDDR_r_d;
wire [7:0]      RXD_IDDR;
wire            RX_DV;
reg             RX_DV_d;
wire            RX_DV_xor_ER;
wire            RX_ER;
reg  [64*8-1:0] frame_data; //一帧数据，64字节，512bit

reg  [2:0]      state;
reg  [2:0]      next_state;
reg  [3:0]      Preamble_cnt;
reg             Preamble_done;
reg             SFD_done;
reg  [31:0]     Byte_cnt;

always @(posedge RXC) begin
    if (!rst_n) begin   
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end

//SAME_EDGE_PIPELINED  
// - Q1（第 N 个时钟上升沿）= 第 N 个上升沿采到的 RXD（低 4 位）
// - Q2（第 N 个时钟上升沿）= 第 N-1 个下降沿采到的 RXD（上一个字节的高 4 位）
always @(posedge RXC) begin
      if (!rst_n) begin
         RXD_IDDR_r_d <= 4'b0;
         RX_DV_d <= 1'b0;
      end else begin
         RXD_IDDR_r_d <= RXD_IDDR_r;
         RX_DV_d <= RX_DV;
      end
end

always @(*) begin
   case (state)
      IDLE: next_state = SFD_done ? RECEIVE : IDLE;
      RECEIVE: next_state = RX_DV_d ? RECEIVE : IDLE;
      default: next_state = IDLE;
   endcase
end


assign RXD_IDDR = {RXD_IDDR_f,RXD_IDDR_r_d};

// 计算前导码计数器，累计7次前导码，考虑误差，接收3次则视为前导码有效
always @(posedge RXC) begin
      if (!rst_n) begin
         Preamble_cnt <= 0;
         Preamble_done <= 0;
      end else if (RXD_IDDR == Preamble && Preamble_cnt < 4'd3 && RX_DV_d) begin
         Preamble_cnt <= Preamble_cnt + 1;
      end else if(Preamble_cnt == 4'd3) begin
         Preamble_cnt <= 0;
         Preamble_done <= 1;
      end else if(RX_DV_d == 1'b0)begin //帧结束拉低
         Preamble_done <= 0;
      end else begin
         Preamble_cnt <= 0;
      end
   end

always @(posedge RXC) begin
   if(!rst_n) begin
      SFD_done <= 0;
   end else if ((Preamble_done || Preamble_cnt == 4'd3) && RXD_IDDR == SFD) begin
      SFD_done <= 1;
   end else if(RX_DV_d == 1'b0)begin //帧结束拉低
      SFD_done <= 0;
   end
end

always @(posedge RXC) begin
   if(!rst_n) begin
      Byte_cnt <= 0;
   end else if ((state == RECEIVE || (state == IDLE && SFD_done)) && RX_DV_d) begin
      Byte_cnt <= Byte_cnt + 1;
end else if(state == IDLE)begin //帧结束拉低
      Byte_cnt <= 0;
   end
end

always @(posedge RXC) begin
      if (!rst_n) begin
         frame_data <= 0;
      end else if ((state == RECEIVE || (state == IDLE && SFD_done)) && RX_DV_d) begin
         frame_data <= {frame_data[63*8-1:0], RXD_IDDR};
      end
   end

IDDR #(
      .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"), // "OPPOSITE_EDGE", "SAME_EDGE" 
                                      //    or "SAME_EDGE_PIPELINED" 
      .INIT_Q1(1'b0), // Initial value of Q1: 1'b0 or 1'b1
      .INIT_Q2(1'b0), // Initial value of Q2: 1'b0 or 1'b1
      .SRTYPE("SYNC") // Set/Reset type: "SYNC" or "ASYNC" 
   ) IDDR_inst_0 (
      .Q1(RXD_IDDR_r[0]), // 1-bit output for positive edge of clock
      .Q2(RXD_IDDR_f[0]), // 1-bit output for negative edge of clock
      .C(RXC),   // 1-bit clock input
      .CE(1'b1), // 1-bit clock enable input
      .D(RXD0),   // 1-bit DDR data input
      .R(1'b0),   // 1-bit reset
      .S(1'b0)    // 1-bit set
   );

IDDR #(
      .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"), 
                                      
      .INIT_Q1(1'b0), 
      .INIT_Q2(1'b0), 
      .SRTYPE("SYNC") 
   ) IDDR_inst1 (
      .Q1(RXD_IDDR_r[1]), 
      .Q2(RXD_IDDR_f[1]), 
      .C(RXC),   
      .CE(1'b1), 
      .D(RXD1),   
      .R(1'b0),   
      .S(1'b0)    
   );

IDDR #(
      .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),  
                                       
      .INIT_Q1(1'b0),  
      .INIT_Q2(1'b0),  
      .SRTYPE("SYNC")  
   ) IDDR_inst_2 (
      .Q1(RXD_IDDR_r[2]),  
      .Q2(RXD_IDDR_f[2]),  
      .C(RXC),    
      .CE(1'b1),  
      .D(RXD2),    
      .R(1'b0),    
      .S(1'b0)     
   );

IDDR #(
      .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),  
                                       
      .INIT_Q1(1'b0),  
      .INIT_Q2(1'b0),  
      .SRTYPE("SYNC")  
   ) IDDR_inst_3 (
      .Q1(RXD_IDDR_r[3]),  
      .Q2(RXD_IDDR_f[3]),  
      .C(RXC),    
      .CE(1'b1),  
      .D(RXD3),    
      .R(1'b0),    
      .S(1'b0)     
   );

IDDR #(
      .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),  
                                       
      .INIT_Q1(1'b0),  
      .INIT_Q2(1'b0),  
      .SRTYPE("SYNC")  
   ) IDDR_inst_ctl (
      .Q1(RX_DV),  
      .Q2(RX_DV_xor_ER),  
      .C(RXC),    
      .CE(1'b1),  
      .D(RX_CTL),    
      .R(1'b0),    
      .S(1'b0)     
   );

assign RX_ER = RX_DV_xor_ER ^ RX_DV;







endmodule


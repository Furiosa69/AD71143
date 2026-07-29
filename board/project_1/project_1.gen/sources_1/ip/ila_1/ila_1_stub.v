// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2023 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2023.2 (win64) Build 4029153 Fri Oct 13 20:14:34 MDT 2023
// Date        : Wed Jul 29 10:57:12 2026
// Host        : LAPTOP-79V8GTMI running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               d:/project/AD71143/board/project_1/project_1.gen/sources_1/ip/ila_1/ila_1_stub.v
// Design      : ila_1
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a200tfbg484-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* X_CORE_INFO = "ila,Vivado 2023.2" *)
module ila_1(clk, probe0, probe1, probe2, probe3, probe4, probe5, 
  probe6, probe7)
/* synthesis syn_black_box black_box_pad_pin="probe0[7:0],probe1[3:0],probe2[3:0],probe3[9:0],probe4[15:0],probe5[15:0],probe6[15:0],probe7[7:0]" */
/* synthesis syn_force_seq_prim="clk" */;
  input clk /* synthesis syn_isclock = 1 */;
  input [7:0]probe0;
  input [3:0]probe1;
  input [3:0]probe2;
  input [9:0]probe3;
  input [15:0]probe4;
  input [15:0]probe5;
  input [15:0]probe6;
  input [7:0]probe7;
endmodule

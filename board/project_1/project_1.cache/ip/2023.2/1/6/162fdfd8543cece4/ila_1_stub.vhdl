-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2023 Advanced Micro Devices, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2023.2 (win64) Build 4029153 Fri Oct 13 20:14:34 MDT 2023
-- Date        : Wed Jul 29 10:57:10 2026
-- Host        : LAPTOP-79V8GTMI running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub -rename_top decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix -prefix
--               decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_ ila_1_stub.vhdl
-- Design      : ila_1
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7a200tfbg484-2
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix is
  Port ( 
    clk : in STD_LOGIC;
    probe0 : in STD_LOGIC_VECTOR ( 7 downto 0 );
    probe1 : in STD_LOGIC_VECTOR ( 3 downto 0 );
    probe2 : in STD_LOGIC_VECTOR ( 3 downto 0 );
    probe3 : in STD_LOGIC_VECTOR ( 9 downto 0 );
    probe4 : in STD_LOGIC_VECTOR ( 15 downto 0 );
    probe5 : in STD_LOGIC_VECTOR ( 15 downto 0 );
    probe6 : in STD_LOGIC_VECTOR ( 15 downto 0 );
    probe7 : in STD_LOGIC_VECTOR ( 7 downto 0 )
  );

end decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix;

architecture stub of decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "clk,probe0[7:0],probe1[3:0],probe2[3:0],probe3[9:0],probe4[15:0],probe5[15:0],probe6[15:0],probe7[7:0]";
attribute X_CORE_INFO : string;
attribute X_CORE_INFO of stub : architecture is "ila,Vivado 2023.2";
begin
end;

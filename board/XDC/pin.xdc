#################################################################################################
## PIN
#################################################################################################

# ---- 系统 ----
set_property PACKAGE_PIN R4 [get_ports sys_clk]
set_property PACKAGE_PIN T3 [get_ports key]

# ---- AD71143 AFE 控制 Panel 0 ----
set_property PACKAGE_PIN G21 [get_ports roic_reset_p0]
set_property PACKAGE_PIN H13 [get_ports sync_p0]
set_property PACKAGE_PIN G13 [get_ports aclk_p0]

# ---- AD71143 AFE 控制 Panel 1 (TBD) ----
set_property PACKAGE_PIN C13 [get_ports roic_reset_p1]
set_property PACKAGE_PIN F13 [get_ports sync_p1]
set_property PACKAGE_PIN F14 [get_ports aclk_p1]

# ---- AD71143 SPI Panel 0 ----
set_property PACKAGE_PIN H15 [get_ports spi_sdo_p0]
set_property PACKAGE_PIN H14 [get_ports spi_cs_p0]
set_property PACKAGE_PIN J14 [get_ports spi_sck_p0]
set_property PACKAGE_PIN J15 [get_ports spi_sdi_p0]

# ---- AD71143 SPI Panel 1 (TBD) ----
set_property PACKAGE_PIN E17 [get_ports spi_sdo_p1]
set_property PACKAGE_PIN B16 [get_ports spi_cs_p1]
set_property PACKAGE_PIN B15 [get_ports spi_sck_p1]
set_property PACKAGE_PIN F16 [get_ports spi_sdi_p1]

# ---- NT39565D 栅极驱动 ----
set_property PACKAGE_PIN AA21 [get_ports cpv_r]
set_property PACKAGE_PIN V9   [get_ports stv1_r]
set_property PACKAGE_PIN V8   [get_ports stv2_r]
set_property PACKAGE_PIN P19  [get_ports oe1_r]
set_property PACKAGE_PIN R19  [get_ports oe2_r]
set_property PACKAGE_PIN AA18 [get_ports ud_r]
set_property PACKAGE_PIN U18  [get_ports lr_r]
set_property PACKAGE_PIN W9   [get_ports mode1_r]
set_property PACKAGE_PIN AA20 [get_ports mode2_r]
set_property PACKAGE_PIN Y8   [get_ports sel_r]
set_property PACKAGE_PIN Y7   [get_ports stv_mode_r]
set_property PACKAGE_PIN Y22  [get_ports chip_sel1_r]
set_property PACKAGE_PIN Y21  [get_ports chip_sel2_r]
set_property PACKAGE_PIN Y9   [get_ports oepsn_r]
set_property PACKAGE_PIN AB18 [get_ports xao_r]

set_property PACKAGE_PIN N13  [get_ports cpv_l]
set_property PACKAGE_PIN W20  [get_ports stv1_l]
set_property PACKAGE_PIN AA19 [get_ports stv2_l]
set_property PACKAGE_PIN N14  [get_ports oe1_l]
set_property PACKAGE_PIN U17  [get_ports oe2_l]
set_property PACKAGE_PIN AB22 [get_ports ud_l]
set_property PACKAGE_PIN AB21 [get_ports lr_l]
set_property PACKAGE_PIN AB20 [get_ports mode1_l]
set_property PACKAGE_PIN W17  [get_ports mode2_l]
set_property PACKAGE_PIN T18  [get_ports sel_l]
set_property PACKAGE_PIN Y18  [get_ports stv_mode_l]
set_property PACKAGE_PIN V17  [get_ports chip_sel1_l]
set_property PACKAGE_PIN R14  [get_ports chip_sel2_l]
set_property PACKAGE_PIN R18  [get_ports oepsn_l]
set_property PACKAGE_PIN W19  [get_ports xao_l]

## set_property PACKAGE_PIN  [get_ports frame_active]
## set_property PACKAGE_PIN  [get_ports frame_done_o]
## set_property PACKAGE_PIN  [get_ports line_done_o]
## set_property PACKAGE_PIN  [get_ports ctrl_init_done_o]

# ---- AD71143 LVDS 数据 Panel 0 ----
set_property PACKAGE_PIN J20 [get_ports dclk_p_A0]
set_property PACKAGE_PIN J21 [get_ports dclk_n_A0]
set_property PACKAGE_PIN G17 [get_ports dout_p_A0]
set_property PACKAGE_PIN G18 [get_ports dout_n_A0]
set_property PACKAGE_PIN G15 [get_ports dout_p_B0]
set_property PACKAGE_PIN G16 [get_ports dout_n_B0]

# ---- AD71143 LVDS 数据 Panel 1 (TBD) ----
set_property PACKAGE_PIN C22 [get_ports dclk_p_A1]
set_property PACKAGE_PIN B22 [get_ports dclk_n_A1]
set_property PACKAGE_PIN E13 [get_ports dout_p_A1]
set_property PACKAGE_PIN E14 [get_ports dout_n_A1]
set_property PACKAGE_PIN B20 [get_ports dout_p_B1]
set_property PACKAGE_PIN A20 [get_ports dout_n_B1]
 
# ---- RGMII ----
set_property PACKAGE_PIN W1  [get_ports rgmii_rst_n]
set_property PACKAGE_PIN W2  [get_ports rgmii_txc]
set_property PACKAGE_PIN Y2  [get_ports rgmii_tx_ctl]
set_property PACKAGE_PIN V4  [get_ports rgmii_txd0]
set_property PACKAGE_PIN W4  [get_ports rgmii_txd1]
set_property PACKAGE_PIN U3  [get_ports rgmii_txd2]
set_property PACKAGE_PIN V3  [get_ports rgmii_txd3]
set_property PACKAGE_PIN T6  [get_ports rgmii_rxc]
set_property PACKAGE_PIN R6  [get_ports rgmii_rx_ctl]
set_property PACKAGE_PIN U5  [get_ports rgmii_rxd0]
set_property PACKAGE_PIN T5  [get_ports rgmii_rxd1]
set_property PACKAGE_PIN V2  [get_ports rgmii_rxd2]
set_property PACKAGE_PIN U2  [get_ports rgmii_rxd3]
set_property PACKAGE_PIN AA1 [get_ports rgmii_mdc]
set_property PACKAGE_PIN AB1 [get_ports rgmii_mdio]

#################################################################################################
## IOSTANDARD
#################################################################################################

# ---- 系统 ----
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports key]

# ---- AD71143 AFE 控制 Panel 0 ----
set_property IOSTANDARD LVCMOS33 [get_ports roic_reset_p0]
set_property IOSTANDARD LVCMOS33 [get_ports sync_p0]
set_property IOSTANDARD LVCMOS33 [get_ports aclk_p0]

# ---- AD71143 AFE 控制 Panel 1 ----
set_property IOSTANDARD LVCMOS33 [get_ports roic_reset_p1]
set_property IOSTANDARD LVCMOS33 [get_ports sync_p1]
set_property IOSTANDARD LVCMOS33 [get_ports aclk_p1]

# ---- AD71143 SPI Panel 0 ----
set_property IOSTANDARD LVCMOS33 [get_ports spi_sdo_p0]
set_property IOSTANDARD LVCMOS33 [get_ports spi_cs_p0]
set_property IOSTANDARD LVCMOS33 [get_ports spi_sck_p0]
set_property IOSTANDARD LVCMOS33 [get_ports spi_sdi_p0]

# ---- AD71143 SPI Panel 1 ----
set_property IOSTANDARD LVCMOS33 [get_ports spi_sdo_p1]
set_property IOSTANDARD LVCMOS33 [get_ports spi_cs_p1]
set_property IOSTANDARD LVCMOS33 [get_ports spi_sck_p1]
set_property IOSTANDARD LVCMOS33 [get_ports spi_sdi_p1]

# ---- NT39565D 栅极驱动 ----
set_property IOSTANDARD LVCMOS33 [get_ports cpv_r]
set_property IOSTANDARD LVCMOS33 [get_ports xao_r]
set_property IOSTANDARD LVCMOS33 [get_ports stv1_r]
set_property IOSTANDARD LVCMOS33 [get_ports stv2_r]
set_property IOSTANDARD LVCMOS33 [get_ports oe1_r]
set_property IOSTANDARD LVCMOS33 [get_ports oe2_r]
set_property IOSTANDARD LVCMOS33 [get_ports ud_r]
set_property IOSTANDARD LVCMOS33 [get_ports lr_r]
set_property IOSTANDARD LVCMOS33 [get_ports mode1_r]
set_property IOSTANDARD LVCMOS33 [get_ports mode2_r]
set_property IOSTANDARD LVCMOS33 [get_ports sel_r]
set_property IOSTANDARD LVCMOS33 [get_ports stv_mode_r]
set_property IOSTANDARD LVCMOS33 [get_ports chip_sel1_r]
set_property IOSTANDARD LVCMOS33 [get_ports chip_sel2_r]
set_property IOSTANDARD LVCMOS33 [get_ports oepsn_r]

set_property IOSTANDARD LVCMOS33 [get_ports cpv_l]
set_property IOSTANDARD LVCMOS33 [get_ports xao_l]
set_property IOSTANDARD LVCMOS33 [get_ports stv1_l]
set_property IOSTANDARD LVCMOS33 [get_ports stv2_l]
set_property IOSTANDARD LVCMOS33 [get_ports oe1_l]
set_property IOSTANDARD LVCMOS33 [get_ports oe2_l]
set_property IOSTANDARD LVCMOS33 [get_ports ud_l]
set_property IOSTANDARD LVCMOS33 [get_ports lr_l]
set_property IOSTANDARD LVCMOS33 [get_ports mode1_l]
set_property IOSTANDARD LVCMOS33 [get_ports mode2_l]
set_property IOSTANDARD LVCMOS33 [get_ports sel_l]
set_property IOSTANDARD LVCMOS33 [get_ports stv_mode_l]
set_property IOSTANDARD LVCMOS33 [get_ports chip_sel1_l]
set_property IOSTANDARD LVCMOS33 [get_ports chip_sel2_l]
set_property IOSTANDARD LVCMOS33 [get_ports oepsn_l]

# ---- 状态输出 ----
# set_property IOSTANDARD LVCMOS33 [get_ports frame_active]
# set_property IOSTANDARD LVCMOS33 [get_ports frame_done_o]
# set_property IOSTANDARD LVCMOS33 [get_ports line_done_o]
# set_property IOSTANDARD LVCMOS33 [get_ports ctrl_init_done_o]

# ---- AD71143 LVDS 数据 Panel 0 ----
set_property IOSTANDARD LVDS_25 [get_ports dclk_p_A0]
set_property IOSTANDARD LVDS_25 [get_ports dclk_n_A0]
set_property IOSTANDARD LVDS_25 [get_ports dout_p_A0]
set_property IOSTANDARD LVDS_25 [get_ports dout_n_A0]
set_property IOSTANDARD LVDS_25 [get_ports dout_p_B0]
set_property IOSTANDARD LVDS_25 [get_ports dout_n_B0]

# ---- AD71143 LVDS 数据 Panel 1 ----
set_property IOSTANDARD LVDS_25 [get_ports dclk_p_A1]
set_property IOSTANDARD LVDS_25 [get_ports dclk_n_A1]
set_property IOSTANDARD LVDS_25 [get_ports dout_p_A1]
set_property IOSTANDARD LVDS_25 [get_ports dout_n_A1]
set_property IOSTANDARD LVDS_25 [get_ports dout_p_B1]
set_property IOSTANDARD LVDS_25 [get_ports dout_n_B1]

# ---- RGMII ----
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_txc]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_tx_ctl]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_txd0]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_txd1]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_txd2]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_txd3]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_rxc]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_rx_ctl]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_rxd0]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_rxd1]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_rxd2]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_rxd3]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_mdc]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_mdio]

#################################################################################################
## BITSTREAM
#################################################################################################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 22 [current_design]

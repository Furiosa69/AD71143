
#################################################################################################
## PIN
#################################################################################################
set_property PACKAGE_PIN R4 [get_ports sys_clk]
set_property PACKAGE_PIN T3 [get_ports key]
set_property PACKAGE_PIN  [get_ports spi_sdo]

set_property PACKAGE_PIN  [get_ports roic_reset]
set_property PACKAGE_PIN  [get_ports sync]
set_property PACKAGE_PIN  [get_ports aclk]
set_property PACKAGE_PIN  [get_ports spi_cs]
set_property PACKAGE_PIN  [get_ports spi_sck]
set_property PACKAGE_PIN  [get_ports spi_sdi]

## ---- NT39 ----
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
set_property PACKAGE_PIN Y20  [get_ports chip_sel1_r]
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

## ---- AD71143 LVDS 数据接口 ----
set_property PACKAGE_PIN   [get_ports dclk_p]
set_property PACKAGE_PIN   [get_ports dclk_n]
set_property PACKAGE_PIN   [get_ports dclko_p_A]
set_property PACKAGE_PIN   [get_ports dclko_n_A]
set_property PACKAGE_PIN   [get_ports dout_p_A]
set_property PACKAGE_PIN   [get_ports dout_n_A]
set_property PACKAGE_PIN   [get_ports dout_p_B]
set_property PACKAGE_PIN   [get_ports dout_n_B]
set_property PACKAGE_PIN   [get_ports merged_burst]
set_property PACKAGE_PIN   [get_ports merged_burst_index]
set_property PACKAGE_PIN   [get_ports merged_valid]
set_property PACKAGE_PIN   [get_ports header_ok]
set_property PACKAGE_PIN   [get_ports rx_line_done]

## ---- RGMII 发送 ----
set_property PACKAGE_PIN   [get_ports rgmii_txc]
set_property PACKAGE_PIN   [get_ports rgmii_tx_ctl]
set_property PACKAGE_PIN   [get_ports rgmii_txd0]
set_property PACKAGE_PIN   [get_ports rgmii_txd1a]
set_property PACKAGE_PIN   [get_ports rgmii_txd2]
set_property PACKAGE_PIN   [get_ports rgmii_txd3]

#################################################################################################
## IOSTAND
#################################################################################################
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports key]
set_property IOSTANDARD LVCMOS33 [get_ports spi_sdo]

set_property IOSTANDARD LVCMOS33 [get_ports roic_reset]
set_property IOSTANDARD LVCMOS33 [get_ports sync]
set_property IOSTANDARD LVCMOS33 [get_ports aclk]
set_property IOSTANDARD LVCMOS33 [get_ports spi_cs]
set_property IOSTANDARD LVCMOS33 [get_ports spi_sck]
set_property IOSTANDARD LVCMOS33 [get_ports spi_sdi]

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

## set_property IOSTANDARD LVCMOS33 [get_ports frame_active]
## set_property IOSTANDARD LVCMOS33 [get_ports frame_done_o]
## set_property IOSTANDARD LVCMOS33 [get_ports line_done_o]
## set_property IOSTANDARD LVCMOS33 [get_ports ctrl_init_done_o]

## ---- AD71143 LVDS 数据接口 ----
set_property IOSTANDARD LVDS_25 [get_ports dclk_p]
set_property IOSTANDARD LVDS_25 [get_ports dclk_n]
set_property IOSTANDARD LVDS_25 [get_ports dclko_p_A]
set_property IOSTANDARD LVDS_25 [get_ports dclko_n_A]
set_property IOSTANDARD LVDS_25 [get_ports dout_p_A]
set_property IOSTANDARD LVDS_25 [get_ports dout_n_A]
set_property IOSTANDARD LVDS_25 [get_ports dout_p_B]
set_property IOSTANDARD LVDS_25 [get_ports dout_n_B]
set_property IOSTANDARD LVCMOS33 [get_ports merged_burst]
set_property IOSTANDARD LVCMOS33 [get_ports merged_burst_index]
set_property IOSTANDARD LVCMOS33 [get_ports merged_valid]
set_property IOSTANDARD LVCMOS33 [get_ports header_ok]
set_property IOSTANDARD LVCMOS33 [get_ports rx_line_done]

## ---- RGMII 发送 ----
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_txc]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_tx_ctl]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_txd0]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_txd1a]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_txd2]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_txd3]


#################################################################################################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 22 [current_design]




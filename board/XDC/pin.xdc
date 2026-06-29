
#################################################################################################
## PIN
#################################################################################################
set_property PACKAGE_PIN R4 [get_ports sys_clk]
set_property PACKAGE_PIN T3 [get_ports key]

set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports key]

#################################################################################################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 22 [current_design]




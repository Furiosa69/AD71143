open_checkpoint D:/project/AD71143/board/project_1/project_1.runs/impl_1/top_routed.dcp
set read_gap [get_cells -hier -filter {NAME =~ *read_gap_cnt*}]
puts "READ_GAP_CELLS=[llength $read_gap]"
foreach cell $read_gap { puts [get_property NAME $cell] }
set read_state [get_cells -hier -filter {NAME =~ *state_reg*}]
puts "SPI_STATE_CELLS=[llength [get_cells -hier -filter {NAME =~ *u_spi_p1*state*}]]"
exit

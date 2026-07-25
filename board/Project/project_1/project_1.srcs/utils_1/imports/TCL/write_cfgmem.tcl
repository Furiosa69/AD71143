
set tcl_Dir [file dirname [info script]]
set pj_Dir  [file normalize "$tcl_Dir/../../../../"]

set top_name   top
set mcs_width  SPIx4
set flash_size 128 

write_cfgmem -format mcs -interface $mcs_width -size $flash_size -loadbit "up 0x0 ${pj_Dir}/project_1.runs/impl_1/${top_name}.bit" -force -file ${pj_Dir}/Result/${top_name}.mcs
write_cfgmem -format bin -interface $mcs_width -size $flash_size -loadbit "up 0x0 ${pj_Dir}/project_1.runs/impl_1/${top_name}.bit" -force -file ${pj_Dir}/Result/${top_name}.bin

file copy -force ${pj_Dir}/project_1.runs/impl_1/${top_name}.bit ${pj_Dir}/Result/ 


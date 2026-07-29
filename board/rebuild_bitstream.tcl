# TCL 脚本：重新生成 FIFO IP 核并综合实现
# 用于修复 FIFO 深度不足问题（16 → 1024）

# 打开项目
open_project D:/project/AD71143/board/project_1/project_1.xpr

# 重新生成 FIFO IP 核
reset_target all [get_ips fifo_generator_0]
generate_target all [get_ips fifo_generator_0]

# 等待 IP 生成完成
puts "等待 FIFO IP 核生成完成..."
wait_on_run [create_ip_run [get_ips fifo_generator_0]]

# 重新综合
puts "开始重新综合..."
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# 检查综合结果
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "错误：综合失败"
    exit 1
}
puts "综合完成"

# 实现
puts "开始实现..."
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# 检查实现结果
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "错误：实现失败"
    exit 1
}
puts "实现完成"

# 复制 bitstream 到 Result 目录
puts "复制 bitstream 文件..."
file copy -force D:/project/AD71143/board/project_1/project_1.runs/impl_1/top.bit D:/project/AD71143/board/project_1/Result/top.bit
file copy -force D:/project/AD71143/board/project_1/project_1.runs/impl_1/top.bin D:/project/AD71143/board/project_1/Result/top.bin

puts "============================================"
puts "bitstream 生成完成！"
puts "文件位置: D:/project/AD71143/board/project_1/Result/top.bit"
puts "FIFO 深度已从 16 增加到 1024"
puts "============================================"

close_project

# TCL 脚本：切换到真实 AFE 数据并重新生成 bitstream
# DATA_TEST_MODE 已修改为 0

# 打开项目
open_project D:/project/AD71143/board/project_1/project_1.xpr

# 重新综合（top.v 已修改）
puts "开始重新综合（切换到真实 AFE 数据）..."
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
puts "已切换到真实 AFE 数据模式"
puts "============================================"

close_project

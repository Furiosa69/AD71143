"""
快速验证脚本：判断接收的是测试数据还是真实 AFE 数据
"""

import socket
import struct
import sys

def check_data_type():
    """检查接收的数据类型"""

    print("=" * 70)
    print("AD71143 数据类型验证工具")
    print("=" * 70)
    print()
    print("正在监听 UDP 端口 1234...")
    print("等待数据包...\n")

    try:
        # 创建 socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(('0.0.0.0', 1234))
        sock.settimeout(5.0)  # 5 秒超时

        # 接收数据包
        data, addr = sock.recvfrom(4096)

        print(f"✅ 收到数据包：{len(data)} bytes，来自 {addr}")
        print()

        # 提取 Payload（最后 32 bytes）
        if len(data) < 32:
            print(f"❌ 错误：数据包太短（{len(data)} < 32 bytes）")
            return

        payload = data[-32:]

        # 显示原始数据
        print("原始 Payload (32 bytes):")
        for i in range(0, 32, 16):
            hex_str = ' '.join(f'{b:02X}' for b in payload[i:i+16])
            print(f"  {i:02d}-{i+15:02d}: {hex_str}")
        print()

        # ===================================================================
        # 检查 1：是否是测试数据
        # ===================================================================

        # 测试数据特征：
        # Bytes 0-3: 递增序号
        # Bytes 4-31: 固定模式 (04, 05, 06, ..., 1F)

        test_pattern = bytes(range(4, 32))
        if payload[4:32] == test_pattern:
            print("⚠️  检测结果：当前是 **测试数据**")
            print()

            # 解析测试序号
            seq_num = struct.unpack('>I', payload[0:4])[0]
            print(f"    测试包序号：{seq_num}")
            print()

            print("可能原因：")
            print("  1. AD71143 未正确配置（SPI 初始化未完成）")
            print("  2. 传感器无光信号输入（检查光源）")
            print("  3. LVDS 连接问题（检查排线）")
            print("  4. AD71143 增益/积分时间配置不当")
            print()

            print("排查步骤：")
            print("  1. 使用 ILA 检查 merged_valid 信号是否有脉冲")
            print("  2. 检查 AD71143 SPI 配置是否完成")
            print("  3. 确认传感器和光源正常工作")
            print("  4. 检查 LVDS 差分信号质量")

            return

        # ===================================================================
        # 检查 2：是否是真实 AFE 数据
        # ===================================================================

        print("✅ 检测结果：当前是 **真实 AFE 数据**")
        print()

        # 检查 Panel 1（应该有数据，Bytes 0-15）
        # 注意：RGMII 使用 MSB first 打包
        # merged_burst[255:128] (Panel 1) → Bytes 0-15
        panel1 = payload[0:16]
        panel1_zeros = sum(1 for b in panel1 if b == 0)
        panel1_nonzeros = 16 - panel1_zeros

        print(f"Panel 1 (Bytes 0-15):  {panel1_nonzeros}/16 字节非零")
        if panel1_nonzeros > 0:
            print("  ✅ 有数据（正常）")
        else:
            print("  ⚠️  全为 0（可能传感器无光输入）")
        print()

        # 检查 Panel 0（应该全为 0，Bytes 16-31）
        panel0 = payload[16:32]
        panel0_zeros = sum(1 for b in panel0 if b == 0)

        print(f"Panel 0 (Bytes 16-31): {panel0_zeros}/16 字节为零")
        if panel0_zeros == 16:
            print("  ✅ 正确（测试模式下 Panel 0 填充 0）")
        else:
            print("  ⚠️  异常（应该全为 0）")
            print("  ⚠️  全为 0（可能传感器无光输入）")
        print()

        # 解析 Panel 1 的 8 个通道
        print("Panel 1 通道值（8 个通道 × 16 bits）：")
        channels = []
        for i in range(8):
            offset = i * 2  # Panel 1 从 byte 0 开始
            value = struct.unpack('>H', payload[offset:offset+2])[0]
            channels.append(value)
            print(f"  通道 {i}: {value:5d} (0x{value:04X})")
        print()

        # 统计信息
        min_val = min(channels)
        max_val = max(channels)
        avg_val = sum(channels) / len(channels)

        print("统计信息：")
        print(f"  最小值: {min_val}")
        print(f"  最大值: {max_val}")
        print(f"  平均值: {avg_val:.1f}")
        print(f"  动态范围: {max_val - min_val}")
        print()

        # 数据质量评估
        if max_val == 0:
            print("⚠️  警告：所有通道值为 0（传感器可能无光输入）")
        elif max_val == 65535:
            print("⚠️  警告：有通道饱和（增益可能过高）")
        elif max_val < 100:
            print("⚠️  警告：信号幅度很低（增益可能过低或无光输入）")
        else:
            print("✅ 数据质量正常")

    except socket.timeout:
        print("❌ 超时：5 秒内未收到数据包")
        print()
        print("可能原因：")
        print("  1. FPGA 未下载或未运行")
        print("  2. 网卡 IP 配置错误（应该是 192.168.1.1）")
        print("  3. 网线未连接或网卡故障")
        print("  4. 防火墙阻止 UDP 端口 1234")
        print()
        print("排查步骤：")
        print("  1. ping 192.168.1.2（可能不通，这是正常的）")
        print("  2. 使用 Wireshark 抓包，查看是否有 UDP 流量")
        print("  3. 检查网卡链路 LED 是否亮起")
        print("  4. 临时关闭防火墙测试")

    except Exception as e:
        print(f"❌ 错误：{e}")
        import traceback
        traceback.print_exc()

    finally:
        sock.close()

if __name__ == '__main__':
    try:
        check_data_type()
    except KeyboardInterrupt:
        print("\n\n用户中断")

    print()
    print("=" * 70)

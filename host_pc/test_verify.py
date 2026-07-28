"""
AD71143 测试数据验证脚本
直接抓取网络数据包并验证测试模式的数据格式
"""

import socket
import struct
import numpy as np

def parse_udp_packet(packet_data):
    """解析 UDP 数据包"""
    # 检查包长度
    if len(packet_data) < 42 + 32:
        return None, None

    # 解析 IP 头
    ip_src = packet_data[26:30]
    ip_protocol = packet_data[23]

    # 检查是否为 UDP (17)
    if ip_protocol != 17:
        return None, None

    # 验证源 IP
    if ip_src != bytes([192, 168, 1, 2]):
        return None, None

    # 解析 UDP 头
    udp_src_port = struct.unpack('>H', packet_data[34:36])[0]
    udp_dst_port = struct.unpack('>H', packet_data[36:38])[0]

    # 验证端口
    if udp_src_port != 1234 or udp_dst_port != 1234:
        return None, None

    # 提取 payload
    payload = packet_data[42:42+32]

    if len(payload) != 32:
        return None, None

    return payload, udp_src_port

def verify_test_pattern(payload):
    """验证测试模式数据格式"""
    # 测试模式格式:
    # Payload[0:3] = 32-bit 序号
    # Payload[4:31] = 递增字节 (04 05 06 ... 1F)

    seq_num = struct.unpack('>I', payload[0:4])[0]
    pattern = payload[4:32]

    # 验证递增模式
    expected = bytes(range(4, 32))
    is_valid = (pattern == expected)

    return seq_num, is_valid, pattern

def main():
    """主函数"""
    print("=" * 60)
    print("AD71143 测试数据验证工具")
    print("=" * 60)
    print()
    print("正在监听 UDP 端口 1234...")
    print("请确保 FPGA 已连接并启用测试模式 (TEST_MODE = 1)")
    print()

    # 创建 UDP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('0.0.0.0', 1234))
    sock.settimeout(5.0)

    packet_count = 0
    valid_count = 0
    invalid_count = 0
    last_seq_num = None
    seq_gaps = []

    try:
        print("开始接收数据包...")
        print("-" * 60)

        while packet_count < 100:  # 接收前 100 个包
            try:
                data, addr = sock.recvfrom(65535)

                # 解析 UDP payload（直接从 socket 接收的是 payload，不包含以太网/IP/UDP 头）
                if len(data) == 32:
                    payload = data
                else:
                    # 如果收到完整的以太网帧，需要解析
                    continue

                # 验证测试模式
                seq_num, is_valid, pattern = verify_test_pattern(payload)

                packet_count += 1

                if is_valid:
                    valid_count += 1
                    status = "✓ 正确"
                else:
                    invalid_count += 1
                    status = "✗ 错误"

                # 检查序号连续性
                if last_seq_num is not None:
                    gap = seq_num - last_seq_num
                    if gap != 1:
                        seq_gaps.append((last_seq_num, seq_num, gap))

                last_seq_num = seq_num

                # 显示前 10 个包的详细信息
                if packet_count <= 10:
                    print(f"包 {packet_count:3d}: 序号={seq_num:6d} {status}")
                    print(f"  前8字节: {payload[0:8].hex(' ')}")
                    print(f"  后8字节: {payload[24:32].hex(' ')}")
                    if not is_valid:
                        print(f"  期望: 04 05 06 07 08 09 0a 0b ... 1e 1f")
                        print(f"  实际: {pattern[0:8].hex(' ')} ... {pattern[24:28].hex(' ')}")
                    print()

            except socket.timeout:
                print("等待数据超时 (5秒)")
                break

        print("-" * 60)
        print(f"\n统计信息:")
        print(f"  总接收包数: {packet_count}")
        print(f"  正确包数: {valid_count}")
        print(f"  错误包数: {invalid_count}")
        print(f"  正确率: {valid_count/packet_count*100:.1f}%")

        if seq_gaps:
            print(f"\n序号跳跃:")
            for prev, curr, gap in seq_gaps[:5]:  # 显示前 5 个跳跃
                print(f"  {prev} → {curr} (跳过 {gap-1} 个)")

        print("\n结论:")
        if valid_count == packet_count:
            print("  ✓ 测试数据格式完全正确！")
            print("  ✓ FPGA 测试模式工作正常")
            print("  → 问题可能在上位机的图像重建算法")
        elif valid_count > 0:
            print("  ⚠ 测试数据部分正确")
            print("  → 可能有丢包或数据损坏")
        else:
            print("  ✗ 测试数据格式错误")
            print("  → 请检查 FPGA 是否启用了测试模式")
            print("  → 或者检查网络连接")

    except KeyboardInterrupt:
        print("\n用户中断")
    finally:
        sock.close()

if __name__ == "__main__":
    main()

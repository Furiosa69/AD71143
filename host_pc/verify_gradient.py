"""
验证水平渐变测试图像数据
每个 UDP 包包含 16 个 16-bit 样本（大端序）
"""

import socket
import struct
import numpy as np
import sys
import io

# 修复 Windows 控制台编码问题
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

def parse_udp_packet(packet_data):
    """解析 UDP 数据包"""
    if len(packet_data) < 42 + 32:
        return None

    # 验证 IP/UDP 协议
    if packet_data[23] != 17:  # UDP
        return None

    # 验证源 IP = 192.168.1.2
    if packet_data[26:30] != bytes([192, 168, 1, 2]):
        return None

    # 提取 payload (32 字节)
    payload = packet_data[42:42+32]

    if len(payload) != 32:
        return None

    return payload

def parse_samples(payload):
    """解析 16 个 16-bit 样本（大端序）"""
    samples = []
    for i in range(16):
        sample = struct.unpack('>H', payload[i*2:i*2+2])[0]
        samples.append(sample)
    return samples

def main():
    # 创建 UDP 套接字监听
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('192.168.1.1', 1234))
    sock.settimeout(5.0)

    print("开始捕获数据包...")
    print("期望：所有样本值应该相同（同一行的像素值相同）")
    print("期望：不同包的样本值应该递增（不同行的像素值递增）\n")

    packet_count = 0
    samples_stats = []

    try:
        while packet_count < 100:
            try:
                payload, addr = sock.recvfrom(2048)
            except socket.timeout:
                print("超时：未收到数据包")
                break

            # 验证源地址
            if addr[0] != '192.168.1.2':
                continue

            if len(payload) != 32:
                print(f"警告：payload 长度 = {len(payload)}，期望 32")
                continue

            samples = parse_samples(payload)
            samples_stats.append(samples)

            # 显示前 10 个包的详细信息
            if packet_count < 10:
                print(f"包 #{packet_count}:")
                print(f"  样本值: {samples[:8]} (前8个) | {samples[8:]} (后8个)")

                # 显示原始字节（16进制）
                hex_bytes = ' '.join(f'{b:02X}' for b in payload[:16])
                print(f"  前16字节: {hex_bytes}")
                hex_bytes = ' '.join(f'{b:02X}' for b in payload[16:32])
                print(f"  后16字节: {hex_bytes}")

                print(f"  最小值: {min(samples)}, 最大值: {max(samples)}, 平均值: {np.mean(samples):.1f}")

                # 检查同一包内的样本是否相同
                if len(set(samples)) == 1:
                    print(f"  ✓ 同一包内所有样本相同")
                else:
                    unique_vals = sorted(set(samples))
                    print(f"  ✗ 同一包内样本不一致！唯一值: {unique_vals}")
                print()

            packet_count += 1

    except KeyboardInterrupt:
        print(f"\n捕获结束，共 {packet_count} 个包\n")

    # 统计分析
    if samples_stats:
        print("=" * 60)
        print("统计分析:")

        # 每个包的平均值
        avg_values = [np.mean(s) for s in samples_stats]

        print(f"  包数: {len(samples_stats)}")
        print(f"  样本值范围: {min([min(s) for s in samples_stats])} ~ {max([max(s) for s in samples_stats])}")
        print(f"  包平均值范围: {min(avg_values):.1f} ~ {max(avg_values):.1f}")

        # 检查是否有递增趋势（移动平均）
        if len(avg_values) > 10:
            first_10_avg = np.mean(avg_values[:10])
            last_10_avg = np.mean(avg_values[-10:])
            print(f"  前 10 包平均: {first_10_avg:.1f}")
            print(f"  后 10 包平均: {last_10_avg:.1f}")

            if last_10_avg > first_10_avg:
                print(f"  ✓ 检测到递增趋势（渐变）")
            else:
                print(f"  ✗ 未检测到递增趋势")

        # 检查是否全零
        all_zero = all(s == 0 for samples in samples_stats for s in samples)
        if all_zero:
            print(f"  ✗ 警告：所有样本都是 0！")
        else:
            print(f"  ✓ 样本值非零")

if __name__ == '__main__':
    main()

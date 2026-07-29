"""
调试帧同步 - 检查是否正确检测到帧起始包
"""

import socket
import struct
import sys
import io

# 修复 Windows 控制台编码
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

FRAME_MAGIC = 0xAA55AA55

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

def is_frame_start(payload):
    """检查是否为帧起始包"""
    if len(payload) < 4:
        return False
    magic = struct.unpack('>I', payload[0:4])[0]
    return magic == FRAME_MAGIC

def main():
    # 创建 UDP 套接字
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('192.168.1.1', 1234))
    sock.settimeout(5.0)

    print("开始监听数据包...")
    print(f"帧起始魔数: 0x{FRAME_MAGIC:08X}\n")

    packet_count = 0
    frame_start_count = 0
    last_frame_packets = 0

    try:
        while packet_count < 1000:
            try:
                payload, addr = sock.recvfrom(2048)
            except socket.timeout:
                print("超时：未收到数据包")
                break

            if addr[0] != '192.168.1.2':
                continue

            if len(payload) != 32:
                continue

            # 检查前 4 字节
            magic = struct.unpack('>I', payload[0:4])[0]

            if is_frame_start(payload):
                print(f"\n✓ 帧起始包 #{frame_start_count + 1}")
                print(f"  包编号: {packet_count}")
                print(f"  距上一帧: {packet_count - last_frame_packets} 个包")
                print(f"  魔数: 0x{magic:08X}")
                print(f"  后续数据: {' '.join(f'{b:02X}' for b in payload[4:12])}...")

                frame_start_count += 1
                last_frame_packets = packet_count

            # 显示前 10 个非帧起始包的魔数位置内容
            elif packet_count < 10:
                print(f"包 #{packet_count}: 前4字节 = 0x{magic:08X}")

            packet_count += 1

    except KeyboardInterrupt:
        print(f"\n\n捕获结束")

    print("\n" + "=" * 60)
    print("统计:")
    print(f"  总包数: {packet_count}")
    print(f"  帧起始包数: {frame_start_count}")

    if frame_start_count > 1:
        avg_packets_per_frame = packet_count / frame_start_count
        expected_packets = 64 * 541  # 64 bursts/行 × 541 行
        print(f"  平均每帧包数: {avg_packets_per_frame:.1f}")
        print(f"  期望每帧包数: {expected_packets}")

        if abs(avg_packets_per_frame - expected_packets) < 100:
            print(f"  ✓ 包数正常")
        else:
            print(f"  ✗ 包数异常")

    if frame_start_count == 0:
        print(f"  ✗ 警告：未检测到帧起始包！")
        print(f"  → FPGA 可能未生成帧起始标记")
        print(f"  → 或者魔数值不匹配")
    else:
        print(f"  ✓ 帧同步正常工作")

if __name__ == '__main__':
    main()

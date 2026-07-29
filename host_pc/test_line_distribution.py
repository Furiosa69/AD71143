"""
测试接收到的行数分布
检查是否每帧都是 ~309 行还是有变化
"""

import socket
import struct
import time

# 配置
LISTEN_IP = "0.0.0.0"
PORT = 1234
BURSTS_PER_LINE = 64

def parse_udp_packet(packet_data):
    """解析 UDP 包，返回 payload"""
    if len(packet_data) < 74:
        return None

    # 验证端口
    udp_src_port = struct.unpack('>H', packet_data[34:36])[0]
    udp_dst_port = struct.unpack('>H', packet_data[36:38])[0]

    if udp_src_port != 1234 or udp_dst_port != 1234:
        return None

    payload = packet_data[42:42+32]
    if len(payload) != 32:
        return None

    return payload

def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((LISTEN_IP, PORT))

    print("开始监听，统计每帧的行数分布...\n")

    burst_count = 0
    line_count = 0
    frame_lines = []
    last_time = time.time()
    gap_threshold = 0.01  # 10ms

    try:
        while len(frame_lines) < 20:  # 收集 20 帧数据
            packet_data, _ = sock.recvfrom(2048)

            # UDP socket 直接返回 payload，不包含以太网/IP/UDP 头
            if len(packet_data) != 32:
                continue

            current_time = time.time()
            time_gap = current_time - last_time

            # 检测帧间隔
            if time_gap > gap_threshold and burst_count > 100:
                # 计算上一帧的行数
                lines = burst_count // BURSTS_PER_LINE
                frame_lines.append(lines)
                print(f"帧 #{len(frame_lines)}: {lines} 行 ({burst_count} 个 burst)")

                # 重置计数器
                burst_count = 0
                line_count = 0

            burst_count += 1
            if burst_count % BURSTS_PER_LINE == 0:
                line_count += 1

            last_time = current_time

    except KeyboardInterrupt:
        pass

    sock.close()

    if frame_lines:
        print(f"\n统计结果 ({len(frame_lines)} 帧):")
        print(f"  最小行数: {min(frame_lines)}")
        print(f"  最大行数: {max(frame_lines)}")
        print(f"  平均行数: {sum(frame_lines) / len(frame_lines):.1f}")
        print(f"  期望行数: 541")

if __name__ == "__main__":
    main()

"""
监控行号变化，找出实际的跳变模式
"""

import socket
import struct
import numpy as np

LISTEN_IP = "0.0.0.0"
PORT = 1234

def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((LISTEN_IP, PORT))

    print("监控行号变化，查找帧边界模式...\n")

    last_line = -1
    packet_count = 0
    jumps = []

    try:
        while len(jumps) < 10:
            packet_data, _ = sock.recvfrom(2048)

            if len(packet_data) != 32:
                continue

            packet_count += 1

            # 解析样本
            samples = []
            for i in range(0, 32, 2):
                val = struct.unpack('>H', packet_data[i:i+2])[0]
                samples.append(val)

            avg_value = np.mean(samples)
            inferred_line = int(avg_value / 121)

            # 检测行号变化
            if last_line >= 0:
                diff = inferred_line - last_line

                # 记录所有的行号下降
                if diff < -50:
                    jumps.append((packet_count, last_line, inferred_line, diff))
                    print(f"包 #{packet_count}: 行号从 {last_line} → {inferred_line} (Δ={diff})")

            last_line = inferred_line

            if packet_count % 10000 == 0:
                print(f"[已检查 {packet_count} 个包，检测到 {len(jumps)} 次跳变]")

    except KeyboardInterrupt:
        pass

    sock.close()

    print(f"\n总结:")
    print(f"  检查包数: {packet_count}")
    print(f"  检测到跳变: {len(jumps)} 次")

    if jumps:
        print(f"\n跳变模式:")
        for idx, (pkt, from_line, to_line, diff) in enumerate(jumps):
            print(f"  #{idx+1}: {from_line} → {to_line} (Δ={diff})")

        # 计算平均间隔
        if len(jumps) > 1:
            intervals = [jumps[i+1][0] - jumps[i][0] for i in range(len(jumps)-1)]
            avg_interval = sum(intervals) / len(intervals)
            print(f"\n平均包间隔: {avg_interval:.0f} 个包")

if __name__ == "__main__":
    main()

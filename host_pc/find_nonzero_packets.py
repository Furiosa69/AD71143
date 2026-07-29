"""
持续监听数据包，显示非零包的内容
"""

import socket
import struct
import time

LISTEN_IP = "0.0.0.0"
PORT = 1234

def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((LISTEN_IP, PORT))

    print("持续监听，显示前 20 个非零数据包...")
    print("查找魔数 0xAA55\n")

    packet_count = 0
    non_zero_count = 0

    start_time = time.time()

    while non_zero_count < 20:
        packet_data, _ = sock.recvfrom(2048)

        if len(packet_data) != 32:
            continue

        packet_count += 1

        # 检查是否全零
        is_all_zero = all(b == 0 for b in packet_data)

        if not is_all_zero:
            non_zero_count += 1
            print(f"\n非零包 #{non_zero_count} (总包数={packet_count}):")

            # 显示 16-bit 值
            values = []
            has_magic = False
            for i in range(0, 32, 2):
                val = struct.unpack('>H', packet_data[i:i+2])[0]
                values.append(val)
                if val == 0xAA55:
                    has_magic = True

            # 显示前 8 个值（Panel 0）
            print(f"  Panel 0: {values[0:8]}")
            # 显示后 8 个值（Panel 1）
            print(f"  Panel 1: {values[8:16]}")

            if has_magic:
                print(f"  ✓ 检测到魔数 0xAA55！")

        # 每 10000 个包报告一次
        if packet_count % 10000 == 0:
            elapsed = time.time() - start_time
            print(f"[{elapsed:.1f}s] 已接收 {packet_count} 个包，非零包={non_zero_count}")

    sock.close()
    print(f"\n完成！共检查 {packet_count} 个包")

if __name__ == "__main__":
    main()

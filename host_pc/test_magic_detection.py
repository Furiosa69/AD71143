"""
测试魔数检测
检查是否能检测到帧起始标记 0xAA55
"""

import socket
import struct

LISTEN_IP = "0.0.0.0"
PORT = 1234

def check_magic(payload):
    """检查最后两个字节是否为 0xAA55"""
    if len(payload) != 32:
        return False
    magic = struct.unpack('>H', payload[30:32])[0]
    return magic == 0xAA55

def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((LISTEN_IP, PORT))

    print("监听魔数 0xAA55...")
    print("按 Ctrl+C 停止\n")

    packet_count = 0
    magic_count = 0

    try:
        while True:
            packet_data, _ = sock.recvfrom(2048)

            if len(packet_data) != 32:
                continue

            packet_count += 1

            if check_magic(packet_data):
                magic_count += 1
                print(f"✓ 检测到魔数！包 #{packet_count}")

                # 显示魔数包的所有样本值
                print(f"  魔数包内容: ", end="")
                for i in range(0, 32, 2):
                    val = struct.unpack('>H', packet_data[i:i+2])[0]
                    print(f"{val:5d}", end=" ")
                print()

            if packet_count % 10000 == 0:
                print(f"已接收 {packet_count} 个包，检测到 {magic_count} 个魔数")

    except KeyboardInterrupt:
        print(f"\n\n总计:")
        print(f"  接收包数: {packet_count}")
        print(f"  魔数包数: {magic_count}")
        if packet_count > 0:
            print(f"  魔数比例: {magic_count / packet_count * 100:.2f}%")

    sock.close()

if __name__ == "__main__":
    main()

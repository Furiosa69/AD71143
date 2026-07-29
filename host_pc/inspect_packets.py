"""
查看实际接收到的数据包内容
找出魔数 0xAA55 的位置
"""

import socket
import struct

LISTEN_IP = "0.0.0.0"
PORT = 1234

def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((LISTEN_IP, PORT))

    print("接收数据包并显示前 10 个包的内容...")
    print("查找魔数 0xAA55 的位置\n")

    for pkt_idx in range(10):
        packet_data, _ = sock.recvfrom(2048)

        if len(packet_data) != 32:
            continue

        print(f"\n包 #{pkt_idx + 1}:")
        print("  十六进制:")
        for i in range(0, 32, 16):
            hex_str = ' '.join(f"{packet_data[i+j]:02x}" for j in range(min(16, 32-i)))
            print(f"    [{i:2d}-{i+15:2d}] {hex_str}")

        print("  16-bit 值 (大端序):")
        for i in range(0, 32, 2):
            val = struct.unpack('>H', packet_data[i:i+2])[0]
            print(f"    [{i:2d}:{i+1:2d}] = 0x{val:04X} = {val:5d}", end="")
            if val == 0xAA55:
                print("  ← 魔数!", end="")
            print()

    sock.close()

if __name__ == "__main__":
    main()

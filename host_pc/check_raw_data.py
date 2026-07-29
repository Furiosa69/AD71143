#!/usr/bin/env python3
"""检查接收到的原始UDP包数据"""

import socket
import struct
import sys

UDP_IP = "0.0.0.0"
UDP_PORT = 8080

print("创建UDP socket...")
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

# 设置端口复用，允许多个程序监听同一端口
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

try:
    sock.bind((UDP_IP, UDP_PORT))
    print(f"✓ 绑定到 {UDP_IP}:{UDP_PORT}")
except OSError as e:
    print(f"✗ 端口绑定失败: {e}")
    print("请先关闭其他占用8080端口的程序")
    sys.exit(1)

sock.settimeout(5.0)

print("监听 UDP 包，检查原始数据...")
print("=" * 60)

try:
    for i in range(20):  # 检查前20个包
        try:
            data, addr = sock.recvfrom(2048)

            # 解析包头
            if len(data) >= 8:
                line_num = struct.unpack('<H', data[0:2])[0]
                burst_idx = struct.unpack('<H', data[2:4])[0]

                # 检查payload
                payload = data[8:]
                non_zero_count = sum(1 for b in payload if b != 0)

                # 显示前16字节的hex
                hex_preview = ' '.join(f'{b:02x}' for b in payload[:16])

                print(f"包 #{i+1}: Line={line_num:3d} Burst={burst_idx:2d} "
                      f"非零字节={non_zero_count:3d}/{len(payload)} "
                      f"前16字节: {hex_preview}")

                if non_zero_count > 0:
                    print(f"  ✓ 发现非零数据！")
                    # 显示所有非零字节的位置和值
                    non_zero = [(idx, b) for idx, b in enumerate(payload) if b != 0]
                    if len(non_zero) <= 10:
                        for idx, val in non_zero:
                            print(f"    [{idx}] = 0x{val:02x} ({val})")

        except socket.timeout:
            print(f"超时：5秒内未收到数据")
            break

except KeyboardInterrupt:
    print("\n停止监听")
finally:
    sock.close()

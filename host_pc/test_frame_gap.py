"""
测试帧间隔 - 检查包之间的时间间隔
"""

import socket
import time
import sys
import io

# 修复 Windows 控制台编码
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

def main():
    # 创建 UDP 套接字
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('192.168.1.1', 1234))
    sock.settimeout(5.0)

    print("开始监听数据包，测量时间间隔...")
    print("期望：大部分包间隔 < 1ms，每帧之间有 > 10ms 的间隔\n")

    packet_count = 0
    last_time = None
    gaps = []

    try:
        while packet_count < 50000:  # 捕获足够多的包来观察至少一个帧间隔
            try:
                payload, addr = sock.recvfrom(2048)
                current_time = time.time()
            except socket.timeout:
                print("超时：未收到数据包")
                break

            if addr[0] != '192.168.1.2':
                continue

            if len(payload) != 32:
                continue

            # 计算时间间隔
            if last_time is not None:
                gap_ms = (current_time - last_time) * 1000
                gaps.append(gap_ms)

                # 检测大间隔
                if gap_ms > 5.0:
                    print(f"✓ 检测到大间隔: 包 #{packet_count}, 间隔 = {gap_ms:.2f}ms")

            last_time = current_time
            packet_count += 1

            # 每 1000 个包显示一次进度
            if packet_count % 1000 == 0:
                print(f"  已接收 {packet_count} 个包...")

    except KeyboardInterrupt:
        print(f"\n\n捕获结束")

    if len(gaps) > 0:
        import numpy as np
        gaps_array = np.array(gaps)

        print("\n" + "=" * 60)
        print("时间间隔统计:")
        print(f"  总包数: {packet_count}")
        print(f"  平均间隔: {np.mean(gaps_array):.3f}ms")
        print(f"  最小间隔: {np.min(gaps_array):.3f}ms")
        print(f"  最大间隔: {np.max(gaps_array):.3f}ms")
        print(f"  中位数间隔: {np.median(gaps_array):.3f}ms")

        # 统计大间隔
        large_gaps = gaps_array[gaps_array > 5.0]
        if len(large_gaps) > 0:
            print(f"\n  检测到 {len(large_gaps)} 个大间隔 (>5ms):")
            for i, gap in enumerate(large_gaps[:10]):  # 只显示前 10 个
                print(f"    #{i+1}: {gap:.2f}ms")
            if len(large_gaps) > 10:
                print(f"    ... 还有 {len(large_gaps) - 10} 个")

            # 计算帧率
            if len(large_gaps) > 1:
                avg_frame_interval = np.mean(np.diff(np.where(gaps_array > 5.0)[0]))
                packets_per_frame = avg_frame_interval
                expected_packets = 64 * 541  # 34624
                print(f"\n  平均每帧包数: {packets_per_frame:.0f}")
                print(f"  期望每帧包数: {expected_packets}")
                if abs(packets_per_frame - expected_packets) < 1000:
                    print(f"  ✓ 帧间隔工作正常")
                else:
                    print(f"  ✗ 帧间隔异常")
        else:
            print(f"\n  ✗ 未检测到帧间隔！FPGA 可能未插入帧间隔")
            print(f"  → 所有包都连续发送，没有停顿")

if __name__ == '__main__':
    main()

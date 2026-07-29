"""
调试工具：检查每帧接收到的实际图像内容
分析图像滚动的根本原因
"""

import socket
import struct
import numpy as np

# 配置
LISTEN_IP = "0.0.0.0"
PORT = 1234
BURSTS_PER_LINE = 64
SAMPLES_PER_BURST = 16
PIXELS_PER_LINE = 512
FRAME_LINES = 541

def parse_samples(payload):
    """从 32 字节 payload 提取 16 个样本"""
    samples = []
    for i in range(0, 32, 2):
        sample = struct.unpack('>H', payload[i:i+2])[0]
        samples.append(sample)
    return np.array(samples, dtype=np.uint16)

def analyze_frame(frame_buffer):
    """
    分析帧内容，推断实际的行号
    因为每行像素值 = line_num * 121，可以反推行号
    """
    line_values = []
    for line_idx in range(len(frame_buffer)):
        line_data = frame_buffer[line_idx]
        # 取该行的平均值（应该都是相同值）
        avg_val = np.mean(line_data[line_data > 0])  # 忽略零值
        if not np.isnan(avg_val) and avg_val > 0:
            # 反推行号：line_num = pixel_value / 121
            inferred_line = int(avg_val / 121)
            line_values.append((line_idx, avg_val, inferred_line))

    return line_values

def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((LISTEN_IP, PORT))

    print("开始接收并分析图像内容...")
    print("检查帧边界是否对齐\n")

    # 帧缓冲
    frame_buffer = np.zeros((FRAME_LINES, PIXELS_PER_LINE), dtype=np.uint16)
    current_line = 0
    current_burst = 0
    packet_count = 0
    frame_count = 0

    try:
        while frame_count < 5:  # 分析 5 帧
            packet_data, _ = sock.recvfrom(2048)

            if len(packet_data) != 32:
                continue

            packet_count += 1
            samples = parse_samples(packet_data)

            # 写入缓冲区
            if current_line < FRAME_LINES:
                start_col = current_burst * SAMPLES_PER_BURST
                end_col = min(start_col + SAMPLES_PER_BURST, PIXELS_PER_LINE)
                frame_buffer[current_line, start_col:end_col] = samples[:end_col-start_col]

                current_burst += 1
                if current_burst >= BURSTS_PER_LINE:
                    current_line += 1
                    current_burst = 0

                    # 达到阈值，分析这一帧
                    if current_line >= 500:
                        frame_count += 1
                        print(f"\n{'='*60}")
                        print(f"帧 #{frame_count} 分析 (接收 {packet_count} 个包，{current_line} 行)")
                        print(f"{'='*60}")

                        # 分析帧内容
                        line_values = analyze_frame(frame_buffer)

                        if len(line_values) > 0:
                            print(f"\n接收到 {len(line_values)} 行有效数据")
                            print(f"\n前 10 行:")
                            for idx, (buf_line, avg_val, inferred_line) in enumerate(line_values[:10]):
                                print(f"  缓冲区行{buf_line}: 像素值={avg_val:.0f}, 推断行号={inferred_line}")

                            print(f"\n后 10 行:")
                            for idx, (buf_line, avg_val, inferred_line) in enumerate(line_values[-10:]):
                                print(f"  缓冲区行{buf_line}: 像素值={avg_val:.0f}, 推断行号={inferred_line}")

                            # 检查是否对齐
                            first_inferred = line_values[0][2]
                            last_inferred = line_values[-1][2]

                            print(f"\n对齐检查:")
                            print(f"  第一行推断行号: {first_inferred} (期望=0)")
                            print(f"  最后行推断行号: {last_inferred} (期望={len(line_values)-1})")

                            if first_inferred == 0:
                                print(f"  ✓ 帧边界对齐")
                            else:
                                print(f"  ✗ 帧边界不对齐！起始行号={first_inferred}")
                                print(f"  → 这就是图像滚动的原因！")

                        # 重置
                        frame_buffer.fill(0)
                        current_line = 0
                        current_burst = 0
                        packet_count = 0

    except KeyboardInterrupt:
        pass

    sock.close()

if __name__ == "__main__":
    main()

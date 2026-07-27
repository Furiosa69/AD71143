"""
AD71143 Panel 2 单通道图像接收上位机
适配硬件配置：只接收 Panel 1 (Panel 2) 数据
"""

import socket
import struct
import numpy as np
import cv2
import time
from datetime import datetime
from collections import deque

class Panel2Receiver:
    """Panel 2 单通道数据接收器"""

    def __init__(self, listen_ip='0.0.0.0', listen_port=1234):
        """
        初始化接收器

        参数:
            listen_ip: 监听 IP 地址（0.0.0.0 表示所有网卡）
            listen_port: UDP 监听端口（默认 1234）
        """
        self.listen_ip = listen_ip
        self.listen_port = listen_port
        self.sock = None

        # 图像参数（基于硬件配置）
        self.CHANNELS_PER_BURST = 8       # 每个 Burst 8 个通道（128 bits / 16 bits）
        self.BURSTS_PER_LINE = 65         # 每行 65 个 Bursts
        self.PIXELS_PER_LINE = 541        # 每行有效像素数（实际只有 8×65=520，前 541 个）
        self.LINES_PER_FRAME = 541        # 每帧行数
        self.PAYLOAD_SIZE = 32            # UDP Payload 大小（bytes）- BURST_BYTES = 32

        # Panel 数据位置（基于 ad71143_data_rx_dual.v 修改）
        # merged_burst[255:0] = {Panel1[127:0], Panel0[127:0]}
        # 32 bytes = 256 bits
        #
        # RGMII 打包顺序（MSB first）：
        # Byte 0 = merged_burst[255:248] (Panel 1 最高字节)
        # ...
        # Byte 15 = merged_burst[128:121] (Panel 1 最低字节)
        # Byte 16 = merged_burst[127:120] (Panel 0 最高字节，填充 0)
        # ...
        # Byte 31 = merged_burst[7:0] (Panel 0 最低字节，填充 0)
        #
        # 所以：
        # Panel 1: bits 255:128 = Bytes 0-15 (有效数据，8 通道)
        # Panel 0: bits 127:0 = Bytes 16-31 (填充 0)
        self.PANEL1_START = 0             # Panel 1: bytes 0-15 (128 bits, 8 通道)
        self.PANEL0_START = 16            # Panel 0: bytes 16-31 (128 bits, 填充 0)
        self.PANEL_SIZE = 16              # 每个 Panel 16 bytes (128 bits)

        # 接收统计
        self.packets_received = 0
        self.bytes_received = 0
        self.packets_lost = 0
        self.frames_completed = 0

        # 当前帧缓冲
        self.current_frame_bursts = []
        self.expected_burst_index = 0

        # 性能统计
        self.start_time = None
        self.last_stats_time = None
        self.stats_interval = 1.0  # 统计刷新间隔（秒）

    def open(self):
        """打开 UDP socket"""
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 2*1024*1024)  # 2MB 接收缓冲
            self.sock.bind((self.listen_ip, self.listen_port))
            self.sock.settimeout(1.0)  # 1 秒超时

            print(f"[INFO] UDP socket 已绑定到 {self.listen_ip}:{self.listen_port}")
            print(f"[INFO] 接收缓冲区大小: {self.sock.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)} bytes")

            self.start_time = time.time()
            self.last_stats_time = self.start_time

            return True
        except Exception as e:
            print(f"[ERROR] 无法打开 socket: {e}")
            return False

    def close(self):
        """关闭 socket"""
        if self.sock:
            self.sock.close()
            self.sock = None
            print("[INFO] Socket 已关闭")

    def parse_packet(self, data):
        """
        解析 UDP 数据包

        硬件格式：
        - UDP Payload = 32 bytes (256 bits)
        - merged_burst[255:0] = {Panel1[127:0], Panel0[127:0]}
        - Panel1[127:0] = 8 个通道 × 16 bits/通道
        - 通道排列：[127:112]=CH0, [111:96]=CH1, ..., [15:0]=CH7

        返回:
            (panel1_channels, burst_index) 或 None
        """
        if len(data) < self.PAYLOAD_SIZE:
            print(f"[WARN] 数据包长度不足: {len(data)} < {self.PAYLOAD_SIZE}")
            return None

        # 提取 Payload（最后 32 bytes）
        payload = data[-self.PAYLOAD_SIZE:]

        # 提取 Panel 1 数据（高 16 bytes = 128 bits）
        panel1_data = payload[self.PANEL1_START:self.PANEL1_START + self.PANEL_SIZE]

        # 解析 8 个通道（每个通道 2 bytes，大端序）
        # 字节顺序：[0:1]=CH0, [2:3]=CH1, ..., [14:15]=CH7
        channels = []
        for i in range(self.CHANNELS_PER_BURST):
            offset = i * 2
            # 大端序解析 16 位无符号整数
            value = struct.unpack('>H', panel1_data[offset:offset+2])[0]
            channels.append(value)

        # Burst 索引（按接收顺序计算）
        burst_index = len(self.current_frame_bursts) % self.BURSTS_PER_LINE

        return (channels, burst_index)

    def assemble_frame(self, channels):
        """
        组装帧数据

        参数:
            channels: 8 个通道数据

        返回:
            完整帧（541×520 numpy 数组，实际有效 541×541）或 None
        """
        self.current_frame_bursts.append(channels)

        # 检查是否收集到完整一帧
        total_bursts = self.LINES_PER_FRAME * self.BURSTS_PER_LINE
        if len(self.current_frame_bursts) >= total_bursts:
            # 重建图像
            # 每行 = 65 Bursts × 8 通道 = 520 通道
            # 实际有效像素 = 541（需要截取或填充）
            frame = np.zeros((self.LINES_PER_FRAME, self.PIXELS_PER_LINE), dtype=np.uint16)

            for line_idx in range(self.LINES_PER_FRAME):
                line_data = []

                # 收集该行的所有 Bursts
                for burst_idx in range(self.BURSTS_PER_LINE):
                    packet_idx = line_idx * self.BURSTS_PER_LINE + burst_idx
                    if packet_idx < len(self.current_frame_bursts):
                        burst = self.current_frame_bursts[packet_idx]
                        line_data.extend(burst)

                # 实际收集到 520 个像素（65×8）
                # 如果需要 541 个像素，最后 21 个用 0 填充
                actual_pixels = len(line_data)
                if actual_pixels >= self.PIXELS_PER_LINE:
                    frame[line_idx, :] = line_data[:self.PIXELS_PER_LINE]
                else:
                    # 填充不足的部分
                    frame[line_idx, :actual_pixels] = line_data
                    # 剩余部分保持为 0

            # 清空缓冲，准备下一帧
            self.current_frame_bursts = []
            self.frames_completed += 1

            return frame

        return None

    def receive_loop(self, callback=None, max_frames=None):
        """
        接收循环

        参数:
            callback: 回调函数，签名为 callback(frame, stats)
            max_frames: 最大接收帧数（None 表示无限）
        """
        if not self.sock:
            print("[ERROR] Socket 未打开，请先调用 open()")
            return

        print("[INFO] 开始接收数据...")
        print(f"[INFO] 预期每帧数据包数: {self.LINES_PER_FRAME * self.BURSTS_PER_LINE}")

        frames_received = 0

        try:
            while True:
                # 检查是否达到最大帧数
                if max_frames and frames_received >= max_frames:
                    print(f"[INFO] 已接收 {max_frames} 帧，停止接收")
                    break

                try:
                    # 接收数据包
                    data, addr = self.sock.recvfrom(4096)

                    self.packets_received += 1
                    self.bytes_received += len(data)

                    # 解析数据包
                    result = self.parse_packet(data)
                    if result is None:
                        continue

                    channels, burst_index = result

                    # 组装帧
                    frame = self.assemble_frame(channels)

                    if frame is not None:
                        frames_received += 1

                        # 计算统计信息
                        stats = self.get_stats()

                        # 调用回调函数
                        if callback:
                            callback(frame, stats)
                        else:
                            # 默认行为：打印统计信息
                            self.print_stats(stats)

                except socket.timeout:
                    # 超时，继续等待
                    pass

                # 定期打印统计信息
                current_time = time.time()
                if current_time - self.last_stats_time >= self.stats_interval:
                    if not callback:  # 如果没有回调，才打印统计
                        stats = self.get_stats()
                        self.print_stats(stats)
                    self.last_stats_time = current_time

        except KeyboardInterrupt:
            print("\n[INFO] 用户中断接收")

        except Exception as e:
            print(f"[ERROR] 接收异常: {e}")
            import traceback
            traceback.print_exc()

    def get_stats(self):
        """获取统计信息"""
        elapsed_time = time.time() - self.start_time

        stats = {
            'packets_received': self.packets_received,
            'bytes_received': self.bytes_received,
            'packets_lost': self.packets_lost,
            'frames_completed': self.frames_completed,
            'elapsed_time': elapsed_time,
            'packet_rate': self.packets_received / elapsed_time if elapsed_time > 0 else 0,
            'data_rate_mbps': (self.bytes_received * 8 / 1e6) / elapsed_time if elapsed_time > 0 else 0,
            'frame_rate': self.frames_completed / elapsed_time if elapsed_time > 0 else 0,
        }

        return stats

    def print_stats(self, stats):
        """打印统计信息"""
        print(f"\r[STATS] 包: {stats['packets_received']:6d} | "
              f"帧: {stats['frames_completed']:4d} | "
              f"速率: {stats['packet_rate']:7.1f} pps | "
              f"{stats['data_rate_mbps']:6.2f} Mbps | "
              f"{stats['frame_rate']:5.2f} fps", end='')


def normalize_frame(frame, method='minmax'):
    """
    归一化帧数据到 0-255 范围

    参数:
        frame: 原始帧数据（16 位）
        method: 归一化方法 ('minmax', 'percentile', 'fixed')

    返回:
        8 位图像
    """
    if method == 'minmax':
        # 最小-最大归一化
        min_val = np.min(frame)
        max_val = np.max(frame)
        if max_val > min_val:
            normalized = ((frame - min_val) / (max_val - min_val) * 255).astype(np.uint8)
        else:
            normalized = np.zeros_like(frame, dtype=np.uint8)

    elif method == 'percentile':
        # 百分位归一化（去除极值影响）
        p_low = np.percentile(frame, 1)
        p_high = np.percentile(frame, 99)
        if p_high > p_low:
            normalized = np.clip((frame - p_low) / (p_high - p_low) * 255, 0, 255).astype(np.uint8)
        else:
            normalized = np.zeros_like(frame, dtype=np.uint8)

    elif method == 'fixed':
        # 固定范围归一化（假设 16 位 ADC）
        normalized = (frame / 256).astype(np.uint8)

    else:
        raise ValueError(f"未知的归一化方法: {method}")

    return normalized


def apply_colormap(frame, colormap=cv2.COLORMAP_JET):
    """应用伪彩色映射"""
    return cv2.applyColorMap(frame, colormap)


def save_frame(frame, directory='.', prefix='frame'):
    """
    保存帧数据

    参数:
        frame: 帧数据（numpy 数组）
        directory: 保存目录
        prefix: 文件名前缀
    """
    import os

    # 创建目录
    os.makedirs(directory, exist_ok=True)

    # 生成时间戳
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S_%f')[:-3]

    # 保存原始数据（.npy）
    raw_filename = os.path.join(directory, f'{prefix}_raw_{timestamp}.npy')
    np.save(raw_filename, frame)

    # 保存图像（.png）
    frame_8bit = normalize_frame(frame, method='percentile')
    frame_color = apply_colormap(frame_8bit, cv2.COLORMAP_JET)
    img_filename = os.path.join(directory, f'{prefix}_img_{timestamp}.png')
    cv2.imwrite(img_filename, frame_color)

    print(f"\n[INFO] 已保存: {raw_filename}")
    print(f"[INFO] 已保存: {img_filename}")


# ============================================================================
# 测试和示例代码
# ============================================================================

def example_display_window(receiver):
    """示例：使用 OpenCV 窗口显示图像"""

    cv2.namedWindow('Panel 2 Image', cv2.WINDOW_NORMAL)
    cv2.resizeWindow('Panel 2 Image', 800, 800)

    save_dir = './captured_frames'
    frame_count = 0

    def callback(frame, stats):
        nonlocal frame_count
        frame_count += 1

        # 归一化为灰度图（不使用伪彩色）
        frame_8bit = normalize_frame(frame, method='percentile')

        # 直接显示灰度图，不应用伪彩色
        # 如果需要彩色，取消下面这行的注释：
        # frame_display = apply_colormap(frame_8bit, cv2.COLORMAP_JET)
        frame_display = frame_8bit  # 灰度显示

        # 添加统计信息文本
        text = f"Frame: {stats['frames_completed']} | FPS: {stats['frame_rate']:.2f}"
        cv2.putText(frame_display, text, (10, 30), cv2.FONT_HERSHEY_SIMPLEX,
                    0.5, (255, 255, 255), 1)

        # 显示图像
        cv2.imshow('Panel 2 Image', frame_display)

        # 每 10 帧保存一次
        if frame_count % 10 == 0:
            save_frame(frame, directory=save_dir, prefix='panel2')

        # 按 'q' 退出
        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            print("\n[INFO] 用户按下 'q'，退出显示")
            raise KeyboardInterrupt

    try:
        receiver.receive_loop(callback=callback)
    finally:
        cv2.destroyAllWindows()


def example_simple_receive():
    """示例：简单接收并保存数据"""

    receiver = Panel2Receiver(listen_ip='0.0.0.0', listen_port=1234)

    if not receiver.open():
        return

    try:
        save_dir = './captured_frames'

        def callback(frame, stats):
            # 保存帧
            save_frame(frame, directory=save_dir, prefix='panel2')

            # 打印统计信息
            receiver.print_stats(stats)

        # 接收 5 帧后停止
        receiver.receive_loop(callback=callback, max_frames=5)

    finally:
        receiver.close()


if __name__ == '__main__':
    import sys

    print("=" * 70)
    print("AD71143 Panel 2 单通道图像接收上位机")
    print("=" * 70)
    print()
    print("网络配置:")
    print("  FPGA IP:   192.168.1.2")
    print("  PC IP:     192.168.1.1 (请配置网卡)")
    print("  UDP 端口:  1234")
    print()
    print("图像参数:")
    print("  分辨率:    541 × 520 (单 Panel, 65 Bursts × 8 通道)")
    print("  像素深度:  16 位")
    print("  数据来源:  Panel 1 (Panel 2)")
    print("  Payload:   32 bytes (256 bits)")
    print("  每帧包数:  35,165 (541 行 × 65 Bursts)")
    print()
    print("=" * 70)
    print()

    # 选择运行模式
    if len(sys.argv) > 1 and sys.argv[1] == '--simple':
        # 简单模式：接收并保存
        print("[INFO] 运行模式: 简单接收（保存 5 帧后退出）")
        example_simple_receive()
    else:
        # 默认模式：实时显示
        print("[INFO] 运行模式: 实时显示窗口")
        print("[INFO] 按 'q' 键退出")
        print()

        receiver = Panel2Receiver(listen_ip='0.0.0.0', listen_port=1234)

        if receiver.open():
            try:
                example_display_window(receiver)
            finally:
                receiver.close()

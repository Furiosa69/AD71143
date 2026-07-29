"""
AD71143 图像接收上位机 - 数据解析模块（修复版本）
根据实际 FPGA 硬件协议解析 UDP 数据包并重建图像

硬件协议说明:
- 以太网帧格式: MAC(14) + IP(20) + UDP(8) + Payload(32) + FCS(4) = 78 bytes
- FPGA 源 IP: 192.168.1.2
- FPGA 源端口: 1234
- 目标 IP: 192.168.1.1
- 目标端口: 1234
- Payload: 32 bytes (256 bits) = merged_burst[255:0]
  - Panel 0: burst[127:0] (16 bytes) = 8 个 16-bit 样本
  - Panel 1: burst[255:128] (16 bytes) = 8 个 16-bit 样本
- 单 LVDS 模式：每个 Panel 256 通道
- 每个 burst 包含 4 个样本（每个 Panel）
- 每行 64 个 burst (256 通道 / 4 样本per burst = 64)
- 每帧 541 行
"""

import struct
import numpy as np
from typing import Tuple, Optional
from dataclasses import dataclass


@dataclass
class ImageConfig:
    """图像配置参数"""
    FRAME_LINES = 541           # 每帧行数
    CHANNELS_PER_PANEL = 256    # 每个 Panel 的通道数（单 LVDS 模式）
    PANELS = 2                  # Panel 数量
    PIXELS_PER_LINE = CHANNELS_PER_PANEL * PANELS  # 每行像素数 = 512
    BURST_BYTES = 32            # 每个 burst 字节数
    BITS_PER_SAMPLE = 16        # 每样本位数
    SAMPLES_PER_BURST_PER_PANEL = 4  # 每个 Panel 每个 burst 的样本数
    SAMPLES_PER_BURST = SAMPLES_PER_BURST_PER_PANEL * PANELS  # 总样本数 = 8
    BURSTS_PER_LINE = 64        # 每行需要的 burst 数 (256 / 4 = 64)


class UDPPacketParser:
    """UDP 数据包解析器"""

    def __init__(self):
        self.config = ImageConfig()

    def parse_udp_packet(self, packet_data: bytes) -> Optional[bytes]:
        """
        解析 UDP 数据包，提取 Payload

        参数:
            packet_data: 完整的以太网帧数据

        返回:
            32 字节的 payload 数据，解析失败返回 None
        """
        # 检查数据包长度
        if len(packet_data) < 42 + 32:  # MAC(14) + IP(20) + UDP(8) + Payload(32)
            return None

        # 解析以太网帧头 (14 bytes)
        eth_type = struct.unpack('>H', packet_data[12:14])[0]

        # 检查是否为 IPv4 (0x0800)
        if eth_type != 0x0800:
            return None

        # 解析 IP 头
        ip_protocol = packet_data[23]  # Protocol 字段在 IP 头的偏移 9
        ip_src = packet_data[26:30]

        # 检查是否为 UDP (17)
        if ip_protocol != 17:
            return None

        # 验证源 IP 是否为 192.168.1.2
        expected_src_ip = bytes([192, 168, 1, 2])
        if ip_src != expected_src_ip:
            return None

        # 解析 UDP 头
        udp_src_port = struct.unpack('>H', packet_data[34:36])[0]
        udp_dst_port = struct.unpack('>H', packet_data[36:38])[0]

        # 验证端口号
        if udp_src_port != 1234 or udp_dst_port != 1234:
            return None

        # 提取 Payload (32 bytes)
        payload = packet_data[42:42+32]

        if len(payload) != 32:
            return None

        return payload

    def extract_samples_from_burst(self, burst_data: bytes) -> np.ndarray:
        """
        从 burst 数据中提取样本值

        burst_data[31:0] = {Panel1[15:0], Panel0[15:0]}
        每个 Panel: 16 bytes = 8 个 16-bit 样本

        FPGA 输出格式（大端序，MSB first）：
        Panel 0 [15:0]: word0, word1, word2, word3 (每个 16-bit)
        Panel 1 [31:16]: word0, word1, word2, word3 (每个 16-bit)

        参数:
            burst_data: 32 字节的 burst 数据

        返回:
            8 个样本值的数组 [Panel0_samples(4), Panel1_samples(4)]
        """
        if len(burst_data) != 32:
            raise ValueError(f"Invalid burst data length: {len(burst_data)}")

        # Panel 0: bytes[15:0]
        panel0_data = burst_data[0:16]
        # Panel 1: bytes[31:16]
        panel1_data = burst_data[16:32]

        # 从每个 Panel 提取 8 个 16-bit 样本（大端序）
        def extract_samples_from_panel(panel_bytes: bytes) -> np.ndarray:
            samples = []
            for i in range(0, 16, 2):
                # 大端序：高字节在前
                sample = struct.unpack('>H', panel_bytes[i:i+2])[0]
                samples.append(sample)
            return np.array(samples, dtype=np.uint16)

        panel0_samples = extract_samples_from_panel(panel0_data)
        panel1_samples = extract_samples_from_panel(panel1_data)

        # 拼接两个 Panel 的样本
        all_samples = np.concatenate([panel0_samples, panel1_samples])

        return all_samples


class FrameAssembler:
    """帧组装器 - 将接收到的 burst 数据组装成完整图像"""

    def __init__(self):
        self.config = ImageConfig()
        self.parser = UDPPacketParser()

        # 图像缓冲区: [行, 列]，使用 uint16 存储 16-bit 样本
        self.frame_buffer = np.zeros(
            (self.config.FRAME_LINES, self.config.PIXELS_PER_LINE),
            dtype=np.uint16
        )

        # 接收统计
        self.current_line = 0
        self.current_burst = 0
        self.packets_received = 0
        self.packets_dropped = 0
        self.frame_count = 0
        self.synced = False  # 帧同步标志

        # 帧间隔检测
        self.last_packet_time = None
        self.gap_threshold = 0.003  # 3ms 间隔阈值（降低到 3ms，更容易检测）
        self.max_gap_seen = 0.0  # 记录见过的最大间隔

    def reset_frame(self):
        """重置帧缓冲区"""
        self.frame_buffer.fill(0)
        self.current_line = 0
        self.current_burst = 0

    def process_packet(self, packet_data: bytes) -> Tuple[bool, Optional[np.ndarray]]:
        """
        处理接收到的数据包

        参数:
            packet_data: 完整的以太网帧数据

        返回:
            (frame_complete, frame_data)
            - frame_complete: 是否完成一帧图像
            - frame_data: 完成的图像数据 (如果帧完成)
        """
        import time

        # 解析 UDP 数据包
        payload = self.parser.parse_udp_packet(packet_data)

        if payload is None:
            self.packets_dropped += 1
            return False, None

        self.packets_received += 1

        # 检测帧间隔：如果距离上一个包超过阈值，认为是新帧开始
        current_time = time.time()
        if self.last_packet_time is not None:
            time_gap = current_time - self.last_packet_time

            # 记录最大间隔用于调试
            if time_gap > self.max_gap_seen:
                self.max_gap_seen = time_gap
                if time_gap > 0.001:  # 只记录 >1ms 的间隔
                    print(f"[调试] 新的最大间隔: {time_gap*1000:.2f}ms")

            if time_gap > self.gap_threshold:
                # 检测到帧间隔
                if not self.synced:
                    print(f"帧同步成功（检测到 {time_gap*1000:.1f}ms 间隔，阈值={self.gap_threshold*1000:.1f}ms）")
                    self.synced = True
                else:
                    print(f"[帧边界] 间隔 {time_gap*1000:.1f}ms，行数={self.current_line}")

                # 如果当前帧有数据，先返回它（即使不完整）
                if self.current_line > 10:  # 至少有 10 行数据才认为是有效帧
                    # 填充剩余的行为零（如果帧不完整）
                    if self.current_line < self.config.FRAME_LINES:
                        print(f"警告：帧不完整，只收到 {self.current_line}/{self.config.FRAME_LINES} 行")

                    frame_data = self.frame_buffer.copy()
                    self.frame_count += 1
                    self.reset_frame()
                    self.last_packet_time = current_time
                    return True, frame_data
                else:
                    # 数据太少，重置
                    print(f"[调试] 数据太少，忽略 (行数={self.current_line})")
                    self.reset_frame()

        self.last_packet_time = current_time

        # 从 payload 提取样本
        try:
            samples = self.parser.extract_samples_from_burst(payload)
        except Exception as e:
            print(f"Error extracting samples: {e}")
            self.packets_dropped += 1
            return False, None

        # 将样本写入帧缓冲区
        if self.current_line < self.config.FRAME_LINES:
            # 计算当前 burst 在行内的起始位置
            start_col = self.current_burst * self.config.SAMPLES_PER_BURST
            end_col = min(start_col + self.config.SAMPLES_PER_BURST,
                         self.config.PIXELS_PER_LINE)

            # 写入样本数据
            samples_to_write = end_col - start_col
            self.frame_buffer[self.current_line, start_col:end_col] = samples[:samples_to_write]

            # 更新 burst 索引
            self.current_burst += 1

            # 检查是否完成一行
            if self.current_burst >= self.config.BURSTS_PER_LINE:
                self.current_line += 1
                self.current_burst = 0

            # 检查是否完成一帧（正常流程，作为备用）
            if self.current_line >= self.config.FRAME_LINES:
                frame_complete = True
                frame_data = self.frame_buffer.copy()
                self.frame_count += 1
                self.reset_frame()
                return True, frame_data

        return False, None

    def get_statistics(self) -> dict:
        """获取接收统计信息"""
        return {
            'packets_received': self.packets_received,
            'packets_dropped': self.packets_dropped,
            'frame_count': self.frame_count,
            'current_line': self.current_line,
            'current_burst': self.current_burst,
            'completion': (self.current_line / self.config.FRAME_LINES * 100)
                         if self.config.FRAME_LINES > 0 else 0
        }


class ImageProcessor:
    """图像处理器 - 对接收到的原始图像进行处理和增强"""

    @staticmethod
    def normalize_image(frame: np.ndarray) -> np.ndarray:
        """
        归一化图像到 0-255 范围

        原始数据是 16bit (0-65535)，需要映射到 0-255
        使用自适应归一化以增强对比度
        """
        # 方法1：线性映射（简单）
        # normalized = (frame.astype(np.float32) / 65535.0 * 255.0).astype(np.uint8)

        # 方法2：自适应归一化（推荐）
        # 计算有效范围（排除异常值）
        min_val = np.percentile(frame, 1)  # 1% 分位数
        max_val = np.percentile(frame, 99)  # 99% 分位数

        if max_val > min_val:
            normalized = np.clip((frame.astype(np.float32) - min_val) / (max_val - min_val) * 255.0, 0, 255)
        else:
            normalized = np.zeros_like(frame, dtype=np.float32)

        return normalized.astype(np.uint8)

    @staticmethod
    def apply_histogram_equalization(frame: np.ndarray) -> np.ndarray:
        """直方图均衡化"""
        import cv2
        return cv2.equalizeHist(frame)

    @staticmethod
    def apply_colormap(frame: np.ndarray, colormap: int) -> np.ndarray:
        """应用伪彩色映射"""
        import cv2
        return cv2.applyColorMap(frame, colormap)

    @staticmethod
    def adjust_contrast(frame: np.ndarray, alpha: float = 1.0) -> np.ndarray:
        """
        调整对比度
        alpha: 对比度系数 (1.0 = 原始, >1.0 = 增强, <1.0 = 降低)
        """
        import cv2
        return cv2.convertScaleAbs(frame, alpha=alpha, beta=0)

    @staticmethod
    def enhance_contrast(frame: np.ndarray, alpha: float = 1.0, beta: float = 0) -> np.ndarray:
        """
        增强对比度（兼容 main.py 的调用）
        alpha: 对比度系数 (1.0 = 原始, >1.0 = 增强, <1.0 = 降低)
        beta: 亮度偏移
        """
        import cv2
        return cv2.convertScaleAbs(frame, alpha=alpha, beta=beta)

    @staticmethod
    def histogram_equalization(frame: np.ndarray) -> np.ndarray:
        """直方图均衡化（兼容 main.py 的调用）"""
        import cv2
        return cv2.equalizeHist(frame)

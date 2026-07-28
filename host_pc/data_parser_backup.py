"""
AD71143 图像接收上位机 - 数据解析模块
根据 FPGA 硬件协议解析 UDP 数据包并重建图像

硬件协议说明:
- 以太网帧格式: MAC(14) + IP(20) + UDP(8) + Payload(32) + FCS(4) = 78 bytes
- FPGA 源 IP: 192.168.1.2
- FPGA 源端口: 1234
- 目标 IP: 192.168.1.1 (广播 MAC: FF:FF:FF:FF:FF:FF)
- 目标端口: 1234
- Payload: 32 bytes (256 bits) = merged_burst[255:0]
  - Panel 0: burst[127:0] (16 bytes)
  - Panel 1: burst[255:128] (16 bytes)
- 每个 burst 包含 64 个像素点 (每像素 4bit)
- 每行 541 像素, 需要 9 个 burst (541 / 64 ≈ 8.45, 向上取整)
"""

import struct
import numpy as np
from typing import Tuple, Optional, List
from dataclasses import dataclass


@dataclass
class ImageConfig:
    """图像配置参数"""
    FRAME_LINES = 541           # 每帧行数
    PIXELS_PER_LINE = 1024      # 每行像素数 (Panel0: 512 + Panel1: 512)
    BURST_BYTES = 32            # 每个 burst 字节数
    BITS_PER_PIXEL = 4          # 每像素位数
    PIXELS_PER_BURST = 64       # 每个 burst 包含的像素数 (256 bits / 4 bits = 64)
    BURSTS_PER_LINE = 16        # 每行需要的 burst 数 (1024 / 64 = 16)


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
        eth_dst_mac = packet_data[0:6]
        eth_src_mac = packet_data[6:12]
        eth_type = struct.unpack('>H', packet_data[12:14])[0]

        # 检查是否为 IPv4 (0x0800)
        if eth_type != 0x0800:
            return None

        # 解析 IP 头 (20 bytes)
        ip_header = packet_data[14:34]
        ip_version_ihl = ip_header[0]
        ip_protocol = ip_header[9]
        ip_src = packet_data[26:30]
        ip_dst = packet_data[30:34]

        # 检查是否为 UDP (17)
        if ip_protocol != 17:
            return None

        # 验证源 IP 是否为 192.168.1.2
        expected_src_ip = bytes([192, 168, 1, 2])
        if ip_src != expected_src_ip:
            return None

        # 解析 UDP 头 (8 bytes)
        udp_header = packet_data[34:42]
        udp_src_port = struct.unpack('>H', udp_header[0:2])[0]
        udp_dst_port = struct.unpack('>H', udp_header[2:4])[0]
        udp_length = struct.unpack('>H', udp_header[4:6])[0]

        # 验证端口号
        if udp_src_port != 1234 or udp_dst_port != 1234:
            return None

        # 提取 Payload (32 bytes)
        payload = packet_data[42:42+32]

        if len(payload) != 32:
            return None

        return payload

    def extract_pixels_from_burst(self, burst_data: bytes) -> np.ndarray:
        """
        从 burst 数据中提取像素值

        burst_data[31:0] = {Panel1[15:0], Panel0[15:0]}
        每个 Panel: 16 bytes = 128 bits = 32 pixels (每像素 4bit)

        参数:
            burst_data: 32 字节的 burst 数据

        返回:
            64 个像素值的数组 [Panel0_pixels(32), Panel1_pixels(32)]
        """
        if len(burst_data) != 32:
            raise ValueError(f"Invalid burst data length: {len(burst_data)}")

        # Panel 0: bytes[15:0]
        panel0_data = burst_data[0:16]
        # Panel 1: bytes[31:16]
        panel1_data = burst_data[16:32]

        # 从每个 Panel 提取 32 个像素 (每字节2个像素)
        def extract_pixels_from_panel(panel_bytes: bytes) -> np.ndarray:
            pixels = []
            for byte in panel_bytes:
                # 高4位是第一个像素，低4位是第二个像素
                pixel_high = (byte >> 4) & 0x0F
                pixel_low = byte & 0x0F
                pixels.append(pixel_high)
                pixels.append(pixel_low)
            return np.array(pixels, dtype=np.uint8)

        panel0_pixels = extract_pixels_from_panel(panel0_data)
        panel1_pixels = extract_pixels_from_panel(panel1_data)

        # 拼接两个 Panel 的像素
        all_pixels = np.concatenate([panel0_pixels, panel1_pixels])

        return all_pixels


class FrameAssembler:
    """帧组装器 - 将接收到的 burst 数据组装成完整图像"""

    def __init__(self):
        self.config = ImageConfig()
        self.parser = UDPPacketParser()

        # 图像缓冲区: [行, 列]
        self.frame_buffer = np.zeros(
            (self.config.FRAME_LINES, self.config.PIXELS_PER_LINE),
            dtype=np.uint8
        )

        # 接收统计
        self.current_line = 0
        self.current_burst = 0
        self.packets_received = 0
        self.packets_dropped = 0
        self.frame_count = 0

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
        # 解析 UDP 数据包
        payload = self.parser.parse_udp_packet(packet_data)

        if payload is None:
            self.packets_dropped += 1
            return False, None

        self.packets_received += 1

        # 从 payload 提取像素
        try:
            pixels = self.parser.extract_pixels_from_burst(payload)
        except Exception as e:
            print(f"Error extracting pixels: {e}")
            self.packets_dropped += 1
            return False, None

        # 将像素写入帧缓冲区
        if self.current_line < self.config.FRAME_LINES:
            # 计算当前 burst 在行内的起始位置
            start_col = self.current_burst * self.config.PIXELS_PER_BURST
            end_col = min(start_col + self.config.PIXELS_PER_BURST,
                         self.config.PIXELS_PER_LINE)

            # 写入像素数据
            pixels_to_write = end_col - start_col
            self.frame_buffer[self.current_line, start_col:end_col] = pixels[:pixels_to_write]

            # 更新 burst 索引
            self.current_burst += 1

            # 检查是否完成一行
            if self.current_burst >= self.config.BURSTS_PER_LINE:
                self.current_line += 1
                self.current_burst = 0

            # 检查是否完成一帧
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

        原始数据是 4bit (0-15)，需要映射到 0-255
        """
        # 将 4bit 数据 (0-15) 扩展到 8bit (0-255)
        normalized = (frame.astype(np.float32) / 15.0 * 255.0).astype(np.uint8)
        return normalized

    @staticmethod
    def apply_colormap(frame: np.ndarray, colormap: int = 2) -> np.ndarray:
        """
        应用伪彩色映射

        参数:
            frame: 灰度图像
            colormap: OpenCV colormap 类型
                0: COLORMAP_AUTUMN
                1: COLORMAP_BONE
                2: COLORMAP_JET (默认)
                3: COLORMAP_WINTER
                4: COLORMAP_RAINBOW
                5: COLORMAP_OCEAN
                6: COLORMAP_SUMMER
                7: COLORMAP_SPRING
                8: COLORMAP_COOL
                9: COLORMAP_HSV
                10: COLORMAP_PINK
                11: COLORMAP_HOT
        """
        import cv2
        # 归一化图像
        normalized = ImageProcessor.normalize_image(frame)
        # 应用伪彩色
        colored = cv2.applyColorMap(normalized, colormap)
        return colored

    @staticmethod
    def enhance_contrast(frame: np.ndarray, alpha: float = 1.5, beta: int = 0) -> np.ndarray:
        """
        增强对比度

        参数:
            frame: 输入图像
            alpha: 对比度增益 (1.0 = 无变化)
            beta: 亮度偏移
        """
        enhanced = np.clip(alpha * frame + beta, 0, 255).astype(np.uint8)
        return enhanced

    @staticmethod
    def histogram_equalization(frame: np.ndarray) -> np.ndarray:
        """直方图均衡化"""
        import cv2
        normalized = ImageProcessor.normalize_image(frame)
        equalized = cv2.equalizeHist(normalized)
        return equalized


if __name__ == "__main__":
    # 测试代码
    print("AD71143 数据解析模块")
    print(f"图像尺寸: {ImageConfig.PIXELS_PER_LINE} x {ImageConfig.FRAME_LINES}")
    print(f"每行需要 {ImageConfig.BURSTS_PER_LINE} 个 burst")
    print(f"每帧需要 {ImageConfig.FRAME_LINES * ImageConfig.BURSTS_PER_LINE} 个数据包")

    # 测试 burst 解析
    parser = UDPPacketParser()
    test_burst = bytes(range(32))  # 测试数据
    pixels = parser.extract_pixels_from_burst(test_burst)
    print(f"\n测试 burst 解析: 提取到 {len(pixels)} 个像素")
    print(f"前 10 个像素: {pixels[:10]}")

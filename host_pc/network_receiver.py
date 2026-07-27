"""
AD71143 图像接收上位机 - 网络接收模块
使用原始套接字接收 UDP 数据包
"""

import socket
import struct
import threading
import time
from typing import Callable, Optional
from queue import Queue, Full


class NetworkReceiver:
    """网络接收器 - 使用原始套接字接收 UDP 数据包"""

    def __init__(self, interface_ip: str = "192.168.1.1", port: int = 1234):
        """
        初始化网络接收器

        参数:
            interface_ip: 本机网卡 IP 地址
            port: 监听端口
        """
        self.interface_ip = interface_ip
        self.port = port
        self.socket = None
        self.running = False
        self.recv_thread = None
        self.packet_queue = Queue(maxsize=1000)
        self.callback = None

        # 统计信息
        self.total_packets = 0
        self.total_bytes = 0
        self.start_time = None

    def start(self, callback: Optional[Callable[[bytes], None]] = None):
        """
        启动接收线程

        参数:
            callback: 数据包回调函数，接收原始以太网帧数据
        """
        if self.running:
            print("接收器已经在运行")
            return

        self.callback = callback
        self.running = True
        self.start_time = time.time()

        try:
            # 创建原始套接字接收 UDP 数据包
            # Windows: 需要管理员权限
            # Linux: 可能需要 sudo
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_UDP)
            self.socket.bind((self.interface_ip, 0))
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024 * 1024)  # 1MB 接收缓冲区

            print(f"网络接收器启动成功，监听 {self.interface_ip}:{self.port}")

        except PermissionError:
            print("错误: 需要管理员权限运行原始套接字")
            print("请使用管理员权限运行程序")
            self.running = False
            return
        except Exception as e:
            print(f"创建套接字失败: {e}")
            self.running = False
            return

        # 启动接收线程
        self.recv_thread = threading.Thread(target=self._recv_loop, daemon=True)
        self.recv_thread.start()

    def _recv_loop(self):
        """接收循环"""
        print("接收线程已启动")

        while self.running:
            try:
                # 接收数据包
                data, addr = self.socket.recvfrom(65535)

                # 统计
                self.total_packets += 1
                self.total_bytes += len(data)

                # 解析 IP 头获取端口信息
                if len(data) >= 28:  # IP头(20) + UDP头(8)
                    # UDP 源端口和目标端口
                    udp_src_port = struct.unpack('>H', data[20:22])[0]
                    udp_dst_port = struct.unpack('>H', data[22:24])[0]

                    # 过滤：只接收目标端口为 1234 的数据包
                    if udp_dst_port == self.port:
                        # 构造完整的以太网帧格式 (补充 MAC 头)
                        # 原始套接字在 Windows 上可能不包含以太网头，需要补充
                        eth_frame = self._construct_eth_frame(data)

                        # 调用回调函数
                        if self.callback:
                            try:
                                self.callback(eth_frame)
                            except Exception as e:
                                print(f"回调函数执行错误: {e}")

                        # 放入队列
                        try:
                            self.packet_queue.put_nowait(eth_frame)
                        except Full:
                            pass  # 队列满，丢弃旧数据

            except Exception as e:
                if self.running:
                    print(f"接收数据包错误: {e}")
                time.sleep(0.001)

    def _construct_eth_frame(self, ip_packet: bytes) -> bytes:
        """
        构造完整的以太网帧
        原始套接字返回的是 IP 层数据，需要补充 MAC 层头部

        参数:
            ip_packet: IP 层数据包

        返回:
            完整的以太网帧
        """
        # 构造以太网头 (14 bytes)
        dst_mac = b'\xFF\xFF\xFF\xFF\xFF\xFF'  # 广播 MAC
        src_mac = b'\x02\x00\x00\x00\x00\x01'  # FPGA SMAC
        eth_type = b'\x08\x00'  # IPv4

        eth_header = dst_mac + src_mac + eth_type
        eth_frame = eth_header + ip_packet

        return eth_frame

    def get_packet(self, timeout: float = 1.0) -> Optional[bytes]:
        """
        从队列获取数据包

        参数:
            timeout: 超时时间（秒）

        返回:
            数据包，超时返回 None
        """
        try:
            return self.packet_queue.get(timeout=timeout)
        except:
            return None

    def stop(self):
        """停止接收"""
        if not self.running:
            return

        print("正在停止网络接收器...")
        self.running = False

        if self.socket:
            self.socket.close()

        if self.recv_thread:
            self.recv_thread.join(timeout=2)

        print("网络接收器已停止")

    def get_statistics(self) -> dict:
        """获取统计信息"""
        elapsed_time = time.time() - self.start_time if self.start_time else 0
        packets_per_sec = self.total_packets / elapsed_time if elapsed_time > 0 else 0
        bytes_per_sec = self.total_bytes / elapsed_time if elapsed_time > 0 else 0

        return {
            'total_packets': self.total_packets,
            'total_bytes': self.total_bytes,
            'elapsed_time': elapsed_time,
            'packets_per_sec': packets_per_sec,
            'bytes_per_sec': bytes_per_sec,
            'mbps': (bytes_per_sec * 8) / (1024 * 1024)  # Mbps
        }


class UDPReceiver:
    """简化的 UDP 接收器 - 使用普通 UDP 套接字"""

    def __init__(self, listen_ip: str = "0.0.0.0", port: int = 1234):
        """
        初始化 UDP 接收器

        参数:
            listen_ip: 监听 IP 地址
            port: 监听端口
        """
        self.listen_ip = listen_ip
        self.port = port
        self.socket = None
        self.running = False
        self.recv_thread = None
        self.callback = None

        # 统计信息
        self.total_packets = 0
        self.total_bytes = 0
        self.start_time = None

    def start(self, callback: Optional[Callable[[bytes], None]] = None):
        """
        启动接收线程

        参数:
            callback: 数据包回调函数
        """
        if self.running:
            print("接收器已经在运行")
            return

        self.callback = callback
        self.running = True
        self.start_time = time.time()

        try:
            # 创建 UDP 套接字
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.socket.bind((self.listen_ip, self.port))
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024 * 1024)

            print(f"UDP 接收器启动成功，监听 {self.listen_ip}:{self.port}")

        except Exception as e:
            print(f"创建 UDP 套接字失败: {e}")
            self.running = False
            return

        # 启动接收线程
        self.recv_thread = threading.Thread(target=self._recv_loop, daemon=True)
        self.recv_thread.start()

    def _recv_loop(self):
        """接收循环"""
        print("UDP 接收线程已启动")

        while self.running:
            try:
                # 接收 UDP 数据包
                data, addr = self.socket.recvfrom(65535)

                # 统计
                self.total_packets += 1
                self.total_bytes += len(data)

                # UDP payload 需要补充以太网头和 IP/UDP 头
                eth_frame = self._construct_full_frame(data, addr)

                # 调用回调函数
                if self.callback:
                    try:
                        self.callback(eth_frame)
                    except Exception as e:
                        print(f"回调函数执行错误: {e}")

            except Exception as e:
                if self.running:
                    print(f"接收 UDP 数据包错误: {e}")
                time.sleep(0.001)

    def _construct_full_frame(self, udp_payload: bytes, src_addr: tuple) -> bytes:
        """
        构造完整的以太网帧（包含 MAC、IP、UDP 头）

        参数:
            udp_payload: UDP 负载数据
            src_addr: 源地址 (ip, port)

        返回:
            完整的以太网帧
        """
        # MAC 头 (14 bytes)
        dst_mac = b'\xFF\xFF\xFF\xFF\xFF\xFF'
        src_mac = b'\x02\x00\x00\x00\x00\x01'
        eth_type = b'\x08\x00'  # IPv4

        # IP 头 (20 bytes) - 简化版本
        ip_header = b'\x45\x00'  # Version=4, IHL=5, DSCP/ECN=0
        total_length = 20 + 8 + len(udp_payload)
        ip_header += struct.pack('>H', total_length)  # Total Length
        ip_header += b'\x00\x00\x00\x00'  # ID, Flags, Fragment
        ip_header += b'\x40\x11'  # TTL=64, Protocol=UDP
        ip_header += b'\x00\x00'  # Checksum (skip)
        ip_header += bytes([192, 168, 1, 2])  # Src IP
        ip_header += bytes([192, 168, 1, 1])  # Dst IP

        # UDP 头 (8 bytes)
        udp_src_port = 1234
        udp_dst_port = 1234
        udp_length = 8 + len(udp_payload)
        udp_header = struct.pack('>HHH', udp_src_port, udp_dst_port, udp_length)
        udp_header += b'\x00\x00'  # Checksum (skip)

        # 拼接完整帧
        eth_frame = dst_mac + src_mac + eth_type + ip_header + udp_header + udp_payload

        return eth_frame

    def stop(self):
        """停止接收"""
        if not self.running:
            return

        print("正在停止 UDP 接收器...")
        self.running = False

        if self.socket:
            self.socket.close()

        if self.recv_thread:
            self.recv_thread.join(timeout=2)

        print("UDP 接收器已停止")

    def get_statistics(self) -> dict:
        """获取统计信息"""
        elapsed_time = time.time() - self.start_time if self.start_time else 0
        packets_per_sec = self.total_packets / elapsed_time if elapsed_time > 0 else 0
        bytes_per_sec = self.total_bytes / elapsed_time if elapsed_time > 0 else 0

        return {
            'total_packets': self.total_packets,
            'total_bytes': self.total_bytes,
            'elapsed_time': elapsed_time,
            'packets_per_sec': packets_per_sec,
            'bytes_per_sec': bytes_per_sec,
            'mbps': (bytes_per_sec * 8) / (1024 * 1024)
        }


if __name__ == "__main__":
    # 测试代码
    print("AD71143 网络接收模块测试")
    print("使用 UDP 接收器 (推荐)")

    def test_callback(data):
        print(f"接收到数据包: {len(data)} bytes")

    receiver = UDPReceiver(listen_ip="0.0.0.0", port=1234)
    receiver.start(callback=test_callback)

    try:
        while True:
            time.sleep(1)
            stats = receiver.get_statistics()
            print(f"统计: {stats['total_packets']} 包, "
                  f"{stats['packets_per_sec']:.2f} pps, "
                  f"{stats['mbps']:.2f} Mbps")
    except KeyboardInterrupt:
        print("\n停止接收...")
        receiver.stop()

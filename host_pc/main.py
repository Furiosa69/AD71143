"""
AD71143 图像接收上位机 - 主程序
基于 PyQt5 的图形界面程序
"""

import sys
import os
import time
import numpy as np
import cv2
from datetime import datetime
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                             QHBoxLayout, QPushButton, QLabel, QComboBox,
                             QGroupBox, QTextEdit, QSlider, QSpinBox, QCheckBox,
                             QFileDialog, QMessageBox, QStatusBar)
from PyQt5.QtCore import Qt, QTimer, pyqtSignal, QThread
from PyQt5.QtGui import QImage, QPixmap, QFont

from data_parser import FrameAssembler, ImageProcessor, ImageConfig
from network_receiver import UDPReceiver


class ReceiveThread(QThread):
    """接收线程 - 处理网络数据包"""
    frame_ready = pyqtSignal(np.ndarray)  # 帧完成信号
    stats_update = pyqtSignal(dict)  # 统计信息更新信号
    error_signal = pyqtSignal(str)  # 错误信号

    def __init__(self, listen_ip="0.0.0.0", port=1234):
        super().__init__()
        self.listen_ip = listen_ip
        self.port = port
        self.receiver = None
        self.assembler = FrameAssembler()
        self.running = False

    def run(self):
        """运行接收线程"""
        try:
            # 创建接收器
            self.receiver = UDPReceiver(self.listen_ip, self.port)
            self.receiver.start(callback=self.process_packet)
            self.running = True

            # 定时更新统计信息
            while self.running:
                time.sleep(0.5)

                # 获取统计信息
                net_stats = self.receiver.get_statistics()
                asm_stats = self.assembler.get_statistics()

                combined_stats = {**net_stats, **asm_stats}
                self.stats_update.emit(combined_stats)

        except Exception as e:
            self.error_signal.emit(f"接收线程错误: {e}")
            self.running = False

    def process_packet(self, packet_data: bytes):
        """处理数据包"""
        try:
            frame_complete, frame_data = self.assembler.process_packet(packet_data)

            if frame_complete and frame_data is not None:
                self.frame_ready.emit(frame_data)

        except Exception as e:
            print(f"处理数据包错误: {e}")

    def stop(self):
        """停止接收线程"""
        self.running = False
        if self.receiver:
            self.receiver.stop()
        self.wait()


class MainWindow(QMainWindow):
    """主窗口"""

    def __init__(self):
        super().__init__()
        self.setWindowTitle("AD71143 图像接收上位机")
        self.setGeometry(100, 100, 1400, 900)

        # 配置
        self.config = ImageConfig()
        self.processor = ImageProcessor()

        # 接收线程
        self.recv_thread = None

        # 当前图像
        self.current_frame = None
        self.display_frame = None

        # 图像处理参数
        self.colormap = cv2.COLORMAP_JET
        self.contrast_alpha = 1.0
        self.contrast_beta = 0
        self.use_colormap = True
        self.use_histogram_eq = False

        # 自动保存
        self.auto_save = False
        self.save_dir = ""
        self.save_count = 0

        # 初始化 UI
        self.init_ui()

        # 定时器更新 FPS
        self.fps_timer = QTimer()
        self.fps_timer.timeout.connect(self.update_fps)
        self.fps_timer.start(1000)

        self.last_frame_count = 0
        self.current_fps = 0.0

    def init_ui(self):
        """初始化用户界面"""
        central_widget = QWidget()
        self.setCentralWidget(central_widget)

        main_layout = QHBoxLayout(central_widget)

        # 左侧：图像显示区
        left_layout = QVBoxLayout()

        # 图像显示标签
        self.image_label = QLabel()
        self.image_label.setMinimumSize(800, 600)
        self.image_label.setStyleSheet("QLabel { background-color: black; border: 2px solid gray; }")
        self.image_label.setAlignment(Qt.AlignCenter)
        self.image_label.setText("等待图像数据...")

        left_layout.addWidget(self.image_label)

        # 图像信息标签
        self.info_label = QLabel(f"图像尺寸: {self.config.PIXELS_PER_LINE} x {self.config.FRAME_LINES}")
        self.info_label.setFont(QFont("Arial", 10))
        left_layout.addWidget(self.info_label)

        main_layout.addLayout(left_layout, stretch=3)

        # 右侧：控制面板
        right_layout = QVBoxLayout()

        # 网络控制组
        network_group = self.create_network_group()
        right_layout.addWidget(network_group)

        # 图像处理组
        process_group = self.create_process_group()
        right_layout.addWidget(process_group)

        # 保存控制组
        save_group = self.create_save_group()
        right_layout.addWidget(save_group)

        # 统计信息组
        stats_group = self.create_stats_group()
        right_layout.addWidget(stats_group)

        right_layout.addStretch()

        main_layout.addLayout(right_layout, stretch=1)

        # 状态栏
        self.statusBar = QStatusBar()
        self.setStatusBar(self.statusBar)
        self.statusBar.showMessage("就绪")

    def create_network_group(self) -> QGroupBox:
        """创建网络控制组"""
        group = QGroupBox("网络控制")
        layout = QVBoxLayout()

        # IP 和端口配置
        ip_layout = QHBoxLayout()
        ip_layout.addWidget(QLabel("监听IP:"))
        self.ip_input = QComboBox()
        self.ip_input.addItems(["0.0.0.0", "192.168.1.1", "127.0.0.1"])
        self.ip_input.setEditable(True)
        ip_layout.addWidget(self.ip_input)
        layout.addLayout(ip_layout)

        port_layout = QHBoxLayout()
        port_layout.addWidget(QLabel("端口:"))
        self.port_input = QSpinBox()
        self.port_input.setRange(1, 65535)
        self.port_input.setValue(1234)
        port_layout.addWidget(self.port_input)
        layout.addLayout(port_layout)

        # 开始/停止按钮
        btn_layout = QHBoxLayout()
        self.start_btn = QPushButton("开始接收")
        self.start_btn.clicked.connect(self.start_receive)
        btn_layout.addWidget(self.start_btn)

        self.stop_btn = QPushButton("停止接收")
        self.stop_btn.clicked.connect(self.stop_receive)
        self.stop_btn.setEnabled(False)
        btn_layout.addWidget(self.stop_btn)
        layout.addLayout(btn_layout)

        group.setLayout(layout)
        return group

    def create_process_group(self) -> QGroupBox:
        """创建图像处理组"""
        group = QGroupBox("图像处理")
        layout = QVBoxLayout()

        # 伪彩色开关
        self.colormap_checkbox = QCheckBox("启用伪彩色")
        self.colormap_checkbox.setChecked(True)
        self.colormap_checkbox.stateChanged.connect(self.on_colormap_changed)
        layout.addWidget(self.colormap_checkbox)

        # 颜色映射选择
        colormap_layout = QHBoxLayout()
        colormap_layout.addWidget(QLabel("颜色映射:"))
        self.colormap_combo = QComboBox()
        self.colormap_combo.addItems([
            "JET", "HOT", "RAINBOW", "OCEAN",
            "COOL", "SPRING", "SUMMER", "AUTUMN", "WINTER"
        ])
        self.colormap_combo.currentIndexChanged.connect(self.on_colormap_type_changed)
        colormap_layout.addWidget(self.colormap_combo)
        layout.addLayout(colormap_layout)

        # 直方图均衡化
        self.hist_eq_checkbox = QCheckBox("直方图均衡化")
        self.hist_eq_checkbox.stateChanged.connect(self.on_hist_eq_changed)
        layout.addWidget(self.hist_eq_checkbox)

        # 对比度调整
        contrast_layout = QVBoxLayout()
        contrast_layout.addWidget(QLabel("对比度:"))
        self.contrast_slider = QSlider(Qt.Horizontal)
        self.contrast_slider.setRange(10, 30)  # 1.0 - 3.0
        self.contrast_slider.setValue(10)  # 默认 1.0
        self.contrast_slider.valueChanged.connect(self.on_contrast_changed)
        contrast_layout.addWidget(self.contrast_slider)
        self.contrast_value_label = QLabel("1.0")
        contrast_layout.addWidget(self.contrast_value_label)
        layout.addLayout(contrast_layout)

        group.setLayout(layout)
        return group

    def create_save_group(self) -> QGroupBox:
        """创建保存控制组"""
        group = QGroupBox("保存设置")
        layout = QVBoxLayout()

        # 保存目录选择
        dir_layout = QHBoxLayout()
        self.save_dir_label = QLabel("未设置")
        self.save_dir_label.setStyleSheet("QLabel { color: gray; }")
        dir_layout.addWidget(self.save_dir_label)

        select_dir_btn = QPushButton("选择目录")
        select_dir_btn.clicked.connect(self.select_save_dir)
        dir_layout.addWidget(select_dir_btn)
        layout.addLayout(dir_layout)

        # 自动保存开关
        self.auto_save_checkbox = QCheckBox("自动保存每帧")
        self.auto_save_checkbox.stateChanged.connect(self.on_auto_save_changed)
        layout.addWidget(self.auto_save_checkbox)

        # 手动保存按钮
        save_btn = QPushButton("保存当前帧")
        save_btn.clicked.connect(self.save_current_frame)
        layout.addWidget(save_btn)

        group.setLayout(layout)
        return group

    def create_stats_group(self) -> QGroupBox:
        """创建统计信息组"""
        group = QGroupBox("统计信息")
        layout = QVBoxLayout()

        self.stats_text = QTextEdit()
        self.stats_text.setReadOnly(True)
        self.stats_text.setMaximumHeight(200)
        self.stats_text.setFont(QFont("Courier", 9))
        layout.addWidget(self.stats_text)

        group.setLayout(layout)
        return group

    def start_receive(self):
        """开始接收"""
        if self.recv_thread and self.recv_thread.isRunning():
            QMessageBox.warning(self, "警告", "接收线程已在运行")
            return

        listen_ip = self.ip_input.currentText()
        port = self.port_input.value()

        # 创建并启动接收线程
        self.recv_thread = ReceiveThread(listen_ip, port)
        self.recv_thread.frame_ready.connect(self.on_frame_received)
        self.recv_thread.stats_update.connect(self.on_stats_update)
        self.recv_thread.error_signal.connect(self.on_error)
        self.recv_thread.start()

        # 更新 UI
        self.start_btn.setEnabled(False)
        self.stop_btn.setEnabled(True)
        self.ip_input.setEnabled(False)
        self.port_input.setEnabled(False)
        self.statusBar.showMessage(f"正在接收: {listen_ip}:{port}")

    def stop_receive(self):
        """停止接收"""
        if self.recv_thread:
            self.recv_thread.stop()
            self.recv_thread = None

        # 更新 UI
        self.start_btn.setEnabled(True)
        self.stop_btn.setEnabled(False)
        self.ip_input.setEnabled(True)
        self.port_input.setEnabled(True)
        self.statusBar.showMessage("已停止接收")

    def on_frame_received(self, frame: np.ndarray):
        """接收到完整帧"""
        self.current_frame = frame
        self.process_and_display()

        # 自动保存
        if self.auto_save and self.save_dir:
            self.save_frame(frame)

    def process_and_display(self):
        """处理并显示图像"""
        if self.current_frame is None:
            return

        frame = self.current_frame.copy()

        # 应用直方图均衡化
        if self.use_histogram_eq:
            frame = self.processor.histogram_equalization(frame)
        else:
            frame = self.processor.normalize_image(frame)

        # 应用对比度增强
        frame = self.processor.enhance_contrast(frame, self.contrast_alpha, self.contrast_beta)

        # 应用伪彩色
        if self.use_colormap:
            frame = self.processor.apply_colormap(frame, self.colormap)
        else:
            # 灰度图需要转换为 RGB
            frame = cv2.cvtColor(frame, cv2.COLOR_GRAY2RGB)

        self.display_frame = frame
        self.display_image(frame)

    def display_image(self, frame: np.ndarray):
        """显示图像"""
        # 转换为 QImage
        height, width = frame.shape[:2]

        if len(frame.shape) == 3:
            # RGB 图像
            bytes_per_line = 3 * width
            q_image = QImage(frame.data, width, height, bytes_per_line, QImage.Format_RGB888)
        else:
            # 灰度图像
            bytes_per_line = width
            q_image = QImage(frame.data, width, height, bytes_per_line, QImage.Format_Grayscale8)

        # 缩放图像以适应标签大小
        pixmap = QPixmap.fromImage(q_image)
        scaled_pixmap = pixmap.scaled(self.image_label.size(), Qt.KeepAspectRatio, Qt.SmoothTransformation)

        self.image_label.setPixmap(scaled_pixmap)

    def on_stats_update(self, stats: dict):
        """更新统计信息"""
        stats_text = f"""
接收统计:
  接收包数: {stats.get('total_packets', 0)}
  接收字节: {stats.get('total_bytes', 0)} bytes
  丢包数: {stats.get('packets_dropped', 0)}
  包速率: {stats.get('packets_per_sec', 0):.2f} pps
  数据速率: {stats.get('mbps', 0):.2f} Mbps

帧统计:
  完成帧数: {stats.get('frame_count', 0)}
  当前行: {stats.get('current_line', 0)} / {self.config.FRAME_LINES}
  当前Burst: {stats.get('current_burst', 0)} / {self.config.BURSTS_PER_LINE}
  完成度: {stats.get('completion', 0):.1f}%
  帧率: {self.current_fps:.2f} fps
        """

        self.stats_text.setText(stats_text.strip())

    def update_fps(self):
        """更新 FPS 显示"""
        if self.recv_thread and self.recv_thread.assembler:
            current_count = self.recv_thread.assembler.frame_count
            self.current_fps = current_count - self.last_frame_count
            self.last_frame_count = current_count

    def on_error(self, error_msg: str):
        """处理错误"""
        QMessageBox.critical(self, "错误", error_msg)
        self.stop_receive()

    def on_colormap_changed(self, state):
        """伪彩色开关改变"""
        self.use_colormap = (state == Qt.Checked)
        self.colormap_combo.setEnabled(self.use_colormap)
        self.process_and_display()

    def on_colormap_type_changed(self, index):
        """颜色映射类型改变"""
        colormap_dict = {
            0: cv2.COLORMAP_JET,
            1: cv2.COLORMAP_HOT,
            2: cv2.COLORMAP_RAINBOW,
            3: cv2.COLORMAP_OCEAN,
            4: cv2.COLORMAP_COOL,
            5: cv2.COLORMAP_SPRING,
            6: cv2.COLORMAP_SUMMER,
            7: cv2.COLORMAP_AUTUMN,
            8: cv2.COLORMAP_WINTER
        }
        self.colormap = colormap_dict.get(index, cv2.COLORMAP_JET)
        self.process_and_display()

    def on_hist_eq_changed(self, state):
        """直方图均衡化开关改变"""
        self.use_histogram_eq = (state == Qt.Checked)
        self.process_and_display()

    def on_contrast_changed(self, value):
        """对比度滑块改变"""
        self.contrast_alpha = value / 10.0
        self.contrast_value_label.setText(f"{self.contrast_alpha:.1f}")
        self.process_and_display()

    def select_save_dir(self):
        """选择保存目录"""
        dir_path = QFileDialog.getExistingDirectory(self, "选择保存目录")
        if dir_path:
            self.save_dir = dir_path
            self.save_dir_label.setText(dir_path)
            self.save_dir_label.setStyleSheet("QLabel { color: black; }")
            self.save_count = 0

    def on_auto_save_changed(self, state):
        """自动保存开关改变"""
        self.auto_save = (state == Qt.Checked)
        if self.auto_save and not self.save_dir:
            QMessageBox.warning(self, "警告", "请先选择保存目录")
            self.auto_save_checkbox.setChecked(False)
            self.auto_save = False

    def save_current_frame(self):
        """保存当前帧"""
        if self.display_frame is None:
            QMessageBox.warning(self, "警告", "没有可保存的图像")
            return

        if not self.save_dir:
            self.select_save_dir()
            if not self.save_dir:
                return

        self.save_frame(self.current_frame)
        QMessageBox.information(self, "提示", "图像已保存")

    def save_frame(self, frame: np.ndarray):
        """保存帧到文件"""
        if not self.save_dir:
            return

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")

        # 保存原始数据 (numpy)
        raw_filename = os.path.join(self.save_dir, f"frame_raw_{timestamp}.npy")
        np.save(raw_filename, frame)

        # 保存处理后的图像 (PNG)
        if self.display_frame is not None:
            img_filename = os.path.join(self.save_dir, f"frame_img_{timestamp}.png")
            # OpenCV 保存时需要 BGR 格式
            save_img = cv2.cvtColor(self.display_frame, cv2.COLOR_RGB2BGR)
            cv2.imwrite(img_filename, save_img)

        self.save_count += 1

    def closeEvent(self, event):
        """关闭窗口事件"""
        if self.recv_thread and self.recv_thread.isRunning():
            reply = QMessageBox.question(self, '确认',
                                        '接收正在进行，确定要退出吗？',
                                        QMessageBox.Yes | QMessageBox.No,
                                        QMessageBox.No)
            if reply == QMessageBox.Yes:
                self.stop_receive()
                event.accept()
            else:
                event.ignore()
        else:
            event.accept()


def main():
    app = QApplication(sys.argv)

    # 设置应用样式
    app.setStyle('Fusion')

    window = MainWindow()
    window.show()

    sys.exit(app.exec_())


if __name__ == "__main__":
    main()

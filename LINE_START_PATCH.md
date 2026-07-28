# line_start无脉冲修复补丁

## 问题
- `ctrl_line_start` 无脉冲 → AFE控制器未启动
- `ctrl_line_done` 有脉冲 → Gate Driver在工作
- 原因：Top FSM可能卡住，未产生`frame_start`信号

## 解决方案
添加强制启动逻辑，绕过Top FSM，直接周期性触发ad71143_ctrl

---

## 修改1: 在top.v中添加强制启动信号生成器

**位置**: `board/project_1/project_1.srcs/sources_1/imports/src/top.v`

**在第704行后（"模块例化"注释之前）添加**:

```verilog
  // =========================================================================
  // 强制AFE启动信号生成（临时调试用）
  // 绕过Top FSM，直接周期性启动ad71143_ctrl
  // =========================================================================
  reg [23:0] force_frame_cnt;
  reg        force_frame_start;

  always @(posedge clk_100m or negedge rst_n_100m) begin
      if (!rst_n_100m) begin
          force_frame_cnt   <= 24'd0;
          force_frame_start <= 1'b0;
      end else begin
          force_frame_start <= 1'b0;

          // 等待初始化和配置完成后才启动
          if (ctrl_init_done && spi_cfg_done) begin
              if (force_frame_cnt >= 24'd5_000_000) begin  // 50ms @ 100MHz = 20fps
                  force_frame_cnt   <= 24'd0;
                  force_frame_start <= 1'b1;
              end else begin
                  force_frame_cnt <= force_frame_cnt + 24'd1;
              end
          end
      end
  end
```

---

## 修改2: 修改ad71143_ctrl的frame_start输入

**位置**: 第719行

**修改前**:
```verilog
  ) u_ad71143_ctrl (
      .clk          (clk_100m),
      .rst_n        (rst_n_100m),
      .frame_start  (frame_start_100m),    // ← 原来使用Top FSM的信号
      .roic_reset   (roic_reset_int),
```

**修改为**:
```verilog
  ) u_ad71143_ctrl (
      .clk          (clk_100m),
      .rst_n        (rst_n_100m),
      .frame_start  (force_frame_start),   // ← 改为使用强制启动信号
      .roic_reset   (roic_reset_int),
```

---

## 完整修改示例

找到这段代码（约704-730行）:

```verilog
      end
  end
  
  // =========================================================================
  // 模块例化
  // =========================================================================
  
  // AD71143 AFE 控制 (100MHz 域)
  ad71143_ctrl #(
      .ACLK_PULSES      (9),
      .LINE_CYCLES      (6000),
      .RESET_CYCLES     (1000),
      .INIT_WAIT_CYCLES (10000),
      .FRAME_LINES      (FRAME_LINES)
  ) u_ad71143_ctrl (
      .clk          (clk_100m),
      .rst_n        (rst_n_100m),
      .frame_start  (frame_start_100m),
      .roic_reset   (roic_reset_int),
      .sync         (sync_int),
      .aclk         (aclk_int),
      .init_done    (ctrl_init_done),
      .line_start   (ctrl_line_start),
      .line_done    (ctrl_line_done),
      .aclk_idx     (),
      .line_cnt     (ctrl_line_cnt),
      .frame_done   (ctrl_frame_done),
      .aclk_done    (aclk_done)
  );
```

**修改为**:

```verilog
      end
  end
  
  // =========================================================================
  // 强制AFE启动信号生成（临时调试用）
  // 绕过Top FSM，直接周期性启动ad71143_ctrl
  // =========================================================================
  reg [23:0] force_frame_cnt;
  reg        force_frame_start;

  always @(posedge clk_100m or negedge rst_n_100m) begin
      if (!rst_n_100m) begin
          force_frame_cnt   <= 24'd0;
          force_frame_start <= 1'b0;
      end else begin
          force_frame_start <= 1'b0;

          // 等待初始化和配置完成后才启动
          if (ctrl_init_done && spi_cfg_done) begin
              if (force_frame_cnt >= 24'd5_000_000) begin  // 50ms @ 100MHz = 20fps
                  force_frame_cnt   <= 24'd0;
                  force_frame_start <= 1'b1;
              end else begin
                  force_frame_cnt <= force_frame_cnt + 24'd1;
              end
          end
      end
  end

  // =========================================================================
  // 模块例化
  // =========================================================================
  
  // AD71143 AFE 控制 (100MHz 域)
  ad71143_ctrl #(
      .ACLK_PULSES      (9),
      .LINE_CYCLES      (6000),
      .RESET_CYCLES     (1000),
      .INIT_WAIT_CYCLES (10000),
      .FRAME_LINES      (FRAME_LINES)
  ) u_ad71143_ctrl (
      .clk          (clk_100m),
      .rst_n        (rst_n_100m),
      .frame_start  (force_frame_start),    // ← 修改这里
      .roic_reset   (roic_reset_int),
      .sync         (sync_int),
      .aclk         (aclk_int),
      .init_done    (ctrl_init_done),
      .line_start   (ctrl_line_start),
      .line_done    (ctrl_line_done),
      .aclk_idx     (),
      .line_cnt     (ctrl_line_cnt),
      .frame_done   (ctrl_frame_done),
      .aclk_done    (aclk_done)
  );
```

---

## 预期效果

### 修复前（ILA波形）:
```
ctrl_init_done:  __|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾  (应该为1)
spi_cfg_done:    __|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾  (应该为1)
ctrl_line_start: _________________________  (无脉冲 ❌)
ctrl_line_done:  _____|‾|___|‾|___|‾|____  (有脉冲 ✓)
aclk_done:       _________________________  (无脉冲)
merged_valid:    _________________________  (无数据)
fifo_empty:      ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾  (一直为空)
```

### 修复后（ILA波形）:
```
ctrl_init_done:  __|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾  (为1)
spi_cfg_done:    __|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾  (为1)
ctrl_line_start: _____|‾|___|‾|___|‾|____  (有周期性脉冲 ✓)
ctrl_line_done:  ______|‾|___|‾|___|‾|___  (有周期性脉冲 ✓)
aclk_done:       _____|‾|___|‾|___|‾|____  (有周期性脉冲 ✓)
merged_valid:    ______|‾|‾|‾|‾|‾|‾|‾|___  (有大量脉冲 ✓)
fifo_empty:      ‾‾‾‾‾‾|__|‾|__|‾|__|‾‾‾‾  (正常跳变 ✓)
```

---

## 工作原理

### 1. **强制启动计数器**
```verilog
if (force_frame_cnt >= 24'd5_000_000) begin  // 50ms = 20fps
    force_frame_start <= 1'b1;  // 产生启动脉冲
    force_frame_cnt <= 24'd0;   // 重置计数器
end
```

- 每50ms产生一个`force_frame_start`脉冲
- 相当于20帧/秒

### 2. **等待初始化完成**
```verilog
if (ctrl_init_done && spi_cfg_done) begin
```

- 只有在AFE初始化和SPI配置都完成后才启动
- 避免过早启动导致配置未生效

### 3. **替换原始信号**
```verilog
.frame_start  (force_frame_start),  // 不再依赖Top FSM
```

- 绕过Top FSM的复杂逻辑
- 直接给ad71143_ctrl提供启动信号

---

## 编译和测试

### 1. 保存文件
- 修改后保存 `top.v`

### 2. 在Vivado中编译
```
Generate Bitstream
```

### 3. 烧录到FPGA
```
Open Hardware Manager → Program Device
```

### 4. 使用ILA验证

**触发条件**:
```
Trigger: ctrl_line_start == 1
```

**观察信号**:
- `ctrl_line_start` (probe0[4]) - 应该有周期性脉冲
- `aclk_done` (probe0[5]) - 应该有周期性脉冲
- `merged_valid` (probe0[0]) - 应该有大量脉冲
- `fifo_empty` (如果已添加) - 应该正常跳变

### 5. 运行上位机
```bash
cd host_pc
python panel2_receiver.py
```

**预期**:
- 应该能接收到数据包
- 丢包率应该显著降低
- 如果LFSR启用，应该看到完整的静态噪点图像

---

## 故障排除

### 如果修复后ctrl_line_start仍无脉冲

**检查1**: `ctrl_init_done`是否为1？
- 如果为0 → ad71143_ctrl卡在初始化
- 上电110μs后应该为1

**检查2**: `spi_cfg_done`是否为1？
- 如果为0 → SPI配置未完成
- 上电1秒后应该为1

**检查3**: `force_frame_start`是否产生？
- 在ILA中添加这个信号的监测
- 应该每50ms有一个脉冲

### 如果ctrl_line_start有脉冲但merged_valid仍然很少

问题转移到：
- LVDS数据接收（检查`dout_a_raw`）
- Header识别（检查`header_ok`）
- ACLK/SYNC时序

---

## 下一步调试

修复后如果：
- ✅ `ctrl_line_start`有脉冲 → 继续检查LVDS和数据接收
- ❌ `ctrl_line_start`仍无脉冲 → 检查ad71143_ctrl初始化

请应用补丁后报告ILA波形结果！

# 最终修复方案：LVDS采样时序优化

## 问题回顾

### 初始问题
```
图像显示：黑白条纹
上位机数据：0x0000 和 0xFFFF 交替
```

### 诊断过程
1. ✓ NT39565D Gate驱动正常（CPV/OE优化）
2. ✓ AD71143 SPI配置成功（cfg_all_done=1）
3. ✓ ACLK/SYNC信号正常输出
4. ✓ 状态机进入S_ACT（burst_en=1）
5. ✗ LVDS采样时序不对（shift_hi大部分时间=0x00或0xFF）

---

## 已应用的修复

### 修复1: 去掉中间采样寄存器
```verilog
// 修改前：使用下降沿中间寄存器
always @(negedge clk_sys) begin
    dout_a_mid <= dout_a_i;
end
lane_a_shift <= {lane_a_shift[62:0], dout_a_mid};

// 修改后：直接采样
lane_a_shift <= {lane_a_shift[62:0], dout_a_i};
```

### 修复2: 调整DCLK DDR边沿
```verilog
// 修改前
.DDR_CLK_EDGE("OPPOSITE_EDGE")

// 修改后
.DDR_CLK_EDGE("SAME_EDGE")
```

### 修复3: 添加IDELAYE2精细延迟 ⭐ 关键修复
```verilog
IDELAYE2 #(
    .IDELAY_TYPE("FIXED"),
    .DELAY_SRC("IDATAIN"),
    .IDELAY_VALUE(16),           // 16 taps = 1.25ns (半周期)
    .HIGH_PERFORMANCE_MODE("TRUE"),
    .REFCLK_FREQUENCY(200.0),
    ...
) idelay_dout_a (
    .IDATAIN(dout_a_ibuf),
    .DATAOUT(dout_a_delayed),
    ...
);
```

**作用**: 
- 延迟LVDS输入信号1.25ns
- 让采样点落在数据眼图中心
- 每个tap = 78ps，16 taps = 半个100MHz周期

---

## 时序分析

### LVDS DDR采样（100MHz = 10ns周期）

```
DCLK:     ┌──┐  ┌──┐  ┌──┐  ┌──┐
          │  │  │  │  │  │  │  │
        ──┘  └──┘  └──┘  └──┘  └──
          0  5  10 15 20 25 30 35 ns

DOUT:     ──D0──D1──D2──D3──D4──D5──
          (数据在DCLK边沿切换)

采样点:      ↑     ↑     ↑     ↑
          (FPGA在DCLK上升沿采样)

问题：DOUT和采样点时序未对齐
解决：IDELAYE2延迟1.25ns，移到数据稳定区
```

### IDELAYE2参数说明

```
IDELAY_VALUE = 16 taps
每tap = 78ps
总延迟 = 16 × 78ps = 1.248ns ≈ 1.25ns

100MHz周期 = 10ns
半周期 = 5ns
1.25ns = 1/4周期
```

---

## 预期效果

重新综合烧录后：

### 成功标志
```
✓ shift_hi 不再是 0x00/0xFF
✓ header_ok = 1 (shift_hi = 0x0A)
✓ 上位机数据有正常灰度值 (1000~60000)
✓ 不再是饱和的 0x0000/0xFFFF
```

### 如果仍然不稳定

可以调整`IDELAY_VALUE`：

```verilog
// 尝试不同的延迟值
.IDELAY_VALUE(12),  // 0.94ns (更早采样)
.IDELAY_VALUE(16),  // 1.25ns (当前值)
.IDELAY_VALUE(20),  // 1.56ns (更晚采样)
.IDELAY_VALUE(24),  // 1.87ns (接近半周期)
```

**调试建议**: 从12开始，每次增加4，直到数据稳定。

---

## 其他已修复的配置

### AD71143寄存器配置
```verilog
Reg3 (REFDAC): 0x030  // 48, ~1.5V (扩大ADC输入范围)
Reg0 (IFS):    0x003  // 增益=3 (降低增益避免饱和)
```

### NT39565D时序优化
```verilog
CPV_PERIOD_US:  6μs   // 加快扫描速度
CPV_PW_US_X10:  30    // 3μs, 50% duty
OE_PW_US_X10:   45    // 4.5μs, 75% duty
FRAME_GAP:      250000 // 5ms帧间隔
```

---

## 修改文件清单

### ad71143_data_rx.v
1. Line 303-305: 直接采样（去掉dout_a_mid）
2. Line 343: DCLK边沿改为SAME_EDGE
3. Line 368-440: 添加IDELAYE2延迟模块

### top.v
1. Line 9: FRAME_GAP_CYCLES = 250000
2. Line 507: REFDAC = 0x030
3. Line 508: IFS = 0x003
4. Line 791-795: NT39565D时序参数
5. Line 993: 添加probe8监测aclk_int（可选）

---

## 验证步骤

### 1. 重新综合编译
```tcl
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
```

### 2. 烧录并检查ILA
```
关键信号：
- shift_hi[7:0] = 0x0A (Header正确)
- header_ok = 1
- burst_en = 1
- merged_valid = 有周期性脉冲
```

### 3. 检查上位机数据
```
✓ 通道值在 1000~60000 范围
✓ 有灰度层次，不是纯黑白
✓ 平均值接近 32768
✓ 标准差 > 1000
```

---

## 如果问题仍然存在

### 硬件检查
1. 用示波器测量DOUT差分对波形
2. 检查LVDS线缆长度（过长会衰减）
3. 确认AD71143供电电压（VDD=3.3V, VREF稳定）
4. 检查PCB走线阻抗匹配

### 软件调试
1. 调整IDELAY_VALUE (12~24范围)
2. 尝试不同的PRE_DELAY值 (0, 1, 2)
3. 检查DCLK频率是否准确100MHz
4. 验证SYNC/ACLK时序符合AD71143规范

---

**生成时间**: 2026-07-27  
**关键修复**: IDELAYE2延迟 + 直接采样 + DCLK相位调整  
**预期**: 解决LVDS采样时序问题，获得正常图像数据

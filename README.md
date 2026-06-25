# 测试
## Normal 模式
1. frame_start 置 1 时，stv1 在 STV1_ASSERT_S 拉高，在 STV_HOLD_S 维持一个周期后拉低，CPV正常生成，三个CPV后，frame_done 生成
2. xao_emergency 置 1 后可以正常跳转到 XAO_SHUT_S 状态，随后 busy 关停，当xao_emergency 置 0 后，由 XAO_SHUT_S 状态跳转到 IDLE 状态，随后停止仿真 
TODO: 测试XAO信号撤销后，芯片需要多少时间恢复？

## 2G 模式



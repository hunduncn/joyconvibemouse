# Joy-Con 空中鼠标 IMU 算法调研

调研日期：2026-08-31。只使用实现作者的源码仓库和 Valve 官方文档；源码链接固定到调研时的 commit。

## 结论

应该参考成熟实现，而且当前问题不只是“交换 X/Y 轴”。更准确的原因是：控制器姿态改变后，同一个“屏幕水平转动”会从本地 yaw 逐渐变成本地 roll；现在的 `GyroPointerEngine` 只混合 Y/Z，并始终忽略 X，所以手柄正面朝向用户时尚可用，接近平放时必然丢失或错误解释水平运动。

本项目最合适的默认方案是 **GamepadMotionHelpers / JoyShockLibrary 的 player-space gyro 思路**：

1. 在解析边界把右 Joy-Con 原始轴转换到固定的标准控制器坐标；
2. 用陀螺仪积分、加速度计缓慢纠偏，得到平滑的本地重力方向；
3. 固定 local pitch 作为垂直输入，用重力方向在 local yaw 与 local roll 之间连续混合，得到水平输入；
4. 再在二维屏幕空间做低速平滑、径向软截止和速度相关灵敏度。

这能让竖握、斜握和平握连续过渡，不需要识别几个离散“握姿模式”。GamepadMotionHelpers 明确把 player space 推荐为独立控制器的良好默认值；world space 更完全依赖重力估计，因此更容易把重力误差带入鼠标。[说明与三种空间的取舍](https://github.com/JibbSmart/GamepadMotionHelpers/blob/f1a76007ec058122a4bb6f19c816c6c0c7b7f12a/README.md#L15-L30)，[JoyShockLibrary 对同一选择的说明](https://github.com/JibbSmart/JoyShockLibrary/blob/023dfb6f83d27134bf0cb0be085bfab4a251ffa5/README.md#L95-L102)

## 成熟实现怎样处理

### 1. Player space：解决竖握和平握的核心

GamepadMotionHelpers 的标准坐标中，X 是 pitch，Y 是 yaw，Z 是 roll。它保留 X 作为垂直输入；水平输入由重力在 Y/Z 平面上的分量加权 yaw/roll，并以 `hypot(yaw, roll)` 限幅：

```text
worldYaw = -(gravity.y * gyro.y + gravity.z * gyro.z)
horizontal = sign(worldYaw) * min(abs(worldYaw) * yawRelax,
                                  hypot(gyro.y, gyro.z))
vertical = gyro.x
```

所以控制器直立时主要使用 yaw，逐渐平放时会连续转向 roll，而不是让其中一轴突然失效。[原始实现](https://github.com/JibbSmart/GamepadMotionHelpers/blob/f1a76007ec058122a4bb6f19c816c6c0c7b7f12a/GamepadMotion.hpp#L1164-L1176)

World space 则用 `-dot(gravity, gyro)` 作为 yaw，并把 pitch 轴投影到与重力垂直的平面；适应性更强，但在重力估计不准或接近奇异姿态时更敏感，源码还专门做了侧握衰减。[world-space 原始实现](https://github.com/JibbSmart/GamepadMotionHelpers/blob/f1a76007ec058122a4bb6f19c816c6c0c7b7f12a/GamepadMotion.hpp#L1178-L1212)

对本项目，根据此前实测“原始 Y≈左右指向、Z≈上下指向、X≈手腕翻转”，标准坐标的初始候选是：

```text
canonical pitch <- raw Z
canonical yaw   <- raw Y
canonical roll  <- raw X
```

加速度也必须**单独标定并转换到同一个物理 canonical frame**，不能未经验证就假设它与 gyro 的包内分量使用相同置换；JoyShockLibrary 对两者分别做了轴置换和符号处理。[Joy-Con 轴规范化源码](https://github.com/JibbSmart/JoyShockLibrary/blob/023dfb6f83d27134bf0cb0be085bfab4a251ffa5/JoyShockLibrary/InputHelpers.cpp#L390-L458) 各轴置换和正负号应由可重复的“六面静置 + 三轴转动”测试固定，不能像当前代码一样根据首帧主分量猜极性。完成规范化后，player-space 的水平轴才会在物理 yaw 与 roll 之间随握姿连续混合，而垂直轴仍是物理 pitch。

### 2. 重力估计：不能直接把瞬时加速度当姿态

GamepadMotionHelpers 每帧先用 gyro 更新四元数和本地重力，再根据“晃动程度”以不同速度让重力估计靠近归一化加速度；运动越剧烈，加速度越可能包含手部线性加速度，纠偏就越慢。它还限制纠偏速度并使计算与 `deltaTime` 相关。[融合与自适应重力纠偏源码](https://github.com/JibbSmart/GamepadMotionHelpers/blob/f1a76007ec058122a4bb6f19c816c6c0c7b7f12a/GamepadMotion.hpp#L572-L651)

这比当前 `updateRollAxis(from:)` 对每个瞬时加速度样本直接做 10% 插值可靠。没有磁力计确实无法修正绝对航向漂移，但这里输出的是相对角速度，player-space 只需要“重力在控制器本地坐标中的方向”，并不依赖绝对指南针航向。[作者对六轴融合限制的说明](https://github.com/JibbSmart/GamepadMotionHelpers/blob/f1a76007ec058122a4bb6f19c816c6c0c7b7f12a/README.md#L27-L30)

### 3. Joy-Con 采样与标定

Nintendo 报告约每 15 ms 到达一次，但每包含 3 组约 5 ms 的 IMU 样本。JoyShockLibrary 为二维指针会把三组平均；本项目已经按顺序逐组处理，这对姿态积分反而更好，应保留。[JoyShockLibrary 的采样说明](https://github.com/JibbSmart/JoyShockLibrary/blob/023dfb6f83d27134bf0cb0be085bfab4a251ffa5/README.md#L178-L181)，[其三样本解析源码](https://github.com/JibbSmart/JoyShockLibrary/blob/023dfb6f83d27134bf0cb0be085bfab4a251ffa5/JoyShockLibrary/InputHelpers.cpp#L390-L458)

当前固定 `1/200 s` 与正常 Joy-Con 样本周期一致，但应该同时检查包计数/时间间隔，记录丢包；不要用不稳定的 15 ms 回调间隔分别积分三次。工厂 SPI 校准仍应保留，运行时零偏则应有明确的手动重校准入口。

GamepadMotionHelpers 的自动标定同时检查 gyro 和 accelerometer 的时间窗口波动，并逐渐修正 bias；作者也特别警告“慢而稳定的真实动作”可能被误判为静止，因此不能激进地在使用中吸收慢速鼠标运动。[静止检测源码](https://github.com/JibbSmart/GamepadMotionHelpers/blob/f1a76007ec058122a4bb6f19c816c6c0c7b7f12a/GamepadMotion.hpp#L724-L866)，[标定模式及风险说明](https://github.com/JibbSmart/GamepadMotionHelpers/blob/f1a76007ec058122a4bb6f19c816c6c0c7b7f12a/README.md#L32-L68)

建议默认行为：连接时静置标定；提供“一键重新标定”；可选的后台 bias 更新只在 SR 未按下且 gyro、accel 都稳定一段时间后非常缓慢地进行。

### 4. 平滑、死区与灵敏度

JoyShockMapper 只在低角速度下平滑，并随速度升高连续过渡到完全不平滑，以避免快速移动产生延迟。[阈值平滑源码](https://github.com/JibbSmart/JoyShockMapper/blob/980dc52c09fbdfb3378b04a8a1895ea3157c29e1/JoyShockMapper/src/main.cpp#L1430-L1470)，[设计说明](https://github.com/JibbSmart/JoyShockMapper/blob/980dc52c09fbdfb3378b04a8a1895ea3157c29e1/README.md#L617-L618)

它在二维映射后按向量长度做 cutoff，并在 cutoff 与 recovery 之间线性恢复，而不是分别切 X/Y；分别做轴向死区会改变斜向运动角度，也会让握姿变化时手感不同。[径向软截止源码](https://github.com/JibbSmart/JoyShockMapper/blob/980dc52c09fbdfb3378b04a8a1895ea3157c29e1/JoyShockMapper/src/main.cpp#L2471-L2505)

JoyShockMapper 还按二维角速度大小，在低速与高速灵敏度之间插值，再乘 `deltaTime` 输出鼠标增量。这让慢速可精确、快速可跨屏；它和“滤波强度”是两件独立的事。[灵敏度曲线源码](https://github.com/JibbSmart/JoyShockMapper/blob/980dc52c09fbdfb3378b04a8a1895ea3157c29e1/JoyShockMapper/include/InputHelpers.h#L29-L63)

对桌面指针，不应继续只用魔法常数 `30 px/degree`。更易理解的设置是“转动多少度横跨当前屏幕宽度”：

```text
pixelsPerDegree = activeScreenWidth / degreesForFullWidth
```

JoyShockMapper 的二维校准约定也是把一圈的相应比例映射到屏幕宽度，并给出“45° 横跨屏幕”作为合理示例。[二维真实尺度校准说明](https://github.com/JibbSmart/JoyShockMapper/blob/980dc52c09fbdfb3378b04a8a1895ea3157c29e1/README.md#L679-L700)

Valve 官方同样要求 gyro/cursor 使用 `absolute_mouse` 风格的**相对增量**，保持 1:1 数据；不要先把它变成带游戏杆死区/响应曲线的摇杆值。[Steam Input 官方文档](https://partner.steamgames.com/doc/features/steam_controller/getting_started_for_devs#14)

## 与当前 `GyroPointerEngine` 的差异

| 项目 | 当前实现 | 建议 |
| --- | --- | --- |
| 姿态空间 | 用瞬时 accel 在 Y/Z 平面旋转；X 永远忽略 | 明确原始→标准坐标矩阵；融合重力；默认 player space，使用全部相关轴 |
| 平放行为 | accel 接近 X 时冻结上次轴，且 raw X 不参与输出 | 水平输入自然从 yaw 过渡到 roll |
| 重力 | 单帧加速度低通 | gyro 传播 + accel 慢纠偏，按 shakiness 调节 |
| 标定 | 启动时仅以 gyro 总速度判断静止，约 0.8 s | gyro+accel 稳定窗口、手动重校准；后台更新保守 |
| 平滑 | 对三轴做速度相关 EMA，但不显式按时间 | player-space 后对二维输出做 dt-aware、仅低速平滑 |
| 死区 | 每个原始轴先做 0.75 dps 减法 | 二维向量径向软截止；标定良好时可接近 0 |
| 灵敏度 | 固定 30 px/degree，再乘单一倍率 | “跨屏角度”基础标尺；可选低/高速双增益与 SL 精准倍率 |
| 采样 | 正确逐个处理包内 3 样本，固定 5 ms | 保留；增加包序/丢包诊断和录制回放 |

## 推荐实施顺序

1. **先锁定坐标契约。** 增加一处显式的 Joy-Con→canonical 变换和录制回放测试；至少覆盖竖握 yaw、平握 roll、pitch、纯手腕翻转四组真实数据。
2. **实现/移植融合重力与 player-space。** 可以按上述公式用 Swift 小模块实现；若直接移植 GamepadMotionHelpers 源码或实质代码，需要在 `THIRD_PARTY_NOTICES.md` 加入其 MIT 版权声明。[MIT 许可证](https://github.com/JibbSmart/GamepadMotionHelpers/blob/f1a76007ec058122a4bb6f19c816c6c0c7b7f12a/LICENSE)
3. **把滤波和死区移到二维屏幕空间。** 使用低速平滑、径向软截止；快速动作不平滑。
4. **把灵敏度改成跨屏角度。** 先以约 45° 横跨当前屏幕宽度做可调默认，再保留 SL 的精准倍率；后续按实际体验调默认值，不把体验问题混进姿态算法。
5. **用真实轨迹验收。** 同一组“屏幕向左/向右、向上/向下”动作在竖握、45°、平握下方向相同；单位角度位移差异设目标 ≤10%；握姿缓慢切换时不跳变；静止漂移与端到端延迟单独量化。

## 建议决策

不要继续在现有 `rollAxisY/rollAxisZ` 上追加姿态特判。直接用 **canonical axes + fused gravity + player-space mapping** 替换这一层，保留现有按键、SR clutch、SL precision 和三样本处理。这样改动边界清晰，也最贴近 JoyShockLibrary 已验证的控制器用法。

## 2026-09-01 实机验证补充

实现 player-space 后的真实 Joy-Con 轨迹显示，用户舒适的平握姿态会让重力约有
46%–72% 落在 canonical pitch 轴上。此时同一个屏幕左右动作也包含很大的 local
pitch 角速度；player-space 固定把它解释成垂直输入，因而产生明显串轴。

最终实现改用同一项目提供的 **world-space gyro**：水平输入取完整三轴
`-dot(gravity, gyro)`，垂直输入取 local pitch 在重力垂直平面上的投影，并在
pitch 接近重力方向的奇异姿态做侧握衰减。实测姿态被固化为回归测试
`testFlatWorldYawDoesNotLeakIntoVerticalCursorMovement`。因此，本报告早期建议的
player-space 仍适合 pitch 轴保持水平的常规握姿，但不适合作为本项目需要支持
任意竖握/平握方式的最终默认值。

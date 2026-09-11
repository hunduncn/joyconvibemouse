# Joy-Con 空中鼠标：握姿、方向与交互逻辑研究

> 研究日期：2026-09-01  
> 范围：Joy-Con (R)，仅陀螺仪 + 加速度计；不修改生产代码  
> 证据标准：只采用硬件/平台官方文档、作者论文和作者源码仓库。GitHub 引用均固定到 commit。

## 结论先行

1. **6 轴足以做高质量的相对空中鼠标。** 鼠标需要的是短时间的相对旋转或角速度，不需要知道磁北。加速度计能长期约束重力方向（倾斜的两个自由度），陀螺仪提供快速运动；静止偏置校准、动态加速度拒绝、离合与重置比磁力计更重要。
2. **6 轴不能给出长期无漂移的绝对航向。** 绕重力轴的 heading/yaw 没有可观测参考，只能由陀螺积分，偏置会累积。Madgwick 明确写道：省略磁力计时，pitch/roll 仍相对地面绝对，heading 从初始方向出发并随时间漂移（论文第 7.6.6 节，PDF 第 157 页）。
3. **磁力计只增加地球水平参考。** 它可把任意水平 X 轴改成磁北参考，并改善长期 yaw；它不能测位置、不能知道 Mac 屏幕在哪里、不能知道屏幕平面，也不能把纯 IMU 变成 Wii 式光学绝对指向。室内金属和电器还会污染磁场。
4. **当前 world-space 角速度公式方向正确，但不等于“完全任意握姿”。** 当选定的 Joy-Con pitch 轴接近重力轴时，把 pitch 投影到重力平面的向量趋近零，屏幕纵向轴在数学上没有唯一答案。GamepadMotionHelpers 在这里直接把纵向降到零；项目当前代码也是这一家族的做法。
5. **针对用户“指向左边，而不是翻腕”的诉求，最合适的新增交互是“SR 离合锚定的虚拟射线”。** SR 按下时把当前手柄方向和当前光标设为零点；之后用完整 quaternion 旋转 Joy-Con 的固定“鼻尖轴”，用射线的左右/上下夹角移动光标；绕鼻尖的 roll 天然不移动光标。松开 SR 冻结光标，重新握好后再按即重新锚定。它是相对锚定，不是假装拥有屏幕的绝对光学坐标。
6. **最稳妥的产品路线是保留两种模式。** 默认继续使用低延迟 `worldRate`（适合像鼠标一样连续拨动），新增实验性 `anchoredRay`（适合真正“指向”）。两者都复用同一个 6 轴 quaternion、固定硬件坐标变换、偏置估计和 SR 离合状态机。
7. **在换算法前必须先修一个确定性的坐标契约错误。** 对照 JoyShockLibrary 的右 Joy-Con 解码，gyro 与 accelerometer 不能套同一个轴变换：按本项目 `rawX/rawY/rawZ` 标签对齐后的 canonical contract 是 `gyro=(-rawY, rawZ, rawX)`、`accel=(-rawY, rawZ, -rawX)`；当前项目却把两者都映射成 `(rawZ, rawY, rawX)`。这会让融合器用“另一个坐标系的重力”解释角速度，很可能就是平握时左右/上下串轴的首要根因。

## 1. 6 轴、磁力计和不可观测边界

Nintendo 官方规格只列出 Joy-Con 的 accelerometer、gyroscope，右 Joy-Con另有 IR Motion Camera，没有列出 magnetometer。[Nintendo Switch Technical Specs（当前官方页面，访问于 2026-09-01）](https://www.nintendo.com/us/gaming-systems/switch/tech-specs/)

Madgwick 的原始论文给出了最直接的边界：

- 陀螺积分能得到相对初始姿态，但误差也会被积分；加速度计测得相对传感器的重力，运动时会被线性加速度污染；磁力计测磁北，也会被局部磁畸变污染（[PhD thesis，第 2.3 节，PDF 第 16–18 页](https://x-io.co.uk/downloads/madgwick-phd-thesis.pdf)）。
- 只用 gyro + accelerometer 的互补滤波器“不能提供绝对 heading”（第 2.3.1 节，PDF 第 17–18 页）。
- 单独一个重力方向不能给出唯一 3D 姿态；重力和磁场两个非共线参考合在一起才把解从一条线缩成一个点（第 3.2.2 节，式 3.10–3.19，PDF 第 35–37 页）。
- 省略磁力计时，heading 由 gyro 单独决定、从初始化方向起步并漂移；pitch/roll 仍相对地面保持绝对（第 7.6.6 节，PDF 第 157 页）。

Apple Core Motion 的官方参考系也表达了同一事实：`xArbitraryZVertical` 的 Z 轴竖直、水平 X 任意；`xMagneticNorthZVertical` 才把 X 指向磁北；`xArbitraryCorrectedZVertical` 使用磁力计改善长期 Z/yaw 准确度。[`CMAttitudeReferenceFrame`](https://developer.apple.com/documentation/coremotion/cmattitudereferenceframe)、[`xArbitraryCorrectedZVertical`](https://developer.apple.com/documentation/coremotion/cmattitudereferenceframe/xarbitrarycorrectedzvertical)

因此，对本项目应采用下面的能力声明：

| 能力 | 6 轴能否可靠提供 | 磁力计是否解决 |
|---|---:|---:|
| 短时间相对旋转/角速度 | 是 | 不需要 |
| 相对地面的倾斜、roll/pitch | 是，动态加速度期间需拒绝错误观测 | 不需要 |
| 长期无漂移的地球 heading | 否 | 可改善，但受磁畸变影响 |
| 手柄相对屏幕的位姿 | 否 | 否；还缺屏幕参考/标定 |
| 平移、距离、屏幕上的绝对落点 | 否 | 否；需要光学/外部定位 |

这也是为什么“高质量相对鼠标”可行，而“无外部参考的真正绝对指向”不可行。

## 2. 成熟实现实际采用了什么

### 2.1 融合、校准与动态拒绝

xioTechnologies 的 Fusion 是 Madgwick 修订算法的作者实现。固定 commit [`9325424011892abacc0ce42b8bb1a8ae20264b9b`](https://github.com/xioTechnologies/Fusion/tree/9325424011892abacc0ce42b8bb1a8ae20264b9b)：

- gyro + acceleration + magnetic feedback 被合并后积分 quaternion（[`FusionAhrs.c#L148-L173`](https://github.com/xioTechnologies/Fusion/blob/9325424011892abacc0ce42b8bb1a8ae20264b9b/Fusion/FusionAhrs.c#L148-L173)）。
- accelerometer 只提供 inclination 残差，运动残差过大时会被拒绝（[`#L238-L268`](https://github.com/xioTechnologies/Fusion/blob/9325424011892abacc0ce42b8bb1a8ae20264b9b/Fusion/FusionAhrs.c#L238-L268)）。
- magnetometer 单独提供 heading 残差，也有磁畸变拒绝（[`#L270-L309`](https://github.com/xioTechnologies/Fusion/blob/9325424011892abacc0ce42b8bb1a8ae20264b9b/Fusion/FusionAhrs.c#L270-L309)）。
- 无磁力计入口仍更新 quaternion，只在启动期把 heading 设零（[`#L427-L440`](https://github.com/xioTechnologies/Fusion/blob/9325424011892abacc0ce42b8bb1a8ae20264b9b/Fusion/FusionAhrs.c#L427-L440)）。
- 运行时偏置只在持续静止后慢速更新；默认阈值 3°/s、静止 3 s、0.02 Hz（[`FusionBias.c#L16-L28`](https://github.com/xioTechnologies/Fusion/blob/9325424011892abacc0ce42b8bb1a8ae20264b9b/Fusion/FusionBias.c#L16-L28)、[`#L55-L82`](https://github.com/xioTechnologies/Fusion/blob/9325424011892abacc0ce42b8bb1a8ae20264b9b/Fusion/FusionBias.c#L55-L82)）。
- 传感器轴必须明确映射到 body frame；作者实现列出 24 种合法轴排列，而不是根据第一次拿法猜正负（[`FusionRemap.h#L19-L50`](https://github.com/xioTechnologies/Fusion/blob/9325424011892abacc0ce42b8bb1a8ae20264b9b/Fusion/FusionRemap.h#L19-L50)）。

直接含义：项目可以无磁力计使用完整 quaternion，但硬件轴和正负必须固定，不能由“启动时最大加速度分量”决定。

### 2.2 local / player / world space 的真实假设

GamepadMotionHelpers 固定 commit [`f1a76007ec058122a4bb6f19c816c6c0c7b7f12a`](https://github.com/JibbSmart/GamepadMotionHelpers/tree/f1a76007ec058122a4bb6f19c816c6c0c7b7f12a) 的作者说明与源码可精确区分三种空间：

| 模式 | 计算/假设 | 对随意竖握、平握 Joy-Con 的结论 |
|---|---|---|
| local | 直接使用校准后的本机角速度；某两个物理轴就是鼠标 X/Y | 低延迟且最稳，但握姿一变，屏幕方向跟着控制器轴旋转；不合适 |
| player | 横向用 `-(gY·ωY + gZ·ωZ)`，纵向仍是 `ωX` | 面向常规双手手柄；只适配 yaw/roll 混合，没有修正 local pitch 被重力污染的情况；不适合本用户的大范围竖/平切换 |
| world | 横向 `-g·ω`；纵向把 local X 投影到重力平面 | 三轴共同参与，最接近当前需求；依赖准确 gravity，并在 local X ∥ gravity 时退化 |

作者 README 说明 player space 的 pitch 就是 local pitch、world space 会继承 gravity 估计误差（[`README.md#L21-L30`](https://github.com/JibbSmart/GamepadMotionHelpers/blob/f1a76007ec058122a4bb6f19c816c6c0c7b7f12a/README.md#L21-L30)）。具体公式在 [`GamepadMotion.hpp#L1164-L1212`](https://github.com/JibbSmart/GamepadMotionHelpers/blob/f1a76007ec058122a4bb6f19c816c6c0c7b7f12a/GamepadMotion.hpp#L1164-L1212)：当投影长度为零，world-space 纵向直接设为零。

所以，**world space 是当前相对角速度模式的正确默认值，但不能承诺覆盖所有奇异握姿。** player space 是成熟的游戏手柄默认值，不是“一切握姿”的通解。

### 2.3 右 Joy-Con 的 gyro/accel 坐标必须分别确认

JoyShockLibrary 固定 commit [`023dfb6f83d27134bf0cb0be085bfab4a251ffa5`](https://github.com/JibbSmart/JoyShockLibrary/tree/023dfb6f83d27134bf0cb0be085bfab4a251ffa5) 是直接读取 Nintendo 报告的作者实现。它先按报告布局读取三组 accelerometer/gyro 子样本（[`InputHelpers.cpp#L396-L447`](https://github.com/JibbSmart/JoyShockLibrary/blob/023dfb6f83d27134bf0cb0be085bfab4a251ffa5/JoyShockLibrary/InputHelpers.cpp#L396-L447)），随后对两类传感器采用**不同**的排列/符号（[`#L448-L460`](https://github.com/JibbSmart/JoyShockLibrary/blob/023dfb6f83d27134bf0cb0be085bfab4a251ffa5/JoyShockLibrary/InputHelpers.cpp#L448-L460)），并另有右 Joy-Con 的 handedness 处理（[`#L488-L510`](https://github.com/JibbSmart/JoyShockLibrary/blob/023dfb6f83d27134bf0cb0be085bfab4a251ffa5/JoyShockLibrary/InputHelpers.cpp#L488-L510)）。

将它与本项目 parser 的 raw 标签逐字节对齐后，本项目融合层应先锁定下面的契约，再谈 world/player/ray：

```text
canonicalGyro = (-rawGyroY, rawGyroZ,  rawGyroX)
canonicalAccel = (-rawAccelY, rawAccelZ, -rawAccelX)
```

两者最后一轴符号不同并不矛盾：原始报告、校准定义和库所选 body frame 的约定共同决定最终符号；真正的合同是**同一个物理正向旋转必须让 gyro propagation 与 gravity 在 body frame 中满足同一右手运动学**。这必须用六面静置 + 三轴正转 fixture 证明，不能为了让某一种握姿“看起来对”而在运行时猜。

### 2.4 离合/重定位不是补丁，而是鼠标语义

JoyShockMapper 固定 commit [`980dc52c09fbdfb3378b04a8a1895ea3157c29e1`](https://github.com/JibbSmart/JoyShockMapper/tree/980dc52c09fbdfb3378b04a8a1895ea3157c29e1) 把 `GYRO_ON`/`GYRO_OFF` 设计为按住启用/停用，并明确类比“抬起鼠标离开鼠标垫再重放位置”（[`README.md#L368-L400`](https://github.com/JibbSmart/JoyShockMapper/blob/980dc52c09fbdfb3378b04a8a1895ea3157c29e1/README.md#L368-L400)）。

这支持当前交互：**SR 按住是 clutch，松开立即停止输出，但融合与偏置估计继续运行。** 下次按下不应补发松开期间的旋转，也不应带着平滑器尾巴跳动。

### 2.5 成熟的完整 quaternion + recenter

Dolphin 固定 commit [`1fd7f3521895f285aa9382af8e7e464991437225`](https://github.com/dolphin-emu/dolphin/tree/1fd7f3521895f285aa9382af8e7e464991437225) 的 IMU Cursor：

- 用 gyro 旋转完整 quaternion，再用 accelerometer 互补修正、限制 yaw、处理 `Recenter`、归一化（[`Dynamics.cpp#L306-L347`](https://github.com/dolphin-emu/dolphin/blob/1fd7f3521895f285aa9382af8e7e464991437225/Source/Core/Core/HW/WiimoteEmu/Dynamics.cpp#L306-L347)）。
- UI 明确提供 `Recenter`、总 yaw 范围、accelerometer influence，并注明增加加速度计权重会减少漂移但增加噪声（[`IMUCursor.cpp#L15-L57`](https://github.com/dolphin-emu/dolphin/blob/1fd7f3521895f285aa9382af8e7e464991437225/Source/Core/InputCommon/ControllerEmu/ControlGroup/IMUCursor.cpp#L15-L57)）。

这证明成熟的 IMU 指针并不回避 recenter；完整 quaternion 解决 Euler 角奇异和组合旋转，不会凭空解决 heading 可观测性。

## 3. Wii IR 与纯 IMU 指针不是一回事

Wii Remote 的“直接指屏幕”依赖屏幕附近的 Sensor Bar。Nintendo 官方手册要求设置传感条在屏幕上/下、在测试中看到两个光点，并建议 1–3 m 距离；阳光和额外红外光会干扰（[Wii Channels & Settings Manual，第 52–53 页](https://www.nintendo.com/eu/media/downloads/support_1/wii_21/Wii_Channels_Settings_RVK_MAN_UK_NFRP.pdf)）。

Dolphin 的真实设备路径显示了两类信息如何互补：

- gyro 积分姿态，accelerometer 修正 pitch/roll；当 IR 对象可见时，再用 IR 中心修正 yaw 和 pitch（[`WiimoteController.cpp#L1210-L1261`](https://github.com/dolphin-emu/dolphin/blob/1fd7f3521895f285aa9382af8e7e464991437225/Source/Core/InputCommon/ControllerInterface/Wiimote/WiimoteController.cpp#L1210-L1261)）。
- 多个 IR 点的均值成为图像中心，点间距还能估计距离（[`#L1264-L1350`](https://github.com/dolphin-emu/dolphin/blob/1fd7f3521895f285aa9382af8e7e464991437225/Source/Core/InputCommon/ControllerInterface/Wiimote/WiimoteController.cpp#L1264-L1350)）。
- 模拟相机把两个传感条 LED 做透视投影，并检查在相机后方/视野外的情况（[`Camera.cpp#L52-L95`](https://github.com/dolphin-emu/dolphin/blob/1fd7f3521895f285aa9382af8e7e464991437225/Source/Core/Core/HW/WiimoteEmu/Camera.cpp#L52-L95)）。

因此：

- **Wii IR 是外部地标约束的图像空间指向**，接近绝对/直接指针；代价是视野、遮挡、距离和环境红外限制。
- **Joy-Con 纯 IMU 是无外部地标的旋转估计**；不能观察屏幕位置或平移。它必须做相对角速度指针，或做“每次按下离合重新建立零点”的相对射线。
- Joy-Con (R) 的 IR Motion Camera 本身不是现成的 Wii Sensor Bar 系统；除非另加可见地标、拿到相机图像并标定相机与屏幕，否则不能把它算作本项目的绝对参考。

## 4. 本 Swift 项目的现状与缺口

以下行号对应工作区 2026-09-01 快照（该目录当前没有 Git commit 可固定）：

- `GyroPointerEngine.swift:71–97` 已采用 GamepadMotionHelpers 风格 world-space：横向 `-g·ω`，纵向为 local X 在重力平面上的投影。
- `GyroPointerEngine.swift:66–69` 在 SR 未按时继续更新融合但清空运动滤波，离合语义正确。
- `GyroPointerEngine.swift:111–120` 以 45°/屏宽换算增益，固定假设 200 Hz。
- `FusedGravityEstimator.swift:24–84` 已有 gyro 传播和“抖动时降低 accelerometer 修正”的雏形。
- **最高优先级错误：** `GyroPointerEngine.swift:44–49,60–64,124–126` 对 gyro 和 accelerometer 共用 `canonical(raw) = (rawZ, rawY, rawX)`。这不符合上述 JoyShockLibrary 坐标契约；融合器的 `g` 与 `ω` 不在同一个正确 body frame，任何 `g·ω` 或 pitch 投影都可能在换握姿后串轴。应先修成两个明确函数并用原始报告 fixture 锁定。
- **首要风险：** `FusedGravityEstimator.swift:111–115` 依据首帧最大加速度分量猜 gravity 正负。这会让完全相同的硬件因为启动握姿不同得到不同极性。成熟实现要求固定 axes/body-frame remap；这里应由六面静置和三轴转动数据一次性确定，而不是运行时猜。
- **第二风险：** `GyroPointerEngine.swift:86–97` 在 pitch 投影接近零时把纵向降为零，且临界区依赖瞬时 gravity。它避免爆炸，却会在某些握姿失去纵向并可能产生增益变化。
- **第三风险：** 当前只维护 gravity，不维护完整 quaternion；因此无法实现锚定射线、完整相对旋转、姿态回放和明确的 recenter。

## 5. 可直接落地的推荐设计

### 5.1 共用传感层

不论选择哪种指针模式，都先统一为一个 `MotionEstimator`：

1. 用录制数据固定 Joy-Con raw → body 的轴排列与正负；gyro 和 accelerometer 必须使用同一个刚体坐标约定。
2. 每个真实子样本使用实际 `dt` 更新；报告中若包含 3 个 5 ms IMU 子样本，逐个更新，不能把整包当一个瞬时样本。
3. 维护单位 quaternion `q`（本文约定 `R(q)` 把 body 向量转到任意 world frame）和 body-frame gravity `g`。
4. gyro 快速积分；只有 acceleration magnitude/倾角残差可信时才纠正 inclination；静止窗口才更新 gyro bias。
5. SR 松开时仍更新 `q/g/bias`；只停止 cursor emitter。
6. 发生 packet gap、gyro overrange、NaN 或 `dt` 异常时进入 recovery，不把异常 `dt` 积成一次巨大光标跳跃。

不建议原样复制第三方库参数；先复现其结构，再用本机 Joy-Con 录制数据调参。

### 5.2 模式 A：`worldRate`（默认、低风险）

令：

- `ω`：校准后的 body-frame 角速度；
- `g`：body-frame 单位重力；
- `p`：固定 Joy-Con pitch body axis；
- `P_g = I - ggᵀ`：投影到重力切平面的矩阵。

屏幕横向角速度：

```text
h = -g · ω
```

屏幕纵向候选轴与速度：

```text
t_candidate = P_g p
v = -normalize(t) · ω
```

不要在 `||t_candidate|| → 0` 时逐帧换轴。采用有状态的迟滞策略：

1. `||t_candidate|| > enter`：使用候选轴；先与上一有效 `t` 做符号连续化（若 dot < 0 则取反），再小幅平滑。
2. `||t_candidate|| < exit`：把上一有效 `t` 像 gravity 一样用 inverse gyro 传播，再重新投影到 `g` 的切平面并归一化。
3. `exit < norm < enter`：保持当前分支，避免临界抖动。
4. 如果应用刚启动就在精确奇异姿态、没有上一轴，只能从最不平行于 `g` 的固定 body axis 选一个并锁定到离合松开；UI 标记 `degradedPose`。这不是算法不够聪明，而是瞬时重力没有定义水平切平面中的唯一方向。

二维速度处理顺序：固定 bias → world mapping → **径向** soft dead zone → 低速一阶平滑 → 可选速度增益 → precision multiplier → points。径向处理保持斜向各向同性。低速滤波的系数应由 `dt` 计算，例如 `α = 1 - exp(-dt/τ)`；SR 松开清零滤波状态。

要实现“手柄幅度更小、鼠标移动更远”，先提高基础 `pointsPerRadian`；如果又要兼顾微调，再加单调、连续的速度增益曲线，而不是改 IMU 轴：

```text
gain(s) = g_min + (g_max - g_min) · smoothstep(s0, s1, |[h,v]|)
delta = [h,v] · gain(s) · dt
```

### 5.3 模式 B：`anchoredRay`（针对“指向，不翻腕”）

这是建议新增、用回放和真人 A/B 验证的模式。它是本项目设计，不宣称 Joy-Con 获得了 Wii 那样的光学绝对坐标。

预先通过硬件坐标测试定义 Joy-Con 的固定 body-frame “鼻尖/指向轴” `f_B`。SR 按下时：

```text
f0 = normalize(R(q0) f_B)       // 当前鼻尖方向成为零点
c0 = currentCursor              // 当前系统光标成为屏幕锚点
up = worldGravity
r0 = normalize(f0 × up)         // 零点右方向
u0 = normalize(r0 × f0)         // 零点上方向
```

运行时：

```text
f = normalize(R(q) f_B)
xAngle = atan2(f · r0, f · f0)
yAngle = atan2(f · u0, hypot(f · r0, f · f0))
cursor.x = c0.x + Kx · xAngle
cursor.y = c0.y - Ky · yAngle
```

关键性质：

- 初次握姿无论竖握、平握或带 roll，按下瞬间都定义为零，不跳动。
- 绕 `f_B` 的纯 roll 不改变 `f`，所以不会移动光标；这直接对应用户“不想靠翻手腕左右移动”的诉求。
- 松开 SR 后光标冻结；手柄可随意搬回舒适位置；再次按下用新的 `q0/c0` 重锚定。长期 heading 漂移被限制在一次按住周期，而不是累积成永久屏幕偏移。
- `Kx/Ky` 直接决定小幅旋转跨多少像素；可以分别按活动屏幕宽高标定。

边界处理：

- 若 `|f0·up| > 0.95`，鼻尖几乎竖直，`f0 × up` 无法稳定定义左右。禁止启用 ray 或沿用上一有效 `r0`，并显示 `degradedPose`；不要任取一轴后每帧切换。
- 限制 `xAngle/yAngle` 到配置 FOV；超出时 clamp/freeze，不让 `atan`/投影在背向屏幕时爆炸。
- 始终直接从 quaternion/向量求夹角，不先转 Euler；这避免 Euler gimbal lock。
- 提供显式 `recenter` 事件：在 SR 仍按住时把当前 `q/cursor` 重新写入 `q0/c0`，不改变可见光标。

若实现透视 ray-plane 版本，必须检查射线与平面分母是否大于 `ε`；射线平行或朝后时冻结。没有屏幕外参时，这个“平面”仍只是离合时建立的虚拟平面。

### 5.4 状态机

```text
disconnected
  -> warmingUp/stillCalibration
  -> readyInactive       // 始终更新 q、g、bias；不输出
  -> activeWorldRate     // SR down
  -> activePrecision     // SR + SL
  -> activeAnchoredRay   // 可选模式；SR down 时捕获 q0/c0/basis

任何活动态 -> readyInactive on SR up：立即停止并清除 2D filter tail
任何态 -> recovering on packet gap / overrange / invalid dt / non-finite state
recovering -> readyInactive after estimator valid；禁止补偿性光标跳跃
```

`degradedPose` 是正交状态标志，不必另造一个阻塞大状态；world-rate 可用历史切线轴继续，ray 模式则拒绝在鼻尖垂直时创建新 anchor。

## 6. 可回放的验收测试

先增加原始录制，不再只用人工构造单帧。每个 5 ms 子样本至少保存：

```text
t_ns, reportCounter, subSampleIndex,
gyroRawX/Y/Z, accelRawX/Y/Z,
sr, sl, expectedGesture, gripLabel
```

所有阈值先作为**项目验收目标**，不是文献宣称；首次真实录制后根据噪声底修订并固定基线。

| 回放 | 必须断言 |
|---|---|
| 六面静置 + 三个正向轴旋转 | raw→body 轴、正负固定；启动握姿不改变 gravity 极性；右/上手势符号一致 |
| 竖握、45°、平握做同一世界水平转动 | `worldRate` 横向符号相同，归一化增益差建议 ≤10%，纵向泄漏建议 ≤10% |
| 三种握姿做同一纵向转动 | 纵向符号相同；经过 singular 区无 NaN、Inf、180° 符号翻转或单帧尖峰 |
| 慢速穿过 `p ∥ g` | 迟滞不抖动；有上一切线时保持连续；无历史时明确进入 degraded，而不是随机选轴 |
| 静止 10 s（各握姿） | active 漂移建立 p50/p95 基线；inactive 永远输出零；bias 只在静止窗口更新 |
| 快速平移/轻敲但少旋转 | accelerometer rejection 生效，gravity/quaternion 不被瞬时线性加速度拉走 |
| SR 离合 | inactive 搬动无输出；press 首帧无跳；release 当帧停止；inactive 重放手柄后再 press 仍无跳 |
| SL precision | 方向不变，位移严格按 multiplier 缩放；不会改变 fusion 状态 |
| packet 重复、乱序、丢包、超长间隔 | 不产生巨大 delta；进入 recovery；恢复后从当前光标继续 |
| ray：竖握/平握各从任意初始 roll 启动 | press 时零位移；同一鼻尖 yaw/pitch 给出同方向、近似同增益 |
| ray：绕鼻尖纯 roll 90° | 光标位移接近零；这项是“翻腕不移动”的核心合同 |
| ray：出去再回到初始方向 | 光标回到 `c0` 的误差在规定像素内；无路径依赖尖峰 |
| ray：鼻尖接近竖直、射线超 FOV/朝后 | 不创建不稳定 anchor，或稳定 freeze/clamp；绝无数值爆炸 |
| ray：长按与重按 | 长按单独量化 yaw drift；松开重按后漂移不会变成永久 offset |

建议保留真实失败样本为永久 fixture，至少包括用户已经遇到的：竖握、buttons-up 平握、约 45° 中间姿态、原先“左右变翻腕”的手势、以及 `g` 在 canonical pitch 上占比很大的平握。

## 7. 实施优先级

1. **P0：先修 gyro/accel 坐标契约。** 分开实现 `canonicalGyro=(-rawY,rawZ,rawX)` 与 `canonicalAccel=(-rawY,rawZ,-rawX)`，删除共用 `(rawZ,rawY,rawX)`；以 JoyShockLibrary 固定 commit 和本机原始 fixture 双重核验。
2. **P0：固定重力极性。** 删除基于首帧主分量猜 polarity 的行为；用六面/三轴 fixture 锁定。
3. **P0：把 gravity-only estimator 升为可测试的完整 quaternion estimator。** 采用 gyro propagation、inclination feedback、动态 acceleration rejection、静止 bias；无磁力计运行是预期模式。
4. **P0：保持 SR clutch、SL precision；所有 inactive 期间继续融合。**
5. **P1：给现有 `worldRate` 增加 stateful tangent basis、迟滞和奇异姿态标志。** 这是最小风险的稳定性改进。
6. **P1：增加 `anchoredRay` feature flag 和录制/回放。** 先验证“鼻尖轴”和真人手感，再决定是否升为默认。
7. **P2：在真实数据上调 dead zone、低速 smoothing、基础灵敏度和可选速度增益；不要把算法问题与灵敏度问题混在一起。**
8. **暂不做：** 为此购买/假设磁力计、宣称绝对屏幕指向、或尝试从加速度二次积分得到手柄位置。这三项都不解决当前核心交互。

最终判断：**用户的目标可达到，而且不需要磁力计；但“任意握姿”必须靠明确的交互参考来定义。** 对普通相对鼠标，用重力 + 有状态切线轴；对“像遥控器一样指向”，用 SR 每次建立 quaternion 射线零点。若既没有外部光学参考、也不允许 clutch/recenter，还要求任何奇异握姿下长期绝对稳定，则超出了 6 轴传感器可观测的信息边界。

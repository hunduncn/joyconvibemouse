# BetterJoy 体感鼠标实现与 macOS 可移植性

> 调研日期：2026-09-01  
> 范围：BetterJoy 官方仓库的体感鼠标算法、Windows 输出路径、驱动依赖，以及对本项目的参考价值  
> 证据标准：BetterJoy/WindowsInput 固定 commit 的源码与 Apple、Microsoft 官方 API 文档；未修改产品代码

## 结论

BetterJoy 的体感鼠标**不是虚拟 HID 鼠标**。它的完整路径是：

```text
Joy-Con HID 报告
  → 工厂/运行时校准与固定轴变换
  → Madgwick 6 轴姿态，或直接读取 gyro
  → Δyaw / Δpitch，或 gyro × 15 ms
  → WindowsInput.MoveBy(dx, dy)
  → user32!SendInput
  → Windows 合成鼠标输入流
```

BetterJoy 安装的 ViGEmBus 只用于模拟 Xbox 360 / DualShock 4 **游戏手柄**，不参与鼠标路径，也不创建虚拟鼠标。BetterJoy 因而不能作为“虚拟鼠标可以触发 macOS 原生摇动定位”的证据；它的 `SendInput` 在概念上更接近本项目当前的 `CGEvent.post`。

算法方面，BetterJoy 值得交叉参考的是 Joy-Con 原始数据解码、校准、单 Joy-Con 的固定轴映射、每包三组 5 ms IMU 样本，以及“按住才启用 gyro”的交互。它的鼠标映射本身则比本项目当前的 anchored quaternion/ray 更简单：滤波模式只取相邻 Euler yaw/pitch 差，原始模式只取两个固定 gyro 轴；没有任意握姿适配、射线锚定、串轴抑制或高低速滤波。因此不建议用它替换当前算法。

若要真正实验 macOS 虚拟 HID 鼠标，应走 Apple 的 `HIDVirtualDevice` / `IOHIDUserDevice` 路线，而不是移植 ViGEm；但 Apple 明确要求 `com.apple.developer.hid.virtual.device` entitlement。当前应用没有该 entitlement，而且 BetterJoy 也不能证明虚拟 HID 一定会触发 macOS 的“摇动鼠标指针以定位”。这应被视为一个需要签名条件和实机验证的独立实验，不是本次源码参考能直接解决的问题。

## 调研基线

BetterJoy 默认分支固定在 commit [`b6715638a3ed1084f8968e8cafebbc6fe2ed0096`](https://github.com/Davidobot/BetterJoy/tree/b6715638a3ed1084f8968e8cafebbc6fe2ed0096)（2024-07-19）。README 明确列出 gyro 控制鼠标，并要求安装 ViGEmBus；但这两个功能在源码里是两条独立输出路径。[BetterJoy README](https://github.com/Davidobot/BetterJoy/blob/b6715638a3ed1084f8968e8cafebbc6fe2ed0096/README.md#L5-L8)、[安装说明](https://github.com/Davidobot/BetterJoy/blob/b6715638a3ed1084f8968e8cafebbc6fe2ed0096/README.md#L23-L37)

BetterJoy 固定依赖 `WindowsInput 6.3.0` 与 `Nefarius.ViGEm.Client 1.17.178`。[packages.config](https://github.com/Davidobot/BetterJoy/blob/b6715638a3ed1084f8968e8cafebbc6fe2ed0096/BetterJoyForCemu/packages.config#L1-L7) `WindowsInput 6.3.0` 的对应源码基线是 [`86abfeee5b026d8ac9b6082f6f908bad3dc7d1ee`](https://github.com/MediatedCommunications/WindowsInput/tree/86abfeee5b026d8ac9b6082f6f908bad3dc7d1ee)，其项目版本字段为 6.3.0。[WindowsInput.csproj](https://github.com/MediatedCommunications/WindowsInput/blob/86abfeee5b026d8ac9b6082f6f908bad3dc7d1ee/WindowsInput/WindowsInput.csproj#L1-L14)

## 1. IMU 到鼠标位移的真实算法

### 1.1 采样与坐标处理

一个 Joy-Con 输入报告内含三组 IMU 子样本。BetterJoy 依次解析三组，每组时间推进 5 ms；按键和鼠标逻辑每份报告执行一次，所以鼠标计算使用固定 `dt = 0.015 s`。[报告循环](https://github.com/Davidobot/BetterJoy/blob/b6715638a3ed1084f8968e8cafebbc6fe2ed0096/BetterJoyForCemu/Joycon.cs#L553-L590)、[固定 15 ms](https://github.com/Davidobot/BetterJoy/blob/b6715638a3ed1084f8968e8cafebbc6fe2ed0096/BetterJoyForCemu/Joycon.cs#L781-L784)

每组样本先从报告的固定字节位置解出三轴 gyro/accelerometer，再使用活动校准或工厂校准数据换算。单 Joy-Con 模式随后做固定符号翻转和 X/Y 交换，最后把 gyro 从度/秒转换为弧度/秒送入 AHRS。[IMU 解码、校准与轴变换](https://github.com/Davidobot/BetterJoy/blob/b6715638a3ed1084f8968e8cafebbc6fe2ed0096/BetterJoyForCemu/Joycon.cs#L1020-L1107)

这部分值得本项目用作解码结果的交叉检查，但不能直接复制符号：BetterJoy 同时支持左右 Joy-Con、成对模式和 Pro Controller，其 `isLeft` / `other` 分支定义了它自己的内部坐标契约；本项目只处理 Joy-Con (R)，必须继续以实机录制和现有 canonical coordinate tests 为准。

### 1.2 6 轴 Madgwick 滤波

BetterJoy 创建采样周期 5 ms 的 `MadgwickAHRS`，默认 `beta = 0.05`。[AHRS 初始化](https://github.com/Davidobot/BetterJoy/blob/b6715638a3ed1084f8968e8cafebbc6fe2ed0096/BetterJoyForCemu/Joycon.cs#L289-L292)、[配置默认值](https://github.com/Davidobot/BetterJoy/blob/b6715638a3ed1084f8968e8cafebbc6fe2ed0096/BetterJoyForCemu/App.config#L95-L104)

该更新函数只有 gyro + accelerometer 六个输入：归一化加速度、执行重力方向的梯度下降纠偏、计算 quaternion 变化率，再按采样周期积分并归一化；没有磁力计输入。[Madgwick 更新](https://github.com/Davidobot/BetterJoy/blob/b6715638a3ed1084f8968e8cafebbc6fe2ed0096/BetterJoyForCemu/MadgwickAHRS.cs#L60-L144)

`GetEulerAngles()` 把 quaternion 转成 pitch/yaw/roll，并同时返回本次和上次角度。它没有在这里处理 Euler 角跨越 `+π/-π` 的 wrap，也没有在鼠标层做握姿补偿。[Euler 输出与上一帧保存](https://github.com/Davidobot/BetterJoy/blob/b6715638a3ed1084f8968e8cafebbc6fe2ed0096/BetterJoyForCemu/MadgwickAHRS.cs#L146-L159)

### 1.3 两条鼠标映射路径

当配置为 `mouse` 且 gyro 处于启用状态时，BetterJoy 从下面两条路径选一条：

```text
UseFilteredIMU = true:
  dx = sensitivityX × (currentYaw - previousYaw)
  dy = -sensitivityY × (currentPitch - previousPitch)

UseFilteredIMU = false:
  dx = sensitivityX × gyroZ × 0.015
  dy = -sensitivityY × gyroY × 0.015
```

结果直接截断为整数并调用 `WindowsInput.Simulate.Events().MoveBy(dx, dy).Invoke()`。[BetterJoy 鼠标分支](https://github.com/Davidobot/BetterJoy/blob/b6715638a3ed1084f8968e8cafebbc6fe2ed0096/BetterJoyForCemu/Joycon.cs#L842-L855)

默认使用 filtered IMU，X/Y 灵敏度分别为 1200/800；raw 模式需要把灵敏度约降低 15 倍。配置还支持按住/切换激活和双 Joy-Con 左右手选择。[体感鼠标配置](https://github.com/Davidobot/BetterJoy/blob/b6715638a3ed1084f8968e8cafebbc6fe2ed0096/BetterJoyForCemu/App.config#L90-L117)

所以 BetterJoy 的“手感”并非来自复杂的空中鼠标算法。filtered 路径相当于姿态角的一阶差分；raw 路径相当于固定两轴角速度积分。两者都没有使用 roll 来连续适配平握，也没有当前项目的 SR 姿态锚点与 virtual ray。

## 2. 最终鼠标输出不是虚拟 HID

BetterJoy 的 `MoveBy` 依赖链可以完整追到 Win32 API：

1. `MoveBy(x,y)` 构造 `MouseMoveRelative`。[EventBuilderMethods.cs](https://github.com/MediatedCommunications/WindowsInput/blob/86abfeee5b026d8ac9b6082f6f908bad3dc7d1ee/WindowsInput/Events/EventBuilderMethods.cs#L170-L175)
2. `MouseMoveRelative` 构造 `MOUSEINPUT`，填入相对 X/Y，并设置 relative move flags。[MouseMove.cs](https://github.com/MediatedCommunications/WindowsInput/blob/86abfeee5b026d8ac9b6082f6f908bad3dc7d1ee/WindowsInput/Events/Mouse/MouseMove.cs#L32-L48)、[relative 类型](https://github.com/MediatedCommunications/WindowsInput/blob/86abfeee5b026d8ac9b6082f6f908bad3dc7d1ee/WindowsInput/Events/Mouse/MouseMove.cs#L61-L64)、[flag 转换](https://github.com/MediatedCommunications/WindowsInput/blob/86abfeee5b026d8ac9b6082f6f908bad3dc7d1ee/WindowsInput/Native/MouseMovementExtensions.cs#L5-L17)
3. `RawInput.Invoke` 把这些 `INPUT` 结构交给 `INPUTDispatcher.SendInput`。[RawInput.cs](https://github.com/MediatedCommunications/WindowsInput/blob/86abfeee5b026d8ac9b6082f6f908bad3dc7d1ee/WindowsInput/Events/RawInput.cs#L78-L102)
4. `INPUTDispatcher` 最终 P/Invoke `user32.dll` 的 `SendInput`。[INPUTDispatcher.cs](https://github.com/MediatedCommunications/WindowsInput/blob/86abfeee5b026d8ac9b6082f6f908bad3dc7d1ee/WindowsInput/Native/INPUT/INPUTDispatcher.cs#L22-L37)

Microsoft 官方定义 `SendInput` 为把一组 `INPUT` 事件插入键盘或鼠标输入流；它“合成”鼠标移动、按键与点击，并不注册一个新的 HID 设备。[Microsoft `SendInput`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput)

BetterJoy 使用的是 relative `MOUSEINPUT`。Microsoft 说明，相对移动会受 Windows 的鼠标速度和加速阈值影响；所以 BetterJoy 在 Windows 上的最终响应还包含操作系统指针曲线，不全由前面的 gyro 灵敏度决定。[Microsoft `MOUSEINPUT`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-mouseinput)

### ViGEm 与鼠标无关

ViGEm client 只在 `ShowAsXInput` 或 `ShowAsDS4` 开启时初始化。[Program.cs](https://github.com/Davidobot/BetterJoy/blob/b6715638a3ed1084f8968e8cafebbc6fe2ed0096/BetterJoyForCemu/Program.cs#L412-L418)

它创建的目标明确是 `CreateXbox360Controller()` 和 `CreateDualShock4Controller()`。[Xbox 360 输出](https://github.com/Davidobot/BetterJoy/blob/b6715638a3ed1084f8968e8cafebbc6fe2ed0096/BetterJoyForCemu/Controller/OutputControllerXbox360.cs#L70-L85)、[DualShock 4 输出](https://github.com/Davidobot/BetterJoy/blob/b6715638a3ed1084f8968e8cafebbc6fe2ed0096/BetterJoyForCemu/Controller/OutputControllerDualShock4.cs#L77-L93) 鼠标分支从 `Joycon.cs` 直接进入 WindowsInput，不经过这两个 output controller。

HidGuardian 的作用也不是创建鼠标，而是控制哪些进程能看到原物理手柄，以避免双重输入；BetterJoy 默认已经不安装它。[Drivers README](https://github.com/Davidobot/BetterJoy/blob/b6715638a3ed1084f8968e8cafebbc6fe2ed0096/BetterJoyForCemu/Drivers/README.txt#L1-L8)、[进程白名单代码](https://github.com/Davidobot/BetterJoy/blob/b6715638a3ed1084f8968e8cafebbc6fe2ed0096/BetterJoyForCemu/Program.cs#L365-L409)

## 3. 与当前 Swift 实现的对比

| 层面 | BetterJoy | 当前 JoyCon Vibe Remote | 判断 |
| --- | --- | --- | --- |
| IMU 采样 | 每报告 3 × 5 ms | 同样逐个处理三子样本 | 已具备，不需照搬 |
| 姿态融合 | Madgwick gyro + accel | 自有 quaternion / gravity 融合与偏置更新 | BetterJoy 可作交叉参考，不构成升级 |
| 鼠标 X/Y | `Δyaw, -Δpitch` 或固定 `gyroZ, -gyroY` | SR 锚定完整 quaternion，旋转 virtual ray | 当前方案更适合用户“指向而非翻腕”的目标 |
| 随意握姿 | 无连续姿态空间转换，roll 不进入鼠标 | 锚定时由当前重力建立 screen-right/up | BetterJoy 不能解决此前竖握/平握问题 |
| 串轴 | 无显式处理 | cardinal stabilization | 当前更强 |
| 低速噪声/高速移动 | 主要依赖 AHRS、整数截断、灵敏度和 Windows 指针曲线 | radial cutoff、低速平滑、每样本限幅 | 不应倒退到 BetterJoy |
| 离合 | 配置按键按住或切换 gyro | SR 按住并在按下时重新锚定 | 当前交互更明确 |
| 系统输出 | Windows `SendInput` 合成输入 | macOS `CGEvent.post` 合成输入 | 同类机制，不是虚拟 HID |

BetterJoy filtered 算法不应替换当前 [`GyroPointerEngine.swift`](../Sources/JoyConVibeCore/GyroPointerEngine.swift)：相邻 Euler 差在角度 wrap 和奇异姿态附近天然更脆弱，而且只用 pitch/yaw 会重新引入用户已经遇到的握姿依赖。当前 anchored ray 使用完整相对 quaternion，并把 SR 按下姿态当作新的屏幕切平面；这比 BetterJoy 更符合本产品目标。

可以从 BetterJoy 吸收的有限内容：

- 用真实数据再次核对右 Joy-Con 校准比例、固定坐标变换和三样本顺序；
- 保留 raw gyro 作为诊断对照模式，以区分“融合错误”和“输出滤波错误”，不作为默认产品模式；
- 若用户仍觉得水平/垂直速度不均，可像 BetterJoy 一样提供独立 X/Y 灵敏度，但先保持默认统一，避免掩盖坐标错误；
- 性能测试时区分本项目自身的 px/degree 曲线和操作系统最终指针曲线。

## 4. macOS 真正虚拟鼠标的边界

Apple 提供两套创建虚拟 HID 的官方入口：

- macOS 15+ 的 CoreHID `HIDVirtualDevice`，由 HID report descriptor 定义设备并向系统派发 input reports；Apple 将其描述为模拟已连接 HID 外设的虚拟服务。[`HIDVirtualDevice`](https://developer.apple.com/documentation/corehid/hidvirtualdevice)、[创建虚拟设备](https://developer.apple.com/documentation/corehid/creatingvirtualdevices)
- 较早的 IOKit `IOHIDUserDeviceCreateWithProperties`。[Apple API](https://developer.apple.com/documentation/iokit/3334952-iohiduserdevicecreatewithpropert)

Apple 官方 entitlement 文档将 `com.apple.developer.hid.virtual.device` 定义为允许 app 创建和管理虚拟 HID 的权限；IOKit SDK 头文件也明确规定创建 `IOHIDUserDevice` 需要此 entitlement 来验证设备来源。[Apple entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device)

当前项目最低目标是 macOS 14，当前安装包没有任何签名 entitlement。因此，“改成虚拟 HID 鼠标”不是把 BetterJoy 的 ViGEm 或 `MoveBy` 翻译成 Swift，而是独立的产品/分发工程：

1. 确认可用的 Apple Developer 签名与 entitlement/provisioning 条件；
2. 选择兼容策略：macOS 15+ CoreHID，或 IOKit/DriverKit 路径；
3. 定义标准相对鼠标 HID report descriptor，处理按键、滚轮和相对 X/Y 报告；
4. 保留 `CGEvent` fallback；
5. 实机验证虚拟设备是否真的计入 macOS 的“摇动鼠标指针以定位”检测。

最后一步不能从 Apple 文档或 BetterJoy 源码推导为必然成功。BetterJoy 只证明 Windows `SendInput` 足以移动指针，不证明 macOS 会把虚拟 HID 的快速反向报告当作物理鼠标摇动。因此，在拿到正确 entitlement 之前，不建议为“指针放大”重构当前稳定的输入层。

## 建议决策

1. **体感算法不换成 BetterJoy。** 当前 anchored quaternion/ray 路线更适合现有需求；BetterJoy 可用于解码、轴向和 raw 模式的回归对照。
2. **不要安装或移植 ViGEm。** 它是 Windows 虚拟游戏手柄总线，与 macOS 和鼠标无关。
3. **不要把 `SendInput` 误认为硬件鼠标。** BetterJoy 的输出与当前 `CGEvent` 都是平台级合成输入。
4. **若仍要追求系统原生摇动放大，单独立项做虚拟 HID 可行性原型。** 前置门槛是 Apple entitlement 与签名；验收标准必须包含系统功能是否响应，而不只是光标能否移动。


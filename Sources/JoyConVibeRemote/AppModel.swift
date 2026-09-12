import AppKit
import Combine
import Foundation
import JoyConVibeCore

enum RemoteStatus: Equatable {
    case disconnected
    case initializing
    case calibrating(Double)
    case connected
    case paused
    case active
    case precision
    case error

    var title: String {
        switch self {
        case .disconnected: return "等待右 Joy-Con"
        case .initializing: return "正在初始化"
        case .calibrating: return "请将手柄静置"
        case .connected: return "已连接"
        case .paused: return "遥控已暂停"
        case .active: return "体感鼠标开启"
        case .precision: return "精准瞄准"
        case .error: return "需要处理"
        }
    }

    var symbolName: String {
        switch self {
        case .disconnected: return "gamecontroller"
        case .initializing: return "antenna.radiowaves.left.and.right"
        case .calibrating: return "gyroscope"
        case .connected: return "gamecontroller.fill"
        case .paused: return "pause.circle.fill"
        case .active: return "scope"
        case .precision: return "viewfinder"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var status: RemoteStatus = .disconnected
    @Published private(set) var deviceName = "Joy-Con (R)"
    @Published private(set) var batteryLevel = 0
    @Published private(set) var isCharging = false
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var loginItemMessage: String?

    let settings: RemoteSettings
    var onShowStatus: (() -> Void)?

    private let eventEmitter = SystemEventEmitter()
    private let loginItemManager: LoginItemManager
    private let managesLoginItem: Bool
    private lazy var pointerMotionEmitter = PointerMotionEmitter(eventEmitter: eventEmitter)
    private var mapper = RemoteActionMapper()
    private var pointerEngine = GyroPointerEngine()
    private var pointerFrameBuffer = ClutchedPointerFrameBuffer()
    private var pointerTuningLifecycle = PointerTuningLifecycle()
    private let transport: any JoyConTransport
    private var isConnected = false
    private var hasStarted = false

    init(
        settings: RemoteSettings,
        transport: (any JoyConTransport)? = nil,
        loginItemManager: LoginItemManager? = nil,
        managesLoginItem: Bool = Bundle.main.bundleURL.pathExtension == "app"
    ) {
        self.settings = settings
        self.transport = transport ?? JoyConHIDTransport()
        self.loginItemManager = loginItemManager ?? LoginItemManager()
        self.managesLoginItem = managesLoginItem
        configureTransport()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        accessibilityTrusted = eventEmitter.requestAccessibility(prompt: true)
        setLaunchAtLogin(settings.launchAtLogin)
        transport.start()
    }

    func stop() {
        hasStarted = false
        transport.stop()
        releaseAllInputs()
    }

    func setRemoteEnabled(_ enabled: Bool) {
        settings.enabled = enabled
        if enabled {
            reconnect()
        } else {
            releaseAllInputs()
            pointerEngine.resetMotion()
            pointerFrameBuffer.reset()
            if isConnected { updateStatus(.paused) }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard managesLoginItem else { return }
        do {
            try loginItemManager.setEnabled(enabled)
            refreshLoginItemStatus()
        } catch {
            settings.launchAtLogin = loginItemManager.isRegistered
            loginItemMessage = "登录启动设置失败：\(error.localizedDescription)"
        }
    }

    private func refreshLoginItemStatus() {
        guard managesLoginItem else { return }
        let registered = loginItemManager.isRegistered
        if settings.launchAtLogin != registered { settings.launchAtLogin = registered }
        loginItemMessage = loginItemManager.requiresApproval
            ? "登录启动等待批准，请在系统设置 → 通用 → 登录项中允许。也可取消勾选以撤销注册。"
            : nil
    }

    func reconnect() {
        hasStarted = true
        releaseAllInputs()
        transport.stop()
        isConnected = false
        updateTelemetry(batteryLevel: 0, isCharging: false)
        pointerEngine.beginCalibration()
        errorMessage = nil
        updateStatus(.disconnected)
        transport.start()
    }

    func recalibrate() {
        pointerEngine.beginCalibration()
        pointerFrameBuffer.reset()
        pointerMotionEmitter.reset()
        updateStatus(.calibrating(0))
    }

    func setPointerTuningEditing(_ isEditing: Bool) {
        guard pointerTuningLifecycle.update(isEditing: isEditing) else { return }
        // A slider drag may span several IMU reports and leave scheduled mouse
        // deltas using intermediate gains. Commit the final value at a clean
        // clutch boundary without throwing away the established gyro bias.
        pointerEngine.resetMotion()
        pointerFrameBuffer.reset()
        pointerMotionEmitter.reset()
    }

    func updateTelemetry(batteryLevel newBatteryLevel: Int, isCharging newIsCharging: Bool) {
        if batteryLevel != newBatteryLevel {
            batteryLevel = newBatteryLevel
        }
        if isCharging != newIsCharging {
            isCharging = newIsCharging
        }
    }

    func updateStatus(_ newStatus: RemoteStatus) {
        guard status != newStatus else { return }
        status = newStatus
    }

    func refreshPermissions() {
        accessibilityTrusted = eventEmitter.isAccessibilityTrusted
        refreshLoginItemStatus()
        if hasStarted && !transport.isRunning { reconnect() }
    }

    func requestAccessibility() {
        accessibilityTrusted = eventEmitter.requestAccessibility(prompt: true)
        if !accessibilityTrusted {
            eventEmitter.openAccessibilitySettings()
        }
    }

    func openInputMonitoringSettings() {
        eventEmitter.openInputMonitoringSettings()
    }

    func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func configureTransport() {
        transport.onConnected = { [weak self] name in
            guard let self else { return }
            self.isConnected = true
            self.deviceName = name
            self.errorMessage = nil
            self.pointerEngine.beginCalibration()
            self.updateStatus(.initializing)
        }
        transport.onDisconnected = { [weak self] in
            guard let self else { return }
            self.isConnected = false
            self.updateStatus(.disconnected)
            self.updateTelemetry(batteryLevel: 0, isCharging: false)
            self.releaseAllInputs()
            self.pointerEngine.beginCalibration()
        }
        transport.onRecovering = { [weak self] in
            guard let self, self.isConnected else { return }
            self.releaseAllInputs()
            self.pointerEngine.beginCalibration()
            self.updateStatus(.initializing)
        }
        transport.onFrame = { [weak self] frame in
            self?.handle(frame: frame)
        }
        transport.onError = { [weak self] message in
            guard let self else { return }
            self.errorMessage = message
            self.updateStatus(.error)
        }
    }

    private func handle(frame: JoyConInputFrame) {
        updateTelemetry(
            batteryLevel: frame.batteryLevel,
            isCharging: frame.isCharging
        )
        guard settings.enabled else {
            if isConnected { updateStatus(.paused) }
            return
        }

        let timestamp = ProcessInfo.processInfo.systemUptime
        for action in mapper.process(
            frame: frame,
            timestamp: timestamp,
            buttonBindings: settings.buttonBindings,
            stickVerticalBinding: settings.stickVerticalBinding
        ) {
            if action == .showStatus {
                onShowStatus?()
            } else {
                eventEmitter.emit(action)
            }
        }

        let gyroActive = frame.buttons.contains(.zr)
        let precision = gyroActive && frame.buttons.contains(.sl)
        let pointerSettings = settings.pointerSettings(
            screenWidthPoints: activeScreenWidthPoints
        )
        let frameDeltas = frame.gyroSamples.compactMap { sample in
            pointerEngine.process(
                sample: sample,
                isActive: gyroActive,
                isPrecision: precision,
                settings: pointerSettings
            )
        }
        let confirmedDeltas = pointerFrameBuffer.process(
            frameDeltas: frameDeltas,
            isActive: gyroActive
        )
        if gyroActive {
            pointerMotionEmitter.emit(confirmedDeltas)
        } else {
            pointerMotionEmitter.reset()
        }

        switch pointerEngine.calibrationState {
        case let .calibrating(progress):
            updateStatus(.calibrating(progress))
        case .ready:
            if precision {
                updateStatus(.precision)
            } else if gyroActive {
                updateStatus(.active)
            } else {
                updateStatus(.connected)
            }
        }
    }

    private var activeScreenWidthPoints: Double {
        let mouseLocation = NSEvent.mouseLocation
        let width = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })?.frame.width
            ?? NSScreen.main?.frame.width
            ?? 1920
        return Double(width)
    }

    private func releaseAllInputs() {
        pointerFrameBuffer.reset()
        pointerMotionEmitter.reset()
        for action in mapper.reset() {
            eventEmitter.emit(action)
        }
        eventEmitter.releaseAll()
    }
}

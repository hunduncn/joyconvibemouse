import SwiftUI
import JoyConVibeCore

struct StatusMenuView: View {
    static let panelWidth: CGFloat = 470
    static let initialHeight: CGFloat = 360

    @ObservedObject var model: AppModel
    @ObservedObject var settings: RemoteSettings
    let onPreferredHeightChange: (CGFloat) -> Void

    @State private var tuningExpanded = false
    @State private var mappingsExpanded = true
    @State private var panelHeight = Self.initialHeight

    init(
        model: AppModel,
        settings: RemoteSettings,
        onPreferredHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.model = model
        self.settings = settings
        self.onPreferredHeightChange = onPreferredHeightChange
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                if !model.accessibilityTrusted {
                    permissionNotice
                }

                if let error = model.errorMessage {
                    errorNotice(error)
                }

                Divider()

                HoverHighlightRow {
                    Toggle(
                        "启用 Joy-Con 遥控",
                        isOn: Binding(
                            get: { settings.enabled },
                            set: { model.setRemoteEnabled($0) }
                        )
                    )
                }

                Divider()
                tuningDisclosure
                if tuningExpanded {
                    pointerControls
                }

                Divider()
                mappingDisclosure
                if mappingsExpanded {
                    mappingGrid
                }
                Divider()

                footer
            }
            .padding(14)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: PanelContentHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            }
        }
        .frame(width: Self.panelWidth, height: panelHeight)
        .onPreferenceChange(PanelContentHeightPreferenceKey.self) { contentHeight in
            let preferredHeight = StatusPanelHeightPolicy.height(for: contentHeight)
            guard abs(preferredHeight - panelHeight) > 0.5 else { return }
            panelHeight = preferredHeight
            onPreferredHeightChange(preferredHeight)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.status.symbolName)
                .font(.system(size: 26))
                .foregroundStyle(statusColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.status.title)
                    .font(.headline)
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.batteryLevel > 0 {
                Label("\(model.batteryLevel * 25)%", systemImage: batterySymbol)
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("需要辅助功能权限才能输出鼠标和键盘事件。", systemImage: "lock.trianglebadge.exclamationmark")
                .font(.caption)
            Button("授予辅助功能权限") {
                model.requestAccessibility()
            }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func errorNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            HStack {
                Button("输入监控设置") { model.openInputMonitoringSettings() }
                Button("蓝牙设置") { model.openBluetoothSettings() }
            }
        }
        .padding(10)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var pointerControls: some View {
        VStack(alignment: .leading, spacing: 2) {
            TuningSliderRow(
                title: "整体灵敏度",
                initialValue: settings.sensitivity,
                range: 0.25...4,
                step: 0.05,
                onValueChanged: { settings.sensitivity = $0 },
                onEditingChanged: model.setPointerTuningEditing
            )
            TuningSliderRow(
                title: "水平倍率",
                initialValue: settings.horizontalSensitivityMultiplier,
                range: 0.75...2.50,
                step: 0.05,
                onValueChanged: { settings.horizontalSensitivityMultiplier = $0 },
                onEditingChanged: model.setPointerTuningEditing
            )
            TuningSliderRow(
                title: "加速度",
                initialValue: settings.accelerationStrength,
                range: 0...2,
                step: 0.05,
                onValueChanged: { settings.accelerationStrength = $0 },
                onEditingChanged: model.setPointerTuningEditing
            )
            TuningSliderRow(
                title: "稳定度",
                initialValue: settings.stabilizationStrength,
                range: 0...2,
                step: 0.05,
                onValueChanged: { settings.stabilizationStrength = $0 },
                onEditingChanged: model.setPointerTuningEditing
            )
            TuningSliderRow(
                title: "精准比例",
                initialValue: settings.precisionMultiplier,
                range: 0.10...0.60,
                step: 0.05,
                display: .percent,
                onValueChanged: { settings.precisionMultiplier = $0 },
                onEditingChanged: model.setPointerTuningEditing
            )

            PointerDirectionRow(settings: settings) {
                model.recalibrate()
            }
        }
    }

    private var tuningDisclosure: some View {
        DisclosureHeader(
            title: "体感调节",
            systemImage: "gyroscope",
            isExpanded: tuningExpanded
        ) {
            tuningExpanded.toggle()
        }
    }

    private var mappingDisclosure: some View {
        DisclosureHeader(
            title: "按键自定义",
            systemImage: "slider.horizontal.3",
            isExpanded: mappingsExpanded
        ) {
            mappingsExpanded.toggle()
        }
    }

    private var mappingGrid: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("按键映射")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("恢复默认") { settings.resetButtonMappings() }
                    .font(.caption)
            }

            HStack(spacing: 6) {
                Text("按键")
                    .frame(width: 62, alignment: .leading)
                Text("单按")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("按住 SL 后")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            ForEach(RemoteButtonAction.configurableButtons, id: \.self) { button in
                HoverHighlightRow {
                    HStack(spacing: 6) {
                        Text(button.mappingTitle)
                            .font(.caption.monospaced().weight(.semibold))
                            .frame(width: 62, alignment: .leading)
                        Picker(
                            "",
                            selection: Binding(
                                get: { settings.binding(for: button).primary },
                                set: { settings.setPrimaryMapping($0, for: button) }
                            )
                        ) {
                            ForEach(RemoteButtonAction.primaryChoices, id: \.self) { action in
                                Text(action.mappingTitle).tag(action)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Picker(
                            "",
                            selection: Binding(
                                get: { settings.binding(for: button).withSL },
                                set: { settings.setSLMapping($0, for: button) }
                            )
                        ) {
                            ForEach(RemoteButtonAction.slChoices, id: \.self) { action in
                                Text(action.mappingTitle).tag(action)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            HoverHighlightRow {
                HStack(spacing: 6) {
                    Text("摇杆上下")
                        .font(.caption.monospaced().weight(.semibold))
                        .frame(width: 62, alignment: .leading)
                    Picker(
                        "",
                        selection: Binding(
                            get: { settings.stickVerticalBinding.primary },
                            set: { settings.setStickVerticalPrimary($0) }
                        )
                    ) {
                        ForEach(RemoteStickVerticalAction.primaryChoices, id: \.self) { action in
                            Text(action.mappingTitle).tag(action)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Picker(
                        "",
                        selection: Binding(
                            get: { settings.stickVerticalBinding.withSL },
                            set: { settings.setStickVerticalSL($0) }
                        )
                    ) {
                        ForEach(RemoteStickVerticalAction.slChoices, id: \.self) { action in
                            Text(action.mappingTitle).tag(action)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Text("固定：ZR 开启体感 · ZR + SL 精细体感 · 摇杆左右为 ← →")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HoverHighlightRow {
            HStack {
                Toggle(
                    "登录时启动",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(.caption)

                Spacer()
                Button("蓝牙") { model.openBluetoothSettings() }
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    private var statusDetail: String {
        switch model.status {
        case let .calibrating(progress):
            return "静置约 1 秒 · \(Int(progress * 100))%"
        case .disconnected:
            return "请配对并唤醒 Joy-Con (R)"
        default:
            return model.deviceName
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .precision: return .purple
        case .active: return .blue
        case .connected: return .green
        case .paused: return .secondary
        case .calibrating, .initializing: return .orange
        case .error: return .red
        case .disconnected: return .secondary
        }
    }

    private var batterySymbol: String {
        if model.isCharging { return "battery.100percent.bolt" }
        switch model.batteryLevel {
        case 4: return "battery.100percent"
        case 3: return "battery.75percent"
        case 2: return "battery.50percent"
        default: return "battery.25percent"
        }
    }
}

enum StatusPanelHeightPolicy {
    static let minimumHeight: CGFloat = 220
    static let maximumHeight: CGFloat = 720

    static func height(for contentHeight: CGFloat) -> CGFloat {
        min(max(ceil(contentHeight), minimumHeight), maximumHeight)
    }
}

private struct PanelContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DisclosureHeader: View {
    let title: String
    let systemImage: String
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        HoverHighlightRow {
            Button(action: action) {
                HStack {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(isExpanded ? "收起" : "展开")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct HoverHighlightRow<Content: View>: View {
    @State private var isHovering = false
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering ? Color.accentColor.opacity(0.12) : Color.clear)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.08)) {
                    isHovering = hovering
                }
            }
    }
}

private struct TuningSliderRow: View {
    enum Display {
        case decimal
        case percent
    }

    let title: String
    let range: ClosedRange<Double>
    let step: Double
    let display: Display
    let onValueChanged: (Double) -> Void
    let onEditingChanged: (Bool) -> Void

    @State private var value: Double

    init(
        title: String,
        initialValue: Double,
        range: ClosedRange<Double>,
        step: Double,
        display: Display = .decimal,
        onValueChanged: @escaping (Double) -> Void,
        onEditingChanged: @escaping (Bool) -> Void
    ) {
        self.title = title
        self.range = range
        self.step = step
        self.display = display
        self.onValueChanged = onValueChanged
        self.onEditingChanged = onEditingChanged
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        HoverHighlightRow {
            HStack {
                Text(title)
                    .frame(width: 76, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { value },
                        set: { newValue in
                            value = newValue
                            onValueChanged(newValue)
                        }
                    ),
                    in: range,
                    step: step,
                    onEditingChanged: onEditingChanged
                )
                valueLabel
                    .font(.caption.monospacedDigit())
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private var valueLabel: some View {
        switch display {
        case .decimal:
            Text(value, format: .number.precision(.fractionLength(2)))
        case .percent:
            Text(value, format: .percent.precision(.fractionLength(0)))
        }
    }
}

private struct PointerDirectionRow: View {
    let settings: RemoteSettings
    let recalibrate: () -> Void

    @State private var invertHorizontal: Bool
    @State private var invertVertical: Bool

    init(settings: RemoteSettings, recalibrate: @escaping () -> Void) {
        self.settings = settings
        self.recalibrate = recalibrate
        _invertHorizontal = State(initialValue: settings.invertHorizontal)
        _invertVertical = State(initialValue: settings.invertVertical)
    }

    var body: some View {
        HoverHighlightRow {
            HStack {
                Toggle(
                    "水平反向",
                    isOn: Binding(
                        get: { invertHorizontal },
                        set: { newValue in
                            invertHorizontal = newValue
                            settings.invertHorizontal = newValue
                        }
                    )
                )
                Toggle(
                    "垂直反向",
                    isOn: Binding(
                        get: { invertVertical },
                        set: { newValue in
                            invertVertical = newValue
                            settings.invertVertical = newValue
                        }
                    )
                )
                Spacer()
                Button("重新校准", action: recalibrate)
            }
            .font(.caption)
        }
    }
}

private extension JoyConButton {
    var mappingTitle: String {
        switch self {
        case .r: return "R"
        case .zr: return "ZR"
        case .a: return "A"
        case .b: return "B"
        case .x: return "X"
        case .y: return "Y"
        case .plus: return "+"
        case .home: return "Home"
        case .stick: return "摇杆按下"
        case .sr: return "SR"
        case .sl: return "SL"
        }
    }
}

private extension RemoteButtonAction {
    var mappingTitle: String {
        switch self {
        case .usePrimary: return "同单按"
        case .none: return "无操作"
        case .function: return "Fn（单击）"
        case .returnKey: return "回车"
        case .space: return "空格"
        case .tab: return "Tab"
        case .deleteBackward: return "删除（可长按）"
        case .escape: return "Esc"
        case .leftArrow: return "方向键 ←"
        case .rightArrow: return "方向键 →"
        case .upArrow: return "方向键 ↑"
        case .downArrow: return "方向键 ↓"
        case .commandModifier: return "Command（按住）"
        case .optionModifier: return "Option（按住）"
        case .controlModifier: return "Control（按住）"
        case .shiftModifier: return "Shift（按住）"
        case .leftClick: return "鼠标左键"
        case .rightClick: return "鼠标右键"
        case .switchApplication: return "切换应用"
        case .showStatus: return "显示面板"
        case .newLine: return "换行（不发送）"
        case .interrupt: return "强制中断"
        case .reverseTab: return "Shift+Tab"
        case .commandSymbols: return "循环 / @ $ !"
        }
    }
}

private extension RemoteStickVerticalAction {
    var mappingTitle: String {
        switch self {
        case .usePrimary: return "同单按"
        case .none: return "无操作"
        case .scroll: return "滚动"
        case .arrowKeys: return "方向键 ↑ ↓"
        }
    }
}

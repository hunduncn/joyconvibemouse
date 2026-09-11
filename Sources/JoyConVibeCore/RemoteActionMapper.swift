import Foundation

public struct RemoteActionMapper: Sendable {
    private struct SymbolCycleState: Sendable {
        var button: JoyConButton
        var index: Int
        var lastTapAt: TimeInterval
        var requiresSL: Bool
    }

    private static let commandSymbols = ["/", "@", "$", "!"]
    private static let symbolCycleTimeout: TimeInterval = 1.0
    private static let stickDeadZone = 0.30

    private var previousButtons = Set<JoyConButton>()
    private var previousTimestamp: TimeInterval?
    private var deleteRepeatAt: [JoyConButton: TimeInterval] = [:]
    private var heldMouseButtons: [JoyConButton: RemoteMouseButton] = [:]
    private var heldModifiers: [JoyConButton: RemoteModifier] = [:]
    private var stickDirection: RemoteKey?
    private var stickRepeatAt: TimeInterval?
    private var symbolCycleState: SymbolCycleState?

    public init() {}

    public mutating func process(
        frame: JoyConInputFrame,
        timestamp: TimeInterval,
        buttonBindings: [JoyConButton: RemoteButtonBinding] = RemoteButtonBinding.defaultBindings,
        stickVerticalBinding: RemoteStickVerticalBinding = .defaultBinding
    ) -> [RemoteAction] {
        var actions: [RemoteAction] = []
        let pressed = frame.buttons.subtracting(previousButtons)
        let released = previousButtons.subtracting(frame.buttons)
        let slLayerActive = frame.buttons.contains(.sl)
            && !frame.buttons.contains(.zr)

        let stickIsActive = abs(frame.stick.x) > Self.stickDeadZone
            || abs(frame.stick.y) > Self.stickDeadZone
        if let state = symbolCycleState,
           (state.requiresSL && released.contains(.sl))
            || (state.requiresSL && frame.buttons.contains(.zr))
            || !pressed.subtracting([state.button, .sl]).isEmpty
            || stickIsActive
            || timestamp - state.lastTapAt > Self.symbolCycleTimeout
        {
            symbolCycleState = nil
        }

        for button in RemoteButtonAction.configurableButtons where released.contains(button) {
            releaseHeldAction(for: button, actions: &actions)
            deleteRepeatAt[button] = nil
        }

        let pressedActions: [(button: JoyConButton, action: RemoteButtonAction)] =
            RemoteButtonAction.configurableButtons.compactMap { button in
                guard pressed.contains(button) else { return nil }
                return (
                    button,
                    action(for: button, isSLActive: slLayerActive, bindings: buttonBindings)
                )
            }
        let symbolCycleButtons = Set(
            pressedActions.compactMap { item in
                item.action == .commandSymbols ? item.button : nil
            }
        )
        let ordinaryPressedActions = pressedActions.filter {
            !symbolCycleButtons.contains($0.button)
        }
        for item in ordinaryPressedActions where modifier(for: item.action) != nil {
            press(item.button, action: item.action, timestamp: timestamp, actions: &actions)
        }
        for item in ordinaryPressedActions where modifier(for: item.action) == nil {
            press(item.button, action: item.action, timestamp: timestamp, actions: &actions)
        }

        for button in symbolCycleButtons {
            cycleCommandSymbol(
                button: button,
                requiresSL: slLayerActive,
                timestamp: timestamp,
                actions: &actions
            )
        }

        for (button, repeatAt) in Array(deleteRepeatAt) {
            guard frame.buttons.contains(button),
                  action(
                    for: button,
                    isSLActive: slLayerActive,
                    bindings: buttonBindings
                  ) == .deleteBackward
            else {
                deleteRepeatAt[button] = nil
                continue
            }
            guard !pressed.contains(button), timestamp >= repeatAt else { continue }
            actions.append(.keyTap(.deleteBackward))
            deleteRepeatAt[button] = timestamp + 0.075
        }

        let deltaTime = min(0.05, max(0, timestamp - (previousTimestamp ?? timestamp)))
        let verticalAction = stickVerticalBinding.resolved(isSLActive: slLayerActive)
        processStick(
            frame.stick,
            timestamp: timestamp,
            deltaTime: deltaTime,
            verticalAction: verticalAction,
            actions: &actions
        )

        previousButtons = frame.buttons
        previousTimestamp = timestamp
        return actions
    }

    public mutating func reset() -> [RemoteAction] {
        var actions: [RemoteAction] = []
        for button in [RemoteMouseButton.left, .right] where heldMouseButtons.values.contains(button) {
            actions.append(.mouseButton(button, isDown: false))
        }
        for modifier in RemoteModifier.allCases where heldModifiers.values.contains(modifier) {
            actions.append(.keyModifier(modifier, isDown: false))
        }

        previousButtons.removeAll()
        previousTimestamp = nil
        deleteRepeatAt.removeAll()
        heldMouseButtons.removeAll()
        heldModifiers.removeAll()
        stickDirection = nil
        stickRepeatAt = nil
        symbolCycleState = nil
        return actions
    }

    private mutating func cycleCommandSymbol(
        button: JoyConButton,
        requiresSL: Bool,
        timestamp: TimeInterval,
        actions: inout [RemoteAction]
    ) {
        let nextIndex: Int
        if let state = symbolCycleState,
           state.button == button,
           timestamp - state.lastTapAt <= Self.symbolCycleTimeout
        {
            actions.append(.keyShortcut(.deleteBackward, modifiers: []))
            nextIndex = (state.index + 1) % Self.commandSymbols.count
        } else {
            nextIndex = 0
        }

        actions.append(.typeText(Self.commandSymbols[nextIndex]))
        symbolCycleState = SymbolCycleState(
            button: button,
            index: nextIndex,
            lastTapAt: timestamp,
            requiresSL: requiresSL
        )
    }

    private func action(
        for button: JoyConButton,
        isSLActive: Bool,
        bindings: [JoyConButton: RemoteButtonBinding]
    ) -> RemoteButtonAction {
        let binding = bindings[button]
            ?? RemoteButtonBinding.defaultBindings[button]
            ?? RemoteButtonBinding(primary: .none, withSL: .usePrimary)
        return binding.resolved(isSLActive: isSLActive)
    }

    private mutating func press(
        _ button: JoyConButton,
        action: RemoteButtonAction,
        timestamp: TimeInterval,
        actions: inout [RemoteAction]
    ) {
        if let key = key(for: action) {
            actions.append(.keyTap(key))
            if action == .deleteBackward {
                deleteRepeatAt[button] = timestamp + 0.42
            }
            return
        }

        if let mouseButton = mouseButton(for: action) {
            if !heldMouseButtons.values.contains(mouseButton) {
                actions.append(.mouseButton(mouseButton, isDown: true))
            }
            heldMouseButtons[button] = mouseButton
            return
        }

        if let modifier = modifier(for: action) {
            if !heldModifiers.values.contains(modifier) {
                actions.append(.keyModifier(modifier, isDown: true))
            }
            heldModifiers[button] = modifier
            return
        }

        switch action {
        case .switchApplication:
            actions.append(.switchApplication)
        case .showStatus:
            actions.append(.showStatus)
        case .newLine:
            actions.append(.keyShortcut(.returnKey, modifiers: [.shift]))
        case .interrupt:
            actions.append(.keyShortcut(.c, modifiers: [.control]))
        case .reverseTab:
            actions.append(.keyShortcut(.tab, modifiers: [.shift]))
        default:
            break
        }
    }

    private mutating func releaseHeldAction(
        for button: JoyConButton,
        actions: inout [RemoteAction]
    ) {
        if let mouseButton = heldMouseButtons.removeValue(forKey: button),
           !heldMouseButtons.values.contains(mouseButton)
        {
            actions.append(.mouseButton(mouseButton, isDown: false))
        }
        if let modifier = heldModifiers.removeValue(forKey: button),
           !heldModifiers.values.contains(modifier)
        {
            actions.append(.keyModifier(modifier, isDown: false))
        }
    }

    private func key(for action: RemoteButtonAction) -> RemoteKey? {
        switch action {
        case .function: return .function
        case .returnKey: return .returnKey
        case .space: return .space
        case .tab: return .tab
        case .deleteBackward: return .deleteBackward
        case .escape: return .escape
        case .leftArrow: return .leftArrow
        case .rightArrow: return .rightArrow
        case .upArrow: return .upArrow
        case .downArrow: return .downArrow
        default: return nil
        }
    }

    private func mouseButton(for action: RemoteButtonAction) -> RemoteMouseButton? {
        switch action {
        case .leftClick: return .left
        case .rightClick: return .right
        default: return nil
        }
    }

    private func modifier(for action: RemoteButtonAction) -> RemoteModifier? {
        switch action {
        case .commandModifier: return .command
        case .optionModifier: return .option
        case .controlModifier: return .control
        case .shiftModifier: return .shift
        default: return nil
        }
    }

    private mutating func processStick(
        _ stick: StickPosition,
        timestamp: TimeInterval,
        deltaTime: TimeInterval,
        verticalAction: RemoteStickVerticalAction,
        actions: inout [RemoteAction]
    ) {
        let deadZone = Self.stickDeadZone
        let horizontalMagnitude = abs(stick.x)
        let verticalMagnitude = abs(stick.y)

        if verticalMagnitude > deadZone, verticalMagnitude >= horizontalMagnitude {
            switch verticalAction {
            case .arrowKeys:
                let direction: RemoteKey = stick.y < 0 ? .downArrow : .upArrow
                repeatStickKey(direction, timestamp: timestamp, actions: &actions)
            case .scroll:
                let normalized = (verticalMagnitude - deadZone) / (1 - deadZone)
                let signed = stick.y < 0 ? -normalized : normalized
                actions.append(.scroll(points: signed * 520 * deltaTime))
                stickDirection = nil
                stickRepeatAt = nil
            case .none, .usePrimary:
                stickDirection = nil
                stickRepeatAt = nil
            }
            return
        }

        guard horizontalMagnitude > deadZone else {
            stickDirection = nil
            stickRepeatAt = nil
            return
        }

        let direction: RemoteKey = stick.x < 0 ? .leftArrow : .rightArrow
        repeatStickKey(direction, timestamp: timestamp, actions: &actions)
    }

    private mutating func repeatStickKey(
        _ direction: RemoteKey,
        timestamp: TimeInterval,
        actions: inout [RemoteAction]
    ) {
        if direction != stickDirection {
            actions.append(.keyTap(direction))
            stickDirection = direction
            stickRepeatAt = timestamp + 0.38
        } else if let repeatAt = stickRepeatAt, timestamp >= repeatAt {
            actions.append(.keyTap(direction))
            stickRepeatAt = timestamp + 0.09
        }
    }
}

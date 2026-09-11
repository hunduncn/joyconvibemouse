import AppKit
import ApplicationServices
import CoreGraphics
import JoyConVibeCore

final class SystemEventEmitter {
    private var leftMouseDown = false
    private var rightMouseDown = false
    private var heldModifiers = Set<RemoteModifier>()

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    func emit(_ action: RemoteAction) {
        guard isAccessibilityTrusted else { return }
        switch action {
        case let .keyTap(key):
            tap(key)
        case let .keyShortcut(key, modifiers):
            tap(key, exactModifiers: modifiers)
        case let .keyModifier(modifier, isDown):
            setModifier(modifier, isDown: isDown)
        case let .typeText(text):
            typeText(text)
        case let .mouseButton(button, isDown):
            setMouseButton(button, isDown: isDown)
        case let .scroll(points):
            scroll(points: points)
        case .switchApplication:
            switchApplication()
        case .showStatus:
            break
        }
    }

    func moveCursor(by delta: PointerDelta) {
        guard isAccessibilityTrusted,
              let source = CGEventSource(stateID: .hidSystemState),
              let currentEvent = CGEvent(source: source)
        else { return }

        let current = currentEvent.location
        let descriptor = MouseMovementEventDescriptor(
            currentX: current.x,
            currentY: current.y,
            delta: delta
        )
        let destination = CGPoint(
            x: descriptor.destinationX,
            y: descriptor.destinationY
        )
        let eventType: CGEventType
        let button: CGMouseButton
        if leftMouseDown {
            eventType = .leftMouseDragged
            button = .left
        } else if rightMouseDown {
            eventType = .rightMouseDragged
            button = .right
        } else {
            eventType = .mouseMoved
            button = .left
        }

        let event = CGEvent(
            mouseEventSource: source,
            mouseType: eventType,
            mouseCursorPosition: destination,
            mouseButton: button
        )
        event?.flags.insert(.maskNonCoalesced)
        event?.setIntegerValueField(
            .mouseEventDeltaX,
            value: descriptor.relativeDeltaX
        )
        event?.setIntegerValueField(
            .mouseEventDeltaY,
            value: descriptor.relativeDeltaY
        )
        event?.post(tap: .cghidEventTap)
    }

    func releaseAll() {
        if leftMouseDown { setMouseButton(.left, isDown: false) }
        if rightMouseDown { setMouseButton(.right, isDown: false) }
        for modifier in RemoteModifier.allCases where heldModifiers.contains(modifier) {
            setModifier(modifier, isDown: false)
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func openInputMonitoringSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func tap(
        _ key: RemoteKey,
        exactModifiers: Set<RemoteModifier>? = nil
    ) {
        let keyCode = keyCode(for: key)
        let baseFlags = exactModifiers.map(flags(for:)) ?? activeModifierFlags
        for step in KeyboardEventPlan.tap(for: key) {
            var eventFlags = baseFlags
            if step.functionModifierIsDown {
                eventFlags.insert(.maskSecondaryFn)
            }
            postKey(code: keyCode, isDown: step.isDown, flags: eventFlags)
        }
    }

    private func keyCode(for key: RemoteKey) -> CGKeyCode {
        let keyCode: CGKeyCode
        switch key {
        case .c: keyCode = 0x08
        case .function: keyCode = 0x3F
        case .returnKey: keyCode = 0x24
        case .space: keyCode = 0x31
        case .tab: keyCode = 0x30
        case .deleteBackward: keyCode = 0x33
        case .escape: keyCode = 0x35
        case .leftArrow: keyCode = 0x7B
        case .rightArrow: keyCode = 0x7C
        case .upArrow: keyCode = 0x7E
        case .downArrow: keyCode = 0x7D
        }
        return keyCode
    }

    private func typeText(_ text: String) {
        let characters = Array(text.utf16)
        guard !characters.isEmpty else { return }

        for isDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 0,
                keyDown: isDown
            ) else { continue }
            event.flags = []
            characters.withUnsafeBufferPointer { buffer in
                guard let address = buffer.baseAddress else { return }
                event.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: address
                )
            }
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            event.post(tap: .cghidEventTap)
        }
    }

    private func setModifier(_ modifier: RemoteModifier, isDown: Bool) {
        if isDown {
            guard heldModifiers.insert(modifier).inserted else { return }
        } else {
            guard heldModifiers.remove(modifier) != nil else { return }
        }
        postKey(
            code: keyCode(for: modifier),
            isDown: isDown,
            flags: activeModifierFlags
        )
    }

    private func keyCode(for modifier: RemoteModifier) -> CGKeyCode {
        switch modifier {
        case .command: return 0x37
        case .option: return 0x3A
        case .control: return 0x3B
        case .shift: return 0x38
        }
    }

    private var activeModifierFlags: CGEventFlags {
        flags(for: heldModifiers)
    }

    private func flags(for modifiers: Set<RemoteModifier>) -> CGEventFlags {
        var result: CGEventFlags = []
        if modifiers.contains(.command) { result.insert(.maskCommand) }
        if modifiers.contains(.option) { result.insert(.maskAlternate) }
        if modifiers.contains(.control) { result.insert(.maskControl) }
        if modifiers.contains(.shift) { result.insert(.maskShift) }
        return result
    }

    private func postKey(code: CGKeyCode, isDown: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: isDown) else { return }
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        event.post(tap: .cghidEventTap)
    }

    private func setMouseButton(_ button: RemoteMouseButton, isDown: Bool) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let current = CGEvent(source: source)?.location
        else { return }

        let cgButton: CGMouseButton = button == .left ? .left : .right
        let type: CGEventType
        switch (button, isDown) {
        case (.left, true): type = .leftMouseDown
        case (.left, false): type = .leftMouseUp
        case (.right, true): type = .rightMouseDown
        case (.right, false): type = .rightMouseUp
        }

        CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: current,
            mouseButton: cgButton
        )?.post(tap: .cghidEventTap)

        if button == .left { leftMouseDown = isDown }
        if button == .right { rightMouseDown = isDown }
    }

    private func scroll(points: Double) {
        let rounded = Int32(max(Double(Int32.min), min(Double(Int32.max), points.rounded())))
        guard rounded != 0 else { return }
        CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: rounded,
            wheel2: 0,
            wheel3: 0
        )?.post(tap: .cghidEventTap)
    }

    private func switchApplication() {
        let commandKey: CGKeyCode = 0x37
        let tabKey: CGKeyCode = 0x30
        var commandFlags = activeModifierFlags
        commandFlags.insert(.maskCommand)
        if !heldModifiers.contains(.command) {
            postKey(code: commandKey, isDown: true, flags: commandFlags)
        }
        postKey(code: tabKey, isDown: true, flags: commandFlags)
        postKey(code: tabKey, isDown: false, flags: commandFlags)
        if !heldModifiers.contains(.command) {
            postKey(code: commandKey, isDown: false, flags: activeModifierFlags)
        }
    }
}

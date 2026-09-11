import Foundation

public struct KeyboardEventStep: Equatable, Sendable {
    public var isDown: Bool
    public var functionModifierIsDown: Bool

    public init(isDown: Bool, functionModifierIsDown: Bool) {
        self.isDown = isDown
        self.functionModifierIsDown = functionModifierIsDown
    }
}

public enum KeyboardEventPlan {
    /// Modifier flags describe the state after each transition. An Fn key-up
    /// event must not retain the Fn-down flag, or macOS can treat the virtual
    /// modifier as still held and ignore the next tap as a dictation toggle.
    public static func tap(for key: RemoteKey) -> [KeyboardEventStep] {
        [
            KeyboardEventStep(
                isDown: true,
                functionModifierIsDown: key == .function
            ),
            KeyboardEventStep(
                isDown: false,
                functionModifierIsDown: false
            )
        ]
    }
}

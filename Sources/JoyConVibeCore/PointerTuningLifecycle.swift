import Foundation

/// Turns the continuous callbacks produced by a slider into one committed
/// tuning boundary. Pointer filters and queued events should be reset once,
/// when the user releases the control, rather than on every intermediate step.
public struct PointerTuningLifecycle: Sendable {
    private var wasEditing = false

    public init() {}

    public mutating func update(isEditing: Bool) -> Bool {
        let didFinish = wasEditing && !isEditing
        wasEditing = isEditing
        return didFinish
    }
}
